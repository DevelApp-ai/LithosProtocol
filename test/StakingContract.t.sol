// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/StakingContract.sol";
import "../src/GovernanceToken.sol";
import "../src/UtilityToken.sol";
import "../src/GameAssetNFT.sol";

contract StakingContractTest is Test {
    StakingContract public stakingContract;
    GovernanceToken public governanceToken;
    UtilityToken public utilityToken;
    GameAssetNFT public gameAssetNFT;
    
    address public owner = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    
    event PoolCreated(uint256 indexed poolId, StakingContract.PoolType poolType, address stakingToken, uint256 rewardRate);
    event TokensStaked(address indexed user, uint256 indexed poolId, uint256 amount);
    event NFTStaked(address indexed user, uint256 indexed poolId, uint256 tokenId);
    event TokensUnstaked(address indexed user, uint256 indexed poolId, uint256 amount);
    event NFTUnstaked(address indexed user, uint256 indexed poolId, uint256 tokenId);
    event RewardsClaimed(address indexed user, uint256 indexed poolId, uint256 amount);
    event PoolUpdated(uint256 indexed poolId, uint256 newRewardRate);
    
    function setUp() public {
        // Deploy governance token
        GovernanceToken govImpl = new GovernanceToken();
        bytes memory govInitData = abi.encodeWithSelector(
            GovernanceToken.initialize.selector,
            owner,
            "Aetherium Governance",
            "GOV",
            1000000 * 10**18
        );
        ERC1967Proxy govProxy = new ERC1967Proxy(address(govImpl), govInitData);
        governanceToken = GovernanceToken(address(govProxy));
        
        // Deploy utility token
        UtilityToken utilityImpl = new UtilityToken();
        bytes memory utilityInitData = abi.encodeWithSelector(
            UtilityToken.initialize.selector,
            owner,
            "Aetherium Play",
            "PLAY",
            0
        );
        ERC1967Proxy utilityProxy = new ERC1967Proxy(address(utilityImpl), utilityInitData);
        utilityToken = UtilityToken(address(utilityProxy));
        
        // Deploy game asset NFT
        GameAssetNFT assetImpl = new GameAssetNFT();
        bytes memory assetInitData = abi.encodeWithSelector(
            GameAssetNFT.initialize.selector,
            owner,
            "Aetherium Assets",
            "ASSET"
        );
        ERC1967Proxy assetProxy = new ERC1967Proxy(address(assetImpl), assetInitData);
        gameAssetNFT = GameAssetNFT(address(assetProxy));
        
        // Deploy staking contract
        StakingContract stakingImpl = new StakingContract();
        bytes memory stakingInitData = abi.encodeWithSelector(
            StakingContract.initialize.selector,
            owner,
            address(governanceToken),
            address(utilityToken),
            address(gameAssetNFT)
        );
        ERC1967Proxy stakingProxy = new ERC1967Proxy(address(stakingImpl), stakingInitData);
        stakingContract = StakingContract(address(stakingProxy));
        
        // Setup permissions (StakingContract does not mint GovernanceToken, which is onlyOwner-minted)
        vm.startPrank(owner);
        utilityToken.grantRole(utilityToken.MINTER_ROLE(), address(stakingContract));
        gameAssetNFT.grantRole(gameAssetNFT.MINTER_ROLE(), address(stakingContract));
        gameAssetNFT.grantRole(gameAssetNFT.GAME_ROLE(), address(stakingContract));
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(address(stakingContract.governanceToken()), address(governanceToken));
        assertEq(address(stakingContract.utilityToken()), address(utilityToken));
        assertEq(address(stakingContract.gameAssetNFT()), address(gameAssetNFT));
        assertEq(stakingContract.owner(), owner);
        assertEq(stakingContract.nextPoolId(), 1);
    }
    
    function testCreateTokenStakingPool() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, false);
        emit PoolCreated(1, StakingContract.PoolType.TOKEN_STAKING, address(governanceToken), 1000);
        
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.TOKEN_STAKING,
            address(governanceToken),
            1000,
            30 days,
            0
        );
        
        assertEq(poolId, 1);
        
        StakingContract.StakingPool memory pool = stakingContract.getStakingPool(poolId);
        assertEq(pool.poolId, poolId);
        assertEq(uint256(pool.poolType), uint256(StakingContract.PoolType.TOKEN_STAKING));
        assertEq(pool.stakingToken, address(governanceToken));
        assertEq(pool.rewardRate, 1000);
        assertEq(pool.lockPeriod, 30 days);
        assertTrue(pool.isActive);
        assertEq(pool.maxStakePerUser, 0);
        
        vm.stopPrank();
    }
    
    function testCreateNFTPool() public {
        vm.startPrank(owner);
        
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.NFT_STAKING,
            address(0),
            500,
            7 days,
            10
        );
        
        assertEq(poolId, 1); // first pool
        
        StakingContract.StakingPool memory pool = stakingContract.getStakingPool(poolId);
        assertEq(uint256(pool.poolType), uint256(StakingContract.PoolType.NFT_STAKING));
        assertEq(pool.maxStakePerUser, 10);
        
        vm.stopPrank();
    }
    
    function testStakeTokens() public {
        // Create pool
        vm.startPrank(owner);
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.TOKEN_STAKING,
            address(governanceToken),
            1000,
            30 days,
            0
        );
        vm.stopPrank();
        
        // Give player tokens
        vm.startPrank(owner);
        governanceToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        // Approve staking contract
        vm.startPrank(player1);
        governanceToken.approve(address(stakingContract), 1000 * 10**18);
        
        vm.expectEmit(true, true, true, false);
        emit TokensStaked(player1, poolId, 500 * 10**18);
        
        stakingContract.stakeTokens(poolId, 500 * 10**18);
        
        StakingContract.UserStake memory userStake = stakingContract.getUserStake(poolId, player1);
        assertEq(userStake.amount, 500 * 10**18);
        assertEq(userStake.lockUntil, block.timestamp + 30 days);
        
        StakingContract.StakingPool memory pool = stakingContract.getStakingPool(poolId);
        assertEq(pool.totalStaked, 500 * 10**18);
        
        vm.stopPrank();
    }
    
    function testStakeNFT() public {
        // Create pool
        vm.startPrank(owner);
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.NFT_STAKING,
            address(0),
            500,
            7 days,
            10
        );
        vm.stopPrank();
        
        // Mint NFT to player
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            player1,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        // Approve staking contract
        vm.startPrank(player1);
        gameAssetNFT.approve(address(stakingContract), tokenId);
        
        vm.expectEmit(true, true, true, false);
        emit NFTStaked(player1, poolId, tokenId);
        
        stakingContract.stakeNFT(poolId, tokenId);
        
        StakingContract.UserStake memory userStake = stakingContract.getUserStake(poolId, player1);
        assertEq(userStake.amount, 1);
        assertEq(userStake.stakedTokenIds.length, 1);
        assertEq(userStake.stakedTokenIds[0], tokenId);
        
        StakingContract.StakingPool memory pool = stakingContract.getStakingPool(poolId);
        assertEq(pool.totalStaked, 1);
        
        // Check NFT owner
        assertEq(stakingContract.nftOwners(tokenId), player1);
        
        vm.stopPrank();
    }
    
    function testCannotStakeBeforeApproval() public {
        // Create pool
        vm.startPrank(owner);
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.TOKEN_STAKING,
            address(governanceToken),
            1000,
            30 days,
            0
        );
        vm.stopPrank();
        
        // Give player tokens but don't approve
        vm.startPrank(owner);
        governanceToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        // Try to stake without approval
        vm.startPrank(player1);
        vm.expectRevert("ERC20: insufficient allowance"); // src uses raw transferFrom (OZ 4.x string)
        stakingContract.stakeTokens(poolId, 500 * 10**18);
        vm.stopPrank();
    }
    
    function testUnstakeTokensAfterLock() public {
        // Create pool
        vm.startPrank(owner);
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.TOKEN_STAKING,
            address(governanceToken),
            1000,
            1 days, // Short lock for testing
            0
        );
        vm.stopPrank();
        
        // Give and stake tokens
        vm.startPrank(owner);
        governanceToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        governanceToken.approve(address(stakingContract), 1000 * 10**18);
        stakingContract.stakeTokens(poolId, 500 * 10**18);
        vm.stopPrank();
        
        // Fast forward past lock period
        vm.warp(block.timestamp + 1 days + 1);
        
        // Unstake
        vm.startPrank(player1);
        vm.expectEmit(true, true, true, false);
        emit TokensUnstaked(player1, poolId, 500 * 10**18);
        
        stakingContract.unstakeTokens(poolId, 500 * 10**18);
        
        assertEq(governanceToken.balanceOf(player1), 1000 * 10**18); // 1000 staked-500 returned + 500 kept
        
        StakingContract.StakingPool memory pool = stakingContract.getStakingPool(poolId);
        assertEq(pool.totalStaked, 0);
        
        vm.stopPrank();
    }
    
    function testCannotUnstakeDuringLock() public {
        // Create pool
        vm.startPrank(owner);
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.TOKEN_STAKING,
            address(governanceToken),
            1000,
            30 days,
            0
        );
        vm.stopPrank();
        
        // Give and stake tokens
        vm.startPrank(owner);
        governanceToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        governanceToken.approve(address(stakingContract), 1000 * 10**18);
        stakingContract.stakeTokens(poolId, 500 * 10**18);
        
        // Try to unstake during lock
        vm.expectRevert("Still locked");
        stakingContract.unstakeTokens(poolId, 500 * 10**18);
        
        vm.stopPrank();
    }
    
    function testClaimRewards() public {
        // Create pool
        vm.startPrank(owner);
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.TOKEN_STAKING,
            address(governanceToken),
            1000000000000000000, // 1 token per second reward rate
            30 days,
            0
        );
        vm.stopPrank();
        
        // Give and stake tokens
        vm.startPrank(owner);
        governanceToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        governanceToken.approve(address(stakingContract), 1000 * 10**18);
        stakingContract.stakeTokens(poolId, 1000 * 10**18);
        vm.stopPrank();
        
        // Fast forward time to accumulate rewards
        vm.warp(block.timestamp + 100);
        
        // Check pending rewards
        uint256 pending = stakingContract.getPendingRewards(poolId, player1);
        assertGt(pending, 0);
        
        // Claim rewards
        vm.startPrank(player1);
        vm.expectEmit(true, true, true, false);
        emit RewardsClaimed(player1, poolId, pending);
        
        stakingContract.claimRewards(poolId);
        
        assertEq(utilityToken.balanceOf(player1), pending);
        
        vm.stopPrank();
    }
    
    function testUpdatePoolRewardRate() public {
        // Create pool
        vm.startPrank(owner);
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.TOKEN_STAKING,
            address(governanceToken),
            1000,
            30 days,
            0
        );
        vm.stopPrank();
        
        // Update reward rate
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false);
        emit PoolUpdated(poolId, 2000);
        
        stakingContract.updatePoolRewardRate(poolId, 2000);
        
        StakingContract.StakingPool memory pool = stakingContract.getStakingPool(poolId);
        assertEq(pool.rewardRate, 2000);
        
        vm.stopPrank();
    }
    
    function testMaxStakePerUser() public {
        // Create pool with max stake limit
        vm.startPrank(owner);
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.TOKEN_STAKING,
            address(governanceToken),
            1000,
            30 days,
            100 * 10**18 // Max 100 tokens per user
        );
        vm.stopPrank();
        
        // Give player tokens
        vm.startPrank(owner);
        governanceToken.transfer(player1, 200 * 10**18);
        vm.stopPrank();
        
        // Approve and stake up to limit
        vm.startPrank(player1);
        governanceToken.approve(address(stakingContract), 200 * 10**18);
        stakingContract.stakeTokens(poolId, 100 * 10**18);
        
        // Try to stake more than limit
        vm.expectRevert("Exceeds max stake per user");
        stakingContract.stakeTokens(poolId, 1 * 10**18);
        
        vm.stopPrank();
    }
    
    function testPauseUnpause() public {
        vm.startPrank(owner);
        
        stakingContract.pause();
        assertTrue(stakingContract.paused());
        
        vm.stopPrank();
        
        // Try to stake while paused
        vm.startPrank(player1);
        vm.expectRevert("Pausable: paused");
        stakingContract.stakeTokens(1, 100);
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        stakingContract.unpause();
        assertFalse(stakingContract.paused());
        vm.stopPrank();
    }
    
    function testGetUserStakedNFTs() public {
        // Create pool
        vm.startPrank(owner);
        uint256 poolId = stakingContract.createPool(
            StakingContract.PoolType.NFT_STAKING,
            address(0),
            500,
            7 days,
            10
        );
        vm.stopPrank();
        
        // Mint multiple NFTs
        vm.startPrank(owner);
        uint256 tokenId1 = gameAssetNFT.mintAsset(
            player1,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        uint256 tokenId2 = gameAssetNFT.mintAsset(
            player1,
            GameAssetNFT.AssetType.WEAPON,
            1,
            "https://example.com/weapon1.json"
        );
        vm.stopPrank();
        
        // Stake both NFTs
        vm.startPrank(player1);
        gameAssetNFT.approve(address(stakingContract), tokenId1);
        gameAssetNFT.approve(address(stakingContract), tokenId2);
        stakingContract.stakeNFT(poolId, tokenId1);
        stakingContract.stakeNFT(poolId, tokenId2);
        vm.stopPrank();
        
        // Get staked NFTs
        uint256[] memory stakedNFTs = stakingContract.getUserStakedNFTs(poolId, player1);
        assertEq(stakedNFTs.length, 2);
        assertEq(stakedNFTs[0], tokenId1);
        assertEq(stakedNFTs[1], tokenId2);
    }
}
