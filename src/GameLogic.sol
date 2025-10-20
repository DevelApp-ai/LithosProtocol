// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./UtilityToken.sol";
import "./GameAssetNFT.sol";
import "./GameResourceNFT.sol";

/**
 * @title GameLogic
 * @dev Core game logic contract that orchestrates interactions and distributes rewards
 * Handles Play-to-Earn mechanics, quests, and game state management
 */
contract GameLogic is 
    Initializable, 
    OwnableUpgradeable, 
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    bytes32 public constant GAME_MASTER_ROLE = keccak256("GAME_MASTER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    // Contract references
    UtilityToken public utilityToken;
    GameAssetNFT public gameAssetNFT;
    GameResourceNFT public gameResourceNFT;

    // Game configuration
    struct GameConfig {
        uint256 dailyQuestReward;
        uint256 pvpWinReward;
        uint256 leaderboardReward;
        uint256 craftingCost;
        uint256 repairCost;
        uint256 tournamentEntryFee;
    }

    GameConfig public gameConfig;

    // Player data
    struct PlayerData {
        uint256 level;
        uint256 experience;
        uint256 lastDailyQuestClaim;
        uint256 pvpWins;
        uint256 pvpLosses;
        bool isActive;
    }

    mapping(address => PlayerData) public players;

    // Quest system
    struct Quest {
        uint256 questId;
        string name;
        string description;
        uint256 rewardAmount;
        uint256 requiredLevel;
        bool isActive;
        bool isDaily;
    }

    mapping(uint256 => Quest) public quests;
    mapping(address => mapping(uint256 => bool)) public completedQuests;
    mapping(address => mapping(uint256 => uint256)) public dailyQuestCompletions; // player => day => questId

    uint256 public nextQuestId;

    // Events
    event PlayerRegistered(address indexed player);
    event QuestCompleted(address indexed player, uint256 indexed questId, uint256 reward);
    event PvPResult(address indexed winner, address indexed loser, uint256 reward);
    event ItemCrafted(address indexed player, uint256 indexed tokenId, uint256 cost);
    event ItemRepaired(address indexed player, uint256 indexed tokenId, uint256 cost);
    event ExperienceGained(address indexed player, uint256 amount, uint256 newLevel);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param initialOwner The initial owner of the contract
     * @param _utilityToken Address of the utility token contract
     * @param _gameAssetNFT Address of the game asset NFT contract
     * @param _gameResourceNFT Address of the game resource NFT contract
     */
    function initialize(
        address initialOwner,
        address _utilityToken,
        address _gameAssetNFT,
        address _gameResourceNFT
    ) initializer public {
        __Ownable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _transferOwnership(initialOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(GAME_MASTER_ROLE, initialOwner);
        _grantRole(ORACLE_ROLE, initialOwner);

        utilityToken = UtilityToken(_utilityToken);
        gameAssetNFT = GameAssetNFT(_gameAssetNFT);
        gameResourceNFT = GameResourceNFT(_gameResourceNFT);

        // Set default game configuration
        gameConfig = GameConfig({
            dailyQuestReward: 100 * 10**18, // 100 PLAY tokens
            pvpWinReward: 50 * 10**18,      // 50 PLAY tokens
            leaderboardReward: 1000 * 10**18, // 1000 PLAY tokens
            craftingCost: 10 * 10**18,      // 10 PLAY tokens
            repairCost: 5 * 10**18,         // 5 PLAY tokens
            tournamentEntryFee: 25 * 10**18 // 25 PLAY tokens
        });

        nextQuestId = 1;
    }

    /**
     * @dev Register a new player
     */
    function registerPlayer() external whenNotPaused {
        require(!players[msg.sender].isActive, "Player already registered");
        
        players[msg.sender] = PlayerData({
            level: 1,
            experience: 0,
            lastDailyQuestClaim: 0,
            pvpWins: 0,
            pvpLosses: 0,
            isActive: true
        });

        emit PlayerRegistered(msg.sender);
    }

    /**
     * @dev Create a new quest
     * @param name Quest name
     * @param description Quest description
     * @param rewardAmount Reward amount in PLAY tokens
     * @param requiredLevel Required player level
     * @param isDaily Whether this is a daily quest
     */
    function createQuest(
        string memory name,
        string memory description,
        uint256 rewardAmount,
        uint256 requiredLevel,
        bool isDaily
    ) external onlyRole(GAME_MASTER_ROLE) returns (uint256) {
        uint256 questId = nextQuestId++;
        
        quests[questId] = Quest({
            questId: questId,
            name: name,
            description: description,
            rewardAmount: rewardAmount,
            requiredLevel: requiredLevel,
            isActive: true,
            isDaily: isDaily
        });

        return questId;
    }

    /**
     * @dev Complete a quest and claim rewards
     * @param questId The quest to complete
     */
    function completeQuest(uint256 questId) external whenNotPaused nonReentrant {
        require(players[msg.sender].isActive, "Player not registered");
        require(quests[questId].isActive, "Quest not active");
        require(players[msg.sender].level >= quests[questId].requiredLevel, "Level too low");

        Quest memory quest = quests[questId];
        
        if (quest.isDaily) {
            uint256 today = block.timestamp / 86400; // Current day
            require(dailyQuestCompletions[msg.sender][today] == 0, "Daily quest already completed");
            dailyQuestCompletions[msg.sender][today] = questId;
        } else {
            require(!completedQuests[msg.sender][questId], "Quest already completed");
            completedQuests[msg.sender][questId] = true;
        }

        // Mint reward tokens
        utilityToken.mint(msg.sender, quest.rewardAmount);
        
        // Grant experience
        _grantExperience(msg.sender, quest.rewardAmount / 10**18);

        emit QuestCompleted(msg.sender, questId, quest.rewardAmount);
    }

    /**
     * @dev Record PvP match result
     * @param winner Address of the winner
     * @param loser Address of the loser
     */
    function recordPvPResult(address winner, address loser) external onlyRole(ORACLE_ROLE) whenNotPaused {
        require(players[winner].isActive && players[loser].isActive, "Invalid players");
        
        players[winner].pvpWins++;
        players[loser].pvpLosses++;
        
        // Reward winner
        utilityToken.mint(winner, gameConfig.pvpWinReward);
        _grantExperience(winner, 10);

        emit PvPResult(winner, loser, gameConfig.pvpWinReward);
    }

    /**
     * @dev Craft an item using resources
     * @param assetType Type of asset to craft
     * @param rarity Rarity of the asset
     * @param resourceIds Array of resource token IDs required
     * @param resourceAmounts Array of resource amounts required
     * @param uri Metadata URI for the crafted item
     */
    function craftItem(
        GameAssetNFT.AssetType assetType,
        uint256 rarity,
        uint256[] memory resourceIds,
        uint256[] memory resourceAmounts,
        string memory uri
    ) external whenNotPaused nonReentrant {
        require(players[msg.sender].isActive, "Player not registered");
        require(resourceIds.length == resourceAmounts.length, "Arrays length mismatch");

        // Burn crafting cost in PLAY tokens
        utilityToken.burnFrom(msg.sender, gameConfig.craftingCost);

        // Burn required resources
        gameResourceNFT.gameBurnBatch(msg.sender, resourceIds, resourceAmounts);

        // Mint the crafted asset
        uint256 tokenId = gameAssetNFT.mintAsset(msg.sender, assetType, rarity, uri);

        // Grant experience
        _grantExperience(msg.sender, rarity * 5);

        emit ItemCrafted(msg.sender, tokenId, gameConfig.craftingCost);
    }

    /**
     * @dev Repair an item
     * @param tokenId The asset token ID to repair
     */
    function repairItem(uint256 tokenId) external whenNotPaused nonReentrant {
        require(players[msg.sender].isActive, "Player not registered");
        require(gameAssetNFT.ownerOf(tokenId) == msg.sender, "Not asset owner");

        // Burn repair cost
        utilityToken.burnFrom(msg.sender, gameConfig.repairCost);

        emit ItemRepaired(msg.sender, tokenId, gameConfig.repairCost);
    }

    /**
     * @dev Grant experience to a player and handle level ups
     * @param player The player address
     * @param amount The experience amount to grant
     */
    function _grantExperience(address player, uint256 amount) internal {
        players[player].experience += amount;
        
        // Simple level calculation: level = sqrt(experience / 100)
        uint256 newLevel = _sqrt(players[player].experience / 100) + 1;
        
        if (newLevel > players[player].level) {
            players[player].level = newLevel;
        }

        emit ExperienceGained(player, amount, players[player].level);
    }

    /**
     * @dev Calculate square root (Babylonian method)
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /**
     * @dev Update game configuration
     */
    function updateGameConfig(GameConfig memory newConfig) external onlyRole(GAME_MASTER_ROLE) {
        gameConfig = newConfig;
    }

    /**
     * @dev Get player data
     */
    function getPlayerData(address player) external view returns (PlayerData memory) {
        return players[player];
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
}

