// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./DynamicTokenomics.sol";
import "../UtilityToken.sol";
import "../GameAssetNFT.sol";
import "../GameResourceNFT.sol";

/**
 * @title GameLogicV2
 * @dev Enhanced game logic contract with dynamic tokenomics integration
 * Implements PvP battle system, crafting recipes, asset progression, and dynamic rewards
 */
contract GameLogicV2 is 
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
    DynamicTokenomics public dynamicTokenomics;

    // Game configuration
    struct GameConfig {
        uint256 baseQuestReward;
        uint256 basePvpWinReward;
        uint256 leaderboardReward;
        uint256 baseCraftingCost;
        uint256 baseRepairCost;
        uint256 tournamentEntryFee;
        uint256 maxPlayerLevel;
    }

    GameConfig public gameConfig;

    // Player data
    struct PlayerData {
        uint256 level;
        uint256 experience;
        uint256 lastDailyQuestClaim;
        uint256 pvpWins;
        uint256 pvpLosses;
        uint256 pvpRating;
        uint256 totalDamageDealt;
        uint256 totalDamageTaken;
        bool isActive;
        uint256 lastActivityTime;
    }

    mapping(address => PlayerData) public players;

    // PvP Battle system
    struct Battle {
        address player1;
        address player2;
        uint256 player1Damage;
        uint256 player2Damage;
        uint256 player1Health;
        uint256 player2Health;
        uint256 startTime;
        bool isActive;
        bytes32 battleId;
    }

    // Crafting recipes
    struct CraftingRecipe {
        uint256 recipeId;
        string name;
        GameAssetNFT.AssetType assetType;
        uint256 requiredLevel;
        uint256 baseCost;
        uint256[] resourceIds;
        uint256[] resourceAmounts;
        uint256 successRate; // Percentage (0-10000)
        bool isActive;
    }

    // Asset upgrade recipes
    struct UpgradeRecipe {
        uint256 recipeId;
        GameAssetNFT.AssetType targetAssetType;
        uint256 fromRarity;
        uint256 toRarity;
        uint256 requiredLevel;
        uint256[] resourceIds;
        uint256[] resourceAmounts;
        uint256 cost;
        bool isActive;
    }

    // Quest system
    struct Quest {
        uint256 questId;
        string name;
        string description;
        uint256 baseRewardAmount;
        uint256 requiredLevel;
        uint256[] objectives;
        bool isActive;
        bool isDaily;
    }

    mapping(uint256 => Quest) public quests;
    mapping(address => mapping(uint256 => bool)) public completedQuests;
    mapping(address => mapping(uint256 => uint256)) public dailyQuestCompletions; // player => day => questId
    mapping(address => mapping(uint256 => uint256)) public questProgress; // player => questId => progress

    // Crafting recipes storage
    mapping(uint256 => CraftingRecipe) public craftingRecipes;
    mapping(uint256 => UpgradeRecipe) public upgradeRecipes;

    // PvP battles
    mapping(bytes32 => Battle) public battles;

    function getGameConfig() external view returns (GameConfig memory) {
        return gameConfig;
    }

    function getBattle(bytes32 battleId) external view returns (Battle memory) {
        return battles[battleId];
    }

    function getCraftingRecipe(uint256 recipeId) external view returns (CraftingRecipe memory) {
        return craftingRecipes[recipeId];
    }

    function getUpgradeRecipe(uint256 recipeId) external view returns (UpgradeRecipe memory) {
        return upgradeRecipes[recipeId];
    }

    function getQuest(uint256 questId) external view returns (Quest memory) {
        return quests[questId];
    }
    mapping(address => uint256) public playerRating;

    // Events
    event PlayerRegistered(address indexed player);
    event QuestCompleted(address indexed player, uint256 indexed questId, uint256 reward);
    event QuestProgressUpdated(address indexed player, uint256 indexed questId, uint256 progress);
    event PvPResult(address indexed winner, address indexed loser, uint256 reward, uint256 ratingChange);
    event BattleStarted(bytes32 indexed battleId, address indexed player1, address indexed player2);
    event BattleResolved(bytes32 indexed battleId, address indexed winner, address indexed loser);
    event ItemCrafted(address indexed player, uint256 indexed tokenId, uint256 recipeId, uint256 cost);
    event CraftingFailed(address indexed player, uint256 recipeId, uint256 costLost);
    event ItemUpgraded(address indexed player, uint256 indexed tokenId, uint256 fromRarity, uint256 toRarity);
    event ItemRepaired(address indexed player, uint256 indexed tokenId, uint256 cost);
    event ExperienceGained(address indexed player, uint256 amount, uint256 newLevel);
    event PlayerLeveledUp(address indexed player, uint256 newLevel);

    uint256 public nextQuestId;
    uint256 public nextRecipeId;
    uint256 public nextUpgradeRecipeId;
    uint256 public nextBattleId;

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
     * @param _dynamicTokenomics Address of the dynamic tokenomics contract
     */
    function initialize(
        address initialOwner,
        address _utilityToken,
        address _gameAssetNFT,
        address _gameResourceNFT,
        address _dynamicTokenomics
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
        dynamicTokenomics = DynamicTokenomics(_dynamicTokenomics);

        // Set default game configuration
        gameConfig = GameConfig({
            baseQuestReward: 100 * 10**18, // 100 PLAY tokens
            basePvpWinReward: 50 * 10**18,      // 50 PLAY tokens
            leaderboardReward: 1000 * 10**18, // 1000 PLAY tokens
            baseCraftingCost: 10 * 10**18,      // 10 PLAY tokens
            baseRepairCost: 5 * 10**18,         // 5 PLAY tokens
            tournamentEntryFee: 25 * 10**18,   // 25 PLAY tokens
            maxPlayerLevel: 100
        });

        nextQuestId = 1;
        nextRecipeId = 1;
        nextUpgradeRecipeId = 1;
        nextBattleId = 1;
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
            pvpRating: 1000, // Starting rating
            totalDamageDealt: 0,
            totalDamageTaken: 0,
            isActive: true,
            lastActivityTime: block.timestamp
        });

        emit PlayerRegistered(msg.sender);
    }

    // ========== PvP BATTLE SYSTEM ==========

    /**
     * @dev Start a new PvP battle
     * @param opponent Address of the opponent
     * @param player1Damage Initial damage for player1
     * @param player2Damage Initial damage for player2
     * @param player1Health Initial health for player1
     * @param player2Health Initial health for player2
     */
    function startBattle(
        address opponent,
        uint256 player1Damage,
        uint256 player2Damage,
        uint256 player1Health,
        uint256 player2Health
    ) external whenNotPaused nonReentrant returns (bytes32) {
        require(players[msg.sender].isActive, "Player not registered");
        require(players[opponent].isActive, "Opponent not registered");
        require(msg.sender != opponent, "Cannot battle self");

        bytes32 battleId = keccak256(abi.encodePacked(msg.sender, opponent, block.timestamp, nextBattleId));
        nextBattleId++;

        battles[battleId] = Battle({
            player1: msg.sender,
            player2: opponent,
            player1Damage: player1Damage,
            player2Damage: player2Damage,
            player1Health: player1Health,
            player2Health: player2Health,
            startTime: block.timestamp,
            isActive: true,
            battleId: battleId
        });

        emit BattleStarted(battleId, msg.sender, opponent);

        return battleId;
    }

    /**
     * @dev Resolve a PvP battle with results
     * @param battleId The battle identifier
     * @param winner The winning player address
     * @param player1FinalDamage Final damage dealt by player1
     * @param player2FinalDamage Final damage dealt by player2
     * @param player1FinalHealth Final health of player1
     * @param player2FinalHealth Final health of player2
     */
    function resolveBattle(
        bytes32 battleId,
        address winner,
        uint256 player1FinalDamage,
        uint256 player2FinalDamage,
        uint256 player1FinalHealth,
        uint256 player2FinalHealth
    ) external onlyRole(ORACLE_ROLE) whenNotPaused nonReentrant {
        Battle storage battle = battles[battleId];
        require(battle.isActive, "Battle not active");
        require(winner == battle.player1 || winner == battle.player2, "Invalid winner");

        address loser = winner == battle.player1 ? battle.player2 : battle.player1;

        // Update player stats
        players[winner].pvpWins++;
        players[loser].pvpLosses++;
        players[winner].totalDamageDealt += player1FinalDamage + player2FinalDamage;
        players[loser].totalDamageTaken += winner == battle.player1 ? player2FinalDamage : player1FinalDamage;
        
        // Update ratings based on damage and health
        uint256 ratingChange = calculateRatingChange(
            battle,
            winner,
            player1FinalDamage,
            player2FinalDamage,
            player1FinalHealth,
            player2FinalHealth
        );

        if (winner == battle.player1) {
            players[winner].pvpRating += ratingChange;
            players[loser].pvpRating -= ratingChange;
        } else {
            players[winner].pvpRating += ratingChange;
            players[loser].pvpRating -= ratingChange;
        }

        // Calculate dynamic reward based on player level and economic state
        uint256 reward = calculateDynamicReward(winner, gameConfig.basePvpWinReward);

        // Mint reward tokens
        utilityToken.mint(winner, reward);
        
        // Grant experience based on battle performance
        uint256 experience = calculateBattleExperience(
            player1FinalDamage + player2FinalDamage,
            battle.player1Health + battle.player2Health,
            winner
        );
        _grantExperience(winner, experience);

        // Mark battle as resolved
        battle.isActive = false;

        emit BattleResolved(battleId, winner, loser);
        emit PvPResult(winner, loser, reward, ratingChange);
    }

    /**
     * @dev Calculate rating change based on battle performance
     */
    function calculateRatingChange(
        Battle memory battle,
        address winner,
        uint256 player1FinalDamage,
        uint256 player2FinalDamage,
        uint256 player1FinalHealth,
        uint256 player2FinalHealth
    ) internal pure returns (uint256) {
        // Calculate damage ratio
        uint256 totalDamage = player1FinalDamage + player2FinalDamage;
        uint256 winnerDamage = winner == battle.player1 ? player1FinalDamage : player2FinalDamage;
        
        // Damage percentage (0-10000)
        uint256 damageRatio = totalDamage > 0 ? (winnerDamage * 10000) / totalDamage : 5000;
        
        // Health remaining ratio
        uint256 winnerHealth = winner == battle.player1 ? player1FinalHealth : player2FinalHealth;
        uint256 healthRatio = (winnerHealth * 10000) / (battle.player1Health + battle.player2Health);
        
        // Combined rating change (1-100)
        uint256 ratingChange = (damageRatio * 60 + healthRatio * 40) / 10000;
        
        // Minimum 1 rating change
        return ratingChange > 0 ? ratingChange : 1;
    }

    /**
     * @dev Calculate experience from battle
     */
    function calculateBattleExperience(
        uint256 totalDamage,
        uint256 totalHealth,
        address winner
    ) internal pure returns (uint256) {
        // Base experience from damage dealt
        uint256 damageExp = totalDamage / 100;
        
        // Bonus for health remaining
        uint256 healthExp = totalHealth / 500;
        
        // Minimum experience
        return damageExp + healthExp > 0 ? damageExp + healthExp : 10;
    }

    /**
     * @dev Record simple PvP match result (legacy compatibility)
     * @param winner Address of the winner
     * @param loser Address of the loser
     */
    function recordPvPResult(address winner, address loser) external onlyRole(ORACLE_ROLE) whenNotPaused {
        require(players[winner].isActive && players[loser].isActive, "Invalid players");
        
        players[winner].pvpWins++;
        players[loser].pvpLosses++;
        
        // Calculate dynamic reward
        uint256 reward = calculateDynamicReward(winner, gameConfig.basePvpWinReward);
        
        // Reward winner
        utilityToken.mint(winner, reward);
        _grantExperience(winner, 10);

        emit PvPResult(winner, loser, reward, 0);
    }

    // ========== CRAFTING SYSTEM ==========

    /**
     * @dev Create a new crafting recipe
     * @param name Recipe name
     * @param assetType Type of asset to craft
     * @param requiredLevel Minimum player level required
     * @param baseCost Base PLAY token cost
     * @param resourceIds Array of resource token IDs required
     * @param resourceAmounts Array of resource amounts required
     * @param successRate Success rate percentage (0-10000)
     */
    function createCraftingRecipe(
        string memory name,
        GameAssetNFT.AssetType assetType,
        uint256 requiredLevel,
        uint256 baseCost,
        uint256[] memory resourceIds,
        uint256[] memory resourceAmounts,
        uint256 successRate
    ) external onlyRole(GAME_MASTER_ROLE) returns (uint256) {
        require(resourceIds.length == resourceAmounts.length, "Arrays length mismatch");
        require(successRate > 0 && successRate <= 10000, "Invalid success rate");
        
        uint256 recipeId = nextRecipeId++;
        
        craftingRecipes[recipeId] = CraftingRecipe({
            recipeId: recipeId,
            name: name,
            assetType: assetType,
            requiredLevel: requiredLevel,
            baseCost: baseCost,
            resourceIds: resourceIds,
            resourceAmounts: resourceAmounts,
            successRate: successRate,
            isActive: true
        });

        return recipeId;
    }

    /**
     * @dev Craft an item using a recipe
     * @param recipeId The crafting recipe ID
     * @param uri Metadata URI for the crafted item
     */
    function craftItem(
        uint256 recipeId,
        string memory uri
    ) external whenNotPaused nonReentrant {
        require(players[msg.sender].isActive, "Player not registered");
        
        CraftingRecipe memory recipe = craftingRecipes[recipeId];
        require(recipe.isActive, "Recipe not active");
        require(players[msg.sender].level >= recipe.requiredLevel, "Level too low");

        // Check player has required resources
        for (uint256 i = 0; i < recipe.resourceIds.length; i++) {
            require(
                gameResourceNFT.balanceOf(msg.sender, recipe.resourceIds[i]) >= recipe.resourceAmounts[i],
                "Insufficient resources"
            );
        }

        // Calculate dynamic cost based on economic state
        uint256 craftingCost = calculateDynamicCost(recipe.baseCost);
        
        // Burn crafting cost in PLAY tokens
        utilityToken.burnFrom(msg.sender, craftingCost);

        // Check success (random number generation would be used in production)
        // For testing, we'll use a deterministic approach based on block timestamp
        uint256 randomSeed = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, recipeId)));
        uint256 successRoll = randomSeed % 10000;
        
        if (successRoll < recipe.successRate) {
            // Success - burn required resources and mint asset
            gameResourceNFT.gameBurnBatch(msg.sender, recipe.resourceIds, recipe.resourceAmounts);
            
            uint256 tokenId = gameAssetNFT.mintAsset(msg.sender, recipe.assetType, 1, uri);
            
            // Grant experience
            _grantExperience(msg.sender, recipe.requiredLevel * 5);

            emit ItemCrafted(msg.sender, tokenId, recipeId, craftingCost);
        } else {
            // Failure - still burn cost but lose some resources
            uint256[] memory failResourceIds = new uint256[](recipe.resourceIds.length);
            uint256[] memory failResourceAmounts = new uint256[](recipe.resourceIds.length);
            
            for (uint256 i = 0; i < recipe.resourceIds.length; i++) {
                // Lose 50% of resources on failure
                failResourceIds[i] = recipe.resourceIds[i];
                failResourceAmounts[i] = recipe.resourceAmounts[i] / 2;
            }
            
            gameResourceNFT.gameBurnBatch(msg.sender, failResourceIds, failResourceAmounts);
            
            emit CraftingFailed(msg.sender, recipeId, craftingCost);
        }
    }

    /**
     * @dev Legacy craftItem for backward compatibility
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
        utilityToken.burnFrom(msg.sender, gameConfig.baseCraftingCost);

        // Burn required resources
        gameResourceNFT.gameBurnBatch(msg.sender, resourceIds, resourceAmounts);

        // Mint the crafted asset
        uint256 tokenId = gameAssetNFT.mintAsset(msg.sender, assetType, rarity, uri);

        // Grant experience
        _grantExperience(msg.sender, rarity * 5);

        emit ItemCrafted(msg.sender, tokenId, 0, gameConfig.baseCraftingCost);
    }

    // ========== ASSET PROGRESSION SYSTEM ==========

    /**
     * @dev Create a new upgrade recipe for assets
     * @param targetAssetType Type of asset to upgrade
     * @param fromRarity Starting rarity level
     * @param toRarity Target rarity level
     * @param requiredLevel Minimum player level required
     * @param resourceIds Array of resource token IDs required
     * @param resourceAmounts Array of resource amounts required
     * @param cost PLAY token cost
     */
    function createUpgradeRecipe(
        GameAssetNFT.AssetType targetAssetType,
        uint256 fromRarity,
        uint256 toRarity,
        uint256 requiredLevel,
        uint256[] memory resourceIds,
        uint256[] memory resourceAmounts,
        uint256 cost
    ) external onlyRole(GAME_MASTER_ROLE) returns (uint256) {
        require(resourceIds.length == resourceAmounts.length, "Arrays length mismatch");
        require(fromRarity < toRarity, "Invalid rarity upgrade");
        require(toRarity <= 5, "Max rarity is 5");
        
        uint256 recipeId = nextUpgradeRecipeId++;
        
        upgradeRecipes[recipeId] = UpgradeRecipe({
            recipeId: recipeId,
            targetAssetType: targetAssetType,
            fromRarity: fromRarity,
            toRarity: toRarity,
            requiredLevel: requiredLevel,
            resourceIds: resourceIds,
            resourceAmounts: resourceAmounts,
            cost: cost,
            isActive: true
        });

        return recipeId;
    }

    /**
     * @dev Upgrade an asset's rarity
     * @param tokenId The asset token ID to upgrade
     * @param recipeId The upgrade recipe ID
     */
    function upgradeAsset(
        uint256 tokenId,
        uint256 recipeId
    ) external whenNotPaused nonReentrant {
        require(players[msg.sender].isActive, "Player not registered");
        require(gameAssetNFT.ownerOf(tokenId) == msg.sender, "Not asset owner");
        
        UpgradeRecipe memory recipe = upgradeRecipes[recipeId];
        require(recipe.isActive, "Recipe not active");
        require(players[msg.sender].level >= recipe.requiredLevel, "Level too low");
        
        GameAssetNFT.AssetMetadata memory metadata = gameAssetNFT.getAssetMetadata(tokenId);
        require(metadata.assetType == recipe.targetAssetType, "Wrong asset type");
        require(metadata.rarity == recipe.fromRarity, "Wrong rarity level");

        // Check player has required resources
        for (uint256 i = 0; i < recipe.resourceIds.length; i++) {
            require(
                gameResourceNFT.balanceOf(msg.sender, recipe.resourceIds[i]) >= recipe.resourceAmounts[i],
                "Insufficient resources"
            );
        }

        // Burn upgrade cost
        utilityToken.burnFrom(msg.sender, recipe.cost);
        
        // Burn required resources
        gameResourceNFT.gameBurnBatch(msg.sender, recipe.resourceIds, recipe.resourceAmounts);

        // Update asset metadata
        gameAssetNFT.levelUpAsset(tokenId);
        
        // Update rarity (this would need to be exposed in GameAssetNFT or handled differently)
        // For now, we'll emit the upgrade event
        emit ItemUpgraded(msg.sender, tokenId, recipe.fromRarity, recipe.toRarity);

        // Grant experience
        _grantExperience(msg.sender, recipe.toRarity * 10);
    }

    /**
     * @dev Level up an asset
     * @param tokenId The asset token ID to level up
     */
    function levelUpAsset(uint256 tokenId) external whenNotPaused nonReentrant {
        require(players[msg.sender].isActive, "Player not registered");
        require(gameAssetNFT.ownerOf(tokenId) == msg.sender, "Not asset owner");

        // Burn level up cost
        utilityToken.burnFrom(msg.sender, gameConfig.baseCraftingCost / 2);

        gameAssetNFT.levelUpAsset(tokenId);

        // Grant experience
        _grantExperience(msg.sender, 5);
    }

    // ========== REPAIR SYSTEM ==========

    /**
     * @dev Repair an item
     * @param tokenId The asset token ID to repair
     */
    function repairItem(uint256 tokenId) external whenNotPaused nonReentrant {
        require(players[msg.sender].isActive, "Player not registered");
        require(gameAssetNFT.ownerOf(tokenId) == msg.sender, "Not asset owner");

        // Calculate dynamic repair cost
        uint256 repairCost = calculateDynamicCost(gameConfig.baseRepairCost);

        // Burn repair cost
        utilityToken.burnFrom(msg.sender, repairCost);

        emit ItemRepaired(msg.sender, tokenId, repairCost);
    }

    // ========== QUEST SYSTEM ==========

    /**
     * @dev Create a new quest
     * @param name Quest name
     * @param description Quest description
     * @param baseRewardAmount Base reward amount in PLAY tokens
     * @param requiredLevel Required player level
     * @param objectives Array of objective IDs
     * @param isDaily Whether this is a daily quest
     */
    function createQuest(
        string memory name,
        string memory description,
        uint256 baseRewardAmount,
        uint256 requiredLevel,
        uint256[] memory objectives,
        bool isDaily
    ) external onlyRole(GAME_MASTER_ROLE) returns (uint256) {
        uint256 questId = nextQuestId++;
        
        quests[questId] = Quest({
            questId: questId,
            name: name,
            description: description,
            baseRewardAmount: baseRewardAmount,
            requiredLevel: requiredLevel,
            objectives: objectives,
            isActive: true,
            isDaily: isDaily
        });

        return questId;
    }

    /**
     * @dev Update quest progress
     * @param questId The quest ID
     * @param progress The new progress value
     */
    function updateQuestProgress(
        uint256 questId,
        uint256 progress
    ) external whenNotPaused {
        require(players[msg.sender].isActive, "Player not registered");
        require(quests[questId].isActive, "Quest not active");
        require(players[msg.sender].level >= quests[questId].requiredLevel, "Level too low");

        questProgress[msg.sender][questId] = progress;

        emit QuestProgressUpdated(msg.sender, questId, progress);
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

        // Calculate dynamic reward based on player level and economic state
        uint256 reward = calculateDynamicReward(msg.sender, quest.baseRewardAmount);
        
        // Mint reward tokens
        utilityToken.mint(msg.sender, reward);
        
        // Grant experience
        _grantExperience(msg.sender, quest.baseRewardAmount / 10**18);

        emit QuestCompleted(msg.sender, questId, reward);
    }

    // ========== DYNAMIC REWARD SYSTEM ==========

    /**
     * @dev Calculate dynamic reward based on player level and economic state
     * @param player The player address
     * @param baseReward The base reward amount
     * @return The calculated dynamic reward
     */
    function calculateDynamicReward(
        address player,
        uint256 baseReward
    ) internal view returns (uint256) {
        PlayerData memory playerData = players[player];
        
        // Level multiplier (higher level = slightly higher rewards)
        uint256 levelMultiplier = 1000 + (playerData.level * 10); // +1% per level
        
        // Get economic adjustment from dynamic tokenomics
        uint256 economicAdjustment = 1000; // Default 1.0x
        
        try dynamicTokenomics.calculateQuestReward(0, baseReward, playerData.level) returns (uint256 adjusted) {
            // If dynamic tokenomics returns a value, use it
            if (adjusted > 0) {
                return adjusted;
            }
        } catch {
            // Fall back to manual calculation
        }
        
        // Manual calculation based on inflation
        if (address(dynamicTokenomics) != address(0)) {
            uint256 healthScore = dynamicTokenomics.getEconomicHealthScore();
            economicAdjustment = (healthScore * 1000) / 100; // Convert score to multiplier
        }
        
        uint256 adjustedReward = (baseReward * levelMultiplier * economicAdjustment) / (1000 * 1000);
        
        return adjustedReward;
    }

    /**
     * @dev Calculate dynamic cost based on economic state
     * @param baseCost The base cost amount
     * @return The calculated dynamic cost
     */
    function calculateDynamicCost(uint256 baseCost) internal view returns (uint256) {
        // Get price from dynamic tokenomics if available
        try dynamicTokenomics.getCurrentPrice(0) returns (uint256 price) {
            if (price > 0) {
                return (baseCost * price) / 1000;
            }
        } catch {
            // Fall back to base cost
        }
        
        return baseCost;
    }

    // ========== PLAYER STATS ==========

    /**
     * @dev Get player PvP rating
     * @param player The player address
     * @return The player's PvP rating
     */
    function getPlayerRating(address player) external view returns (uint256) {
        return players[player].pvpRating;
    }

    /**
     * @dev Get player data
     */
    function getPlayerData(address player) external view returns (PlayerData memory) {
        return players[player];
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
            
            // Cap at max level
            if (players[player].level > gameConfig.maxPlayerLevel) {
                players[player].level = gameConfig.maxPlayerLevel;
            }
            
            emit ExperienceGained(player, amount, players[player].level);
            emit PlayerLeveledUp(player, players[player].level);
        }
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

