// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./GovernanceToken.sol";
import "./UtilityToken.sol";
import "./GameAssetNFT.sol";

/**
 * @title StakingContract
 * @dev Contract for staking governance tokens and NFTs to earn rewards
 * Supports multiple staking pools with different reward rates and lock periods
 */
contract StakingContract is 
    Initializable, 
    OwnableUpgradeable, 
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");

    // Contract references
    GovernanceToken public governanceToken;
    UtilityToken public utilityToken;
    GameAssetNFT public gameAssetNFT;

    // Pool types
    enum PoolType { TOKEN_STAKING, NFT_STAKING }

    // Staking pool structure
    struct StakingPool {
        uint256 poolId;
        PoolType poolType;
        address stakingToken; // For token pools
        uint256 rewardRate; // Rewards per second per unit staked
        uint256 lockPeriod; // Lock period in seconds
        uint256 totalStaked; // Total amount staked in pool
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        bool isActive;
        uint256 maxStakePerUser; // 0 for unlimited
    }

    // User stake information
    struct UserStake {
        uint256 amount; // Amount staked (for tokens) or count (for NFTs)
        uint256 stakedAt;
        uint256 lockUntil;
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
        uint256[] stakedTokenIds; // For NFT staking
    }

    // Mappings
    mapping(uint256 => StakingPool) public stakingPools;
    mapping(uint256 => mapping(address => UserStake)) public userStakes;
    mapping(uint256 => uint256[]) public poolStakedNFTs; // poolId => tokenIds
    mapping(uint256 => address) public nftOwners; // tokenId => owner

    uint256 public nextPoolId;
    uint256 public totalRewardsDistributed;

    // Events
    event PoolCreated(uint256 indexed poolId, PoolType poolType, address stakingToken, uint256 rewardRate);
    event TokensStaked(address indexed user, uint256 indexed poolId, uint256 amount);
    event NFTStaked(address indexed user, uint256 indexed poolId, uint256 tokenId);
    event TokensUnstaked(address indexed user, uint256 indexed poolId, uint256 amount);
    event NFTUnstaked(address indexed user, uint256 indexed poolId, uint256 tokenId);
    event RewardsClaimed(address indexed user, uint256 indexed poolId, uint256 amount);
    event PoolUpdated(uint256 indexed poolId, uint256 newRewardRate);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param initialOwner The initial owner of the contract
     * @param _governanceToken Address of the governance token
     * @param _utilityToken Address of the utility token
     * @param _gameAssetNFT Address of the game asset NFT contract
     */
    function initialize(
        address initialOwner,
        address _governanceToken,
        address _utilityToken,
        address _gameAssetNFT
    ) initializer public {
        __Ownable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _transferOwnership(initialOwner);

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(POOL_MANAGER_ROLE, initialOwner);

        governanceToken = GovernanceToken(_governanceToken);
        utilityToken = UtilityToken(_utilityToken);
        gameAssetNFT = GameAssetNFT(_gameAssetNFT);

        nextPoolId = 1;
    }

    /**
     * @dev Create a new staking pool
     * @param poolType Type of pool (token or NFT)
     * @param stakingToken Address of token to stake (for token pools)
     * @param rewardRate Reward rate per second per unit staked
     * @param lockPeriod Lock period in seconds
     * @param maxStakePerUser Maximum stake per user (0 for unlimited)
     */
    function createPool(
        PoolType poolType,
        address stakingToken,
        uint256 rewardRate,
        uint256 lockPeriod,
        uint256 maxStakePerUser
    ) external onlyRole(POOL_MANAGER_ROLE) returns (uint256) {
        uint256 poolId = nextPoolId++;

        stakingPools[poolId] = StakingPool({
            poolId: poolId,
            poolType: poolType,
            stakingToken: stakingToken,
            rewardRate: rewardRate,
            lockPeriod: lockPeriod,
            totalStaked: 0,
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            isActive: true,
            maxStakePerUser: maxStakePerUser
        });

        emit PoolCreated(poolId, poolType, stakingToken, rewardRate);

        return poolId;
    }

    /**
     * @dev Stake tokens in a pool
     * @param poolId The pool ID to stake in
     * @param amount The amount of tokens to stake
     */
    function stakeTokens(uint256 poolId, uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        StakingPool storage pool = stakingPools[poolId];
        require(pool.isActive, "Pool not active");
        require(pool.poolType == PoolType.TOKEN_STAKING, "Not a token staking pool");

        UserStake storage userStake = userStakes[poolId][msg.sender];
        
        // Check max stake limit
        if (pool.maxStakePerUser > 0) {
            require(userStake.amount + amount <= pool.maxStakePerUser, "Exceeds max stake per user");
        }

        // Update pool rewards
        _updatePool(poolId);
        
        // Update user rewards
        _updateUserRewards(poolId, msg.sender);

        // Transfer tokens to contract
        require(IERC20(pool.stakingToken).transferFrom(msg.sender, address(this), amount), "Transfer failed");

        // Update user stake
        userStake.amount += amount;
        userStake.stakedAt = block.timestamp;
        userStake.lockUntil = block.timestamp + pool.lockPeriod;

        // Update pool total
        pool.totalStaked += amount;

        emit TokensStaked(msg.sender, poolId, amount);
    }

    /**
     * @dev Stake NFT in a pool
     * @param poolId The pool ID to stake in
     * @param tokenId The NFT token ID to stake
     */
    function stakeNFT(uint256 poolId, uint256 tokenId) external whenNotPaused nonReentrant {
        StakingPool storage pool = stakingPools[poolId];
        require(pool.isActive, "Pool not active");
        require(pool.poolType == PoolType.NFT_STAKING, "Not an NFT staking pool");
        require(gameAssetNFT.ownerOf(tokenId) == msg.sender, "Not token owner");

        UserStake storage userStake = userStakes[poolId][msg.sender];
        
        // Check max stake limit
        if (pool.maxStakePerUser > 0) {
            require(userStake.amount + 1 <= pool.maxStakePerUser, "Exceeds max stake per user");
        }

        // Update pool rewards
        _updatePool(poolId);
        
        // Update user rewards
        _updateUserRewards(poolId, msg.sender);

        // Transfer NFT to contract
        gameAssetNFT.safeTransferFrom(msg.sender, address(this), tokenId);

        // Update user stake
        userStake.amount += 1;
        userStake.stakedAt = block.timestamp;
        userStake.lockUntil = block.timestamp + pool.lockPeriod;
        userStake.stakedTokenIds.push(tokenId);

        // Update pool data
        pool.totalStaked += 1;
        poolStakedNFTs[poolId].push(tokenId);
        nftOwners[tokenId] = msg.sender;

        // Set staking status on NFT
        gameAssetNFT.setStakingStatus(tokenId, true);

        emit NFTStaked(msg.sender, poolId, tokenId);
    }

    /**
     * @dev Unstake tokens from a pool
     * @param poolId The pool ID to unstake from
     * @param amount The amount of tokens to unstake
     */
    function unstakeTokens(uint256 poolId, uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        StakingPool storage pool = stakingPools[poolId];
        UserStake storage userStake = userStakes[poolId][msg.sender];
        
        require(userStake.amount >= amount, "Insufficient staked amount");
        require(block.timestamp >= userStake.lockUntil, "Still locked");

        // Update pool rewards
        _updatePool(poolId);
        
        // Update user rewards
        _updateUserRewards(poolId, msg.sender);

        // Update user stake
        userStake.amount -= amount;

        // Update pool total
        pool.totalStaked -= amount;

        // Transfer tokens back to user
        require(IERC20(pool.stakingToken).transfer(msg.sender, amount), "Transfer failed");

        emit TokensUnstaked(msg.sender, poolId, amount);
    }

    /**
     * @dev Unstake NFT from a pool
     * @param poolId The pool ID to unstake from
     * @param tokenId The NFT token ID to unstake
     */
    function unstakeNFT(uint256 poolId, uint256 tokenId) external whenNotPaused nonReentrant {
        StakingPool storage pool = stakingPools[poolId];
        UserStake storage userStake = userStakes[poolId][msg.sender];
        
        require(nftOwners[tokenId] == msg.sender, "Not token owner");
        require(block.timestamp >= userStake.lockUntil, "Still locked");

        // Update pool rewards
        _updatePool(poolId);
        
        // Update user rewards
        _updateUserRewards(poolId, msg.sender);

        // Remove token from user's staked list
        for (uint256 i = 0; i < userStake.stakedTokenIds.length; i++) {
            if (userStake.stakedTokenIds[i] == tokenId) {
                userStake.stakedTokenIds[i] = userStake.stakedTokenIds[userStake.stakedTokenIds.length - 1];
                userStake.stakedTokenIds.pop();
                break;
            }
        }

        // Update user stake
        userStake.amount -= 1;

        // Update pool total
        pool.totalStaked -= 1;

        // Clear NFT owner
        delete nftOwners[tokenId];

        // Set staking status on NFT
        gameAssetNFT.setStakingStatus(tokenId, false);

        // Transfer NFT back to user
        gameAssetNFT.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTUnstaked(msg.sender, poolId, tokenId);
    }

    /**
     * @dev Claim rewards from a pool
     * @param poolId The pool ID to claim from
     */
    function claimRewards(uint256 poolId) external whenNotPaused nonReentrant {
        // Update pool rewards
        _updatePool(poolId);
        
        // Update user rewards
        _updateUserRewards(poolId, msg.sender);

        UserStake storage userStake = userStakes[poolId][msg.sender];
        uint256 reward = userStake.rewards;
        
        require(reward > 0, "No rewards to claim");

        userStake.rewards = 0;
        totalRewardsDistributed += reward;

        // Mint utility tokens as rewards
        utilityToken.mint(msg.sender, reward);

        emit RewardsClaimed(msg.sender, poolId, reward);
    }

    /**
     * @dev Update pool reward calculations
     * @param poolId The pool ID to update
     */
    function _updatePool(uint256 poolId) internal {
        StakingPool storage pool = stakingPools[poolId];
        
        if (pool.totalStaked == 0) {
            pool.lastUpdateTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
        uint256 reward = timeElapsed * pool.rewardRate;
        
        pool.rewardPerTokenStored += (reward * 1e18) / pool.totalStaked;
        pool.lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Update user reward calculations
     * @param poolId The pool ID
     * @param user The user address
     */
    function _updateUserRewards(uint256 poolId, address user) internal {
        StakingPool storage pool = stakingPools[poolId];
        UserStake storage userStake = userStakes[poolId][user];

        uint256 rewardPerToken = pool.rewardPerTokenStored - userStake.userRewardPerTokenPaid;
        userStake.rewards += (userStake.amount * rewardPerToken) / 1e18;
        userStake.userRewardPerTokenPaid = pool.rewardPerTokenStored;
    }

    /**
     * @dev Get pending rewards for a user in a pool
     * @param poolId The pool ID
     * @param user The user address
     */
    function getPendingRewards(uint256 poolId, address user) external view returns (uint256) {
        StakingPool memory pool = stakingPools[poolId];
        UserStake memory userStake = userStakes[poolId][user];

        if (pool.totalStaked == 0) {
            return userStake.rewards;
        }

        uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
        uint256 reward = timeElapsed * pool.rewardRate;
        uint256 rewardPerTokenStored = pool.rewardPerTokenStored + (reward * 1e18) / pool.totalStaked;
        
        uint256 rewardPerToken = rewardPerTokenStored - userStake.userRewardPerTokenPaid;
        return userStake.rewards + (userStake.amount * rewardPerToken) / 1e18;
    }

    /**
     * @dev Get user's staked NFT token IDs
     * @param poolId The pool ID
     * @param user The user address
     */
    function getUserStakedNFTs(uint256 poolId, address user) external view returns (uint256[] memory) {
        return userStakes[poolId][user].stakedTokenIds;
    }

    /**
     * @dev Update pool reward rate
     * @param poolId The pool ID
     * @param newRewardRate The new reward rate
     */
    function updatePoolRewardRate(uint256 poolId, uint256 newRewardRate) external onlyRole(POOL_MANAGER_ROLE) {
        _updatePool(poolId);
        stakingPools[poolId].rewardRate = newRewardRate;
        
        emit PoolUpdated(poolId, newRewardRate);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Required for receiving NFTs
    function onERC721Received(address, address, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

