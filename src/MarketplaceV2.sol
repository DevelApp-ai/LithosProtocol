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

    // Custom errors (revert strings removed to satisfy the EIP-170 size limit)
    error ZeroPrice();
    error ZeroAmount();
    error ZeroDuration();
    error InvalidPriceRange();
    error InvalidIndex();
    error InvalidAddress();
    error ArrayLengthMismatch();
    error EmptyBulkListing();
    error NotTokenOwner();
    error NotApproved();
    error InsufficientBalance();
    error InsufficientPayment();
    error PaymentFailed();
    error FeeTransferFailed();
    error SellerPaymentFailed();
    error ListingNotActive();
    error BulkListingNotActive();
    error NotDutchAuction();
    error NotAuction();
    error NotFixedPrice();
    error AuctionNotActive();
    error AuctionEnded();
    error AuctionNotEnded();
    error SelfPurchase();
    error NotAuthorized();
    error FeeTooHigh();
    error InvalidBidAmount();
    error EthNotAccepted();
    error BidTooLow();

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

    // ========== INTERNAL HELPERS ==========

    /**
     * @dev Verify msg.sender owns tokenId and the marketplace is approved (ERC721)
     */
    function _assertERC721Listable(address nftContract, uint256 tokenId) internal view {
        if (IERC721(nftContract).ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (!IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) && IERC721(nftContract).getApproved(tokenId) != address(this)) revert NotApproved();
    }

    /**
     * @dev Verify msg.sender holds amount of tokenId and the marketplace is approved (ERC1155)
     */
    function _assertERC1155Listable(address nftContract, uint256 tokenId, uint256 amount) internal view {
        if (IERC1155(nftContract).balanceOf(msg.sender, tokenId) < amount) revert InsufficientBalance();
        if (!IERC1155(nftContract).isApprovedForAll(msg.sender, address(this))) revert NotApproved();
    }

    /**
     * @dev Create a listing record and index it under the seller
     */
    function _createListing(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        AssetType assetType,
        ListingType listingType,
        address paymentToken,
        uint256 price,
        uint256 endPrice,
        uint256 endTime
    ) internal returns (uint256 listingId) {
        listingId = nextListingId++;
        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            assetType: assetType,
            listingType: listingType,
            paymentToken: paymentToken,
            price: price,
            endPrice: endPrice,
            endTime: endTime,
            isActive: true,
            highestBidder: address(0),
            highestBid: 0
        });
        userListings[msg.sender].push(listingId);
    }

    /**
     * @dev Create the Dutch auction state for a listing
     */
    function _startDutchAuction(
        uint256 listingId,
        uint256 startingPrice,
        uint256 endingPrice,
        uint256 endTime
    ) internal {
        dutchAuctions[listingId] = DutchAuction({
            startingPrice: startingPrice,
            endingPrice: endingPrice,
            startTime: block.timestamp,
            endTime: endTime,
            isActive: true
        });
    }

    /**
     * @dev Create a bulk listing record
     */
    function _createBulkListing(
        address nftContract,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        ListingType listingType,
        address paymentToken,
        uint256 pricePerItem,
        uint256 duration
    ) internal returns (uint256 bulkId) {
        bulkId = nextListingId++;
        bulkListings[bulkId] = BulkListing({
            bulkId: bulkId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenIds: tokenIds,
            amounts: amounts,
            listingType: listingType,
            paymentToken: paymentToken,
            pricePerItem: pricePerItem,
            endTime: listingType == ListingType.AUCTION ? block.timestamp + duration : 0,
            isActive: true,
            itemsSold: 0
        });
    }

    /**
     * @dev Collect payment (ETH or ERC20), forward the fee and pay the seller
     * @return fee The marketplace fee taken from totalPrice
     */
    function _settlePayment(
        address paymentToken,
        address seller,
        uint256 totalPrice
    ) internal returns (uint256 fee) {
        fee = (totalPrice * marketplaceFee) / 10000;
        uint256 sellerAmount = totalPrice - fee;

        if (paymentToken == address(0)) {
            if (msg.value < totalPrice) revert InsufficientPayment();

            // Send fee to fee recipient
            if (fee > 0) {
                payable(feeRecipient).transfer(fee);
            }

            // Send payment to seller
            payable(seller).transfer(sellerAmount);

            // Refund excess
            if (msg.value > totalPrice) {
                payable(msg.sender).transfer(msg.value - totalPrice);
            }
        } else {
            if (!IERC20(paymentToken).transferFrom(msg.sender, address(this), totalPrice)) revert PaymentFailed();

            // Send fee to fee recipient
            if (fee > 0) {
                if (!IERC20(paymentToken).transfer(feeRecipient, fee)) revert FeeTransferFailed();
            }

            // Send payment to seller
            if (!IERC20(paymentToken).transfer(seller, sellerAmount)) revert SellerPaymentFailed();
        }
    }

    /**
     * @dev Release contract-held funds (ETH or ERC20) to a recipient
     */
    function _releaseFunds(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            if (!IERC20(token).transfer(to, amount)) revert PaymentFailed();
        }
    }

    /**
     * @dev Transfer a set of bulk-listed NFTs to msg.sender
     */
    function _transferBulk(
        BulkListing storage bulk,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) internal {
        if (amounts[0] == 1) {
            // ERC721
            for (uint256 i = 0; i < tokenIds.length; i++) {
                IERC721(bulk.nftContract).safeTransferFrom(bulk.seller, msg.sender, tokenIds[i]);
            }
        } else {
            // ERC1155
            IERC1155(bulk.nftContract).safeBatchTransferFrom(
                bulk.seller,
                msg.sender,
                tokenIds,
                amounts,
                ""
            );
        }
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
        if (price == 0) revert ZeroPrice();
        _assertERC721Listable(nftContract, tokenId);

        uint256 endTime = listingType == ListingType.AUCTION ? block.timestamp + duration : 0;
        uint256 listingId = _createListing(
            nftContract,
            tokenId,
            1,
            AssetType.ERC721,
            listingType,
            paymentToken,
            price,
            0,
            endTime
        );

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
        if (price == 0) revert ZeroPrice();
        if (amount == 0) revert ZeroAmount();
        _assertERC1155Listable(nftContract, tokenId, amount);

        uint256 endTime = listingType == ListingType.AUCTION ? block.timestamp + duration : 0;
        uint256 listingId = _createListing(
            nftContract,
            tokenId,
            amount,
            AssetType.ERC1155,
            listingType,
            paymentToken,
            price,
            0,
            endTime
        );

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
        if (startingPrice <= endingPrice) revert InvalidPriceRange();
        if (duration == 0) revert ZeroDuration();
        _assertERC721Listable(nftContract, tokenId);

        uint256 endTime = block.timestamp + duration;
        uint256 listingId = _createListing(
            nftContract,
            tokenId,
            1,
            AssetType.ERC721,
            ListingType.DUTCH_AUCTION,
            paymentToken,
            startingPrice,
            endingPrice,
            endTime
        );

        _startDutchAuction(listingId, startingPrice, endingPrice, endTime);

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
        if (startingPrice <= endingPrice) revert InvalidPriceRange();
        if (duration == 0) revert ZeroDuration();
        if (amount == 0) revert ZeroAmount();
        _assertERC1155Listable(nftContract, tokenId, amount);

        uint256 endTime = block.timestamp + duration;
        uint256 listingId = _createListing(
            nftContract,
            tokenId,
            amount,
            AssetType.ERC1155,
            ListingType.DUTCH_AUCTION,
            paymentToken,
            startingPrice,
            endingPrice,
            endTime
        );

        _startDutchAuction(listingId, startingPrice, endingPrice, endTime);

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
        if (!auction.isActive) revert AuctionNotActive();
        if (block.timestamp > auction.endTime) revert AuctionEnded();

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
        if (!listing.isActive) revert ListingNotActive();
        if (listing.listingType != ListingType.DUTCH_AUCTION) revert NotDutchAuction();
        if (msg.sender == listing.seller) revert SelfPurchase();
        if (block.timestamp > listing.endTime) revert AuctionEnded();

        uint256 currentPrice = getDutchAuctionPrice(listingId);
        uint256 totalPrice = currentPrice * listing.amount;
        uint256 fee = _settlePayment(listing.paymentToken, listing.seller, totalPrice);

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
        if (tokenIds.length == 0) revert EmptyBulkListing();
        if (pricePerItem == 0) revert ZeroPrice();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _assertERC721Listable(nftContract, tokenIds[i]);
        }

        // Amounts are 1 per token for ERC721
        uint256[] memory amounts = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            amounts[i] = 1;
        }

        uint256 bulkId = _createBulkListing(
            nftContract,
            tokenIds,
            amounts,
            listingType,
            paymentToken,
            pricePerItem,
            duration
        );

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
        if (tokenIds.length == 0) revert EmptyBulkListing();
        if (tokenIds.length != amounts.length) revert ArrayLengthMismatch();
        if (pricePerItem == 0) revert ZeroPrice();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (amounts[i] == 0) revert ZeroAmount();
            if (IERC1155(nftContract).balanceOf(msg.sender, tokenIds[i]) < amounts[i]) revert InsufficientBalance();
        }
        if (!IERC1155(nftContract).isApprovedForAll(msg.sender, address(this))) revert NotApproved();

        uint256 bulkId = _createBulkListing(
            nftContract,
            tokenIds,
            amounts,
            listingType,
            paymentToken,
            pricePerItem,
            duration
        );

        emit BulkListingCreated(bulkId, msg.sender, tokenIds.length, pricePerItem);

        return bulkId;
    }

    /**
     * @dev Buy all items from a bulk listing
     * @param bulkId The bulk listing ID
     */
    function buyBulkListing(uint256 bulkId) external payable whenNotPaused nonReentrant {
        BulkListing storage bulk = bulkListings[bulkId];
        if (!bulk.isActive) revert BulkListingNotActive();
        if (bulk.listingType != ListingType.FIXED_PRICE) revert NotFixedPrice();
        if (msg.sender == bulk.seller) revert SelfPurchase();

        // Calculate total price
        uint256 totalItems = 0;
        for (uint256 i = 0; i < bulk.tokenIds.length; i++) {
            totalItems += bulk.amounts[i];
        }

        uint256 totalPrice = bulk.pricePerItem * totalItems;
        _settlePayment(bulk.paymentToken, bulk.seller, totalPrice);

        // Transfer all NFTs
        _transferBulk(bulk, bulk.tokenIds, bulk.amounts);

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
        if (!bulk.isActive) revert BulkListingNotActive();
        if (bulk.listingType != ListingType.FIXED_PRICE) revert NotFixedPrice();
        if (msg.sender == bulk.seller) revert SelfPurchase();

        uint256 totalItems = itemIndices.length;
        uint256 totalPrice = bulk.pricePerItem * totalItems;
        _settlePayment(bulk.paymentToken, bulk.seller, totalPrice);

        // Transfer selected NFTs
        uint256[] memory selectedTokenIds = new uint256[](itemIndices.length);
        uint256[] memory selectedAmounts = new uint256[](itemIndices.length);

        for (uint256 i = 0; i < itemIndices.length; i++) {
            uint256 index = itemIndices[i];
            if (index >= bulk.tokenIds.length) revert InvalidIndex();
            selectedTokenIds[i] = bulk.tokenIds[index];
            selectedAmounts[i] = bulk.amounts[index];
        }

        _transferBulk(bulk, selectedTokenIds, selectedAmounts);

        bulk.itemsSold += totalItems;

        emit BulkItemSold(bulkId, bulk.seller, msg.sender, totalItems, totalPrice);
    }

    /**
     * @dev Cancel a bulk listing
     * @param bulkId The bulk listing ID
     */
    function cancelBulkListing(uint256 bulkId) external whenNotPaused nonReentrant {
        BulkListing storage bulk = bulkListings[bulkId];
        if (!bulk.isActive) revert BulkListingNotActive();
        if (bulk.seller != msg.sender && !hasRole(MODERATOR_ROLE, msg.sender)) revert NotAuthorized();

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
        if (!listing.isActive) revert ListingNotActive();
        if (listing.listingType != ListingType.FIXED_PRICE) revert NotFixedPrice();
        if (msg.sender == listing.seller) revert SelfPurchase();

        uint256 totalPrice = listing.price;
        uint256 fee = _settlePayment(listing.paymentToken, listing.seller, totalPrice);

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
        if (!listing.isActive) revert ListingNotActive();
        if (listing.listingType != ListingType.AUCTION) revert NotAuction();
        if (block.timestamp >= listing.endTime) revert AuctionEnded();
        if (msg.sender == listing.seller) revert SelfPurchase();

        uint256 finalBidAmount;
        
        if (listing.paymentToken == address(0)) {
            finalBidAmount = msg.value;
            if (bidAmount != 0) revert InvalidBidAmount();
        } else {
            if (msg.value != 0) revert EthNotAccepted();
            if (bidAmount == 0) revert InvalidBidAmount();
            finalBidAmount = bidAmount;
            if (!IERC20(listing.paymentToken).transferFrom(msg.sender, address(this), finalBidAmount)) revert PaymentFailed();
        }

        if (finalBidAmount <= listing.highestBid) revert BidTooLow();
        if (finalBidAmount < listing.price) revert BidTooLow();

        // Refund previous highest bidder
        if (listing.highestBidder != address(0)) {
            _releaseFunds(listing.paymentToken, listing.highestBidder, listing.highestBid);
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
        if (!listing.isActive) revert ListingNotActive();
        if (listing.listingType != ListingType.AUCTION) revert NotAuction();
        if (block.timestamp < listing.endTime) revert AuctionNotEnded();

        listing.isActive = false;

        if (listing.highestBidder != address(0)) {
            uint256 totalPrice = listing.highestBid;
            uint256 fee = (totalPrice * marketplaceFee) / 10000;
            uint256 sellerAmount = totalPrice - fee;

            // Send fee to fee recipient
            if (fee > 0) {
                _releaseFunds(listing.paymentToken, feeRecipient, fee);
            }

            // Send payment to seller
            _releaseFunds(listing.paymentToken, listing.seller, sellerAmount);

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
        if (!listing.isActive) revert ListingNotActive();
        if (listing.seller != msg.sender && !hasRole(MODERATOR_ROLE, msg.sender)) revert NotAuthorized();

        // For auctions, refund highest bidder
        if (listing.listingType == ListingType.AUCTION && listing.highestBidder != address(0)) {
            _releaseFunds(listing.paymentToken, listing.highestBidder, listing.highestBid);
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
        if (newFee > 1000) revert FeeTooHigh(); // Max 10%
        marketplaceFee = newFee;
    }

    /**
     * @dev Update fee recipient
     * @param newRecipient The new fee recipient address
     */
    function updateFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRecipient == address(0)) revert InvalidAddress();
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
