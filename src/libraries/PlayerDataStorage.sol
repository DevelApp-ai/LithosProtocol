// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title PlayerDataStorage
 * @dev Dedicated storage contract for player data, separated from game logic
 * This allows for safer upgrades and better data management
 */
contract PlayerDataStorage is 
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    struct PlayerData {
        uint256 level;
        uint256 experience;
        uint256 lastQuestTime;
        uint256 totalQuestsCompleted;
        uint256 pvpWins;
        uint256 pvpLosses;
        uint256 totalCrafted;
        bool isRegistered;
        string playerName; // Off-chain data, emitted as events
        uint256 joinTimestamp;
    }

    struct PlayerStats {
        uint256 totalDamageDealt;
        uint256 totalDamageTaken;
        uint256 totalItemsCrafted;
        uint256 totalTokensEarned;
        uint256 totalTokensSpent;
        uint256 longestWinStreak;
        uint256 currentWinStreak;
    }

    // Core player data
    mapping(address => PlayerData) private playerData;
    mapping(address => PlayerStats) private playerStats;
    
    // Player achievements and progress
    mapping(address => mapping(uint256 => bool)) private playerAchievements;
    mapping(address => mapping(uint256 => uint256)) private questProgress;
    
    // Player inventory tracking (for off-chain indexing)
    mapping(address => uint256[]) private playerAssets;
    mapping(address => mapping(uint256 => uint256)) private playerResources;

    // Events for off-chain indexing
    event PlayerRegistered(address indexed player, string playerName, uint256 timestamp);
    event PlayerLevelUp(address indexed player, uint256 newLevel, uint256 experience);
    event PlayerStatsUpdated(address indexed player, string statType, uint256 newValue);
    event AchievementUnlocked(address indexed player, uint256 achievementId, uint256 timestamp);
    event QuestProgressUpdated(address indexed player, uint256 questId, uint256 progress);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin) initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, defaultAdmin);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    /**
     * @dev Register a new player
     * @param player The player address
     * @param playerName The player's chosen name
     */
    function registerPlayer(
        address player, 
        string memory playerName
    ) external onlyRole(GAME_ROLE) {
        require(!playerData[player].isRegistered, "Player already registered");
        
        playerData[player] = PlayerData({
            level: 1,
            experience: 0,
            lastQuestTime: 0,
            totalQuestsCompleted: 0,
            pvpWins: 0,
            pvpLosses: 0,
            totalCrafted: 0,
            isRegistered: true,
            playerName: playerName,
            joinTimestamp: block.timestamp
        });

        emit PlayerRegistered(player, playerName, block.timestamp);
    }

    /**
     * @dev Update player experience and handle level ups
     * @param player The player address
     * @param experienceGained Amount of experience to add
     */
    function addExperience(
        address player, 
        uint256 experienceGained
    ) external onlyRole(GAME_ROLE) {
        require(playerData[player].isRegistered, "Player not registered");
        
        PlayerData storage data = playerData[player];
        data.experience += experienceGained;
        
        // Calculate new level (simple formula: level = sqrt(experience / 100))
        uint256 newLevel = _calculateLevel(data.experience);
        
        if (newLevel > data.level) {
            data.level = newLevel;
            emit PlayerLevelUp(player, newLevel, data.experience);
        }
    }

    /**
     * @dev Update quest-related data
     * @param player The player address
     */
    function completeQuest(address player) external onlyRole(GAME_ROLE) {
        require(playerData[player].isRegistered, "Player not registered");
        
        PlayerData storage data = playerData[player];
        data.lastQuestTime = block.timestamp;
        data.totalQuestsCompleted++;
        
        emit PlayerStatsUpdated(player, "questsCompleted", data.totalQuestsCompleted);
    }

    /**
     * @dev Update PvP statistics
     * @param player The player address
     * @param won Whether the player won the battle
     */
    function updatePvPStats(
        address player, 
        bool won
    ) external onlyRole(GAME_ROLE) {
        require(playerData[player].isRegistered, "Player not registered");
        
        PlayerData storage data = playerData[player];
        PlayerStats storage stats = playerStats[player];
        
        if (won) {
            data.pvpWins++;
            stats.currentWinStreak++;
            if (stats.currentWinStreak > stats.longestWinStreak) {
                stats.longestWinStreak = stats.currentWinStreak;
            }
        } else {
            data.pvpLosses++;
            stats.currentWinStreak = 0;
        }
        
        emit PlayerStatsUpdated(player, won ? "pvpWins" : "pvpLosses", won ? data.pvpWins : data.pvpLosses);
    }

    /**
     * @dev Update crafting statistics
     * @param player The player address
     * @param itemsCrafted Number of items crafted
     */
    function updateCraftingStats(
        address player, 
        uint256 itemsCrafted
    ) external onlyRole(GAME_ROLE) {
        require(playerData[player].isRegistered, "Player not registered");
        
        PlayerData storage data = playerData[player];
        PlayerStats storage stats = playerStats[player];
        
        data.totalCrafted += itemsCrafted;
        stats.totalItemsCrafted += itemsCrafted;
        
        emit PlayerStatsUpdated(player, "totalCrafted", data.totalCrafted);
    }

    /**
     * @dev Unlock an achievement for a player
     * @param player The player address
     * @param achievementId The achievement identifier
     */
    function unlockAchievement(
        address player, 
        uint256 achievementId
    ) external onlyRole(GAME_ROLE) {
        require(playerData[player].isRegistered, "Player not registered");
        require(!playerAchievements[player][achievementId], "Achievement already unlocked");
        
        playerAchievements[player][achievementId] = true;
        emit AchievementUnlocked(player, achievementId, block.timestamp);
    }

    /**
     * @dev Update quest progress
     * @param player The player address
     * @param questId The quest identifier
     * @param progress The current progress value
     */
    function updateQuestProgress(
        address player,
        uint256 questId,
        uint256 progress
    ) external onlyRole(GAME_ROLE) {
        require(playerData[player].isRegistered, "Player not registered");
        
        questProgress[player][questId] = progress;
        emit QuestProgressUpdated(player, questId, progress);
    }

    // View functions
    function getPlayerData(address player) external view returns (PlayerData memory) {
        return playerData[player];
    }

    function getPlayerStats(address player) external view returns (PlayerStats memory) {
        return playerStats[player];
    }

    function hasAchievement(address player, uint256 achievementId) external view returns (bool) {
        return playerAchievements[player][achievementId];
    }

    function getQuestProgress(address player, uint256 questId) external view returns (uint256) {
        return questProgress[player][questId];
    }

    function isPlayerRegistered(address player) external view returns (bool) {
        return playerData[player].isRegistered;
    }

    /**
     * @dev Calculate player level based on experience
     * @param experience Total experience points
     * @return The calculated level
     */
    function _calculateLevel(uint256 experience) internal pure returns (uint256) {
        if (experience < 100) return 1;
        
        // Simple square root approximation for level calculation
        uint256 level = 1;
        uint256 threshold = 100;
        
        while (experience >= threshold && level < 100) {
            level++;
            threshold = level * level * 100; // Quadratic scaling
        }
        
        return level;
    }
}

