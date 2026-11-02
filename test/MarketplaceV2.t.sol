// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/MarketplaceV2.sol";
import "../src/GameAssetNFT.sol";
import "../src/GameResourceNFT.sol";

contract MarketplaceV2Test is Test {
    MarketplaceV2 public marketplace;
    GameAssetNFT public gameAssetNFT;
    GameResourceNFT public gameResourceNFT;
    
    address public owner = address(0x1);
    address public seller = address(0x2);
    address public buyer = address(0x3);
    address public bidder1 = address(0x4);
    address public bidder2 = address(0x5);
    address public feeRecipient = address(0x6);
    
    event ItemListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        MarketplaceV2.ListingType listingType
    );
    event DutchAuctionStarted(
        uint256 indexed listingId,
        uint256 startingPrice,
        uint256 endingPrice,
        uint256 duration
    );
    event BulkListingCreated(
        uint256 indexed bulkId,
        address indexed seller,
        uint256 itemCount,
        uint256 pricePerItem
    );
    event ItemSold(
        uint256 indexed listingId,
        address indexed seller,
        address indexed buyer,
        uint256 price,
        uint256 fee
    );
    event BulkItemSold(
        uint256 indexed bulkId,
        address indexed seller,
        address indexed buyer,
        uint256 itemCount,
        uint256 totalPrice
    );
    event ItemDelisted(uint256 indexed listingId, address indexed seller);
    event BulkListingCancelled(uint256 indexed bulkId, address indexed seller);
    event BidPlaced(
        uint256 indexed listingId,
        address indexed bidder,
        uint256 amount
    );
    event AuctionEnded(
        uint256 indexed listingId,
        address indexed winner,
        uint256 winningBid
    );
    event DutchAuctionEnded(
        uint256 indexed listingId,
        address indexed winner,
        uint256 finalPrice
    );
    
    function setUp() public {
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
        
        // Deploy marketplace V2
        MarketplaceV2 marketplaceImpl = new MarketplaceV2();
        bytes memory marketplaceInitData = abi.encodeWithSelector(
            MarketplaceV2.initialize.selector,
            owner,
            250, // 2.5% fee
            feeRecipient
        );
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(address(marketplaceImpl), marketplaceInitData);
        marketplace = MarketplaceV2(address(marketplaceProxy));
        
        // Setup permissions
        vm.startPrank(owner);
        gameAssetNFT.grantRole(gameAssetNFT.MINTER_ROLE(), owner);
        gameResourceNFT.grantRole(gameResourceNFT.MINTER_ROLE(), owner);
        marketplace.grantRole(marketplace.MODERATOR_ROLE(), owner);
        vm.stopPrank();
        
        // Fund test participants
        vm.deal(seller, 1000 ether);
        vm.deal(buyer, 1000 ether);
        vm.deal(bidder1, 1000 ether);
        vm.deal(bidder2, 1000 ether);
    }
    
    function testInitialization() public {
        assertEq(marketplace.marketplaceFee(), 250);
        assertEq(marketplace.feeRecipient(), feeRecipient);
        assertEq(marketplace.owner(), owner);
        assertEq(marketplace.nextListingId(), 1);
    }
    
    // ========== DUTCH AUCTION TESTS ==========
    
    function testListDutchAuctionERC721() public {
        // Mint NFT to seller
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            seller,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        // List for Dutch auction
        vm.startPrank(seller);
        gameAssetNFT.approve(address(marketplace), tokenId);
        
        vm.expectEmit(true, true, true, false);
        emit ItemListed(1, seller, address(gameAssetNFT), tokenId, 1, 100 * 10**18, MarketplaceV2.ListingType.DUTCH_AUCTION);
        emit DutchAuctionStarted(1, 100 * 10**18, 10 * 10**18, 1 days);
        
        uint256 listingId = marketplace.listDutchAuctionERC721(
            address(gameAssetNFT),
            tokenId,
            100 * 10**18, // Starting price
            10 * 10**18,  // Ending price
            1 days,
            address(0) // ETH
        );
        
        assertEq(listingId, 1);
        
        MarketplaceV2.Listing memory listing = marketplace.getListing(listingId);
        assertEq(uint256(listing.listingType), uint256(MarketplaceV2.ListingType.DUTCH_AUCTION));
        assertEq(listing.price, 100 * 10**18);
        assertEq(listing.endPrice, 10 * 10**18);
        assertEq(listing.endTime, block.timestamp + 1 days);
        
        MarketplaceV2.DutchAuction memory auction = marketplace.getDutchAuction(listingId);
        assertEq(auction.startingPrice, 100 * 10**18);
        assertEq(auction.endingPrice, 10 * 10**18);
        assertTrue(auction.isActive);
        
        vm.stopPrank();
    }
    
    function testListDutchAuctionERC1155() public {
        // Create and mint resource
        vm.startPrank(owner);
        uint256 resourceId = gameResourceNFT.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            0,
            "Iron Ore",
            "Basic crafting material"
        );
        gameResourceNFT.mintResource(seller, resourceId, 100);
        vm.stopPrank();
        
        // List for Dutch auction
        vm.startPrank(seller);
        gameResourceNFT.setApprovalForAll(address(marketplace), true);
        
        vm.expectEmit(true, true, true, false);
        emit ItemListed(1, seller, address(gameResourceNFT), resourceId, 50, 100 * 10**18, MarketplaceV2.ListingType.DUTCH_AUCTION);
        emit DutchAuctionStarted(1, 100 * 10**18, 10 * 10**18, 1 days);
        
        uint256 listingId = marketplace.listDutchAuctionERC1155(
            address(gameResourceNFT),
            resourceId,
            50,
            100 * 10**18,
            10 * 10**18,
            1 days,
            address(0)
        );
        
        assertEq(listingId, 1);
        
        MarketplaceV2.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.amount, 50);
        assertEq(uint256(listing.assetType), uint256(MarketplaceV2.AssetType.ERC1155));
        
        vm.stopPrank();
    }
    
    function testGetDutchAuctionPrice() public {
        // Setup Dutch auction
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            seller,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        vm.startPrank(seller);
        gameAssetNFT.approve(address(marketplace), tokenId);
        uint256 listingId = marketplace.listDutchAuctionERC721(
            address(gameAssetNFT),
            tokenId,
            100 * 10**18,
            10 * 10**18,
            100, // 100 seconds
            address(0)
        );
        vm.stopPrank();
        
        // Check initial price
        uint256 initialPrice = marketplace.getDutchAuctionPrice(listingId);
        assertEq(initialPrice, 100 * 10**18);
        
        // Fast forward 50 seconds
        vm.warp(block.timestamp + 50);
        
        // Check price decreased
        uint256 halfPrice = marketplace.getDutchAuctionPrice(listingId);
        assertEq(halfPrice, 55 * 10**18); // (100 + 10) / 2 = 55
        
        // Fast forward to the exact auction end (price may be queried at endTime)
        vm.warp(block.timestamp + 50);
        
        // Price should be the ending price
        uint256 endPrice = marketplace.getDutchAuctionPrice(listingId);
        assertEq(endPrice, 10 * 10**18);
        
        vm.stopPrank();
    }
    
    function testBuyFromDutchAuction() public {
        // Setup Dutch auction
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            seller,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        vm.startPrank(seller);
        gameAssetNFT.approve(address(marketplace), tokenId);
        uint256 listingId = marketplace.listDutchAuctionERC721(
            address(gameAssetNFT),
            tokenId,
            100 * 10**18,
            50 * 10**18,
            100,
            address(0)
        );
        vm.stopPrank();
        
        // Fast forward to get lower price
        vm.warp(block.timestamp + 50);
        
        // Buy from Dutch auction
        vm.startPrank(buyer);
        
        uint256 currentPrice = marketplace.getDutchAuctionPrice(listingId);
        
        vm.expectEmit(true, true, true, false);
        emit ItemSold(listingId, seller, buyer, currentPrice, 0);
        emit DutchAuctionEnded(listingId, buyer, currentPrice);
        
        marketplace.buyFromDutchAuction{value: currentPrice}(listingId);
        
        // Check NFT transferred
        assertEq(gameAssetNFT.ownerOf(tokenId), buyer);
        
        // Check seller received payment minus fee
        assertGt(seller.balance, 0);
        
        // Check fee recipient received fee
        assertGt(feeRecipient.balance, 0);
        
        // Check listing inactive
        MarketplaceV2.Listing memory _sold = marketplace.getListing(listingId);
        assertFalse(_sold.isActive);
        MarketplaceV2.DutchAuction memory _auction = marketplace.getDutchAuction(listingId);
        assertFalse(_auction.isActive);
        
        vm.stopPrank();
    }
    
    function testCannotBuyFromDutchAuctionWithLowPrice() public {
        // Setup Dutch auction
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            seller,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        vm.startPrank(seller);
        gameAssetNFT.approve(address(marketplace), tokenId);
        uint256 listingId = marketplace.listDutchAuctionERC721(
            address(gameAssetNFT),
            tokenId,
            100 * 10**18,
            50 * 10**18,
            100,
            address(0)
        );
        vm.stopPrank();
        
        // Try to buy with insufficient funds
        vm.startPrank(buyer);
        uint256 currentPrice = marketplace.getDutchAuctionPrice(listingId);
        vm.expectRevert("Insufficient payment");
        marketplace.buyFromDutchAuction{value: currentPrice - 1}(listingId);
        vm.stopPrank();
    }
    
    // ========== BULK OPERATIONS TESTS ==========
    
    function testCreateBulkListingERC721() public {
        // Mint multiple NFTs to seller
        vm.startPrank(owner);
        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = gameAssetNFT.mintAsset(
                seller,
                GameAssetNFT.AssetType.CHARACTER,
                1,
                string(abi.encodePacked("https://example.com/character", i, ".json"))
            );
        }
        vm.stopPrank();
        
        // Create bulk listing
        vm.startPrank(seller);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            gameAssetNFT.approve(address(marketplace), tokenIds[i]);
        }
        
        vm.expectEmit(true, false, false, false);
        emit BulkListingCreated(1, seller, 3, 50 * 10**18);
        
        uint256 bulkId = marketplace.createBulkListingERC721(
            address(gameAssetNFT),
            tokenIds,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            50 * 10**18,
            0
        );
        
        assertEq(bulkId, 1);
        
        MarketplaceV2.BulkListing memory bulk = marketplace.getBulkListing(bulkId);
        assertEq(bulk.seller, seller);
        assertEq(bulk.tokenIds.length, 3);
        assertEq(bulk.pricePerItem, 50 * 10**18);
        assertTrue(bulk.isActive);
        
        vm.stopPrank();
    }
    
    function testCreateBulkListingERC1155() public {
        // Create and mint multiple resources
        vm.startPrank(owner);
        uint256 resourceId = gameResourceNFT.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            0,
            "Iron Ore",
            "Basic crafting material"
        );
        gameResourceNFT.mintResource(seller, resourceId, 100);
        vm.stopPrank();
        
        // Create bulk listing
        vm.startPrank(seller);
        gameResourceNFT.setApprovalForAll(address(marketplace), true);
        
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        tokenIds[0] = resourceId;
        tokenIds[1] = resourceId;
        amounts[0] = 10;
        amounts[1] = 20;
        
        vm.expectEmit(true, false, false, false);
        emit BulkListingCreated(1, seller, 2, 10 * 10**18);
        
        uint256 bulkId = marketplace.createBulkListingERC1155(
            address(gameResourceNFT),
            tokenIds,
            amounts,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            10 * 10**18,
            0
        );
        
        assertEq(bulkId, 1);
        
        MarketplaceV2.BulkListing memory bulk = marketplace.getBulkListing(bulkId);
        assertEq(bulk.amounts.length, 2);
        assertEq(bulk.amounts[0], 10);
        assertEq(bulk.amounts[1], 20);
        
        vm.stopPrank();
    }
    
    function testBuyBulkListing() public {
        // Setup bulk listing
        vm.startPrank(owner);
        uint256[] memory tokenIds = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            tokenIds[i] = gameAssetNFT.mintAsset(
                seller,
                GameAssetNFT.AssetType.CHARACTER,
                1,
                string(abi.encodePacked("https://example.com/character", i, ".json"))
            );
        }
        vm.stopPrank();
        
        vm.startPrank(seller);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            gameAssetNFT.approve(address(marketplace), tokenIds[i]);
        }
        uint256 bulkId = marketplace.createBulkListingERC721(
            address(gameAssetNFT),
            tokenIds,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            50 * 10**18,
            0
        );
        vm.stopPrank();
        
        // Buy all items
        vm.startPrank(buyer);
        
        uint256 totalPrice = 50 * 10**18 * tokenIds.length;
        
        vm.expectEmit(true, true, false, false);
        emit BulkItemSold(bulkId, seller, buyer, tokenIds.length, totalPrice);
        
        marketplace.buyBulkListing{value: totalPrice}(bulkId);
        
        // Check all NFTs transferred
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(gameAssetNFT.ownerOf(tokenIds[i]), buyer);
        }
        
        // Check seller received payment minus fee
        assertGt(seller.balance, 0);
        
        // Check bulk listing inactive
        MarketplaceV2.BulkListing memory _bulk = marketplace.getBulkListing(bulkId);
        assertFalse(_bulk.isActive);
        
        vm.stopPrank();
    }
    
    function testBuyFromBulkListing() public {
        // Setup bulk listing
        vm.startPrank(owner);
        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = gameAssetNFT.mintAsset(
                seller,
                GameAssetNFT.AssetType.CHARACTER,
                1,
                string(abi.encodePacked("https://example.com/character", i, ".json"))
            );
        }
        vm.stopPrank();
        
        vm.startPrank(seller);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            gameAssetNFT.approve(address(marketplace), tokenIds[i]);
        }
        uint256 bulkId = marketplace.createBulkListingERC721(
            address(gameAssetNFT),
            tokenIds,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            50 * 10**18,
            0
        );
        vm.stopPrank();
        
        // Buy specific items (first and third)
        vm.startPrank(buyer);
        
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 2;
        
        uint256 totalPrice = 50 * 10**18 * 2;
        
        vm.expectEmit(true, true, false, false);
        emit BulkItemSold(bulkId, seller, buyer, 2, totalPrice);
        
        marketplace.buyFromBulkListing{value: totalPrice}(bulkId, indices);
        
        // Check selected NFTs transferred
        assertEq(gameAssetNFT.ownerOf(tokenIds[0]), buyer);
        assertEq(gameAssetNFT.ownerOf(tokenIds[2]), buyer);
        assertEq(gameAssetNFT.ownerOf(tokenIds[1]), seller); // Still owned by seller
        
        vm.stopPrank();
    }
    
    function testCancelBulkListing() public {
        // Setup bulk listing
        vm.startPrank(owner);
        uint256[] memory tokenIds = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            tokenIds[i] = gameAssetNFT.mintAsset(
                seller,
                GameAssetNFT.AssetType.CHARACTER,
                1,
                string(abi.encodePacked("https://example.com/character", i, ".json"))
            );
        }
        vm.stopPrank();
        
        vm.startPrank(seller);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            gameAssetNFT.approve(address(marketplace), tokenIds[i]);
        }
        uint256 bulkId = marketplace.createBulkListingERC721(
            address(gameAssetNFT),
            tokenIds,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            50 * 10**18,
            0
        );
        
        // Cancel bulk listing
        vm.expectEmit(true, true, false, false);
        emit BulkListingCancelled(bulkId, seller);
        
        marketplace.cancelBulkListing(bulkId);
        
        MarketplaceV2.BulkListing memory _bulk = marketplace.getBulkListing(bulkId);
        assertFalse(_bulk.isActive);
        
        // NFTs should still be owned by seller
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(gameAssetNFT.ownerOf(tokenIds[i]), seller);
        }
        
        vm.stopPrank();
    }
    
    // ========== SEARCH AND FILTER TESTS ==========
    
    function testSetListingMetadata() public {
        // Setup listing
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            seller,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        vm.startPrank(seller);
        gameAssetNFT.approve(address(marketplace), tokenId);
        uint256 listingId = marketplace.listERC721(
            address(gameAssetNFT),
            tokenId,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            100 * 10**18,
            0
        );
        vm.stopPrank();
        
        // Set metadata
        vm.startPrank(owner);
        marketplace.setListingMetadata(
            listingId,
            "Legendary Sword",
            "A powerful sword",
            1, // category: Weapons
            5, // rarity: Legendary
            10, // level
            true // verified
        );
        vm.stopPrank();
        
        MarketplaceV2.ListingMetadata memory metadata = marketplace.getListingMetadata(listingId);
        assertEq(metadata.name, "Legendary Sword");
        assertEq(metadata.categoryId, 1);
        assertEq(metadata.rarity, 5);
    }
    
    function testSearchByName() public {
        // Setup listings with metadata
        vm.startPrank(owner);
        
        // Create and list NFT
        uint256 tokenId = gameAssetNFT.mintAsset(
            owner,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        gameAssetNFT.approve(address(marketplace), tokenId);
        uint256 listingId = marketplace.listERC721(
            address(gameAssetNFT),
            tokenId,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            100 * 10**18,
            0
        );
        
        // Set metadata
        marketplace.setListingMetadata(
            listingId,
            "Legendary Sword",
            "A powerful sword",
            1,
            5,
            10,
            true
        );
        
        vm.stopPrank();
        
        // Search by name
        uint256[] memory results = marketplace.searchByName("Legendary Sword");
        assertEq(results.length, 1);
        assertEq(results[0], listingId);
    }
    
    function testFilterByCategory() public {
        // Setup listings with different categories
        vm.startPrank(owner);
        
        // List NFT with category 1
        uint256 tokenId1 = gameAssetNFT.mintAsset(
            owner,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        gameAssetNFT.approve(address(marketplace), tokenId1);
        uint256 listingId1 = marketplace.listERC721(
            address(gameAssetNFT),
            tokenId1,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            100 * 10**18,
            0
        );
        marketplace.setListingMetadata(listingId1, "Sword", "A sword", 1, 3, 5, true);
        
        // List NFT with category 2
        uint256 tokenId2 = gameAssetNFT.mintAsset(
            owner,
            GameAssetNFT.AssetType.LAND,
            1,
            "https://example.com/land1.json"
        );
        gameAssetNFT.approve(address(marketplace), tokenId2);
        uint256 listingId2 = marketplace.listERC721(
            address(gameAssetNFT),
            tokenId2,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            200 * 10**18,
            0
        );
        marketplace.setListingMetadata(listingId2, "Land", "A land", 2, 4, 10, true);
        
        vm.stopPrank();
        
        // Filter by category 1
        uint256[] memory category1 = marketplace.filterByCategory(1);
        assertEq(category1.length, 1);
        assertEq(category1[0], listingId1);
        
        // Filter by category 2
        uint256[] memory category2 = marketplace.filterByCategory(2);
        assertEq(category2.length, 1);
        assertEq(category2[0], listingId2);
    }
    
    function testFilterByRarity() public {
        // Setup listings with different rarities
        vm.startPrank(owner);
        
        // List common NFT
        uint256 tokenId1 = gameAssetNFT.mintAsset(
            owner,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        gameAssetNFT.approve(address(marketplace), tokenId1);
        uint256 listingId1 = marketplace.listERC721(
            address(gameAssetNFT),
            tokenId1,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            100 * 10**18,
            0
        );
        marketplace.setListingMetadata(listingId1, "Common", "Common item", 1, 1, 1, true);
        
        // List legendary NFT
        uint256 tokenId2 = gameAssetNFT.mintAsset(
            owner,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character2.json"
        );
        gameAssetNFT.approve(address(marketplace), tokenId2);
        uint256 listingId2 = marketplace.listERC721(
            address(gameAssetNFT),
            tokenId2,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            1000 * 10**18,
            0
        );
        marketplace.setListingMetadata(listingId2, "Legendary", "Legendary item", 1, 5, 20, true);
        
        vm.stopPrank();
        
        // Filter by rarity 5 (legendary)
        uint256[] memory legendary = marketplace.filterByRarity(5);
        assertEq(legendary.length, 1);
        assertEq(legendary[0], listingId2);
        
        // Filter by rarity 1 (common)
        uint256[] memory common = marketplace.filterByRarity(1);
        assertEq(common.length, 1);
        assertEq(common[0], listingId1);
    }
    
    function testAdvancedSearch() public {
        // Setup multiple listings with various attributes
        vm.startPrank(owner);
        
        // List 4 NFTs with different attributes
        uint256[] memory tokenIds = new uint256[](4);
        uint256[] memory listingIds = new uint256[](4);
        
        for (uint256 i = 0; i < 4; i++) {
            tokenIds[i] = gameAssetNFT.mintAsset(
                owner,
                GameAssetNFT.AssetType.CHARACTER,
                1,
                string(abi.encodePacked("https://example.com/character", i, ".json"))
            );
            gameAssetNFT.approve(address(marketplace), tokenIds[i]);
            listingIds[i] = marketplace.listERC721(
                address(gameAssetNFT),
                tokenIds[i],
                MarketplaceV2.ListingType.FIXED_PRICE,
                address(0),
                100 * 10**18,
                0
            );
        }
        
        // Set metadata with different attributes
        marketplace.setListingMetadata(listingIds[0], "Sword", "A sword", 1, 3, 10, true);  // Category 1, Rarity 3
        marketplace.setListingMetadata(listingIds[1], "Shield", "A shield", 1, 2, 5, true);   // Category 1, Rarity 2
        marketplace.setListingMetadata(listingIds[2], "Land", "A land", 2, 4, 15, false);     // Category 2, Rarity 4, not verified
        marketplace.setListingMetadata(listingIds[3], "Potion", "A potion", 3, 1, 1, true);    // Category 3, Rarity 1
        
        vm.stopPrank();
        
        // Search: Category 1, Rarity >= 2, Verified only
        uint256[] memory results = marketplace.advancedSearch(1, 2, 5, true);
        assertEq(results.length, 2); // Sword and Shield
        
        // Search: Category 1, Rarity >= 3, Verified only
        results = marketplace.advancedSearch(1, 3, 5, true);
        assertEq(results.length, 1); // Only Sword
    }
    
    // ========== LEGACY FUNCTIONS TESTS ==========
    
    function testBuyItemFixedPrice() public {
        // Setup listing
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            seller,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        vm.startPrank(seller);
        gameAssetNFT.approve(address(marketplace), tokenId);
        uint256 listingId = marketplace.listERC721(
            address(gameAssetNFT),
            tokenId,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            100 * 10**18,
            0
        );
        vm.stopPrank();
        
        // Buy item
        vm.startPrank(buyer);
        
        vm.expectEmit(true, true, true, false);
        emit ItemSold(listingId, seller, buyer, 100 * 10**18, 25000000000000000); // 2.5% fee
        
        marketplace.buyItem{value: 100 * 10**18}(listingId);
        
        // Check NFT transferred
        assertEq(gameAssetNFT.ownerOf(tokenId), buyer);
        
        vm.stopPrank();
    }
    
    function testPlaceBidAndEndAuction() public {
        // Setup auction
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            seller,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        vm.startPrank(seller);
        gameAssetNFT.approve(address(marketplace), tokenId);
        uint256 listingId = marketplace.listERC721(
            address(gameAssetNFT),
            tokenId,
            MarketplaceV2.ListingType.AUCTION,
            address(0),
            10 * 10**18,
            100
        );
        vm.stopPrank();
        
        // Place bid
        vm.startPrank(bidder1);
        
        vm.expectEmit(true, true, true, false);
        emit BidPlaced(listingId, bidder1, 15 * 10**18);
        
        marketplace.placeBid{value: 15 * 10**18}(listingId);
        
        vm.stopPrank();
        
        // Fast forward past auction end
        vm.warp(block.timestamp + 101);
        
        // End auction
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, false);
        emit AuctionEnded(listingId, bidder1, 15 * 10**18);
        
        marketplace.endAuction(listingId);
        
        // Check NFT transferred
        assertEq(gameAssetNFT.ownerOf(tokenId), bidder1);
        
        vm.stopPrank();
    }
    
    function testPauseUnpause() public {
        vm.startPrank(owner);
        marketplace.pause();
        assertTrue(marketplace.paused());
        
        vm.stopPrank();
        
        // Try to list while paused
        vm.startPrank(seller);
        vm.expectRevert("Pausable: paused");
        marketplace.listERC721(
            address(gameAssetNFT),
            1,
            MarketplaceV2.ListingType.FIXED_PRICE,
            address(0),
            100 * 10**18,
            0
        );
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        marketplace.unpause();
        assertFalse(marketplace.paused());
        vm.stopPrank();
    }
    
    function testFuzzDutchAuctionPrice(uint256 startingPrice, uint256 endingPrice, uint256 duration) public {
        vm.assume(startingPrice > endingPrice);
        vm.assume(duration > 0);
        vm.assume(startingPrice <= 1e30);
        vm.assume(duration <= 365 days);
        
        // Setup Dutch auction
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            seller,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        vm.startPrank(seller);
        gameAssetNFT.approve(address(marketplace), tokenId);
        uint256 listingId = marketplace.listDutchAuctionERC721(
            address(gameAssetNFT),
            tokenId,
            startingPrice,
            endingPrice,
            duration,
            address(0)
        );
        vm.stopPrank();
        
        // Check initial price
        uint256 initialPrice = marketplace.getDutchAuctionPrice(listingId);
        assertEq(initialPrice, startingPrice);
        
        // Fast forward to the exact auction end
        vm.warp(block.timestamp + duration);
        
        // Check final price
        uint256 finalPrice = marketplace.getDutchAuctionPrice(listingId);
        assertEq(finalPrice, endingPrice);
    }
}
