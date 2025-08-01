// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title GameOracle
 * @dev Dedicated oracle contract for reporting game events and external data
 * Abstracts oracle functionality from core game logic for better modularity
 */
contract GameOracle is 
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    struct PvPResult {
        address player1;
        address player2;
        address winner;
        uint256 timestamp;
        bytes32 matchId;
        bool verified;
    }

    struct QuestCompletion {
        address player;
        uint256 questId;
        uint256 timestamp;
        uint256 rewardAmount;
        bool verified;
    }

    struct MarketData {
        uint256 averagePrice;
        uint256 volume24h;
        uint256 totalListings;
        uint256 timestamp;
    }

    // Storage
    mapping(bytes32 => PvPResult) public pvpResults;
    mapping(bytes32 => QuestCompletion) public questCompletions;
    mapping(uint256 => MarketData) public marketData; // itemId => MarketData
    
    // Oracle reputation system
    mapping(address => uint256) public oracleReputation;
    mapping(address => uint256) public oracleStake;
    
    // Multi-signature requirements
    uint256 public requiredConfirmations;
    mapping(bytes32 => mapping(address => bool)) public confirmations;
    mapping(bytes32 => uint256) public confirmationCount;

    // Events
    event PvPResultReported(bytes32 indexed matchId, address indexed winner, address indexed loser);
    event QuestCompletionReported(bytes32 indexed questHash, address indexed player, uint256 questId);
    event MarketDataUpdated(uint256 indexed itemId, uint256 averagePrice, uint256 volume);
    event OracleStakeUpdated(address indexed oracle, uint256 newStake);
    event RequiredConfirmationsUpdated(uint256 newRequirement);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        uint256 _requiredConfirmations
    ) initializer public {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, defaultAdmin);
        
        requiredConfirmations = _requiredConfirmations;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    /**
     * @dev Report a PvP battle result
     * @param matchId Unique identifier for the match
     * @param player1 First player address
     * @param player2 Second player address
     * @param winner Address of the winning player
     */
    function reportPvPResult(
        bytes32 matchId,
        address player1,
        address player2,
        address winner
    ) external onlyRole(ORACLE_ROLE) whenNotPaused {
        require(winner == player1 || winner == player2, "Invalid winner");
        require(!pvpResults[matchId].verified, "Result already verified");
        
        // If this is the first report for this match
        if (pvpResults[matchId].timestamp == 0) {
            pvpResults[matchId] = PvPResult({
                player1: player1,
                player2: player2,
                winner: winner,
                timestamp: block.timestamp,
                matchId: matchId,
                verified: false
            });
        }
        
        // Add confirmation
        if (!confirmations[matchId][msg.sender]) {
            confirmations[matchId][msg.sender] = true;
            confirmationCount[matchId]++;
            
            // If enough confirmations, verify the result
            if (confirmationCount[matchId] >= requiredConfirmations) {
                pvpResults[matchId].verified = true;
                
                address loser = winner == player1 ? player2 : player1;
                emit PvPResultReported(matchId, winner, loser);
            }
        }
    }

    /**
     * @dev Report a quest completion
     * @param player Player who completed the quest
     * @param questId The quest identifier
     * @param rewardAmount Reward amount for the quest
     */
    function reportQuestCompletion(
        address player,
        uint256 questId,
        uint256 rewardAmount
    ) external onlyRole(ORACLE_ROLE) whenNotPaused {
        bytes32 questHash = keccak256(abi.encodePacked(player, questId, block.timestamp));
        
        questCompletions[questHash] = QuestCompletion({
            player: player,
            questId: questId,
            timestamp: block.timestamp,
            rewardAmount: rewardAmount,
            verified: true // Single oracle for quest completion
        });
        
        emit QuestCompletionReported(questHash, player, questId);
    }

    /**
     * @dev Update market data for an item
     * @param itemId The item identifier
     * @param averagePrice Current average price
     * @param volume24h 24-hour trading volume
     * @param totalListings Current number of listings
     */
    function updateMarketData(
        uint256 itemId,
        uint256 averagePrice,
        uint256 volume24h,
        uint256 totalListings
    ) external onlyRole(ORACLE_ROLE) whenNotPaused {
        marketData[itemId] = MarketData({
            averagePrice: averagePrice,
            volume24h: volume24h,
            totalListings: totalListings,
            timestamp: block.timestamp
        });
        
        emit MarketDataUpdated(itemId, averagePrice, volume24h);
    }

    /**
     * @dev Stake tokens to become an oracle (placeholder for future implementation)
     * @param amount Amount to stake
     */
    function stakeAsOracle(uint256 amount) external {
        // This would integrate with a staking token in a full implementation
        oracleStake[msg.sender] += amount;
        oracleReputation[msg.sender] = 100; // Starting reputation
        
        emit OracleStakeUpdated(msg.sender, oracleStake[msg.sender]);
    }

    /**
     * @dev Set required confirmations for multi-sig operations
     * @param _requiredConfirmations New requirement
     */
    function setRequiredConfirmations(
        uint256 _requiredConfirmations
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_requiredConfirmations > 0, "Must require at least 1 confirmation");
        requiredConfirmations = _requiredConfirmations;
        emit RequiredConfirmationsUpdated(_requiredConfirmations);
    }

    /**
     * @dev Get PvP result if verified
     * @param matchId The match identifier
     * @return The PvP result struct
     */
    function getVerifiedPvPResult(bytes32 matchId) external view returns (PvPResult memory) {
        require(pvpResults[matchId].verified, "Result not verified");
        return pvpResults[matchId];
    }

    /**
     * @dev Get quest completion data
     * @param questHash The quest hash
     * @return The quest completion struct
     */
    function getQuestCompletion(bytes32 questHash) external view returns (QuestCompletion memory) {
        return questCompletions[questHash];
    }

    /**
     * @dev Get current market data for an item
     * @param itemId The item identifier
     * @return The market data struct
     */
    function getMarketData(uint256 itemId) external view returns (MarketData memory) {
        return marketData[itemId];
    }

    /**
     * @dev Check if a PvP result is verified
     * @param matchId The match identifier
     * @return Whether the result is verified
     */
    function isPvPResultVerified(bytes32 matchId) external view returns (bool) {
        return pvpResults[matchId].verified;
    }

    /**
     * @dev Get oracle reputation score
     * @param oracle The oracle address
     * @return The reputation score
     */
    function getOracleReputation(address oracle) external view returns (uint256) {
        return oracleReputation[oracle];
    }

    /**
     * @dev Pause the contract (emergency function)
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}

