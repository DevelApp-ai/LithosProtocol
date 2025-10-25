// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/GameLogic.sol";
import "../src/UtilityToken.sol";
import "../src/GameAssetNFT.sol";
import "../src/GameResourceNFT.sol";

contract GameLogicTest is Test {
    GameLogic public gameLogic;
    UtilityToken public utilityToken;
    GameAssetNFT public gameAssetNFT;
    GameResourceNFT public gameResourceNFT;
    
    address public owner = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public oracle = address(0x4);
    
    event PlayerRegistered(address indexed player);
    event QuestCompleted(address indexed player, uint256 indexed questId, uint256 reward);
    event PvPResult(address indexed winner, address indexed loser, uint256 reward);
    event ItemCrafted(address indexed player, uint256 indexed tokenId, uint256 cost);
    event ItemRepaired(address indexed player, uint256 indexed tokenId, uint256 cost);
    event ExperienceGained(address indexed player, uint256 amount, uint256 newLevel);
    
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
        
        // Deploy game logic
        GameLogic gameImpl = new GameLogic();
        bytes memory gameInitData = abi.encodeWithSelector(
            GameLogic.initialize.selector,
            owner,
            address(utilityToken),
            address(gameAssetNFT),
            address(gameResourceNFT)
        );
        ERC1967Proxy gameProxy = new ERC1967Proxy(address(gameImpl), gameInitData);
        gameLogic = GameLogic(address(gameProxy));
        
        // Setup permissions
        vm.startPrank(owner);
        utilityToken.grantRole(utilityToken.MINTER_ROLE(), address(gameLogic));
        utilityToken.grantRole(utilityToken.BURNER_ROLE(), address(gameLogic));
        gameAssetNFT.grantRole(gameAssetNFT.MINTER_ROLE(), address(gameLogic));
        gameResourceNFT.grantRole(gameResourceNFT.MINTER_ROLE(), address(gameLogic));
        gameResourceNFT.grantRole(gameResourceNFT.GAME_ROLE(), address(gameLogic));
        gameLogic.grantRole(gameLogic.ORACLE_ROLE(), oracle);
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(address(gameLogic.utilityToken()), address(utilityToken));
        assertEq(address(gameLogic.gameAssetNFT()), address(gameAssetNFT));
        assertEq(address(gameLogic.gameResourceNFT()), address(gameResourceNFT));
        assertEq(gameLogic.owner(), owner);
        
        // Check default game config
        (
            uint256 dailyQuestReward,
            uint256 pvpWinReward,
            uint256 leaderboardReward,
            uint256 craftingCost,
            uint256 repairCost,
            uint256 tournamentEntryFee
        ) = gameLogic.gameConfig();
        assertEq(dailyQuestReward, 100 * 10**18);
        assertEq(pvpWinReward, 50 * 10**18);
        assertEq(craftingCost, 10 * 10**18);
    }
    
    function testPlayerRegistration() public {
        vm.startPrank(player1);
        
        vm.expectEmit(true, false, false, false);
        emit PlayerRegistered(player1);
        
        gameLogic.registerPlayer();
        
        GameLogic.PlayerData memory playerData = gameLogic.getPlayerData(player1);
        assertEq(playerData.level, 1);
        assertEq(playerData.experience, 0);
        assertTrue(playerData.isActive);
        
        vm.stopPrank();
    }
    
    function testCannotRegisterTwice() public {
        vm.startPrank(player1);
        
        gameLogic.registerPlayer();
        
        vm.expectRevert("Player already registered");
        gameLogic.registerPlayer();
        
        vm.stopPrank();
    }
    
    function testCreateQuest() public {
        vm.startPrank(owner);
        
        uint256 questId = gameLogic.createQuest(
            "Daily Mining",
            "Mine 10 resources",
            200 * 10**18,
            1,
            true
        );
        
        assertEq(questId, 1);
        
        (
            uint256 id,
            string memory name,
            string memory description,
            uint256 rewardAmount,
            uint256 requiredLevel,
            bool isActive,
            bool isDaily
        ) = gameLogic.quests(questId);
        
        assertEq(id, questId);
        assertEq(name, "Daily Mining");
        assertEq(description, "Mine 10 resources");
        assertEq(rewardAmount, 200 * 10**18);
        assertEq(requiredLevel, 1);
        assertTrue(isActive);
        assertTrue(isDaily);
        
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
            false
        );
        vm.stopPrank();
        
        // Complete quest
        vm.startPrank(player1);
        
        vm.expectEmit(true, true, false, true);
        emit QuestCompleted(player1, questId, 100 * 10**18);
        
        gameLogic.completeQuest(questId);
        
        // Check rewards
        assertEq(utilityToken.balanceOf(player1), 100 * 10**18);
        
        // Check experience gain
        GameLogic.PlayerData memory playerData = gameLogic.getPlayerData(player1);
        assertEq(playerData.experience, 100); // reward amount / 10**18
        
        vm.stopPrank();
    }
    
    function testCannotCompleteQuestTwice() public {
        // Register player and create quest
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(owner);
        uint256 questId = gameLogic.createQuest("Test Quest", "Test", 100 * 10**18, 1, false);
        vm.stopPrank();
        
        // Complete quest first time
        vm.startPrank(player1);
        gameLogic.completeQuest(questId);
        
        // Try to complete again
        vm.expectRevert("Quest already completed");
        gameLogic.completeQuest(questId);
        
        vm.stopPrank();
    }
    
    function testDailyQuestCompletion() public {
        // Register player
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Create daily quest
        vm.startPrank(owner);
        uint256 questId = gameLogic.createQuest("Daily Quest", "Daily task", 50 * 10**18, 1, true);
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
        assertEq(utilityToken.balanceOf(player1), 100 * 10**18); // 2x rewards
        vm.stopPrank();
    }
    
    function testPvPResult() public {
        // Register players
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(player2);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Record PvP result
        vm.startPrank(oracle);
        
        vm.expectEmit(true, true, false, true);
        emit PvPResult(player1, player2, 50 * 10**18);
        
        gameLogic.recordPvPResult(player1, player2);
        
        // Check winner rewards
        assertEq(utilityToken.balanceOf(player1), 50 * 10**18);
        assertEq(utilityToken.balanceOf(player2), 0);
        
        // Check stats
        GameLogic.PlayerData memory winner = gameLogic.getPlayerData(player1);
        GameLogic.PlayerData memory loser = gameLogic.getPlayerData(player2);
        
        assertEq(winner.pvpWins, 1);
        assertEq(winner.pvpLosses, 0);
        assertEq(loser.pvpWins, 0);
        assertEq(loser.pvpLosses, 1);
        
        vm.stopPrank();
    }
    
    function testCraftItem() public {
        // Register player
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Give player some PLAY tokens for crafting cost
        vm.startPrank(owner);
        utilityToken.mint(player1, 1000 * 10**18);
        vm.stopPrank();
        
        // Create some resources
        vm.startPrank(owner);
        uint256 resourceId = gameResourceNFT.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            0,
            "Iron Ore",
            "Basic crafting material"
        );
        gameResourceNFT.mintResource(player1, resourceId, 10);
        vm.stopPrank();
        
        // Approve game logic to spend tokens and resources
        vm.startPrank(player1);
        utilityToken.approve(address(gameLogic), 1000 * 10**18);
        gameResourceNFT.setApprovalForAll(address(gameLogic), true);
        
        uint256[] memory resourceIds = new uint256[](1);
        uint256[] memory resourceAmounts = new uint256[](1);
        resourceIds[0] = resourceId;
        resourceAmounts[0] = 5;
        
        uint256 initialBalance = utilityToken.balanceOf(player1);
        
        vm.expectEmit(true, true, false, false);
        emit ItemCrafted(player1, 1, 10 * 10**18);
        
        gameLogic.craftItem(
            GameAssetNFT.AssetType.WEAPON,
            1,
            resourceIds,
            resourceAmounts,
            "https://example.com/weapon1.json"
        );
        
        // Check that crafting cost was deducted
        assertEq(utilityToken.balanceOf(player1), initialBalance - 10 * 10**18);
        
        // Check that resources were consumed
        assertEq(gameResourceNFT.balanceOf(player1, resourceId), 5);
        
        // Check that asset was minted
        assertEq(gameAssetNFT.balanceOf(player1), 1);
        assertEq(gameAssetNFT.ownerOf(1), player1);
        
        vm.stopPrank();
    }
    
    function testRepairItem() public {
        // Register player and give tokens
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(owner);
        utilityToken.mint(player1, 1000 * 10**18);
        
        // Mint an asset to player
        uint256 tokenId = gameAssetNFT.mintAsset(
            player1,
            GameAssetNFT.AssetType.WEAPON,
            1,
            "https://example.com/weapon.json"
        );
        vm.stopPrank();
        
        // Repair the item
        vm.startPrank(player1);
        utilityToken.approve(address(gameLogic), 1000 * 10**18);
        
        uint256 initialBalance = utilityToken.balanceOf(player1);
        
        vm.expectEmit(true, true, false, true);
        emit ItemRepaired(player1, tokenId, 5 * 10**18);
        
        gameLogic.repairItem(tokenId);
        
        // Check repair cost was deducted
        assertEq(utilityToken.balanceOf(player1), initialBalance - 5 * 10**18);
        
        vm.stopPrank();
    }
    
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
        GameLogic.PlayerData memory playerData = gameLogic.getPlayerData(player1);
        assertEq(playerData.experience, 5000); // 5 * 1000
        
        // Level should be calculated as sqrt(experience / 100) + 1
        // sqrt(5000 / 100) + 1 = sqrt(50) + 1 ≈ 7 + 1 = 8
        assertGt(playerData.level, 1);
    }
    
    function testGameConfigUpdate() public {
        vm.startPrank(owner);
        
        GameLogic.GameConfig memory newConfig = GameLogic.GameConfig({
            dailyQuestReward: 200 * 10**18,
            pvpWinReward: 100 * 10**18,
            leaderboardReward: 2000 * 10**18,
            craftingCost: 20 * 10**18,
            repairCost: 10 * 10**18,
            tournamentEntryFee: 50 * 10**18
        });
        
        gameLogic.updateGameConfig(newConfig);
        
        (
            uint256 dailyQuestReward,
            uint256 pvpWinReward,
            uint256 leaderboardReward,
            uint256 craftingCost,
            uint256 repairCost,
            uint256 tournamentEntryFee
        ) = gameLogic.gameConfig();
        assertEq(dailyQuestReward, 200 * 10**18);
        assertEq(pvpWinReward, 100 * 10**18);
        assertEq(craftingCost, 20 * 10**18);
        
        vm.stopPrank();
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
    
    function testOnlyOracleCanRecordPvP() public {
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(player2);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        // Non-oracle tries to record PvP result
        vm.startPrank(player1);
        vm.expectRevert();
        gameLogic.recordPvPResult(player1, player2);
        vm.stopPrank();
    }
    
    function testFuzzQuestReward(uint256 rewardAmount) public {
        vm.assume(rewardAmount > 0 && rewardAmount <= 10000 * 10**18);
        
        vm.startPrank(player1);
        gameLogic.registerPlayer();
        vm.stopPrank();
        
        vm.startPrank(owner);
        uint256 questId = gameLogic.createQuest("Fuzz Quest", "Test", rewardAmount, 1, false);
        vm.stopPrank();
        
        vm.startPrank(player1);
        gameLogic.completeQuest(questId);
        
        assertEq(utilityToken.balanceOf(player1), rewardAmount);
        vm.stopPrank();
    }
}

