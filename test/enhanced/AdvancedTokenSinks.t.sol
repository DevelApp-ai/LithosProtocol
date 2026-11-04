// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/enhanced/AdvancedTokenSinks.sol";
import "../../src/UtilityToken.sol";

contract AdvancedTokenSinksTest is Test {
    AdvancedTokenSinks public tokenSinks;
    UtilityToken public utilityToken;
    
    address public owner = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public gameContract = address(0x4);
    
    event CosmeticPurchased(address indexed player, uint256 indexed itemId, uint256 price);
    event TournamentEntered(address indexed player, uint256 indexed tournamentId, uint256 entryFee);
    event AssetRented(address indexed renter, address indexed owner, uint256 indexed assetId, uint256 dailyRate);
    event ConvenienceActivated(address indexed player, uint256 indexed featureId, uint256 duration);
    event TokensBurned(string category, uint256 amount, address indexed player);
    
    function setUp() public {
        // Deploy utility token
        UtilityToken utilityImpl = new UtilityToken();
        bytes memory utilityInitData = abi.encodeWithSelector(
            UtilityToken.initialize.selector,
            owner,
            "Aetherium Play",
            "PLAY",
            1000000 * 10**18
        );
        ERC1967Proxy utilityProxy = new ERC1967Proxy(address(utilityImpl), utilityInitData);
        utilityToken = UtilityToken(address(utilityProxy));
        
        // Deploy advanced token sinks
        AdvancedTokenSinks sinksImpl = new AdvancedTokenSinks();
        bytes memory sinksInitData = abi.encodeWithSelector(
            AdvancedTokenSinks.initialize.selector,
            owner,
            address(utilityToken)
        );
        ERC1967Proxy sinksProxy = new ERC1967Proxy(address(sinksImpl), sinksInitData);
        tokenSinks = AdvancedTokenSinks(address(sinksProxy));
        
        // Setup permissions
        vm.startPrank(owner);
        tokenSinks.grantRole(tokenSinks.GAME_ROLE(), gameContract);
        tokenSinks.grantRole(tokenSinks.UPGRADER_ROLE(), owner);
        utilityToken.grantRole(utilityToken.MINTER_ROLE(), address(tokenSinks));
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(address(tokenSinks.utilityToken()), address(utilityToken));
        assertTrue(tokenSinks.hasRole(tokenSinks.DEFAULT_ADMIN_ROLE(), owner));
        assertEq(tokenSinks.nextCosmeticId(), 1);
        assertEq(tokenSinks.nextTournamentId(), 1);
        assertEq(tokenSinks.nextRentalId(), 1);
        assertEq(tokenSinks.totalTokensBurned(), 0);
    }
    
    function testCreateCosmeticItem() public {
        vm.startPrank(owner);
        tokenSinks.createCosmeticItem("Golden Sword Skin", 100 * 10**18, 1);
        vm.stopPrank();
        
        AdvancedTokenSinks.CosmeticItem memory item = tokenSinks.getCosmeticItem(1);
        assertEq(item.name, "Golden Sword Skin");
        assertEq(item.price, 100 * 10**18);
        assertTrue(item.isActive);
        assertEq(item.categoryId, 1);
        assertEq(tokenSinks.nextCosmeticId(), 2);
    }
    
    function testPurchaseCosmetic() public {
        // Create cosmetic item
        vm.startPrank(owner);
        tokenSinks.createCosmeticItem("Golden Sword Skin", 100 * 10**18, 1);
        vm.stopPrank();
        
        // Give player tokens
        vm.startPrank(owner);
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        // Approve token sinks
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        
        vm.expectEmit(true, true, true, false);
        emit CosmeticPurchased(player1, 1, 100 * 10**18);
        
        tokenSinks.purchaseCosmetic(1);
        
        // Check player owns cosmetic
        assertTrue(tokenSinks.hasCosmetic(player1, 1));
        
        // Check tokens burned (tracked)
        assertEq(tokenSinks.getTotalBurnByCategory("cosmetics"), 100 * 10**18);
        assertEq(tokenSinks.totalTokensBurned(), 100 * 10**18);
        
        vm.stopPrank();
    }
    
    function testCannotPurchaseSameCosmeticTwice() public {
        // Create cosmetic item
        vm.startPrank(owner);
        tokenSinks.createCosmeticItem("Golden Sword Skin", 100 * 10**18, 1);
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        tokenSinks.purchaseCosmetic(1);
        
        // Try to purchase again
        vm.expectRevert("Already owned");
        tokenSinks.purchaseCosmetic(1);
        
        vm.stopPrank();
    }
    
    function testCannotPurchaseInactiveItem() public {
        // Create cosmetic item
        vm.startPrank(owner);
        tokenSinks.createCosmeticItem("Golden Sword Skin", 100 * 10**18, 1);
        
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        
        // Item 2 was never created; its default isActive is false
        vm.expectRevert("Item not available");
        tokenSinks.purchaseCosmetic(2);
        
        vm.stopPrank();
    }
    
    function testCreateTournament() public {
        vm.startPrank(gameContract);
        tokenSinks.createTournament(50 * 10**18, 100, 7 days);
        vm.stopPrank();
        
        AdvancedTokenSinks.TournamentEntry memory tournament = tokenSinks.getTournament(1);
        assertEq(tournament.entryFee, 50 * 10**18);
        assertEq(tournament.maxParticipants, 100);
        assertEq(tournament.isActive, true);
        assertEq(tokenSinks.nextTournamentId(), 2);
    }
    
    function testEnterTournament() public {
        // Create tournament
        vm.startPrank(gameContract);
        tokenSinks.createTournament(50 * 10**18, 100, 7 days);
        vm.stopPrank();
        
        // Give player tokens
        vm.startPrank(owner);
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        // Enter tournament
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        
        vm.expectEmit(true, true, true, false);
        emit TournamentEntered(player1, 1, 50 * 10**18);
        
        tokenSinks.enterTournament(1);
        
        // Check player registered
        uint256[] memory playerTournaments = tokenSinks.getPlayerTournaments(player1);
        assertEq(playerTournaments.length, 1);
        assertEq(playerTournaments[0], 1);
        
        // Check tournament data
        AdvancedTokenSinks.TournamentEntry memory tournament = tokenSinks.getTournament(1);
        assertEq(tournament.currentParticipants, 1);
        assertEq(tournament.prizePool, 25 * 10**18); // 50% of entry fee
        
        // Check tokens burned
        assertEq(tokenSinks.getTotalBurnByCategory("tournaments"), 25 * 10**18);
        
        vm.stopPrank();
    }
    
    function testCannotEnterFullTournament() public {
        // Create tournament with 2 participants max
        vm.startPrank(gameContract);
        tokenSinks.createTournament(50 * 10**18, 2, 7 days);
        vm.stopPrank();
        
        // Fill tournament
        vm.startPrank(owner);
        utilityToken.transfer(player1, 1000 * 10**18);
        utilityToken.transfer(player2, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        tokenSinks.enterTournament(1);
        vm.stopPrank();
        
        vm.startPrank(player2);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        tokenSinks.enterTournament(1);
        vm.stopPrank();
        
        // Try to enter full tournament
        vm.startPrank(owner);
        utilityToken.transfer(address(0x5), 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(address(0x5));
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        vm.expectRevert("Tournament full");
        tokenSinks.enterTournament(1);
        vm.stopPrank();
    }
    
    function testCreateAssetRental() public {
        vm.startPrank(gameContract);
        tokenSinks.createAssetRental(123, 10 * 10**18, 30); // Asset 123, 10 PLAY/day, max 30 days
        vm.stopPrank();
        
        AdvancedTokenSinks.AssetRental memory rental = tokenSinks.getAssetRental(1);
        assertEq(rental.assetId, 123);
        assertEq(rental.dailyRate, 10 * 10**18);
        assertEq(rental.duration, 30); // src stores maxDuration raw (days), not seconds
        assertEq(rental.owner, gameContract);
        assertTrue(rental.isActive);
        assertEq(tokenSinks.nextRentalId(), 2);
    }
    
    function testRentAsset() public {
        // Create rental
        vm.startPrank(gameContract);
        tokenSinks.createAssetRental(123, 10 * 10**18, 30);
        vm.stopPrank();
        
        // Give player tokens
        vm.startPrank(owner);
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        // Rent asset for 5 days
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        
        vm.expectEmit(true, true, true, false);
        emit AssetRented(player1, gameContract, 123, 10 * 10**18);
        
        tokenSinks.rentAsset(1, 5);
        
        // Check rental data
        AdvancedTokenSinks.AssetRental memory rental = tokenSinks.getAssetRental(1);
        assertEq(rental.renter, player1);
        assertEq(rental.duration, 5 days);
        
        // Check player rentals
        uint256[] memory playerRentals = tokenSinks.getPlayerRentals(player1);
        assertEq(playerRentals.length, 1);
        assertEq(playerRentals[0], 1);
        
        // Check tokens burned (10% of rental cost)
        // Total cost: 10 PLAY/day * 5 days = 50 PLAY
        // Burned: 5 PLAY (10%)
        // Owner receives: 45 PLAY
        assertEq(tokenSinks.getTotalBurnByCategory("rentals"), 5 * 10**18);
        
        vm.stopPrank();
    }
    
    function testCannotRentAlreadyRentedAsset() public {
        // Create rental
        vm.startPrank(gameContract);
        tokenSinks.createAssetRental(123, 10 * 10**18, 30);
        vm.stopPrank();
        
        // Rent it
        vm.startPrank(owner);
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        tokenSinks.rentAsset(1, 5);
        vm.stopPrank();
        
        // Try to rent again
        vm.startPrank(owner);
        utilityToken.transfer(player2, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player2);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        vm.expectRevert("Already rented");
        tokenSinks.rentAsset(1, 3);
        vm.stopPrank();
    }
    
    function testCreateConvenienceFeature() public {
        vm.startPrank(owner);
        tokenSinks.createConvenienceFeature("Auto-Loot", 50 * 10**18, 30 days);
        vm.stopPrank();
        
        AdvancedTokenSinks.ConvenienceFeature memory feature = tokenSinks.getConvenienceFeature(1);
        assertEq(feature.name, "Auto-Loot");
        assertEq(feature.price, 50 * 10**18);
        assertEq(feature.duration, 30 days);
        assertTrue(feature.isActive);
        assertEq(tokenSinks.nextConvenienceId(), 2);
    }
    
    function testActivateConvenienceFeature() public {
        // Create feature
        vm.startPrank(owner);
        tokenSinks.createConvenienceFeature("Auto-Loot", 50 * 10**18, 30 days);
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        // Activate feature
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        
        vm.expectEmit(true, true, true, false);
        emit ConvenienceActivated(player1, 1, 30 days);
        
        tokenSinks.activateConvenienceFeature(1);
        
        // Check feature active
        assertTrue(tokenSinks.isConvenienceActive(player1, 1));
        
        // Check tokens burned
        assertEq(tokenSinks.getTotalBurnByCategory("convenience"), 50 * 10**18);
        
        vm.stopPrank();
    }
    
    function testConvenienceFeatureExpiry() public {
        // Create and activate feature
        vm.startPrank(owner);
        tokenSinks.createConvenienceFeature("Auto-Loot", 50 * 10**18, 30 days);
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        tokenSinks.activateConvenienceFeature(1);
        vm.stopPrank();
        
        // Check active
        assertTrue(tokenSinks.isConvenienceActive(player1, 1));
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 31 days);
        
        // Check expired
        assertFalse(tokenSinks.isConvenienceActive(player1, 1));
    }
    
    function testBurnForGameMode() public {
        vm.startPrank(gameContract);
        tokenSinks.burnForGameMode(100 * 10**18, "Hard Mode");
        vm.stopPrank();
        
        // Check tokens burned
        assertEq(tokenSinks.getTotalBurnByCategory("Hard Mode"), 100 * 10**18);
        assertEq(tokenSinks.totalTokensBurned(), 100 * 10**18);
    }
    
    function testGetBurnStatistics() public {
        // Create and use various burn mechanisms
        vm.startPrank(owner);
        tokenSinks.createCosmeticItem("Skin 1", 50 * 10**18, 1);
        tokenSinks.createConvenienceFeature("Feature 1", 25 * 10**18, 30 days);
        vm.stopPrank();
        
        vm.startPrank(gameContract);
        tokenSinks.createTournament(10 * 10**18, 50, 7 days);
        tokenSinks.createAssetRental(123, 5 * 10**18, 30);
        tokenSinks.burnForGameMode(10 * 10**18, "Special Mode");
        vm.stopPrank();
        
        vm.startPrank(owner);
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        tokenSinks.purchaseCosmetic(1);
        tokenSinks.activateConvenienceFeature(1);
        tokenSinks.enterTournament(1);
        tokenSinks.rentAsset(1, 5);
        vm.stopPrank();
        
        // Get statistics
        (
            uint256 totalBurned,
            uint256 cosmeticsBurned,
            uint256 tournamentsBurned,
            uint256 rentalsBurned,
            uint256 convenienceBurned
        ) = tokenSinks.getBurnStatistics();
        
        assertEq(totalBurned, 925 * 10**17); // 50 + 25 + 5 + 2.5 + 10 (game-mode burn has no category bucket)
        assertEq(cosmeticsBurned, 50 * 10**18);
        assertEq(tournamentsBurned, 5 * 10**18); // 50% of 10
        assertEq(rentalsBurned, 2.5 * 10**18); // 10% of 25
        assertEq(convenienceBurned, 25 * 10**18);
    }
    
    function testIsAssetRented() public {
        // Create rental
        vm.startPrank(gameContract);
        tokenSinks.createAssetRental(123, 10 * 10**18, 30);
        vm.stopPrank();
        
        // Initially not rented
        assertFalse(tokenSinks.isAssetRented(123));
        
        // Rent it
        vm.startPrank(owner);
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        tokenSinks.rentAsset(1, 5);
        vm.stopPrank();
        
        // Check rented
        assertTrue(tokenSinks.isAssetRented(123));
        
        // Fast forward past rental
        vm.warp(block.timestamp + 6 days);
        
        // Check no longer rented
        assertFalse(tokenSinks.isAssetRented(123));
    }
    
    function testPauseUnpause() public {
        vm.startPrank(owner);
        tokenSinks.pause();
        assertTrue(tokenSinks.paused());
        
        vm.stopPrank();
        
        // Try to purchase while paused
        vm.startPrank(owner);
        tokenSinks.createCosmeticItem("Skin 1", 50 * 10**18, 1);
        utilityToken.transfer(player1, 1000 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), 1000 * 10**18);
        vm.expectRevert("Pausable: paused");
        tokenSinks.purchaseCosmetic(1);
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        tokenSinks.unpause();
        assertFalse(tokenSinks.paused());
        vm.stopPrank();
    }
    
    function testFuzzCosmeticPurchase(uint256 price) public {
        vm.assume(price > 0 && price <= 1000 * 10**18);
        
        vm.startPrank(owner);
        tokenSinks.createCosmeticItem("Test Skin", price, 1);
        utilityToken.transfer(player1, price * 2);
        vm.stopPrank();
        
        vm.startPrank(player1);
        utilityToken.approve(address(tokenSinks), price * 2);
        tokenSinks.purchaseCosmetic(1);
        
        assertTrue(tokenSinks.hasCosmetic(player1, 1));
        
        vm.stopPrank();
    }
}
