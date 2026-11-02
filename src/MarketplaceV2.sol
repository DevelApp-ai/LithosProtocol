// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MarketplaceV2
 * @dev Enhanced marketplace with Dutch auctions, bulk operations, and search capabilities
 */
contract MarketplaceV2 is 
    Initializable, 
    OwnableUpgradeable, 
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    // Marketplace fee (in basis points, e.g., 250 = 2.5%)
    uint256 public marketplaceFee;
    address public feeRecipient;

    // Listing counter
    uint256 public nextListingId;

    // Listing types
    enum ListingType { FIXED_PRICE, AUCTION, DUTCH_AUCTION }
    enum AssetType { ERC721, ERC1155 }

    // Listing structure
    struct Listing {
        uint256 listingId;
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 amount; // For ERC1155, 1 for ERC721
        AssetType assetType;
        ListingType listingType;
        address paymentToken; // Address(0) for ETH
        uint256 price; // Fixed price, starting bid, or starting price for Dutch
        uint256 endPrice; // For Dutch auctions: ending price
        uint256 endTime; // For auctions
        bool isActive;
        address highestBidder; // For auctions
        uint256 highestBid; // For auctions
    }

    // Dutch auction state
    struct DutchAuction {
        uint256 startingPrice;
        uint256 endingPrice;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }

    // Bulk listing structure
    struct BulkListing {
        uint256 bulkId;
        address seller;
        address nftContract;
        uint256[] tokenIds;
        uint256[] amounts;
        ListingType listingType;
        address paymentToken;
        uint256 pricePerItem;
        uint256 endTime;
        bool isActive;
        uint256 itemsSold;
    }

    // Search and filter data
    struct ListingMetadata {
        string name;
        string description;
        uint256 categoryId;
        uint256 rarity;
        uint256 level;
        bool isVerified;
    }

    // Mappings
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => DutchAuction) public dutchAuctions;
    mapping(uint256 => BulkListing) public bulkListings;
    mapping(address => uint256[]) public userListings;
    mapping(uint256 => mapping(address => uint256)) public auctionBids; // listingId => bidder => amount
    mapping(uint256 => ListingMetadata) public listingMetadata;

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getDutchAuction(uint256 listingId) external view returns (DutchAuction memory) {
        return dutchAuctions[listingId];
    }

    function getBulkListing(uint256 bulkId) external view returns (BulkListing memory) {
        return bulkListings[bulkId];
    }

    function getListingMetadata(uint256 listingId) external view returns (ListingMetadata memory) {
        return listingMetadata[listingId];
    }

    // Search index
    mapping(uint256 => uint256[]) public categoryListings; // categoryId => listingIds
    mapping(uint256 => uint256[]) public rarityListings; // rarity => listingIds
    mapping(string => uint256[]) public nameSearchIndex; // name keyword => listingIds

    // Events
    event ItemListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        ListingType listingType
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param initialOwner The initial owner of the contract
     * @param _marketplaceFee The marketplace fee in basis points
     * @param _feeRecipient The address to receive marketplace fees
     */
    function initialize(
        address initialOwner,
        uint256 _marketplaceFee,
        address _feeRecipient
    ) initializer public {
        __Ownable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _transferOwnership(initialOwner);

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(MODERATOR_ROLE, initialOwner);

        marketplaceFee = _marketplaceFee;
        feeRecipient = _feeRecipient;
        nextListingId = 1;
    }

    // ========== FIXED PRICE & AUCTION LISTINGS (Legacy) ==========

    /**
     * @dev List an ERC721 NFT for sale
     * @param nftContract The NFT contract address
     * @param tokenId The token ID to list
     * @param listingType Fixed price or auction
     * @param paymentToken Payment token address (address(0) for ETH)
     * @param price The price or starting bid
     * @param duration Duration for auctions (0 for fixed price)
     */
    function listERC721(
        address nftContract,
        uint256 tokenId,
        ListingType listingType,
        address paymentToken,
        uint256 price,
        uint256 duration
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(price > 0, "Price must be greater than 0");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not token owner");
        require(IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) || IERC721(nftContract).getApproved(tokenId) == address(this), "Not approved");

        uint256 listingId = nextListingId++;
        uint256 endTime = listingType == ListingType.AUCTION ? block.timestamp + duration : 0;

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            amount: 1,
            assetType: AssetType.ERC721,
            listingType: listingType,
            paymentToken: paymentToken,
            price: price,
            endPrice: 0,
            endTime: endTime,
            isActive: true,
            highestBidder: address(0),
            highestBid: 0
        });

        userListings[msg.sender].push(listingId);

        emit ItemListed(listingId, msg.sender, nftContract, tokenId, 1, price, listingType);

        return listingId;
    }

    /**
     * @dev List an ERC1155 NFT for sale
     * @param nftContract The NFT contract address
     * @param tokenId The token ID to list
     * @param amount The amount to list
     * @param listingType Fixed price or auction
     * @param paymentToken Payment token address (address(0) for ETH)
     * @param price The price or starting bid
     * @param duration Duration for auctions (0 for fixed price)
     */
    function listERC1155(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        ListingType listingType,
        address paymentToken,
        uint256 price,
        uint256 duration
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(price > 0, "Price must be greater than 0");
        require(amount > 0, "Amount must be greater than 0");
        require(IERC1155(nftContract).balanceOf(msg.sender, tokenId) >= amount, "Insufficient balance");
        require(IERC1155(nftContract).isApprovedForAll(msg.sender, address(this)), "Not approved");

        uint256 listingId = nextListingId++;
        uint256 endTime = listingType == ListingType.AUCTION ? block.timestamp + duration : 0;

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            assetType: AssetType.ERC1155,
            listingType: listingType,
            paymentToken: paymentToken,
            price: price,
            endPrice: 0,
            endTime: endTime,
            isActive: true,
            highestBidder: address(0),
            highestBid: 0
        });

        userListings[msg.sender].push(listingId);

        emit ItemListed(listingId, msg.sender, nftContract, tokenId, amount, price, listingType);

        return listingId;
    }

    // ========== DUTCH AUCTION ==========

    /**
     * @dev List an ERC721 NFT for Dutch auction
     * @param nftContract The NFT contract address
     * @param tokenId The token ID to list
     * @param startingPrice Starting price
     * @param endingPrice Ending price (must be < startingPrice)
     * @param duration Auction duration in seconds
     * @param paymentToken Payment token address (address(0) for ETH)
     */
    function listDutchAuctionERC721(
        address nftContract,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 endingPrice,
        uint256 duration,
        address paymentToken
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(startingPrice > endingPrice, "Ending price must be lower");
        require(duration > 0, "Duration must be positive");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not token owner");
        require(IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) || IERC721(nftContract).getApproved(tokenId) == address(this), "Not approved");

        uint256 listingId = nextListingId++;
        uint256 endTime = block.timestamp + duration;

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            amount: 1,
            assetType: AssetType.ERC721,
            listingType: ListingType.DUTCH_AUCTION,
            paymentToken: paymentToken,
            price: startingPrice,
            endPrice: endingPrice,
            endTime: endTime,
            isActive: true,
            highestBidder: address(0),
            highestBid: 0
        });

        dutchAuctions[listingId] = DutchAuction({
            startingPrice: startingPrice,
            endingPrice: endingPrice,
            startTime: block.timestamp,
            endTime: endTime,
            isActive: true
        });

        userListings[msg.sender].push(listingId);

        emit ItemListed(listingId, msg.sender, nftContract, tokenId, 1, startingPrice, ListingType.DUTCH_AUCTION);
        emit DutchAuctionStarted(listingId, startingPrice, endingPrice, duration);

        return listingId;
    }

    /**
     * @dev List an ERC1155 NFT for Dutch auction
     * @param nftContract The NFT contract address
     * @param tokenId The token ID to list
     * @param amount The amount to list
     * @param startingPrice Starting price
     * @param endingPrice Ending price
     * @param duration Auction duration in seconds
     * @param paymentToken Payment token address
     */
    function listDutchAuctionERC1155(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 startingPrice,
        uint256 endingPrice,
        uint256 duration,
        address paymentToken
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(startingPrice > endingPrice, "Ending price must be lower");
        require(duration > 0, "Duration must be positive");
        require(amount > 0, "Amount must be greater than 0");
        require(IERC1155(nftContract).balanceOf(msg.sender, tokenId) >= amount, "Insufficient balance");
        require(IERC1155(nftContract).isApprovedForAll(msg.sender, address(this)), "Not approved");

        uint256 listingId = nextListingId++;
        uint256 endTime = block.timestamp + duration;

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            assetType: AssetType.ERC1155,
            listingType: ListingType.DUTCH_AUCTION,
            paymentToken: paymentToken,
            price: startingPrice,
            endPrice: endingPrice,
            endTime: endTime,
            isActive: true,
            highestBidder: address(0),
            highestBid: 0
        });

        dutchAuctions[listingId] = DutchAuction({
            startingPrice: startingPrice,
            endingPrice: endingPrice,
            startTime: block.timestamp,
            endTime: endTime,
            isActive: true
        });

        userListings[msg.sender].push(listingId);

        emit ItemListed(listingId, msg.sender, nftContract, tokenId, amount, startingPrice, ListingType.DUTCH_AUCTION);
        emit DutchAuctionStarted(listingId, startingPrice, endingPrice, duration);

        return listingId;
    }

    /**
     * @dev Get current price for a Dutch auction
     * @param listingId The listing ID
     * @return The current price
     */
    function getDutchAuctionPrice(uint256 listingId) public view returns (uint256) {
        DutchAuction memory auction = dutchAuctions[listingId];
        require(auction.isActive, "Auction not active");
        require(block.timestamp <= auction.endTime, "Auction ended");

        uint256 elapsed = block.timestamp - auction.startTime;
        uint256 totalDuration = auction.endTime - auction.startTime;

        // Linear price decrease
        uint256 priceRange = auction.startingPrice - auction.endingPrice;
        uint256 priceDecrease = (priceRange * elapsed) / totalDuration;

        return auction.startingPrice - priceDecrease;
    }

    /**
     * @dev Buy from a Dutch auction
     * @param listingId The listing ID to purchase
     */
    function buyFromDutchAuction(uint256 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing not active");
        require(listing.listingType == ListingType.DUTCH_AUCTION, "Not a Dutch auction");
        require(msg.sender != listing.seller, "Cannot buy own item");
        require(block.timestamp <= listing.endTime, "Auction ended");

        uint256 currentPrice = getDutchAuctionPrice(listingId);
        uint256 totalPrice = currentPrice * listing.amount;
        uint256 fee = (totalPrice * marketplaceFee) / 10000;
        uint256 sellerAmount = totalPrice - fee;

        // Handle payment
        if (listing.paymentToken == address(0)) {
            require(msg.value >= totalPrice, "Insufficient payment");
            
            // Send fee to fee recipient
            if (fee > 0) {
                payable(feeRecipient).transfer(fee);
            }
            
            // Send payment to seller
            payable(listing.seller).transfer(sellerAmount);
            
            // Refund excess
            if (msg.value > totalPrice) {
                payable(msg.sender).transfer(msg.value - totalPrice);
            }
        } else {
            require(IERC20(listing.paymentToken).transferFrom(msg.sender, address(this), totalPrice), "Payment failed");
            
            // Send fee to fee recipient
            if (fee > 0) {
                require(IERC20(listing.paymentToken).transfer(feeRecipient, fee), "Fee transfer failed");
            }
            
            // Send payment to seller
            require(IERC20(listing.paymentToken).transfer(listing.seller, sellerAmount), "Seller payment failed");
        }

        // Transfer NFT
        _transferNFT(listing, msg.sender);

        // Mark listing as inactive
        listing.isActive = false;
        dutchAuctions[listingId].isActive = false;

        emit ItemSold(listingId, listing.seller, msg.sender, totalPrice, fee);
        emit DutchAuctionEnded(listingId, msg.sender, currentPrice);
    }

    // ========== BULK OPERATIONS ==========

    /**
     * @dev Create a bulk listing for multiple ERC721 NFTs
     * @param nftContract The NFT contract address
     * @param tokenIds Array of token IDs to list
     * @param listingType Listing type
     * @param paymentToken Payment token address
     * @param pricePerItem Price per item
     * @param duration Duration for auctions (0 for fixed price)
     */
    function createBulkListingERC721(
        address nftContract,
        uint256[] memory tokenIds,
        ListingType listingType,
        address paymentToken,
        uint256 pricePerItem,
        uint256 duration
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(tokenIds.length > 0, "Must list at least one item");
        require(pricePerItem > 0, "Price must be positive");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(IERC721(nftContract).ownerOf(tokenIds[i]) == msg.sender, "Not token owner");
            require(IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) || IERC721(nftContract).getApproved(tokenIds[i]) == address(this), "Not approved");
        }

        uint256 bulkId = nextListingId++;
        uint256 endTime = listingType == ListingType.AUCTION ? block.timestamp + duration : 0;

        bulkListings[bulkId] = BulkListing({
            bulkId: bulkId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenIds: tokenIds,
            amounts: new uint256[](tokenIds.length),
            listingType: listingType,
            paymentToken: paymentToken,
            pricePerItem: pricePerItem,
            endTime: endTime,
            isActive: true,
            itemsSold: 0
        });

        // Initialize amounts array
        for (uint256 i = 0; i < tokenIds.length; i++) {
            bulkListings[bulkId].amounts[i] = 1;
        }

        emit BulkListingCreated(bulkId, msg.sender, tokenIds.length, pricePerItem);

        return bulkId;
    }

    /**
     * @dev Create a bulk listing for multiple ERC1155 NFTs
     * @param nftContract The NFT contract address
     * @param tokenIds Array of token IDs to list
     * @param amounts Array of amounts to list
     * @param listingType Listing type
     * @param paymentToken Payment token address
     * @param pricePerItem Price per item
     * @param duration Duration for auctions
     */
    function createBulkListingERC1155(
        address nftContract,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        ListingType listingType,
        address paymentToken,
        uint256 pricePerItem,
        uint256 duration
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(tokenIds.length > 0, "Must list at least one item");
        require(tokenIds.length == amounts.length, "Arrays length mismatch");
        require(pricePerItem > 0, "Price must be positive");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(amounts[i] > 0, "Amount must be positive");
            require(IERC1155(nftContract).balanceOf(msg.sender, tokenIds[i]) >= amounts[i], "Insufficient balance");
        }
        require(IERC1155(nftContract).isApprovedForAll(msg.sender, address(this)), "Not approved");

        uint256 bulkId = nextListingId++;
        uint256 endTime = listingType == ListingType.AUCTION ? block.timestamp + duration : 0;

        bulkListings[bulkId] = BulkListing({
            bulkId: bulkId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenIds: tokenIds,
            amounts: amounts,
            listingType: listingType,
            paymentToken: paymentToken,
            pricePerItem: pricePerItem,
            endTime: endTime,
            isActive: true,
            itemsSold: 0
        });

        emit BulkListingCreated(bulkId, msg.sender, tokenIds.length, pricePerItem);

        return bulkId;
    }

    /**
     * @dev Buy all items from a bulk listing
     * @param bulkId The bulk listing ID
     */
    function buyBulkListing(uint256 bulkId) external payable whenNotPaused nonReentrant {
        BulkListing storage bulk = bulkListings[bulkId];
        require(bulk.isActive, "Bulk listing not active");
        require(bulk.listingType == ListingType.FIXED_PRICE, "Only fixed price bulk listings supported");
        require(msg.sender != bulk.seller, "Cannot buy own items");

        // Calculate total price
        uint256 totalItems = 0;
        for (uint256 i = 0; i < bulk.tokenIds.length; i++) {
            totalItems += bulk.amounts[i];
        }
        
        uint256 totalPrice = bulk.pricePerItem * totalItems;
        uint256 fee = (totalPrice * marketplaceFee) / 10000;
        uint256 sellerAmount = totalPrice - fee;

        // Handle payment
        if (bulk.paymentToken == address(0)) {
            require(msg.value >= totalPrice, "Insufficient payment");
            
            // Send fee to fee recipient
            if (fee > 0) {
                payable(feeRecipient).transfer(fee);
            }
            
            // Send payment to seller
            payable(bulk.seller).transfer(sellerAmount);
            
            // Refund excess
            if (msg.value > totalPrice) {
                payable(msg.sender).transfer(msg.value - totalPrice);
            }
        } else {
            require(IERC20(bulk.paymentToken).transferFrom(msg.sender, address(this), totalPrice), "Payment failed");
            
            // Send fee to fee recipient
            if (fee > 0) {
                require(IERC20(bulk.paymentToken).transfer(feeRecipient, fee), "Fee transfer failed");
            }
            
            // Send payment to seller
            require(IERC20(bulk.paymentToken).transfer(bulk.seller, sellerAmount), "Seller payment failed");
        }

        // Transfer all NFTs
        if (bulk.amounts[0] == 1) {
            // ERC721
            for (uint256 i = 0; i < bulk.tokenIds.length; i++) {
                IERC721(bulk.nftContract).safeTransferFrom(bulk.seller, msg.sender, bulk.tokenIds[i]);
            }
        } else {
            // ERC1155
            IERC1155(bulk.nftContract).safeBatchTransferFrom(
                bulk.seller,
                msg.sender,
                bulk.tokenIds,
                bulk.amounts,
                ""
            );
        }

        // Mark bulk listing as inactive
        bulk.isActive = false;

        emit BulkItemSold(bulkId, bulk.seller, msg.sender, totalItems, totalPrice);
    }

    /**
     * @dev Buy specific items from a bulk listing
     * @param bulkId The bulk listing ID
     * @param itemIndices Array of indices to buy
     */
    function buyFromBulkListing(
        uint256 bulkId,
        uint256[] memory itemIndices
    ) external payable nonReentrant {
        BulkListing storage bulk = bulkListings[bulkId];
        require(bulk.isActive, "Bulk listing not active");
        require(bulk.listingType == ListingType.FIXED_PRICE, "Only fixed price bulk listings supported");
        require(msg.sender != bulk.seller, "Cannot buy own items");

        uint256 totalItems = itemIndices.length;
        uint256 totalPrice = bulk.pricePerItem * totalItems;
        uint256 fee = (totalPrice * marketplaceFee) / 10000;
        uint256 sellerAmount = totalPrice - fee;

        // Handle payment
        if (bulk.paymentToken == address(0)) {
            require(msg.value >= totalPrice, "Insufficient payment");
            
            // Send fee to fee recipient
            if (fee > 0) {
                payable(feeRecipient).transfer(fee);
            }
            
            // Send payment to seller
            payable(bulk.seller).transfer(sellerAmount);
            
            // Refund excess
            if (msg.value > totalPrice) {
                payable(msg.sender).transfer(msg.value - totalPrice);
            }
        } else {
            require(IERC20(bulk.paymentToken).transferFrom(msg.sender, address(this), totalPrice), "Payment failed");
            
            // Send fee to fee recipient
            if (fee > 0) {
                require(IERC20(bulk.paymentToken).transfer(feeRecipient, fee), "Fee transfer failed");
            }
            
            // Send payment to seller
            require(IERC20(bulk.paymentToken).transfer(bulk.seller, sellerAmount), "Seller payment failed");
        }

        // Transfer selected NFTs
        uint256[] memory selectedTokenIds = new uint256[](itemIndices.length);
        uint256[] memory selectedAmounts = new uint256[](itemIndices.length);

        for (uint256 i = 0; i < itemIndices.length; i++) {
            uint256 index = itemIndices[i];
            require(index < bulk.tokenIds.length, "Invalid index");
            selectedTokenIds[i] = bulk.tokenIds[index];
            selectedAmounts[i] = bulk.amounts[index];
        }

        if (selectedAmounts[0] == 1) {
            // ERC721
            for (uint256 i = 0; i < selectedTokenIds.length; i++) {
                IERC721(bulk.nftContract).safeTransferFrom(bulk.seller, msg.sender, selectedTokenIds[i]);
            }
        } else {
            // ERC1155
            IERC1155(bulk.nftContract).safeBatchTransferFrom(
                bulk.seller,
                msg.sender,
                selectedTokenIds,
                selectedAmounts,
                ""
            );
        }

        bulk.itemsSold += totalItems;

        emit BulkItemSold(bulkId, bulk.seller, msg.sender, totalItems, totalPrice);
    }

    /**
     * @dev Cancel a bulk listing
     * @param bulkId The bulk listing ID
     */
    function cancelBulkListing(uint256 bulkId) external whenNotPaused nonReentrant {
        BulkListing storage bulk = bulkListings[bulkId];
        require(bulk.isActive, "Bulk listing not active");
        require(bulk.seller == msg.sender || hasRole(MODERATOR_ROLE, msg.sender), "Not authorized");

        bulk.isActive = false;

        emit BulkListingCancelled(bulkId, bulk.seller);
    }

    // ========== SEARCH AND FILTER ==========

    /**
     * @dev Set metadata for a listing (for search and filter)
     * @param listingId The listing ID
     * @param name Listing name
     * @param description Listing description
     * @param categoryId Category identifier
     * @param rarity Rarity level
     * @param level Item level
     * @param isVerified Whether the listing is verified
     */
    function setListingMetadata(
        uint256 listingId,
        string memory name,
        string memory description,
        uint256 categoryId,
        uint256 rarity,
        uint256 level,
        bool isVerified
    ) external onlyRole(MODERATOR_ROLE) {
        listingMetadata[listingId] = ListingMetadata({
            name: name,
            description: description,
            categoryId: categoryId,
            rarity: rarity,
            level: level,
            isVerified: isVerified
        });

        // Add to indexes
        categoryListings[categoryId].push(listingId);
        rarityListings[rarity].push(listingId);
        
        // Simple name indexing (in production, use proper text search)
        nameSearchIndex[name].push(listingId);
    }

    /**
     * @dev Search listings by name keyword
     * @param keyword The search keyword
     * @return Array of listing IDs matching the keyword
     */
    function searchByName(string memory keyword) external view returns (uint256[] memory) {
        return nameSearchIndex[keyword];
    }

    /**
     * @dev Filter listings by category
     * @param categoryId The category identifier
     * @return Array of listing IDs in the category
     */
    function filterByCategory(uint256 categoryId) external view returns (uint256[] memory) {
        return categoryListings[categoryId];
    }

    /**
     * @dev Filter listings by rarity
     * @param rarity The rarity level
     * @return Array of listing IDs with the rarity
     */
    function filterByRarity(uint256 rarity) external view returns (uint256[] memory) {
        return rarityListings[rarity];
    }

    /**
     * @dev Advanced search with multiple filters
     * @param categoryId Category filter (0 for any)
     * @param minRarity Minimum rarity (0 for any)
     * @param maxRarity Maximum rarity (5 for any)
     * @param isVerified Only verified listings
     * @return Array of matching listing IDs
     */
    function advancedSearch(
        uint256 categoryId,
        uint256 minRarity,
        uint256 maxRarity,
        bool isVerified
    ) external view returns (uint256[] memory) {
        uint256[] memory results = new uint256[](0);
        
        // Iterate through all listings (in production, use proper indexing)
        for (uint256 i = 1; i < nextListingId; i++) {
            Listing memory listing = listings[i];
            if (!listing.isActive) continue;
            
            ListingMetadata memory metadata = listingMetadata[i];
            
            bool matches = true;
            
            if (categoryId > 0 && metadata.categoryId != categoryId) {
                matches = false;
            }
            
            if (minRarity > 0 && metadata.rarity < minRarity) {
                matches = false;
            }
            
            if (maxRarity < 5 && metadata.rarity > maxRarity) {
                matches = false;
            }
            
            if (isVerified && !metadata.isVerified) {
                matches = false;
            }
            
            if (matches) {
                // Add to results
                uint256[] memory newResults = new uint256[](results.length + 1);
                for (uint256 j = 0; j < results.length; j++) {
                    newResults[j] = results[j];
                }
                newResults[results.length] = i;
                results = newResults;
            }
        }
        
        return results;
    }

    // ========== LEGACY FUNCTIONS ==========

    /**
     * @dev Buy a fixed price listing
     * @param listingId The listing ID to purchase
     */
    function buyItem(uint256 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing not active");
        require(listing.listingType == ListingType.FIXED_PRICE, "Not a fixed price listing");
        require(msg.sender != listing.seller, "Cannot buy own item");

        uint256 totalPrice = listing.price;
        uint256 fee = (totalPrice * marketplaceFee) / 10000;
        uint256 sellerAmount = totalPrice - fee;

        // Handle payment
        if (listing.paymentToken == address(0)) {
            require(msg.value >= totalPrice, "Insufficient payment");
            
            // Send fee to fee recipient
            if (fee > 0) {
                payable(feeRecipient).transfer(fee);
            }
            
            // Send payment to seller
            payable(listing.seller).transfer(sellerAmount);
            
            // Refund excess
            if (msg.value > totalPrice) {
                payable(msg.sender).transfer(msg.value - totalPrice);
            }
        } else {
            require(IERC20(listing.paymentToken).transferFrom(msg.sender, address(this), totalPrice), "Payment failed");
            
            // Send fee to fee recipient
            if (fee > 0) {
                require(IERC20(listing.paymentToken).transfer(feeRecipient, fee), "Fee transfer failed");
            }
            
            // Send payment to seller
            require(IERC20(listing.paymentToken).transfer(listing.seller, sellerAmount), "Seller payment failed");
        }

        // Transfer NFT
        _transferNFT(listing, msg.sender);

        // Mark listing as inactive
        listing.isActive = false;

        emit ItemSold(listingId, listing.seller, msg.sender, totalPrice, fee);
    }

    /**
     * @dev Place a bid on an auction
     * @param listingId The listing ID to bid on
     */
    function placeBid(uint256 listingId) external payable whenNotPaused {
        placeBid(listingId, 0);
    }

    /**
     * @dev Place a bid on an auction
     * @param listingId The listing ID to bid on
     * @param bidAmount The bid amount (only for ERC20 tokens, ignored for ETH)
     */
    function placeBid(uint256 listingId, uint256 bidAmount) public payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing not active");
        require(listing.listingType == ListingType.AUCTION, "Not an auction");
        require(block.timestamp < listing.endTime, "Auction ended");
        require(msg.sender != listing.seller, "Cannot bid on own item");

        uint256 finalBidAmount;
        
        if (listing.paymentToken == address(0)) {
            finalBidAmount = msg.value;
            require(bidAmount == 0, "Bid amount should be 0 for ETH auctions");
        } else {
            require(msg.value == 0, "Should not send ETH for ERC20 auctions");
            require(bidAmount > 0, "Bid amount must be specified for ERC20 tokens");
            finalBidAmount = bidAmount;
            require(IERC20(listing.paymentToken).transferFrom(msg.sender, address(this), finalBidAmount), "Bid transfer failed");
        }

        require(finalBidAmount > listing.highestBid, "Bid too low");
        require(finalBidAmount >= listing.price, "Bid below starting price");

        // Refund previous highest bidder
        if (listing.highestBidder != address(0)) {
            if (listing.paymentToken == address(0)) {
                payable(listing.highestBidder).transfer(listing.highestBid);
            } else {
                require(IERC20(listing.paymentToken).transfer(listing.highestBidder, listing.highestBid), "Refund failed");
            }
        }

        listing.highestBidder = msg.sender;
        listing.highestBid = finalBidAmount;
        auctionBids[listingId][msg.sender] = finalBidAmount;

        emit BidPlaced(listingId, msg.sender, finalBidAmount);
    }

    /**
     * @dev End an auction and transfer assets
     * @param listingId The listing ID to end
     */
    function endAuction(uint256 listingId) external whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing not active");
        require(listing.listingType == ListingType.AUCTION, "Not an auction");
        require(block.timestamp >= listing.endTime, "Auction not ended");

        listing.isActive = false;

        if (listing.highestBidder != address(0)) {
            uint256 totalPrice = listing.highestBid;
            uint256 fee = (totalPrice * marketplaceFee) / 10000;
            uint256 sellerAmount = totalPrice - fee;

            // Send fee to fee recipient
            if (fee > 0) {
                if (listing.paymentToken == address(0)) {
                    payable(feeRecipient).transfer(fee);
                } else {
                    require(IERC20(listing.paymentToken).transfer(feeRecipient, fee), "Fee transfer failed");
                }
            }

            // Send payment to seller
            if (listing.paymentToken == address(0)) {
                payable(listing.seller).transfer(sellerAmount);
            } else {
                require(IERC20(listing.paymentToken).transfer(listing.seller, sellerAmount), "Seller payment failed");
            }

            // Transfer NFT to winner
            _transferNFT(listing, listing.highestBidder);

            emit AuctionEnded(listingId, listing.highestBidder, listing.highestBid);
        } else {
            emit AuctionEnded(listingId, address(0), 0);
        }
    }

    /**
     * @dev Cancel a listing
     * @param listingId The listing ID to cancel
     */
    function cancelListing(uint256 listingId) external whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing not active");
        require(listing.seller == msg.sender || hasRole(MODERATOR_ROLE, msg.sender), "Not authorized");

        // For auctions, refund highest bidder
        if (listing.listingType == ListingType.AUCTION && listing.highestBidder != address(0)) {
            if (listing.paymentToken == address(0)) {
                payable(listing.highestBidder).transfer(listing.highestBid);
            } else {
                require(IERC20(listing.paymentToken).transfer(listing.highestBidder, listing.highestBid), "Refund failed");
            }
        }

        listing.isActive = false;

        emit ItemDelisted(listingId, listing.seller);
    }

    /**
     * @dev Internal function to transfer NFTs
     */
    function _transferNFT(Listing memory listing, address to) internal {
        if (listing.assetType == AssetType.ERC721) {
            IERC721(listing.nftContract).safeTransferFrom(listing.seller, to, listing.tokenId);
        } else {
            IERC1155(listing.nftContract).safeTransferFrom(listing.seller, to, listing.tokenId, listing.amount, "");
        }
    }

    /**
     * @dev Get user's active listings
     * @param user The user address
     */
    function getUserListings(address user) external view returns (uint256[] memory) {
        return userListings[user];
    }

    /**
     * @dev Update marketplace fee
     * @param newFee The new fee in basis points
     */
    function updateMarketplaceFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        marketplaceFee = newFee;
    }

    /**
     * @dev Update fee recipient
     * @param newRecipient The new fee recipient address
     */
    function updateFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRecipient != address(0), "Invalid address");
        feeRecipient = newRecipient;
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

