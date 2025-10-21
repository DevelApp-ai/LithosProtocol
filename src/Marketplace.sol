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
 * @title Marketplace
 * @dev Decentralized marketplace for trading game assets (ERC721 and ERC1155)
 * Supports both fixed price sales and auctions
 */
contract Marketplace is 
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
    enum ListingType { FIXED_PRICE, AUCTION }
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
        uint256 price; // Fixed price or starting bid
        uint256 endTime; // For auctions
        bool isActive;
        address highestBidder; // For auctions
        uint256 highestBid; // For auctions
    }

    // Mappings
    mapping(uint256 => Listing) public listings;
    mapping(address => uint256[]) public userListings;
    mapping(uint256 => mapping(address => uint256)) public auctionBids; // listingId => bidder => amount

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
        require(IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) || 
                IERC721(nftContract).getApproved(tokenId) == address(this), "Not approved");

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
            endTime: endTime,
            isActive: true,
            highestBidder: address(0),
            highestBid: 0
        });

        userListings[msg.sender].push(listingId);

        emit ItemListed(listingId, msg.sender, nftContract, tokenId, amount, price, listingType);

        return listingId;
    }

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
    function placeBid(uint256 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing not active");
        require(listing.listingType == ListingType.AUCTION, "Not an auction");
        require(block.timestamp < listing.endTime, "Auction ended");
        require(msg.sender != listing.seller, "Cannot bid on own item");

        uint256 bidAmount;
        
        if (listing.paymentToken == address(0)) {
            bidAmount = msg.value;
        } else {
            bidAmount = msg.value; // This should be passed as parameter for ERC20 bids
            require(IERC20(listing.paymentToken).transferFrom(msg.sender, address(this), bidAmount), "Bid transfer failed");
        }

        require(bidAmount > listing.highestBid, "Bid too low");
        require(bidAmount >= listing.price, "Bid below starting price");

        // Refund previous highest bidder
        if (listing.highestBidder != address(0)) {
            if (listing.paymentToken == address(0)) {
                payable(listing.highestBidder).transfer(listing.highestBid);
            } else {
                require(IERC20(listing.paymentToken).transfer(listing.highestBidder, listing.highestBid), "Refund failed");
            }
        }

        listing.highestBidder = msg.sender;
        listing.highestBid = bidAmount;
        auctionBids[listingId][msg.sender] = bidAmount;

        emit BidPlaced(listingId, msg.sender, bidAmount);
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

