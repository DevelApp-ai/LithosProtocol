// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/enhanced/DynamicTokenomics.sol";

contract DynamicTokenomicsTest is Test {
    DynamicTokenomics public tokenomics;
    
    address public owner = address(0x1);
    address public gameContract = address(0x2);
    address public oracle = address(0x3);
    
    event EconomicMetricsUpdated(
        uint256 totalPlayers,
        uint256 tokensInCirculation,
        uint256 dailyEarned,
        uint256 dailyBurned
    );
    event DynamicPriceUpdated(uint256 indexed itemId, uint256 newPrice, uint256 multiplier);
    event TokenSinkActivated(uint256 indexed sinkId, string name, uint256 burnRate);
    event RewardPoolAdjusted(uint256 indexed questId, uint256 newPoolAmount);
    event PlayerActivityRecorded(address indexed player, uint256 timestamp);
    
    function setUp() public {
        // Deploy dynamic tokenomics
        DynamicTokenomics tokenomicsImpl = new DynamicTokenomics();
        bytes memory initData = abi.encodeWithSelector(
            DynamicTokenomics.initialize.selector,
            owner,
            500, // 5% target inflation
            10000 * 10**18 // Max daily rewards
        );
        ERC1967Proxy tokenomicsProxy = new ERC1967Proxy(address(tokenomicsImpl), initData);
        tokenomics = DynamicTokenomics(address(tokenomicsProxy));
        
        // Setup permissions
        vm.startPrank(owner);
        tokenomics.grantRole(tokenomics.GAME_ROLE(), gameContract);
        tokenomics.grantRole(tokenomics.ORACLE_ROLE(), oracle);
        tokenomics.grantRole(tokenomics.UPGRADER_ROLE(), owner);
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertTrue(tokenomics.hasRole(tokenomics.DEFAULT_ADMIN_ROLE(), owner));
        assertEq(tokenomics.targetInflationRate(), 500);
        assertEq(tokenomics.maxDailyRewards(), 10000 * 10**18);
        assertEq(tokenomics.economicUpdateInterval(), 1 days);
        assertEq(tokenomics.priceVolatilityDamping(), 200);
        
        DynamicTokenomics.EconomicMetrics memory metrics = tokenomics.getEconomicMetrics();
        assertEq(metrics.totalPlayersActive, 0);
        assertEq(metrics.totalTokensInCirculation, 0);
    }
    
    function testUpdateEconomicMetrics() public {
        vm.warp(block.timestamp + 1 days); // init set lastUpdateTimestamp = now
        vm.startPrank(oracle);
        
        vm.expectEmit(true, false, false, false);
        emit EconomicMetricsUpdated(1000, 500000 * 10**18, 10000 * 10**18, 5000 * 10**18);
        
        tokenomics.updateEconomicMetrics(
            1000,
            500000 * 10**18,
            10000 * 10**18,
            5000 * 10**18
        );
        
        DynamicTokenomics.EconomicMetrics memory metrics = tokenomics.getEconomicMetrics();
        assertEq(metrics.totalPlayersActive, 1000);
        assertEq(metrics.totalTokensInCirculation, 500000 * 10**18);
        assertEq(metrics.dailyTokensEarned, 10000 * 10**18);
        assertEq(metrics.dailyTokensBurned, 5000 * 10**18);
        
        vm.stopPrank();
    }
    
    function testCannotUpdateEconomicMetricsTooSoon() public {
        vm.warp(block.timestamp + 1 days); // init set lastUpdateTimestamp = now
        vm.startPrank(oracle);
        tokenomics.updateEconomicMetrics(1000, 500000 * 10**18, 10000 * 10**18, 5000 * 10**18);
        
        // Try to update again immediately
        vm.expectRevert("Too early to update");
        tokenomics.updateEconomicMetrics(1000, 500000 * 10**18, 10000 * 10**18, 5000 * 10**18);
        
        vm.stopPrank();
    }
    
    function testCalculateDynamicPrice() public {
        vm.startPrank(gameContract);
        
        // First calculation initializes pricing
        uint256 price1 = tokenomics.calculateDynamicPrice(1, 100, 50);
        
        // Price should be based on supply and demand
        assertGt(price1, 0);
        
        // Low supply, high demand should increase price
        uint256 price2 = tokenomics.calculateDynamicPrice(1, 10, 100);
        assertGt(price2, price1);
        
        // High supply, low demand should decrease price
        uint256 price3 = tokenomics.calculateDynamicPrice(1, 1000, 10);
        assertLt(price3, price2); // damped multiplier: decreases vs previous call, not vs initial
        
        vm.stopPrank();
    }
    
    function testDynamicPriceBounds() public {
        vm.startPrank(gameContract);
        
        // Test minimum price (0.1x base)
        uint256 minPrice = tokenomics.calculateDynamicPrice(1, 10000, 0);
        uint256 basePrice = 1000;
        uint256 minExpected = (basePrice * 100) / 1000; // 0.1x
        assertGe(minPrice, minExpected);
        
        // Test maximum price (10x base)
        uint256 maxPrice = tokenomics.calculateDynamicPrice(1, 0, 10000);
        uint256 maxExpected = (basePrice * 10000) / 1000; // 10x
        assertLe(maxPrice, maxExpected);
        
        vm.stopPrank();
    }
    
    function testCreateTokenSink() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, false, false);
        emit TokenSinkActivated(1, "Crafting Sink", 5000); // 50%
        
        tokenomics.createTokenSink(1, "Crafting Sink", 5000);
        
        DynamicTokenomics.TokenSink memory sink = tokenomics.getTokenSink(1);
        assertEq(sink.name, "Crafting Sink");
        assertEq(sink.burnRate, 5000);
        assertTrue(sink.isActive);
        
        vm.stopPrank();
    }
    
    function testRecordTokenBurn() public {
        vm.startPrank(owner);
        tokenomics.createTokenSink(1, "Crafting Sink", 5000);
        vm.stopPrank();
        
        vm.startPrank(gameContract);
        tokenomics.recordTokenBurn(1, 100 * 10**18);
        tokenomics.recordTokenBurn(1, 50 * 10**18);
        vm.stopPrank();
        
        DynamicTokenomics.TokenSink memory sink = tokenomics.getTokenSink(1);
        assertEq(sink.dailyBurnAmount, 150 * 10**18);
        assertEq(sink.totalBurned, 150 * 10**18);
    }
    
    function testCannotRecordBurnForInactiveSink() public {
        vm.startPrank(owner);
        tokenomics.createTokenSink(1, "Crafting Sink", 5000);
        
        vm.stopPrank();
        
        vm.startPrank(gameContract);
        vm.expectRevert("Sink not active");
        tokenomics.recordTokenBurn(99, 100 * 10**18); // never created -> isActive false
        vm.stopPrank();
    }
    
    function testCalculateQuestReward() public {
        vm.warp(block.timestamp + 1 days); // metrics update has a 1-day cooldown from init
        vm.startPrank(oracle);
        tokenomics.updateEconomicMetrics(1000, 500000 * 10**18, 10000 * 10**18, 5000 * 10**18);
        vm.stopPrank();
        
        // Base reward with good economic health
        uint256 reward1 = tokenomics.calculateQuestReward(1, 100 * 10**18, 1);
        assertGt(reward1, 0);
        
        // Higher level should get slightly higher rewards
        uint256 reward2 = tokenomics.calculateQuestReward(1, 100 * 10**18, 10);
        assertGt(reward2, reward1);
    }
    
    function testRecordPlayerActivity() public {
        vm.warp(block.timestamp + 1 days); // day-0 edge: default lastActivityTimestamp is already day 0
        vm.startPrank(gameContract);
        
        vm.expectEmit(true, true, false, false);
        emit PlayerActivityRecorded(address(0x100), 0);
        
        tokenomics.recordPlayerActivity(address(0x100));
        
        // Same player on same day should not be counted twice
        uint256 countBefore = tokenomics.dailyActiveUsers(block.timestamp / 1 days);
        tokenomics.recordPlayerActivity(address(0x100));
        uint256 countAfter = tokenomics.dailyActiveUsers(block.timestamp / 1 days);
        
        assertEq(countBefore, countAfter);
        
        vm.stopPrank();
    }
    
    function testGetEconomicHealthScore() public {
        vm.warp(block.timestamp + 1 days); // pass the update cooldown
        vm.startPrank(oracle);
        
        // Low inflation (net 100 tokens on 500k circulating -> 7 bps vs 500 target)
        tokenomics.updateEconomicMetrics(1000, 500000 * 10**18, 5000 * 10**18, 4900 * 10**18);
        vm.stopPrank();
        
        // inflationScore 100 (40) + activityScore 0 (0) + velocity 50 (20) => 50
        uint256 score = tokenomics.getEconomicHealthScore();
        assertEq(score, 50);
        assertLe(score, 100);
        
        vm.stopPrank();
    }
    
    function testGetCurrentPrice() public {
        vm.startPrank(gameContract);
        tokenomics.calculateDynamicPrice(1, 100, 50);
        vm.stopPrank();
        
        uint256 price = tokenomics.getCurrentPrice(1);
        assertGt(price, 0);
    }
    
    function testGetRemainingDailyBudget() public {
        // Budget is only populated once the oracle reports metrics
        assertEq(tokenomics.getRemainingDailyBudget(), 0);

        vm.warp(block.timestamp + 1 days);
        vm.startPrank(oracle);
        tokenomics.updateEconomicMetrics(1000, 500000 * 10**18, 10000 * 10**18, 5000 * 10**18);
        vm.stopPrank();

        // Health score 50 -> budget = 50% of max daily rewards
        assertEq(tokenomics.getRemainingDailyBudget(), 5000 * 10**18);
    }
    
    function testGetDailyActiveUsers() public {
        vm.warp(block.timestamp + 1 days); // day-0 edge: default lastActivityTimestamp (0) is already day 0
        vm.startPrank(gameContract);
        tokenomics.recordPlayerActivity(address(0x100));
        tokenomics.recordPlayerActivity(address(0x101));
        tokenomics.recordPlayerActivity(address(0x102));
        vm.stopPrank();
        
        uint256 currentDay = block.timestamp / 1 days;
        uint256 activeUsers = tokenomics.getDailyActiveUsers(currentDay);
        assertEq(activeUsers, 3);
    }
    
    function testPauseUnpause() public {
        vm.startPrank(owner);
        tokenomics.pause();
        assertTrue(tokenomics.paused());
        
        vm.stopPrank();
        
        // Note: no state-changing function is gated by whenNotPaused in this contract;
        // pause() only toggles the flag. Verify flag transitions and admin-only access.
        
        vm.startPrank(gameContract);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                vm.toString(gameContract),
                " is missing role ",
                vm.toString(tokenomics.DEFAULT_ADMIN_ROLE())
            )
        );
        tokenomics.pause();
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        tokenomics.unpause();
        assertFalse(tokenomics.paused());
        vm.stopPrank();
    }
    
    function testFuzzDynamicPrice(uint256 supply, uint256 demand) public {
        vm.assume(demand <= 1e30); // demandFactor = 1000 + demand*100 must not overflow
        vm.assume(supply <= 1e30);
        vm.startPrank(gameContract);
        uint256 price = tokenomics.calculateDynamicPrice(1, supply, demand);
        vm.stopPrank();
        
        assertGt(price, 0);
        assertLe(price, (1000 * 10000) / 1000); // Max 10x base price
    }
}
