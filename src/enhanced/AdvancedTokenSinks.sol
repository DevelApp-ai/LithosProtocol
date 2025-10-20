// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title AdvancedTokenSinks
 * @dev Comprehensive token sink mechanisms to maintain economic balance
 * Implements multiple deflationary mechanisms beyond basic crafting and repairs
 */
contract AdvancedTokenSinks is 
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    IERC20Upgradeable public utilityToken;

    struct CosmeticItem {
        string name;
        uint256 price;
        bool isActive;
        uint256 totalPurchased;
        uint256 categoryId;
    }

    struct TournamentEntry {
        uint256 entryFee;
        uint256 prizePool;
        uint256 maxParticipants;
        uint256 currentParticipants;
        bool isActive;
        uint256 startTime;
        uint256 endTime;
    }

    struct AssetRental {
        address owner;
        address renter;
        uint256 assetId;
        uint256 dailyRate;
        uint256 startTime;
        uint256 duration;
        bool isActive;
    }

    struct ConvenienceFeature {
        string name;
        uint256 price;
        uint256 duration; // in seconds
        bool isActive;
    }

    // Storage
    mapping(uint256 => CosmeticItem) public cosmeticItems;
    mapping(uint256 => TournamentEntry) public tournaments;
    mapping(uint256 => AssetRental) public assetRentals;
    mapping(uint256 => ConvenienceFeature) public convenienceFeatures;
    
    // Player purchases and subscriptions
    mapping(address => mapping(uint256 => bool)) public playerCosmetics;
    mapping(address => mapping(uint256 => uint256)) public playerConvenienceExpiry;
    mapping(address => uint256[]) public playerTournaments;
    
    // Rental system
    mapping(address => uint256[]) public playerRentals;
    mapping(uint256 => uint256) public assetToRental; // assetId => rentalId
    
    // Burn tracking
    uint256 public totalTokensBurned;
    mapping(string => uint256) public burnByCategory;
    
    // Counters
    uint256 public nextCosmeticId;
    uint256 public nextTournamentId;
    uint256 public nextRentalId;
    uint256 public nextConvenienceId;

    // Events
    event CosmeticPurchased(address indexed player, uint256 indexed itemId, uint256 price);
    event TournamentEntered(address indexed player, uint256 indexed tournamentId, uint256 entryFee);
    event AssetRented(address indexed renter, address indexed owner, uint256 indexed assetId, uint256 dailyRate);
    event ConvenienceActivated(address indexed player, uint256 indexed featureId, uint256 duration);
    event TokensBurned(string category, uint256 amount, address indexed player);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address _utilityToken
    ) initializer public {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, defaultAdmin);
        
        utilityToken = IERC20Upgradeable(_utilityToken);
        
        nextCosmeticId = 1;
        nextTournamentId = 1;
        nextRentalId = 1;
        nextConvenienceId = 1;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    /**
     * @dev Create a new cosmetic item
     * @param name Item name
     * @param price Price in utility tokens
     * @param categoryId Category identifier
     */
    function createCosmeticItem(
        string memory name,
        uint256 price,
        uint256 categoryId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        cosmeticItems[nextCosmeticId] = CosmeticItem({
            name: name,
            price: price,
            isActive: true,
            totalPurchased: 0,
            categoryId: categoryId
        });
        
        nextCosmeticId++;
    }

    /**
     * @dev Purchase a cosmetic item
     * @param itemId The cosmetic item ID
     */
    function purchaseCosmetic(uint256 itemId) external nonReentrant whenNotPaused {
        CosmeticItem storage item = cosmeticItems[itemId];
        require(item.isActive, "Item not available");
        require(!playerCosmetics[msg.sender][itemId], "Already owned");
        
        // Burn tokens
        require(
            utilityToken.transferFrom(msg.sender, address(this), item.price),
            "Transfer failed"
        );
        _burnTokens("cosmetics", item.price);
        
        // Grant cosmetic to player
        playerCosmetics[msg.sender][itemId] = true;
        item.totalPurchased++;
        
        emit CosmeticPurchased(msg.sender, itemId, item.price);
    }

    /**
     * @dev Create a tournament with entry fee
     * @param entryFee Fee to enter tournament
     * @param maxParticipants Maximum number of participants
     * @param duration Tournament duration in seconds
     */
    function createTournament(
        uint256 entryFee,
        uint256 maxParticipants,
        uint256 duration
    ) external onlyRole(GAME_ROLE) {
        tournaments[nextTournamentId] = TournamentEntry({
            entryFee: entryFee,
            prizePool: 0,
            maxParticipants: maxParticipants,
            currentParticipants: 0,
            isActive: true,
            startTime: block.timestamp,
            endTime: block.timestamp + duration
        });
        
        nextTournamentId++;
    }

    /**
     * @dev Enter a tournament
     * @param tournamentId The tournament ID
     */
    function enterTournament(uint256 tournamentId) external nonReentrant whenNotPaused {
        TournamentEntry storage tournament = tournaments[tournamentId];
        require(tournament.isActive, "Tournament not active");
        require(block.timestamp < tournament.endTime, "Tournament ended");
        require(tournament.currentParticipants < tournament.maxParticipants, "Tournament full");
        
        // Pay entry fee (50% burned, 50% to prize pool)
        require(
            utilityToken.transferFrom(msg.sender, address(this), tournament.entryFee),
            "Transfer failed"
        );
        
        uint256 burnAmount = tournament.entryFee / 2;
        uint256 prizeAmount = tournament.entryFee - burnAmount;
        
        _burnTokens("tournaments", burnAmount);
        tournament.prizePool += prizeAmount;
        tournament.currentParticipants++;
        
        playerTournaments[msg.sender].push(tournamentId);
        
        emit TournamentEntered(msg.sender, tournamentId, tournament.entryFee);
    }

    /**
     * @dev Create an asset rental listing
     * @param assetId The asset to rent
     * @param dailyRate Daily rental rate
     * @param maxDuration Maximum rental duration in days
     */
    function createAssetRental(
        uint256 assetId,
        uint256 dailyRate,
        uint256 maxDuration
    ) external onlyRole(GAME_ROLE) {
        require(assetToRental[assetId] == 0, "Asset already listed");
        
        assetRentals[nextRentalId] = AssetRental({
            owner: msg.sender,
            renter: address(0),
            assetId: assetId,
            dailyRate: dailyRate,
            startTime: 0,
            duration: maxDuration,
            isActive: true
        });
        
        assetToRental[assetId] = nextRentalId;
        nextRentalId++;
    }

    /**
     * @dev Rent an asset
     * @param rentalId The rental listing ID
     * @param rentalDays Number of days to rent
     */
    function rentAsset(uint256 rentalId, uint256 rentalDays) external nonReentrant whenNotPaused {
        AssetRental storage rental = assetRentals[rentalId];
        require(rental.isActive, "Rental not active");
        require(rental.renter == address(0), "Already rented");
        require(rentalDays <= rental.duration, "Duration too long");
        
        uint256 totalCost = rental.dailyRate * rentalDays;
        
        // Pay rental fee (10% burned, 90% to owner)
        require(
            utilityToken.transferFrom(msg.sender, address(this), totalCost),
            "Transfer failed"
        );
        
        uint256 burnAmount = totalCost / 10;
        uint256 ownerAmount = totalCost - burnAmount;
        
        _burnTokens("rentals", burnAmount);
        require(utilityToken.transfer(rental.owner, ownerAmount), "Owner payment failed");
        
        // Set rental details
        rental.renter = msg.sender;
        rental.startTime = block.timestamp;
        rental.duration = rentalDays * 1 days;
        
        playerRentals[msg.sender].push(rentalId);
        
        emit AssetRented(msg.sender, rental.owner, rental.assetId, rental.dailyRate);
    }

    /**
     * @dev Create a convenience feature
     * @param name Feature name
     * @param price Price for the feature
     * @param duration Duration in seconds
     */
    function createConvenienceFeature(
        string memory name,
        uint256 price,
        uint256 duration
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        convenienceFeatures[nextConvenienceId] = ConvenienceFeature({
            name: name,
            price: price,
            duration: duration,
            isActive: true
        });
        
        nextConvenienceId++;
    }

    /**
     * @dev Activate a convenience feature
     * @param featureId The feature ID
     */
    function activateConvenienceFeature(uint256 featureId) external nonReentrant whenNotPaused {
        ConvenienceFeature storage feature = convenienceFeatures[featureId];
        require(feature.isActive, "Feature not available");
        
        // Burn tokens for convenience feature
        require(
            utilityToken.transferFrom(msg.sender, address(this), feature.price),
            "Transfer failed"
        );
        _burnTokens("convenience", feature.price);
        
        // Extend or set expiry
        uint256 currentExpiry = playerConvenienceExpiry[msg.sender][featureId];
        uint256 newExpiry = currentExpiry > block.timestamp ? 
            currentExpiry + feature.duration : 
            block.timestamp + feature.duration;
        
        playerConvenienceExpiry[msg.sender][featureId] = newExpiry;
        
        emit ConvenienceActivated(msg.sender, featureId, feature.duration);
    }

    /**
     * @dev Burn tokens for special game modes
     * @param amount Amount to burn
     * @param gameMode The game mode name
     */
    function burnForGameMode(
        uint256 amount,
        string memory gameMode
    ) external onlyRole(GAME_ROLE) {
        _burnTokens(gameMode, amount);
    }

    /**
     * @dev Internal function to burn tokens and track by category
     * @param category Burn category for tracking
     * @param amount Amount to burn
     */
    function _burnTokens(string memory category, uint256 amount) internal {
        // In a real implementation, this would burn tokens from the contract
        // For now, we'll track the burns
        totalTokensBurned += amount;
        burnByCategory[category] += amount;
        
        emit TokensBurned(category, amount, msg.sender);
    }

    // View functions
    function hasCosmetic(address player, uint256 itemId) external view returns (bool) {
        return playerCosmetics[player][itemId];
    }

    function getConvenienceExpiry(address player, uint256 featureId) external view returns (uint256) {
        return playerConvenienceExpiry[player][featureId];
    }

    function isConvenienceActive(address player, uint256 featureId) external view returns (bool) {
        return playerConvenienceExpiry[player][featureId] > block.timestamp;
    }

    function getPlayerTournaments(address player) external view returns (uint256[] memory) {
        return playerTournaments[player];
    }

    function getPlayerRentals(address player) external view returns (uint256[] memory) {
        return playerRentals[player];
    }

    function getTotalBurnByCategory(string memory category) external view returns (uint256) {
        return burnByCategory[category];
    }

    function isAssetRented(uint256 assetId) external view returns (bool) {
        uint256 rentalId = assetToRental[assetId];
        if (rentalId == 0) return false;
        
        AssetRental memory rental = assetRentals[rentalId];
        return rental.renter != address(0) && 
               block.timestamp < rental.startTime + rental.duration;
    }

    /**
     * @dev Get comprehensive burn statistics
     * @return Total burned, daily average, top categories
     */
    function getBurnStatistics() external view returns (
        uint256 totalBurned,
        uint256 cosmeticsBurned,
        uint256 tournamentsBurned,
        uint256 rentalsBurned,
        uint256 convenienceBurned
    ) {
        return (
            totalTokensBurned,
            burnByCategory["cosmetics"],
            burnByCategory["tournaments"],
            burnByCategory["rentals"],
            burnByCategory["convenience"]
        );
    }
}

