// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/enhanced/GameLogicV2.sol";
import "../../src/enhanced/DynamicTokenomics.sol";
import "../../src/UtilityToken.sol";
import "../../src/GameAssetNFT.sol";
import "../../src/GameResourceNFT.sol";

contract GameLogicV2Test is Test {
    GameLogicV2 public gameLogic;
    DynamicTokenomics public dynamicTokenomics;
    UtilityToken public utilityToken;
    GameAssetNFT public gameAssetNFT;
    GameResourceNFT public gameResourceNFT;
    
    address public owner = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public oracle = address(0x4);
    
    event PlayerRegistered(address indexed player);
    event QuestCompleted(address indexed player, uint256 indexed questId, uint256 reward);
    event PvPResult(address indexed winner, address indexed loser, uint256 reward, uint256 ratingChange);
    event BattleStarted(bytes32 indexed battleId, address indexed player1, address indexed player2);
    event BattleResolved(bytes32 indexed battleId, address indexed winner, address indexed loser);
    event ItemCrafted(address indexed player, uint256 indexed tokenId, uint256 recipeId, uint256 cost);
    event CraftingFailed(address indexed player, uint256 recipeId, uint256 costLost);
    event QuestProgressUpdated(address indexed player, uint256 indexed questId, uint256 progress);
    event ItemUpgraded(address indexed player, uint256 indexed tokenId, uint256 fromRarity, uint256 toRarity);
    event ItemRepaired(address indexed player, uint256 indexed tokenId, uint256 cost);
    event ExperienceGained(address indexed player, uint256 amount, uint256 newLevel);
    event PlayerLeveledUp(address indexed player, uint256 newLevel);
    
    function setUp() public {
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
        
        // Deploy game resource NFT
        GameResourceNFT resourceImpl = new GameResourceNFT();
        bytes memory resourceInitData = abi.encodeWithSelector(
            GameResourceNFT.initialize.selector,
            owner,
            "https://api.example.com/metadata/"
        );
        ERC1967Proxy resourceProxy = new ERC1967Proxy(address(resourceImpl), resourceInitData);
        gameResourceNFT = GameResourceNFT(address(resourceProxy));
        
        // Deploy dynamic tokenomics
        DynamicTokenomics tokenomicsImpl = new DynamicTokenomics();
        bytes memory tokenomicsInitData = abi.encodeWithSelector(
            DynamicTokenomics.initialize.selector,
            owner,
            500, // 5% target inflation
            10000 * 10**18 // Max daily rewards
        );
        ERC1967Proxy tokenomicsProxy = new ERC1967Proxy(address(tokenomicsImpl), tokenomicsInitData);
        dynamicTokenomics = DynamicTokenomics(address(tokenomicsProxy));
        
        // Deploy game logic V2
        GameLogicV2 gameImpl = new GameLogicV2();
        bytes memory gameInitData = abi.encodeWithSelector(
            GameLogicV2.initialize.selector,
            owner,
            address(utilityToken),
            address(gameAssetNFT),
            address(gameResourceNFT),
            address(dynamicTokenomics)
        );
        ERC1967Proxy gameProxy = new ERC1967Proxy(address(gameImpl), gameInitData);
        gameLogic = GameLogicV2(address(gameProxy));
        
        // Setup permissions
        vm.startPrank(owner);
        utilityToken.grantRole(utilityToken.MINTER_ROLE(), address(gameLogic));
        utilityToken.grantRole(utilityToken.BURNER_ROLE(), address(gameLogic));
        utilityToken.grantRole(utilityToken.GAME_ROLE(), address(gameLogic));
        gameAssetNFT.grantRole(gameAssetNFT.MINTER_ROLE(), address(gameLogic));
        gameAssetNFT.grantRole(gameAssetNFT.GAME_ROLE(), address(gameLogic));
        gameResourceNFT.grantRole(gameResourceNFT.MINTER_ROLE(), address(gameLogic));
        gameResourceNFT.grantRole(gameResourceNFT.GAME_ROLE(), address(gameLogic));
        gameLogic.grantRole(gameLogic.ORACLE_ROLE(), oracle);
        dynamicTokenomics.grantRole(dynamicTokenomics.GAME_ROLE(), address(gameLogic));
        dynamicTokenomics.grantRole(dynamicTokenomics.ORACLE_ROLE(), owner);
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(address(gameLogic.utilityToken()), address(utilityToken));
        assertEq(address(gameLogic.gameAssetNFT()), address(gameAssetNFT));
        assertEq(address(gameLogic.gameResourceNFT()), address(gameResourceNFT));
        assertEq(address(gameLogic.dynamicTokenomics()), address(dynamicTokenomics));
        assertEq(gameLogic.owner(), owner);
        
        // Check default game config
        GameLogicV2.GameConfig memory config = gameLogic.getGameConfig();
        assertEq(config.baseQuestReward, 100 * 10**18);
        assertEq(config.basePvpWinReward, 50 * 10**18);
        assertEq(config.baseCraftingCost, 10 * 10**18);
        assertEq(config.maxPlayerLevel, 100);
    }
    
    function testPlayerRegistration() public {
        vm.startPrank(player1);
        
        vm.expectEmit(true, false, false, false);
        emit PlayerRegistered(player1);
        
        gameLogic.registerPlayer();
        
        GameLogicV2.PlayerData memory playerData = gameLogic.getPlayerData(player1);
        assertEq(playerData.level, 1);
        assertEq(playerData.experience, 0);
        assertTrue(playerData.isActive);
        assertEq(playerData.pvpRating, 1000); // Starting rating
        
        vm.stopPrank();
    }
    
    function testCannotRegisterTwice() public {
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        
        vm.expectRevert("Player already registered");
        gameLogic.registerPlayer();
        
        vm.stopPrank();
    }
    
    // ========== PvP BATTLE SYSTEM TESTS ==========
    
    function testStartBattle() public {
        // Register players
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(player2);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Start battle
        vm.startPrank(player1);
        
        vm.expectEmit(false, true, true, false);
        emit BattleStarted(bytes32(0), player1, player2);
        
        bytes32 battleId = gameLogic.startBattle(
            player2,
            100, // player1 damage
            90,  // player2 damage
            500, // player1 health
            500  // player2 health
        );
        
        assertFalse(battleId == bytes32(0));
        
        GameLogicV2.Battle memory battle = gameLogic.getBattle(battleId);
        assertEq(battle.player1, player1);
        assertEq(battle.player2, player2);
        assertTrue(battle.isActive);
        
        vm.stopPrank();
    }
    
    function testCannotStartBattleWithSelf() public {
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        
        vm.expectRevert("Cannot battle self");
        gameLogic.startBattle(player1, 100, 90, 500, 500);
        
        vm.stopPrank();
    }
    
    function testResolveBattle() public {
        // Register players and start battle
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(player2);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(player1);
        bytes32 battleId = gameLogic.startBattle(player2, 100, 90, 500, 500);
        vm.stopPrank();
        
        // Resolve battle
        vm.startPrank(oracle);
        
        vm.expectEmit(true, true, true, true);
        emit BattleResolved(battleId, player1, player2);
        emit PvPResult(player1, player2, 0, 0);
        
        gameLogic.resolveBattle(
            battleId,
            player1, // winner
            400, // player1 final damage
            300, // player2 final damage
            100, // player1 final health
            0    // player2 final health (dead)
        );
        
        // Check player stats
        GameLogicV2.PlayerData memory winner = gameLogic.getPlayerData(player1);
        GameLogicV2.PlayerData memory loser = gameLogic.getPlayerData(player2);
        
        assertEq(winner.pvpWins, 1);
        assertEq(loser.pvpLosses, 1);
        assertGt(winner.pvpRating, 1000); // Rating increased
        assertLt(loser.pvpRating, 1000); // Rating decreased
        
        // Check battle inactive
        GameLogicV2.Battle memory _battle = gameLogic.getBattle(battleId);
        assertFalse(_battle.isActive);
        
        vm.stopPrank();
    }
    
    function testRecordPvPResultLegacy() public {
        // Register players
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(player2);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Record PvP result
        vm.startPrank(oracle);
        
        vm.expectEmit(true, true, false, false);
        emit PvPResult(player1, player2, 0, 0);
        
        gameLogic.recordPvPResult(player1, player2);
        
        // Check winner rewards
        assertGt(utilityToken.balanceOf(player1), 0);
        
        // Check stats
        GameLogicV2.PlayerData memory winner = gameLogic.getPlayerData(player1);
        GameLogicV2.PlayerData memory loser = gameLogic.getPlayerData(player2);
        
        assertEq(winner.pvpWins, 1);
        assertEq(loser.pvpLosses, 1);
        
        vm.stopPrank();
    }
    
    // ========== CRAFTING SYSTEM TESTS ==========
    
    function testCreateCraftingRecipe() public {
        vm.startPrank(owner);
        
        uint256 recipeId = gameLogic.createCraftingRecipe(
            "Sword of Power",
            GameAssetNFT.AssetType.WEAPON,
            5, // required level
            50 * 10**18, // base cost
            new uint256[](1),
            new uint256[](1),
            8000 // 80% success rate
        );
        
        assertEq(recipeId, 1);
        
        GameLogicV2.CraftingRecipe memory recipe = gameLogic.getCraftingRecipe(recipeId);
        assertEq(recipe.name, "Sword of Power");
        assertEq(uint256(recipe.assetType), uint256(GameAssetNFT.AssetType.WEAPON));
        assertEq(recipe.requiredLevel, 5);
        assertEq(recipe.successRate, 8000);
        
        vm.stopPrank();
    }
    
    function testCraftItemSuccess() public {
        // Register player and create recipe
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(owner);
        
        // Create resource
        uint256 resourceId = gameResourceNFT.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            0,
            "Iron Ore",
            "Basic crafting material"
        );
        
        // Create recipe with the resource already wired in
        uint256[] memory resourceIds = new uint256[](1);
        resourceIds[0] = resourceId;
        uint256[] memory resourceAmounts = new uint256[](1);
        resourceAmounts[0] = 5;
        uint256 recipeId = gameLogic.createCraftingRecipe(
            "Iron Sword",
            GameAssetNFT.AssetType.WEAPON,
            1, // required level
            10 * 10**18, // base cost
            resourceIds,
            resourceAmounts,
            10000 // 100% success rate
        );
        
        // Give player tokens and resources
        utilityToken.mint(player1, 100 * 10**18);
        gameResourceNFT.mintResource(player1, resourceId, 10);
        
        vm.stopPrank();
        
        // Craft item
        vm.startPrank(player1);
        utilityToken.approve(address(gameLogic), 100 * 10**18);
        gameResourceNFT.setApprovalForAll(address(gameLogic), true);
        
        vm.expectEmit(true, true, false, false);
        emit ItemCrafted(player1, 1, recipeId, 0);
        
        gameLogic.craftItem(recipeId, "https://example.com/sword.json");
        
        // Check asset minted
        assertEq(gameAssetNFT.balanceOf(player1), 1);
        
        // Check resources consumed
        assertEq(gameResourceNFT.balanceOf(player1, resourceId), 5);
        
        vm.stopPrank();
    }
    
    function testCraftItemFailure() public {
        // Register player and create recipe with low success rate
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(owner);
        
        // Create resource
        uint256 resourceId = gameResourceNFT.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            0,
            "Iron Ore",
            "Basic crafting material"
        );
        
        // Create recipe with minimal success rate for testing
        uint256[] memory resourceIds = new uint256[](1);
        resourceIds[0] = resourceId;
        uint256[] memory resourceAmounts = new uint256[](1);
        resourceAmounts[0] = 5;
        uint256 recipeId = gameLogic.createCraftingRecipe(
            "Risky Sword",
            GameAssetNFT.AssetType.WEAPON,
            1,
            10 * 10**18,
            resourceIds,
            resourceAmounts,
            1 // 0.01% success rate (minimum allowed)
        );
        
        // Give player tokens and resources
        utilityToken.mint(player1, 100 * 10**18);
        gameResourceNFT.mintResource(player1, resourceId, 10);
        
        vm.stopPrank();
        
        // Craft item (should fail)
        vm.startPrank(player1);
        utilityToken.approve(address(gameLogic), 100 * 10**18);
        gameResourceNFT.setApprovalForAll(address(gameLogic), true);

        // Warp to a timestamp where the deterministic roll fails (roll != 0)
        uint256 ts = block.timestamp;
        while (uint256(keccak256(abi.encodePacked(ts, player1, recipeId))) % 10000 == 0) {
            ts++;
        }
        vm.warp(ts);
        
        vm.expectEmit(true, true, false, false);
        emit CraftingFailed(player1, recipeId, 0);
        
        gameLogic.craftItem(recipeId, "https://example.com/sword.json");
        
        // Check no asset minted
        assertEq(gameAssetNFT.balanceOf(player1), 0);
        
        // Check some resources lost (50% on failure)
        assertEq(gameResourceNFT.balanceOf(player1, resourceId), 8); // failure burns amounts/2 = 5/2 = 2
        
        vm.stopPrank();
    }
    
    function testLegacyCraftItem() public {
        // Register player
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Create and give resources
        vm.startPrank(owner);
        utilityToken.mint(player1, 1000 * 10**18);
        
        uint256 resourceId = gameResourceNFT.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            0,
            "Iron Ore",
            "Basic crafting material"
        );
        gameResourceNFT.mintResource(player1, resourceId, 10);
        vm.stopPrank();
        
        // Craft using legacy method
        vm.startPrank(player1);
        utilityToken.approve(address(gameLogic), 1000 * 10**18);
        gameResourceNFT.setApprovalForAll(address(gameLogic), true);
        
        uint256[] memory resourceIds = new uint256[](1);
        uint256[] memory resourceAmounts = new uint256[](1);
        resourceIds[0] = resourceId;
        resourceAmounts[0] = 5;
        
        uint256 initialBalance = utilityToken.balanceOf(player1);
        
        vm.expectEmit(true, true, false, false);
        emit ItemCrafted(player1, 1, 0, 10 * 10**18);
        
        gameLogic.craftItem(
            GameAssetNFT.AssetType.WEAPON,
            1,
            resourceIds,
            resourceAmounts,
            "https://example.com/weapon.json"
        );
        
        // Check crafting cost deducted
        assertEq(utilityToken.balanceOf(player1), initialBalance - 10 * 10**18);
        
        // Check asset minted
        assertEq(gameAssetNFT.balanceOf(player1), 1);
        
        vm.stopPrank();
    }
    
    // ========== ASSET PROGRESSION TESTS ==========
    
    function testCreateUpgradeRecipe() public {
        vm.startPrank(owner);
        
        uint256 recipeId = gameLogic.createUpgradeRecipe(
            GameAssetNFT.AssetType.WEAPON,
            1, // from rarity
            2, // to rarity
            10, // required level
            new uint256[](1),
            new uint256[](1),
            100 * 10**18 // cost
        );
        
        assertEq(recipeId, 1);
        
        GameLogicV2.UpgradeRecipe memory recipe = gameLogic.getUpgradeRecipe(recipeId);
        assertEq(uint256(recipe.targetAssetType), uint256(GameAssetNFT.AssetType.WEAPON));
        assertEq(recipe.fromRarity, 1);
        assertEq(recipe.toRarity, 2);
        
        vm.stopPrank();
    }
    
    function testLevelUpAsset() public {
        // Register player and mint asset
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(owner);
        utilityToken.mint(player1, 1000 * 10**18);
        uint256 tokenId = gameAssetNFT.mintAsset(
            player1,
            GameAssetNFT.AssetType.WEAPON,
            1,
            "https://example.com/weapon.json"
        );
        vm.stopPrank();
        
        // Level up asset
        vm.startPrank(player1);
        utilityToken.approve(address(gameLogic), 1000 * 10**18);
        
        uint256 initialBalance = utilityToken.balanceOf(player1);
        
        gameLogic.levelUpAsset(tokenId);
        
        // Check cost deducted
        assertEq(utilityToken.balanceOf(player1), initialBalance - 5 * 10**18); // baseCraftingCost / 2
        
        // Check asset leveled up
        GameAssetNFT.AssetMetadata memory metadata = gameAssetNFT.getAssetMetadata(tokenId);
        assertEq(metadata.level, 2);
        
        vm.stopPrank();
    }
    
    function testRepairItem() public {
        // Register player and mint asset
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(owner);
        utilityToken.mint(player1, 1000 * 10**18);
        uint256 tokenId = gameAssetNFT.mintAsset(
            player1,
            GameAssetNFT.AssetType.WEAPON,
            1,
            "https://example.com/weapon.json"
        );
        vm.stopPrank();
        
        // Repair item
        vm.startPrank(player1);
        utilityToken.approve(address(gameLogic), 1000 * 10**18);
        
        uint256 initialBalance = utilityToken.balanceOf(player1);
        
        vm.expectEmit(true, true, false, true);
        emit ItemRepaired(player1, tokenId, 5 * 10**18); // baseRepairCost (tokenomics price is unset -> fallback)
        
        gameLogic.repairItem(tokenId);
        
        // Check repair cost deducted
        assertEq(utilityToken.balanceOf(player1), initialBalance - 5 * 10**18); // baseRepairCost
        
        vm.stopPrank();
    }
    
    // ========== QUEST SYSTEM TESTS ==========
    
    function testCreateQuestWithObjectives() public {
        vm.startPrank(owner);
        
        uint256[] memory objectives = new uint256[](2);
        objectives[0] = 1; // Objective 1
        objectives[1] = 2; // Objective 2
        
        uint256 questId = gameLogic.createQuest(
            "Slay Dragons",
            "Slay 2 dragons",
            500 * 10**18,
            10,
            objectives,
            false
        );
        
        assertEq(questId, 1);
        
        GameLogicV2.Quest memory quest = gameLogic.getQuest(questId);
        assertEq(quest.name, "Slay Dragons");
        assertEq(quest.baseRewardAmount, 500 * 10**18);
        assertEq(quest.requiredLevel, 10);
        assertEq(quest.objectives.length, 2);
        
        vm.stopPrank();
    }
    
    function testUpdateQuestProgress() public {
        // Register player and create quest
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(owner);
        uint256 questId = gameLogic.createQuest(
            "Collect Resources",
            "Collect 100 resources",
            100 * 10**18,
            1,
            new uint256[](0),
            false
        );
        vm.stopPrank();
        
        // Update quest progress
        vm.startPrank(player1);
        
        vm.expectEmit(true, true, false, false);
        emit QuestProgressUpdated(player1, questId, 50);
        
        gameLogic.updateQuestProgress(questId, 50);
        
        assertEq(gameLogic.questProgress(player1, questId), 50);
        
        vm.stopPrank();
    }
    
    function testCompleteQuest() public {
        // Register player
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Create quest
        vm.startPrank(owner);
        uint256 questId = gameLogic.createQuest(
            "First Quest",
            "Complete tutorial",
            100 * 10**18,
            1,
            new uint256[](0),
            false
        );
        vm.stopPrank();
        
        // Complete quest
        vm.startPrank(player1);
        
        vm.expectEmit(true, true, false, false);
        emit QuestCompleted(player1, questId, 0);
        
        gameLogic.completeQuest(questId);
        
        // Check rewards
        assertGt(utilityToken.balanceOf(player1), 0);
        
        // Check experience gain
        GameLogicV2.PlayerData memory playerData = gameLogic.getPlayerData(player1);
        assertGt(playerData.experience, 0);
        
        vm.stopPrank();
    }
    
    function testDailyQuestCompletion() public {
        // Register player
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Create daily quest
        vm.startPrank(owner);
        uint256 questId = gameLogic.createQuest(
            "Daily Quest",
            "Daily task",
            50 * 10**18,
            1,
            new uint256[](0),
            true
        );
        vm.stopPrank();
        
        // Complete daily quest
        vm.startPrank(player1);
        gameLogic.completeQuest(questId);
        
        // Try to complete same daily quest again on same day
        vm.expectRevert("Daily quest already completed");
        gameLogic.completeQuest(questId);
        
        vm.stopPrank();
        
        // Fast forward to next day
        vm.warp(block.timestamp + 1 days);
        
        // Should be able to complete daily quest again
        vm.startPrank(player1);
        gameLogic.completeQuest(questId);
        // Tokenomics daily budget is 0, so each completion pays baseReward/2 = 25e18
        assertEq(utilityToken.balanceOf(player1), 50 * 10**18); // 25e18 + 25e18
        vm.stopPrank();
    }
    
    // ========== EXPERIENCE AND LEVELING TESTS ==========
    
    function testExperienceAndLevelUp() public {
        // Register player
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Create and complete multiple quests to gain experience
        vm.startPrank(owner);
        for (uint256 i = 1; i <= 5; i++) {
            uint256 questId = gameLogic.createQuest(
                string(abi.encodePacked("Quest ", i)),
                "Test quest",
                1000 * 10**18, // 1000 experience points
                1,
                new uint256[](0),
                false
            );
            
            vm.stopPrank();
            vm.startPrank(player1);
            gameLogic.completeQuest(questId);
            vm.stopPrank();
            vm.startPrank(owner);
        }
        vm.stopPrank();
        
        // Check final level and experience
        GameLogicV2.PlayerData memory playerData = gameLogic.getPlayerData(player1);
        assertEq(playerData.experience, 5000); // 5 * 1000
        assertGt(playerData.level, 1);
    }
    
    function testLevelCap() public {
        // Register player
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Update config to set low max level
        vm.startPrank(owner);
        GameLogicV2.GameConfig memory newConfig = gameLogic.getGameConfig();
        newConfig.maxPlayerLevel = 5;
        gameLogic.updateGameConfig(newConfig);
        vm.stopPrank();
        
        // Gain lots of experience
        vm.startPrank(owner);
        for (uint256 i = 1; i <= 20; i++) {
            uint256 questId = gameLogic.createQuest(
                string(abi.encodePacked("Quest ", i)),
                "Test quest",
                1000 * 10**18,
                1,
                new uint256[](0),
                false
            );
            
            vm.stopPrank();
            vm.startPrank(player1);
            gameLogic.completeQuest(questId);
            vm.stopPrank();
            vm.startPrank(owner);
        }
        vm.stopPrank();
        
        // Check level is capped at 5
        GameLogicV2.PlayerData memory playerData = gameLogic.getPlayerData(player1);
        assertEq(playerData.level, 5);
    }
    
    // ========== PLAYER RATING TESTS ==========
    
    function testGetPlayerRating() public {
        // Register player
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Check starting rating
        assertEq(gameLogic.getPlayerRating(player1), 1000);
    }
    
    function testPauseUnpause() public {
        vm.startPrank(owner);
        
        gameLogic.pause();
        assertTrue(gameLogic.paused());
        
        vm.stopPrank();
        
        // Try to register player while paused
        vm.startPrank(player1);
        vm.expectRevert("Pausable: paused");
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        gameLogic.unpause();
        assertFalse(gameLogic.paused());
        vm.stopPrank();
        
        // Should work after unpause
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        assertTrue(gameLogic.getPlayerData(player1).isActive);
        vm.stopPrank();
    }
    
    function testFuzzQuestReward(uint256 rewardAmount) public {
        vm.assume(rewardAmount > 0 && rewardAmount <= 10000 * 10**18);
        
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(owner);
        uint256 questId = gameLogic.createQuest("Fuzz Quest", "Test", rewardAmount, 1, new uint256[](0), false);
        vm.stopPrank();
        
        vm.startPrank(player1);
        gameLogic.completeQuest(questId);
        
        // Tokenomics daily budget is 0 -> calculateQuestReward returns baseReward/2
        assertEq(utilityToken.balanceOf(player1), rewardAmount / 2);
        vm.stopPrank();
    }
}
