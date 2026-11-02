// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/Marketplace.sol";
import "../src/GameAssetNFT.sol";
import "../src/GameResourceNFT.sol";

contract MarketplaceTest is Test {
    Marketplace public marketplace;
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
        Marketplace.ListingType listingType
    );
    event ItemSold(
        uint256 indexed listingId,
        address indexed seller,
        address indexed buyer,
        uint256 price,
        uint256 fee
    );
    event ItemDelisted(uint256 indexed listingId, address indexed seller);
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
        
        // Deploy marketplace
        Marketplace marketplaceImpl = new Marketplace();
        bytes memory marketplaceInitData = abi.encodeWithSelector(
            Marketplace.initialize.selector,
            owner,
            250, // 2.5% fee
            feeRecipient
        );
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(address(marketplaceImpl), marketplaceInitData);
        marketplace = Marketplace(address(marketplaceProxy));
        
        // Setup permissions
        vm.startPrank(owner);
        gameAssetNFT.grantRole(gameAssetNFT.MINTER_ROLE(), owner);
        gameResourceNFT.grantRole(gameResourceNFT.MINTER_ROLE(), owner);
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
    
    function testListERC721() public {
        // Mint NFT to seller
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            seller,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        // Approve marketplace
        vm.startPrank(seller);
        gameAssetNFT.approve(address(marketplace), tokenId);
        
        vm.expectEmit(true, true, true, false);
        emit ItemListed(1, seller, address(gameAssetNFT), tokenId, 1, 100 * 10**18, Marketplace.ListingType.FIXED_PRICE);
        
        uint256 listingId = marketplace.listERC721(
            address(gameAssetNFT),
            tokenId,
            Marketplace.ListingType.FIXED_PRICE,
            address(0), // ETH
            100 * 10**18,
            0
        );
        
        assertEq(listingId, 1);
        
        Marketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.listingId, listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.nftContract, address(gameAssetNFT));
        assertEq(listing.tokenId, tokenId);
        assertEq(listing.amount, 1);
        assertEq(uint256(listing.assetType), uint256(Marketplace.AssetType.ERC721));
        assertEq(uint256(listing.listingType), uint256(Marketplace.ListingType.FIXED_PRICE));
        assertEq(listing.paymentToken, address(0));
        assertEq(listing.price, 100 * 10**18);
        assertTrue(listing.isActive);
        
        // Check user listings
        uint256[] memory userListings = marketplace.getUserListings(seller);
        assertEq(userListings.length, 1);
        assertEq(userListings[0], listingId);
        
        vm.stopPrank();
    }
    
    function testListERC1155() public {
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
        
        // Approve marketplace
        vm.startPrank(seller);
        gameResourceNFT.setApprovalForAll(address(marketplace), true);
        
        vm.expectEmit(true, true, true, false);
        emit ItemListed(1, seller, address(gameResourceNFT), resourceId, 50, 50 * 10**18, Marketplace.ListingType.FIXED_PRICE);
        
        uint256 listingId = marketplace.listERC1155(
            address(gameResourceNFT),
            resourceId,
            50,
            Marketplace.ListingType.FIXED_PRICE,
            address(0),
            50 * 10**18,
            0
        );
        
        assertEq(listingId, 1);
        
        Marketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.amount, 50);
        assertEq(uint256(listing.assetType), uint256(Marketplace.AssetType.ERC1155));
        
        vm.stopPrank();
    }
    
    function testBuyERC721WithETH() public {
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
            Marketplace.ListingType.FIXED_PRICE,
            address(0),
            100 * 10**18,
            0
        );
        vm.stopPrank();
        
        // Buy with ETH
        vm.startPrank(buyer);
        
        vm.expectEmit(true, true, true, false);
        emit ItemSold(listingId, seller, buyer, 100 * 10**18, 25000000000000000); // 2.5% fee
        
        marketplace.buyItem{value: 100 * 10**18}(listingId);
        
        // Check NFT transferred
        assertEq(gameAssetNFT.ownerOf(tokenId), buyer);
        
        // Check seller received payment (minus fee)
        assertEq(seller.balance, 1000 ether + 975 * 10**17); // 1000 dealt + 97.5 ETH proceeds
        
        // Check fee recipient received fee
        assertEq(feeRecipient.balance, 25 * 10**17); // 2.5 ETH fee
        
        // Check listing inactive
        Marketplace.Listing memory _purchased = marketplace.getListing(listingId);
        assertFalse(_purchased.isActive);
        
        vm.stopPrank();
    }
    
    function testBuyERC1155() public {
        // Setup listing
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
        
        vm.startPrank(seller);
        gameResourceNFT.setApprovalForAll(address(marketplace), true);
        uint256 listingId = marketplace.listERC1155(
            address(gameResourceNFT),
            resourceId,
            50,
            Marketplace.ListingType.FIXED_PRICE,
            address(0),
            50 * 10**18,
            0
        );
        vm.stopPrank();
        
        // Buy with ETH
        vm.startPrank(buyer);
        marketplace.buyItem{value: 50 * 10**18}(listingId);
        
        // Check resources transferred
        assertEq(gameResourceNFT.balanceOf(buyer, resourceId), 50);
        assertEq(gameResourceNFT.balanceOf(seller, resourceId), 50);
        
        vm.stopPrank();
    }
    
    function testAuctionListing() public {
        // Mint NFT to seller
        vm.startPrank(owner);
        uint256 tokenId = gameAssetNFT.mintAsset(
            seller,
            GameAssetNFT.AssetType.CHARACTER,
            1,
            "https://example.com/character1.json"
        );
        vm.stopPrank();
        
        // Create auction listing
        vm.startPrank(seller);
        gameAssetNFT.approve(address(marketplace), tokenId);
        uint256 listingId = marketplace.listERC721(
            address(gameAssetNFT),
            tokenId,
            Marketplace.ListingType.AUCTION,
            address(0),
            10 * 10**18, // Starting bid
            1 days
        );
        vm.stopPrank();
        
        Marketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(uint256(listing.listingType), uint256(Marketplace.ListingType.AUCTION));
        assertEq(listing.endTime, block.timestamp + 1 days);
    }
    
    function testPlaceBid() public {
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
            Marketplace.ListingType.AUCTION,
            address(0),
            10 * 10**18,
            1 days
        );
        vm.stopPrank();
        
        // Place first bid
        vm.startPrank(bidder1);
        vm.expectEmit(true, true, true, false);
        emit BidPlaced(listingId, bidder1, 15 * 10**18);
        
        marketplace.placeBid{value: 15 * 10**18}(listingId);
        
        Marketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.highestBidder, bidder1);
        assertEq(listing.highestBid, 15 * 10**18);
        
        vm.stopPrank();
        
        // Place higher bid
        vm.startPrank(bidder2);
        vm.expectEmit(true, true, true, false);
        emit BidPlaced(listingId, bidder2, 20 * 10**18);
        
        marketplace.placeBid{value: 20 * 10**18}(listingId);
        
        listing = marketplace.getListing(listingId);
        assertEq(listing.highestBidder, bidder2);
        assertEq(listing.highestBid, 20 * 10**18);
        
        // Check first bidder refunded
        assertEq(bidder1.balance, 1000 ether); // refunded after being outbid
        vm.stopPrank();
    }
    
    function testCannotBidBelowStartingPrice() public {
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
            Marketplace.ListingType.AUCTION,
            address(0),
            10 * 10**18,
            1 days
        );
        vm.stopPrank();
        
        // Try to bid below starting price
        vm.startPrank(bidder1);
        vm.expectRevert("Bid below starting price");
        marketplace.placeBid{value: 5 * 10**18}(listingId);
        vm.stopPrank();
    }
    
    function testEndAuction() public {
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
            Marketplace.ListingType.AUCTION,
            address(0),
            10 * 10**18,
            100 // 100 second auction
        );
        vm.stopPrank();
        
        // Place bid
        vm.startPrank(bidder1);
        marketplace.placeBid{value: 15 * 10**18}(listingId);
        vm.stopPrank();
        
        // Fast forward past auction end
        vm.warp(block.timestamp + 101);
        
        // End auction
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, false);
        emit AuctionEnded(listingId, bidder1, 15 * 10**18);
        
        marketplace.endAuction(listingId);
        
        // Check NFT transferred to winner
        assertEq(gameAssetNFT.ownerOf(tokenId), bidder1);
        
        // Check seller received payment minus fee
        assertEq(seller.balance, 1000 ether + (15 * 10**18) - (15 * 10**18 * 250) / 10000);
        
        // Check fee recipient received fee
        assertEq(feeRecipient.balance, (15 * 10**18 * 250) / 10000);
        
        vm.stopPrank();
    }
    
    function testCancelListing() public {
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
            Marketplace.ListingType.FIXED_PRICE,
            address(0),
            100 * 10**18,
            0
        );
        vm.stopPrank();
        
        // Cancel listing
        vm.startPrank(seller);
        vm.expectEmit(true, true, false, false);
        emit ItemDelisted(listingId, seller);
        
        marketplace.cancelListing(listingId);
        
        Marketplace.Listing memory _cancelled = marketplace.getListing(listingId);
        assertFalse(_cancelled.isActive);
        
        // NFT should be returned
        assertEq(gameAssetNFT.ownerOf(tokenId), seller);
        
        vm.stopPrank();
    }
    
    function testCancelAuctionWithRefund() public {
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
            Marketplace.ListingType.AUCTION,
            address(0),
            10 * 10**18,
            1 days
        );
        vm.stopPrank();
        
        // Place bid
        vm.startPrank(bidder1);
        marketplace.placeBid{value: 15 * 10**18}(listingId);
        vm.stopPrank();
        
        // Cancel auction
        vm.startPrank(seller);
        marketplace.cancelListing(listingId);
        
        // Check bidder refunded
        assertEq(bidder1.balance, 1000 ether);
        
        vm.stopPrank();
    }
    
    function testCannotBuyOwnItem() public {
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
            Marketplace.ListingType.FIXED_PRICE,
            address(0),
            100 * 10**18,
            0
        );
        
        // Try to buy own item
        vm.expectRevert("Cannot buy own item");
        marketplace.buyItem{value: 100 * 10**18}(listingId);
        
        vm.stopPrank();
    }
    
    function testCannotBuyInactiveListing() public {
        // Setup and cancel listing
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
            Marketplace.ListingType.FIXED_PRICE,
            address(0),
            100 * 10**18,
            0
        );
        marketplace.cancelListing(listingId);
        vm.stopPrank();
        
        // Try to buy inactive listing
        vm.startPrank(buyer);
        vm.expectRevert("Listing not active");
        marketplace.buyItem{value: 100 * 10**18}(listingId);
        vm.stopPrank();
    }
    
    function testUpdateMarketplaceFee() public {
        vm.startPrank(owner);
        marketplace.updateMarketplaceFee(500); // 5%
        assertEq(marketplace.marketplaceFee(), 500);
        vm.stopPrank();
    }
    
    function testUpdateFeeRecipient() public {
        address newRecipient = address(0x7);
        vm.startPrank(owner);
        marketplace.updateFeeRecipient(newRecipient);
        assertEq(marketplace.feeRecipient(), newRecipient);
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
            Marketplace.ListingType.FIXED_PRICE,
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
    
    function testFuzzListingPrice(uint256 price) public {
        vm.assume(price > 0 && price <= 1000 * 10**18);
        
        // Setup
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
            Marketplace.ListingType.FIXED_PRICE,
            address(0),
            price,
            0
        );
        
        Marketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.price, price);
        
        vm.stopPrank();
    }
}
