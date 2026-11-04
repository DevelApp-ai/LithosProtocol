// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/libraries/PlayerDataStorage.sol";

contract PlayerDataStorageTest is Test {
    PlayerDataStorage public playerDataStorage;
    
    address public owner = address(0x1);
    address public gameContract = address(0x2);
    address public player1 = address(0x3);
    address public player2 = address(0x4);
    
    event PlayerRegistered(address indexed player, string playerName, uint256 timestamp);
    event PlayerLevelUp(address indexed player, uint256 newLevel, uint256 experience);
    event PlayerStatsUpdated(address indexed player, string statType, uint256 newValue);
    event AchievementUnlocked(address indexed player, uint256 achievementId, uint256 timestamp);
    event QuestProgressUpdated(address indexed player, uint256 questId, uint256 progress);
    
    function setUp() public {
        // Deploy player data storage
        PlayerDataStorage storageImpl = new PlayerDataStorage();
        bytes memory initData = abi.encodeWithSelector(
            PlayerDataStorage.initialize.selector,
            owner
        );
        ERC1967Proxy storageProxy = new ERC1967Proxy(address(storageImpl), initData);
        playerDataStorage = PlayerDataStorage(address(storageProxy));
        
        // Setup permissions
        vm.startPrank(owner);
        playerDataStorage.grantRole(playerDataStorage.GAME_ROLE(), gameContract);
        playerDataStorage.grantRole(playerDataStorage.UPGRADER_ROLE(), owner);
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertTrue(playerDataStorage.hasRole(playerDataStorage.DEFAULT_ADMIN_ROLE(), owner));
        assertFalse(playerDataStorage.isPlayerRegistered(player1));
    }
    
    function testRegisterPlayer() public {
        vm.startPrank(gameContract);
        
        vm.expectEmit(true, true, false, false);
        emit PlayerRegistered(player1, "TestPlayer", 0);
        
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        vm.stopPrank();
        
        assertTrue(playerDataStorage.isPlayerRegistered(player1));
        
        PlayerDataStorage.PlayerData memory playerData = playerDataStorage.getPlayerData(player1);
        assertEq(playerData.level, 1);
        assertEq(playerData.experience, 0);
        assertEq(playerData.playerName, "TestPlayer");
        assertTrue(playerData.isRegistered);
        assertEq(playerData.joinTimestamp, block.timestamp);
    }
    
    function testCannotRegisterTwice() public {
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        
        vm.expectRevert("Player already registered");
        playerDataStorage.registerPlayer(player1, "TestPlayer2");
        
        vm.stopPrank();
    }
    
    function testAddExperience() public {
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        vm.stopPrank();
        
        vm.startPrank(gameContract);
        
        vm.expectEmit(true, true, false, false);
        emit PlayerLevelUp(player1, 2, 150);
        
        playerDataStorage.addExperience(player1, 150);
        vm.stopPrank();
        
        PlayerDataStorage.PlayerData memory playerData = playerDataStorage.getPlayerData(player1);
        assertEq(playerData.experience, 150);
        assertEq(playerData.level, 2);
    }
    
    function testLevelUp() public {
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        
        // Add enough experience for multiple level ups
        playerDataStorage.addExperience(player1, 10000);
        vm.stopPrank();
        
        PlayerDataStorage.PlayerData memory playerData = playerDataStorage.getPlayerData(player1);
        assertGt(playerData.level, 1);
    }
    
    function testCompleteQuest() public {
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        
        vm.expectEmit(true, true, false, false);
        emit PlayerStatsUpdated(player1, "questsCompleted", 1);
        
        playerDataStorage.completeQuest(player1);
        vm.stopPrank();
        
        PlayerDataStorage.PlayerData memory playerData = playerDataStorage.getPlayerData(player1);
        assertEq(playerData.totalQuestsCompleted, 1);
        assertGt(playerData.lastQuestTime, 0);
    }
    
    function testUpdatePvPStatsWin() public {
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        
        vm.expectEmit(true, true, false, false);
        emit PlayerStatsUpdated(player1, "pvpWins", 1);
        
        playerDataStorage.updatePvPStats(player1, true);
        vm.stopPrank();
        
        PlayerDataStorage.PlayerData memory playerData = playerDataStorage.getPlayerData(player1);
        assertEq(playerData.pvpWins, 1);
        assertEq(playerData.pvpLosses, 0);
        
        PlayerDataStorage.PlayerStats memory playerStats = playerDataStorage.getPlayerStats(player1);
        assertEq(playerStats.currentWinStreak, 1);
        assertEq(playerStats.longestWinStreak, 1);
    }
    
    function testUpdatePvPStatsLoss() public {
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        
        // First add a win
        playerDataStorage.updatePvPStats(player1, true);
        
        vm.expectEmit(true, true, false, false);
        emit PlayerStatsUpdated(player1, "pvpLosses", 1);
        
        playerDataStorage.updatePvPStats(player1, false);
        vm.stopPrank();
        
        PlayerDataStorage.PlayerData memory playerData = playerDataStorage.getPlayerData(player1);
        assertEq(playerData.pvpWins, 1);
        assertEq(playerData.pvpLosses, 1);
        
        PlayerDataStorage.PlayerStats memory playerStats = playerDataStorage.getPlayerStats(player1);
        assertEq(playerStats.currentWinStreak, 0);
        assertEq(playerStats.longestWinStreak, 1);
    }
    
    function testUpdateCraftingStats() public {
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        
        vm.expectEmit(true, true, false, false);
        emit PlayerStatsUpdated(player1, "totalCrafted", 5);
        
        playerDataStorage.updateCraftingStats(player1, 5);
        vm.stopPrank();
        
        PlayerDataStorage.PlayerData memory playerData = playerDataStorage.getPlayerData(player1);
        assertEq(playerData.totalCrafted, 5);
        
        PlayerDataStorage.PlayerStats memory playerStats = playerDataStorage.getPlayerStats(player1);
        assertEq(playerStats.totalItemsCrafted, 5);
    }
    
    function testUnlockAchievement() public {
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        
        vm.expectEmit(true, true, false, false);
        emit AchievementUnlocked(player1, 1, 0);
        
        playerDataStorage.unlockAchievement(player1, 1);
        vm.stopPrank();
        
        assertTrue(playerDataStorage.hasAchievement(player1, 1));
    }
    
    function testCannotUnlockSameAchievementTwice() public {
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        playerDataStorage.unlockAchievement(player1, 1);
        
        vm.expectRevert("Achievement already unlocked");
        playerDataStorage.unlockAchievement(player1, 1);
        
        vm.stopPrank();
    }
    
    function testUpdateQuestProgress() public {
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        
        vm.expectEmit(true, true, false, false);
        emit QuestProgressUpdated(player1, 123, 50);
        
        playerDataStorage.updateQuestProgress(player1, 123, 50);
        vm.stopPrank();
        
        uint256 progress = playerDataStorage.getQuestProgress(player1, 123);
        assertEq(progress, 50);
    }
    
    function testCalculateLevel() public {
        // Test various experience levels
        assertEq(playerDataStorage.calculateLevel(0), 1);
        assertEq(playerDataStorage.calculateLevel(99), 1);
        assertEq(playerDataStorage.calculateLevel(100), 2);
        assertEq(playerDataStorage.calculateLevel(400), 3); // sqrt(400/100) + 1 = 2 + 1 = 3
        assertEq(playerDataStorage.calculateLevel(900), 4); // sqrt(900/100) + 1 = 3 + 1 = 4
    }
    
    function testPauseUnpause() public {
        vm.startPrank(owner);
        playerDataStorage.pause();
        assertTrue(playerDataStorage.paused());
        
        vm.stopPrank();
        
        // Try to register while paused
        vm.startPrank(gameContract);
        vm.expectRevert("Pausable: paused");
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        playerDataStorage.unpause();
        assertFalse(playerDataStorage.paused());
        vm.stopPrank();
    }
    
    function testFuzzPlayerRegistration(uint256 playerNum) public {
        address player = address(uint160(playerNum));
        vm.assume(player != address(0) && player != owner && player != gameContract);
        
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player, "TestPlayer");
        vm.stopPrank();
        
        assertTrue(playerDataStorage.isPlayerRegistered(player));
    }
    
    function testFuzzExperienceGain(uint256 expAmount) public {
        vm.assume(expAmount > 0 && expAmount <= 100000);
        
        vm.startPrank(gameContract);
        playerDataStorage.registerPlayer(player1, "TestPlayer");
        playerDataStorage.addExperience(player1, expAmount);
        vm.stopPrank();
        
        PlayerDataStorage.PlayerData memory playerData = playerDataStorage.getPlayerData(player1);
        assertEq(playerData.experience, expAmount);
        assertGt(playerData.level, 0);
    }
}
