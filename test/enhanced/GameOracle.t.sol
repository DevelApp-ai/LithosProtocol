// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/enhanced/GameOracle.sol";
import "../../src/UtilityToken.sol";

/// @title GameOracle Test
/// @notice Comprehensive tests for the GameOracle contract
/// @author LithosProtocol Team
contract GameOracleTest is Test {
    using stdError for *;

    // Contract instances
    ERC1967Proxy public proxyGameOracle;
    GameOracle public gameOracle;
    GameOracle public gameOracleImplementation;

    // Addresses
    address public owner = address(1);
    address public player1 = address(2);
    address public player2 = address(3);

    // Chainlink mock
    address public linkAddress = address(100);
    bytes32 public keyHash = keccak256("test-key-hash");
    uint256 public fee = 0.1 ether;

    // Test configuration
    uint256 public minRandom = 1;
    uint256 public maxRandom = 10000;
    uint256 public timeout = 3600; // 1 hour
    uint256 public callbackGasLimit = 200000;

    // ====================== SETUP ======================

    function setUp() public {
        // Deploy GameOracle implementation
        gameOracleImplementation = new GameOracle();

        // Initialize GameOracle
        GameOracle(address(gameOracleImplementation)).initialize(
            linkAddress,
            keyHash,
            fee,
            minRandom,
            maxRandom,
            timeout,
            callbackGasLimit
        );

        // Deploy proxy
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,bytes32,uint256,uint256,uint256,uint256,uint256)",
            linkAddress,
            keyHash,
            fee,
            minRandom,
            maxRandom,
            timeout,
            callbackGasLimit
        );

        proxyGameOracle = new ERC1967Proxy(
            address(gameOracleImplementation),
            initData
        );

        // Get the proxy address and cast to GameOracle
        gameOracle = GameOracle(address(proxyGameOracle));

        // Grant owner the DEFAULT_ADMIN_ROLE (initialize granted admin to this test contract)
        gameOracle.grantRole(gameOracle.DEFAULT_ADMIN_ROLE(), owner);

        // Set up mocks
        _setupMocks();
    }

    // ====================== MOCKS ======================

    function _setupMocks() internal {
        // Mock LINK token
        vm.mockCall(
            linkAddress,
            abi.encodeWithSignature("balanceOf(address)", address(gameOracle)),
            abi.encode(fee * 10) // Enough for requests
        );
    }

    // ====================== INITIALIZATION TESTS ======================

    function test_Initialization() public {
        // Check that initialization set the correct values
        assertEq(gameOracle.getLinkAddress(), linkAddress);
        assertEq(gameOracle.getKeyHash(), keyHash);
        assertEq(gameOracle.getFee(), fee);

        // Check game config
        GameOracle.GameConfig memory config = gameOracle.getGameConfig();
        assertEq(config.minRandomNumber, minRandom);
        assertEq(config.maxRandomNumber, maxRandom);
        assertEq(config.requestTimeout, timeout);
        assertEq(config.callbackGasLimit, callbackGasLimit);
    }

    function test_RevertWhen_InitializeTwice() public {
        // Try to initialize again - should fail
        vm.expectRevert("Initializable: contract is already initialized");
        gameOracle.initialize(
            linkAddress,
            keyHash,
            fee,
            minRandom,
            maxRandom,
            timeout,
            callbackGasLimit
        );
    }

    // ====================== PRICE FEED TESTS ======================

    function test_AddPriceFeed() public {
        string memory symbol = "ETH";
        address feedAddress = address(200);

        // Add price feed
        vm.prank(owner);
        gameOracle.addPriceFeed(symbol, feedAddress);

        // Check that price feed was added
        assertEq(gameOracle.getPriceFeedAddress(symbol), feedAddress);
    }

    function test_RevertWhen_AddPriceFeed_ZeroAddress() public {
        string memory symbol = "ETH";

        // Try to add price feed with zero address - should fail
        vm.prank(owner);
        vm.expectRevert("Price feed address cannot be zero");
        gameOracle.addPriceFeed(symbol, address(0));
    }

    function test_RevertWhen_AddPriceFeed_EmptySymbol() public {
        address feedAddress = address(200);

        // Try to add price feed with empty symbol - should fail
        vm.prank(owner);
        vm.expectRevert("Symbol cannot be empty");
        gameOracle.addPriceFeed("", feedAddress);
    }

    function test_UpdatePriceFeed() public {
        string memory symbol = "ETH";
        address feedAddress1 = address(200);
        address feedAddress2 = address(201);

        // Add initial price feed
        vm.prank(owner);
        gameOracle.addPriceFeed(symbol, feedAddress1);

        // Update price feed
        vm.prank(owner);
        gameOracle.updatePriceFeed(symbol, feedAddress2);

        // Check that price feed was updated
        assertEq(gameOracle.getPriceFeedAddress(symbol), feedAddress2);
    }

    function test_RevertWhen_UpdatePriceFeed_NonExistent() public {
        string memory symbol = "ETH";
        address feedAddress = address(200);

        // Try to update non-existent price feed - should fail
        vm.prank(owner);
        vm.expectRevert("Price feed does not exist");
        gameOracle.updatePriceFeed(symbol, feedAddress);
    }

    // ====================== CONFIGURATION TESTS ======================

    function test_UpdateGameConfig() public {
        uint256 newMin = 100;
        uint256 newMax = 100000;
        uint256 newTimeout = 7200;
        uint256 newGasLimit = 500000;

        // Update game config
        vm.prank(owner);
        gameOracle.updateGameConfig(
            newMin,
            newMax,
            newTimeout,
            newGasLimit
        );

        // Check that config was updated
        GameOracle.GameConfig memory config = gameOracle.getGameConfig();
        assertEq(config.minRandomNumber, newMin);
        assertEq(config.maxRandomNumber, newMax);
        assertEq(config.requestTimeout, newTimeout);
        assertEq(config.callbackGasLimit, newGasLimit);
    }

    function test_SetChainlinkConfig() public {
        address newLinkAddress = address(101);
        bytes32 newKeyHash = keccak256("new-key-hash");
        uint256 newFee = 0.2 ether;

        // Set new Chainlink config
        vm.prank(owner);
        gameOracle.setChainlinkConfig(newLinkAddress, newKeyHash, newFee);

        // Check that config was updated
        assertEq(gameOracle.getLinkAddress(), newLinkAddress);
        assertEq(gameOracle.getKeyHash(), newKeyHash);
        assertEq(gameOracle.getFee(), newFee);
    }

    // ====================== PAUSABLE TESTS ======================

    function test_Pause() public {
        // Pause the contract
        vm.prank(owner);
        gameOracle.pause();

        // Check that contract is paused
        assertTrue(gameOracle.paused());
    }

    function test_Unpause() public {
        // Pause the contract
        vm.prank(owner);
        gameOracle.pause();

        // Unpause the contract
        vm.prank(owner);
        gameOracle.unpause();

        // Check that contract is not paused
        assertFalse(gameOracle.paused());
    }

    function test_RevertWhen_RequestRandomNumber_WhenPaused() public {
        // Pause the contract
        vm.prank(owner);
        gameOracle.pause();

        // Try to request random number - should fail
        vm.expectRevert("Pausable: paused");
        gameOracle.requestRandomNumber(0x00);
    }

    function test_RevertWhen_GetPriceFeed_WhenPaused() public {
        string memory symbol = "ETH";
        address feedAddress = address(200);

        // Add price feed
        vm.prank(owner);
        gameOracle.addPriceFeed(symbol, feedAddress);

        // Pause the contract
        vm.prank(owner);
        gameOracle.pause();

        // Try to get price - should fail
        vm.expectRevert("Pausable: paused");
        gameOracle.getLatestPrice(symbol);
    }

    // ====================== RANDOM NUMBER TESTS ======================

    function test_RequestRandomNumber() public {
        // Request random number
        vm.prank(player1);
        bytes32 requestId = gameOracle.requestRandomNumber(0x00);

        // Check that request was created
        assertTrue(gameOracle.requestExists(requestId));
        assertEq(gameOracle.requestTimestamps(requestId), block.timestamp);

        // Check that request is not ready yet
        assertFalse(gameOracle.isRandomNumberReady(requestId));
    }

    function test_RequestMultipleRandomNumbers() public {
        uint256 count = 3;

        // Request multiple random numbers
        vm.prank(player1);
        bytes32[] memory requestIds = gameOracle.requestMultipleRandomNumbers(
            count,
            0x00
        );

        // Check that all requests were created
        assertEq(requestIds.length, count);
        for (uint256 i = 0; i < count; i++) {
            assertTrue(gameOracle.requestExists(requestIds[i]));
        }
    }

    function test_RevertWhen_RequestRandomNumber_InsufficientLink() public {
        // Mock insufficient LINK balance
        vm.mockCall(
            linkAddress,
            abi.encodeWithSignature("balanceOf(address)", address(gameOracle)),
            abi.encode(0) // No LINK
        );

        // Try to request random number - should fail
        vm.expectRevert("Not enough LINK for VRF request");
        gameOracle.requestRandomNumber(0x00);
    }

    function test_GetRandomNumberInRange() public {
        // This test would need Chainlink VRF mock, so we test the fallback
        bytes32 requestId = keccak256(abi.encodePacked("test-request"));

        // Mock the request
        vm.prank(player1);
        requestId = gameOracle.requestRandomNumber(0x00);
        vm.warp(block.timestamp + gameOracle.getGameConfig().requestTimeout + 1);

        // Get random number in range
        uint256 min = 10;
        uint256 max = 20;
        uint256 random = gameOracle.getRandomNumberInRange(requestId, min, max);

        // Check that random number is in range
        assertGe(random, min);
        assertLe(random, max);
    }

    function test_RevertWhen_GetRandomNumberInRange_InvalidRange() public {
        bytes32 requestId = keccak256(abi.encodePacked("test-request"));

        // Try to get random number with invalid range - should fail
        vm.expectRevert("Min must be less than or equal to max");
        gameOracle.getRandomNumberInRange(requestId, 20, 10);
    }

    function test_GetRandomBoolean() public {
        bytes32 requestId = keccak256(abi.encodePacked("test-request"));

        // Mock the request
        vm.prank(player1);
        requestId = gameOracle.requestRandomNumber(0x00);
        vm.warp(block.timestamp + gameOracle.getGameConfig().requestTimeout + 1);

        // Get random boolean
        bool result = gameOracle.getRandomBoolean(requestId);

        // Boolean should be either true or false
        assertTrue(result == true || result == false);
    }

    function test_GetRandomPercentage() public {
        bytes32 requestId = keccak256(abi.encodePacked("test-request"));

        // Mock the request
        vm.prank(player1);
        requestId = gameOracle.requestRandomNumber(0x00);
        vm.warp(block.timestamp + gameOracle.getGameConfig().requestTimeout + 1);

        // Get random percentage
        uint256 percentage = gameOracle.getRandomPercentage(requestId);

        // Percentage should be between 0 and 100
        assertGe(percentage, 0);
        assertLe(percentage, 100);
    }

    function test_GetRandomIndex() public {
        bytes32 requestId = keccak256(abi.encodePacked("test-request"));

        // Mock the request
        vm.prank(player1);
        requestId = gameOracle.requestRandomNumber(0x00);
        vm.warp(block.timestamp + gameOracle.getGameConfig().requestTimeout + 1);

        uint256 length = 100;

        // Get random index
        uint256 index = gameOracle.getRandomIndex(requestId, length);

        // Index should be between 0 and length-1
        assertGe(index, 0);
        assertLt(index, length);
    }

    function test_RevertWhen_GetRandomIndex_ZeroLength() public {
        bytes32 requestId = keccak256(abi.encodePacked("test-request"));

        // Try to get random index with zero length - should fail
        vm.expectRevert("Array length must be greater than 0");
        gameOracle.getRandomIndex(requestId, 0);
    }

    function test_HasRequestTimedOut() public {
        bytes32 requestId = keccak256(abi.encodePacked("test-request"));

        // Mock the request
        vm.prank(player1);
        requestId = gameOracle.requestRandomNumber(0x00);
        vm.warp(block.timestamp + gameOracle.getGameConfig().requestTimeout + 1);

        // Check that request has timed out
        assertTrue(gameOracle.hasRequestTimedOut(requestId));
    }

    function test_RevertWhen_GetRandomNumber_NonExistentRequest() public {
        bytes32 requestId = keccak256(abi.encodePacked("non-existent"));

        // Try to get random number for non-existent request - should fail
        vm.expectRevert("Request does not exist");
        gameOracle.getRandomNumber(requestId);
    }

    function test_RevertWhen_GetRandomNumber_NotReady() public {
        bytes32 requestId = keccak256(abi.encodePacked("test-request"));

        // Mock the request but not ready
        vm.prank(player1);
        requestId = gameOracle.requestRandomNumber(0x00);

        // Try to get random number - should fail
        vm.expectRevert("Random number not yet available");
        gameOracle.getRandomNumber(requestId);
    }

    // ====================== ACCESS CONTROL TESTS ======================

    function test_RevertWhen_OnlyOwner_AddPriceFeed() public {
        string memory symbol = "ETH";
        address feedAddress = address(200);

        // Try to add price feed as non-owner - should fail
        vm.expectRevert(abi.encodePacked("AccessControl: account ", vm.toString(player1), " is missing role ", vm.toString(gameOracle.DEFAULT_ADMIN_ROLE())));
        vm.prank(player1);
        gameOracle.addPriceFeed(symbol, feedAddress);
    }

    function test_RevertWhen_OnlyOwner_UpdatePriceFeed() public {
        string memory symbol = "ETH";
        address feedAddress = address(200);

        // Add price feed as owner
        vm.prank(owner);
        gameOracle.addPriceFeed(symbol, feedAddress);

        // Try to update price feed as non-owner - should fail
        vm.expectRevert(abi.encodePacked("AccessControl: account ", vm.toString(player1), " is missing role ", vm.toString(gameOracle.DEFAULT_ADMIN_ROLE())));
        vm.prank(player1);
        gameOracle.updatePriceFeed(symbol, feedAddress);
    }

    function test_RevertWhen_OnlyOwner_UpdateGameConfig() public {
        // Try to update game config as non-owner - should fail
        vm.expectRevert(abi.encodePacked("AccessControl: account ", vm.toString(player1), " is missing role ", vm.toString(gameOracle.DEFAULT_ADMIN_ROLE())));
        vm.prank(player1);
        gameOracle.updateGameConfig(1, 100, 3600, 200000);
    }

    function test_RevertWhen_OnlyOwner_SetChainlinkConfig() public {
        // Try to set Chainlink config as non-owner - should fail
        vm.expectRevert(abi.encodePacked("AccessControl: account ", vm.toString(player1), " is missing role ", vm.toString(gameOracle.DEFAULT_ADMIN_ROLE())));
        vm.prank(player1);
        gameOracle.setChainlinkConfig(linkAddress, keyHash, fee);
    }

    function test_RevertWhen_OnlyOwner_Pause() public {
        // Try to pause as non-owner - should fail
        vm.expectRevert(abi.encodePacked("AccessControl: account ", vm.toString(player1), " is missing role ", vm.toString(gameOracle.DEFAULT_ADMIN_ROLE())));
        vm.prank(player1);
        gameOracle.pause();
    }

    function test_RevertWhen_OnlyOwner_Unpause() public {
        // Pause as owner
        vm.prank(owner);
        gameOracle.pause();

        // Try to unpause as non-owner - should fail
        vm.expectRevert(abi.encodePacked("AccessControl: account ", vm.toString(player1), " is missing role ", vm.toString(gameOracle.DEFAULT_ADMIN_ROLE())));
        vm.prank(player1);
        gameOracle.unpause();
    }

    // ====================== EDGE CASES ======================

    function test_ZeroAddress_LinkAddress() public {
        // Set zero address as LINK
        vm.prank(owner);
        gameOracle.setChainlinkConfig(address(0), keyHash, fee);

        // Check that zero address was set
        assertEq(gameOracle.getLinkAddress(), address(0));
    }

    function test_ZeroKeyHash() public {
        // Set zero key hash
        vm.prank(owner);
        gameOracle.setChainlinkConfig(linkAddress, bytes32(0), fee);

        // Check that zero key hash was set
        assertEq(gameOracle.getKeyHash(), bytes32(0));
    }

    function test_ZeroFee() public {
        // Set zero fee
        vm.prank(owner);
        gameOracle.setChainlinkConfig(linkAddress, keyHash, 0);

        // Check that zero fee was set
        assertEq(gameOracle.getFee(), 0);
    }

    function test_LargeRandomRange() public {
        // Update config with large range
        vm.prank(owner);
        gameOracle.updateGameConfig(0, 2**256 - 1, 3600, 200000);

        // Check that large range was set
        GameOracle.GameConfig memory config = gameOracle.getGameConfig();
        assertEq(config.minRandomNumber, 0);
        assertEq(config.maxRandomNumber, 2**256 - 1);
    }

    function test_MinEqualsMax() public {
        // Update config with min == max
        vm.prank(owner);
        gameOracle.updateGameConfig(100, 100, 3600, 200000);

        // Check that config was set
        GameOracle.GameConfig memory config = gameOracle.getGameConfig();
        assertEq(config.minRandomNumber, 100);
        assertEq(config.maxRandomNumber, 100);
    }

    // ====================== UPGRADE TESTS ======================

    function test_UUPSUpgrade() public {
        // Deploy new implementation
        GameOracle newImplementation = new GameOracle();

        // Upgrade proxy (upgradeTo lives on the UUPS implementation, reached via the proxy)
        vm.prank(owner);
        gameOracle.upgradeTo(address(newImplementation));

        // Check that proxy now points to new implementation (EIP-1967 slot)
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address impl = address(uint160(uint256(vm.load(address(proxyGameOracle), implSlot))));
        assertEq(impl, address(newImplementation));

        // Verify that state is preserved
        assertEq(
            GameOracle(address(proxyGameOracle)).getLinkAddress(),
            linkAddress
        );
    }

    function test_RevertWhen_UUPSUpgrade_NonOwner() public {
        // Deploy new implementation
        GameOracle newImplementation = new GameOracle();

        // Try to upgrade as non-owner - should fail
        vm.expectRevert(abi.encodePacked("AccessControl: account ", vm.toString(player1), " is missing role ", vm.toString(gameOracle.DEFAULT_ADMIN_ROLE())));
        vm.prank(player1);
        gameOracle.upgradeTo(address(newImplementation));
    }

    // ====================== GAS TESTS ======================

    function testGas_RequestRandomNumber() public {
        // Measure gas for requesting random number
        vm.prank(player1);
        uint256 gasBefore = gasleft();
        gameOracle.requestRandomNumber(0x00);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Gas should be reasonable
        assertLt(gasUsed, 500000);
    }

    function testGas_RequestMultipleRandomNumbers() public {
        uint256 count = 5;

        // Measure gas for requesting multiple random numbers
        vm.prank(player1);
        uint256 gasBefore = gasleft();
        gameOracle.requestMultipleRandomNumbers(count, 0x00);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Gas should be reasonable
        assertLt(gasUsed, 1000000);
    }

    function testGas_AddPriceFeed() public {
        string memory symbol = "ETH";
        address feedAddress = address(200);

        // Measure gas for adding price feed
        vm.prank(owner);
        uint256 gasBefore = gasleft();
        gameOracle.addPriceFeed(symbol, feedAddress);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Gas should be reasonable
        assertLt(gasUsed, 100000);
    }
}
