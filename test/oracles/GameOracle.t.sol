// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/oracles/GameOracle.sol";

contract GameOracleTest is Test {
    GameOracle public oracle;
    
    address public owner = address(0x1);
    address public oracle1 = address(0x2);
    address public oracle2 = address(0x3);
    address public player1 = address(0x4);
    address public player2 = address(0x5);
    
    event PvPResultReported(bytes32 indexed matchId, address indexed winner, address indexed loser);
    event QuestCompletionReported(bytes32 indexed questHash, address indexed player, uint256 questId);
    event MarketDataUpdated(uint256 indexed itemId, uint256 averagePrice, uint256 volume);
    event OracleStakeUpdated(address indexed oracle, uint256 newStake);
    event RequiredConfirmationsUpdated(uint256 newRequirement);
    
    function setUp() public {
        // Deploy game oracle
        GameOracle oracleImpl = new GameOracle();
        bytes memory initData = abi.encodeWithSelector(
            GameOracle.initialize.selector,
            owner,
            2 // Require 2 confirmations
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), initData);
        oracle = GameOracle(address(oracleProxy));
        
        // Setup permissions
        vm.startPrank(owner);
        oracle.grantRole(oracle.ORACLE_ROLE(), oracle1);
        oracle.grantRole(oracle.ORACLE_ROLE(), oracle2);
        oracle.grantRole(oracle.GAME_ROLE(), owner);
        oracle.grantRole(oracle.UPGRADER_ROLE(), owner);
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), owner));
        assertEq(oracle.requiredConfirmations(), 2);
    }
    
    function testReportPvPResultSingleConfirmation() public {
        bytes32 matchId = keccak256(abi.encodePacked("match1"));
        
        vm.startPrank(oracle1);
        oracle.reportPvPResult(matchId, player1, player2, player1);
        vm.stopPrank();
        
        // Result should not be verified yet (need 2 confirmations)
        assertFalse(oracle.isPvPResultVerified(matchId));
        assertEq(oracle.confirmationCount(matchId), 1);
    }
    
    function testReportPvPResultMultipleConfirmations() public {
        bytes32 matchId = keccak256(abi.encodePacked("match2"));
        
        // First confirmation
        vm.startPrank(oracle1);
        oracle.reportPvPResult(matchId, player1, player2, player1);
        vm.stopPrank();
        
        // Second confirmation
        vm.startPrank(oracle2);
        vm.expectEmit(true, true, true, false);
        emit PvPResultReported(matchId, player1, player2);
        
        oracle.reportPvPResult(matchId, player1, player2, player1);
        vm.stopPrank();
        
        // Now should be verified
        assertTrue(oracle.isPvPResultVerified(matchId));
        assertEq(oracle.confirmationCount(matchId), 2);
        
        // Get the result
        GameOracle.PvPResult memory result = oracle.getVerifiedPvPResult(matchId);
        assertEq(result.player1, player1);
        assertEq(result.player2, player2);
        assertEq(result.winner, player1);
        assertTrue(result.verified);
    }
    
    function testCannotReportInvalidWinner() public {
        bytes32 matchId = keccak256(abi.encodePacked("match3"));
        
        vm.startPrank(oracle1);
        vm.expectRevert("Invalid winner");
        oracle.reportPvPResult(matchId, player1, player2, address(0x6)); // Winner not in match
        vm.stopPrank();
    }
    
    function testReportQuestCompletion() public {
        uint256 questId = 123;
        bytes32 questHash = keccak256(abi.encodePacked(player1, questId, block.timestamp));
        
        vm.startPrank(oracle1);
        vm.expectEmit(true, true, true, false);
        emit QuestCompletionReported(questHash, player1, questId);
        
        oracle.reportQuestCompletion(player1, questId, 100 * 10**18);
        vm.stopPrank();
        
        GameOracle.QuestCompletion memory completion = oracle.getQuestCompletion(questHash);
        assertEq(completion.player, player1);
        assertEq(completion.questId, questId);
        assertEq(completion.rewardAmount, 100 * 10**18);
        assertTrue(completion.verified);
    }
    
    function testUpdateMarketData() public {
        uint256 itemId = 1;
        
        vm.startPrank(oracle1);
        vm.expectEmit(true, true, false, false);
        emit MarketDataUpdated(itemId, 100 * 10**18, 50 * 10**18);
        
        oracle.updateMarketData(itemId, 100 * 10**18, 50 * 10**18, 10);
        vm.stopPrank();
        
        GameOracle.MarketData memory marketData = oracle.getMarketData(itemId);
        assertEq(marketData.averagePrice, 100 * 10**18);
        assertEq(marketData.volume24h, 50 * 10**18);
        assertEq(marketData.totalListings, 10);
    }
    
    function testStakeAsOracle() public {
        vm.startPrank(oracle1);
        vm.expectEmit(true, true, false, false);
        emit OracleStakeUpdated(oracle1, 1000 * 10**18);
        
        oracle.stakeAsOracle(1000 * 10**18);
        vm.stopPrank();
        
        assertEq(oracle.getOracleReputation(oracle1), 100);
        assertEq(oracle.oracleStake(oracle1), 1000 * 10**18);
    }
    
    function testSetRequiredConfirmations() public {
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false);
        emit RequiredConfirmationsUpdated(3);
        
        oracle.setRequiredConfirmations(3);
        vm.stopPrank();
        
        assertEq(oracle.requiredConfirmations(), 3);
    }
    
    function testCannotSetZeroConfirmations() public {
        vm.startPrank(owner);
        vm.expectRevert("Must require at least 1 confirmation");
        oracle.setRequiredConfirmations(0);
        vm.stopPrank();
    }
    
    function testGetPvPResultNotVerified() public {
        bytes32 matchId = keccak256(abi.encodePacked("match4"));
        
        // Report but don't verify
        vm.startPrank(oracle1);
        oracle.reportPvPResult(matchId, player1, player2, player1);
        vm.stopPrank();
        
        // Try to get unverified result
        vm.expectRevert("Result not verified");
        oracle.getVerifiedPvPResult(matchId);
    }
    
    function testPauseUnpause() public {
        vm.startPrank(owner);
        oracle.pause();
        assertTrue(oracle.paused());
        
        vm.stopPrank();
        
        // Try to report while paused
        bytes32 matchId = keccak256(abi.encodePacked("match5"));
        vm.startPrank(oracle1);
        vm.expectRevert("Pausable: paused");
        oracle.reportPvPResult(matchId, player1, player2, player1);
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        oracle.unpause();
        assertFalse(oracle.paused());
        vm.stopPrank();
    }
    
    function testFuzzPvPReporting(address playerA, address playerB) public {
        vm.assume(playerA != playerB && playerA != address(0) && playerB != address(0));
        
        bytes32 matchId = keccak256(abi.encodePacked("fuzzMatch"));
        
        // First oracle reports
        vm.startPrank(oracle1);
        oracle.reportPvPResult(matchId, playerA, playerB, playerA);
        vm.stopPrank();
        
        // Second oracle confirms
        vm.startPrank(oracle2);
        oracle.reportPvPResult(matchId, playerA, playerB, playerA);
        vm.stopPrank();
        
        assertTrue(oracle.isPvPResultVerified(matchId));
    }
}
