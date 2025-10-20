// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title DynamicTokenomics
 * @dev Advanced tokenomics contract with dynamic pricing and supply management
 * Implements self-balancing mechanisms to maintain economic sustainability
 */
contract DynamicTokenomics is 
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    struct EconomicMetrics {
        uint256 totalPlayersActive;
        uint256 totalTokensInCirculation;
        uint256 dailyTokensEarned;
        uint256 dailyTokensBurned;
        uint256 averagePlayerLevel;
        uint256 lastUpdateTimestamp;
    }

    struct DynamicPricing {
        uint256 basePrice;
        uint256 currentMultiplier; // Scaled by 1000 (1000 = 1.0x)
        uint256 demandFactor;
        uint256 supplyFactor;
        uint256 lastPriceUpdate;
    }

    struct TokenSink {
        string name;
        uint256 dailyBurnAmount;
        uint256 totalBurned;
        bool isActive;
        uint256 burnRate; // Percentage of transactions (scaled by 100)
    }

    // Economic state
    EconomicMetrics public economicMetrics;
    mapping(uint256 => DynamicPricing) public itemPricing; // itemId => pricing
    mapping(uint256 => TokenSink) public tokenSinks; // sinkId => sink
    
    // Dynamic reward pools
    mapping(uint256 => uint256) public questRewardPools; // questId => pool amount
    mapping(uint256 => uint256) public dailyRewardBudget; // day => budget
    
    // Economic parameters
    uint256 public targetInflationRate; // Scaled by 100 (500 = 5%)
    uint256 public maxDailyRewards;
    uint256 public economicUpdateInterval;
    uint256 public priceVolatilityDamping; // Scaled by 100
    
    // Player activity tracking
    mapping(address => uint256) public lastActivityTimestamp;
    mapping(uint256 => uint256) public dailyActiveUsers; // day => count
    
    // Events
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        uint256 _targetInflationRate,
        uint256 _maxDailyRewards
    ) initializer public {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, defaultAdmin);
        
        targetInflationRate = _targetInflationRate;
        maxDailyRewards = _maxDailyRewards;
        economicUpdateInterval = 1 days;
        priceVolatilityDamping = 200; // 2x damping factor
        
        // Initialize base economic metrics
        economicMetrics.lastUpdateTimestamp = block.timestamp;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    /**
     * @dev Update economic metrics based on current game state
     * @param totalPlayers Current number of active players
     * @param tokensInCirculation Current token supply
     * @param dailyEarned Tokens earned in the last 24h
     * @param dailyBurned Tokens burned in the last 24h
     */
    function updateEconomicMetrics(
        uint256 totalPlayers,
        uint256 tokensInCirculation,
        uint256 dailyEarned,
        uint256 dailyBurned
    ) external onlyRole(ORACLE_ROLE) {
        require(
            block.timestamp >= economicMetrics.lastUpdateTimestamp + economicUpdateInterval,
            "Too early to update"
        );
        
        economicMetrics.totalPlayersActive = totalPlayers;
        economicMetrics.totalTokensInCirculation = tokensInCirculation;
        economicMetrics.dailyTokensEarned = dailyEarned;
        economicMetrics.dailyTokensBurned = dailyBurned;
        economicMetrics.lastUpdateTimestamp = block.timestamp;
        
        // Adjust daily reward budget based on economic health
        _adjustDailyRewardBudget();
        
        emit EconomicMetricsUpdated(totalPlayers, tokensInCirculation, dailyEarned, dailyBurned);
    }

    /**
     * @dev Calculate dynamic price for an item based on supply and demand
     * @param itemId The item identifier
     * @param currentSupply Current number of items in circulation
     * @param recentDemand Recent purchase activity
     * @return The calculated dynamic price
     */
    function calculateDynamicPrice(
        uint256 itemId,
        uint256 currentSupply,
        uint256 recentDemand
    ) external onlyRole(GAME_ROLE) returns (uint256) {
        DynamicPricing storage pricing = itemPricing[itemId];
        
        // Initialize if first time
        if (pricing.basePrice == 0) {
            pricing.basePrice = 1000; // Default base price
            pricing.currentMultiplier = 1000; // 1.0x
        }
        
        // Calculate supply factor (more supply = lower price)
        uint256 supplyFactor = currentSupply > 0 ? 
            (1000 * 1000) / (currentSupply + 1000) : 1000;
        
        // Calculate demand factor (more demand = higher price)
        uint256 demandFactor = recentDemand > 0 ? 
            1000 + (recentDemand * 100) : 1000;
        
        // Apply volatility damping
        uint256 newMultiplier = (
            (pricing.currentMultiplier * priceVolatilityDamping) + 
            (supplyFactor * demandFactor / 1000)
        ) / (priceVolatilityDamping + 1);
        
        // Ensure reasonable bounds (0.1x to 10x)
        if (newMultiplier < 100) newMultiplier = 100;
        if (newMultiplier > 10000) newMultiplier = 10000;
        
        pricing.currentMultiplier = newMultiplier;
        pricing.supplyFactor = supplyFactor;
        pricing.demandFactor = demandFactor;
        pricing.lastPriceUpdate = block.timestamp;
        
        uint256 finalPrice = (pricing.basePrice * newMultiplier) / 1000;
        
        emit DynamicPriceUpdated(itemId, finalPrice, newMultiplier);
        
        return finalPrice;
    }

    /**
     * @dev Create or update a token sink mechanism
     * @param sinkId Unique identifier for the sink
     * @param name Human-readable name
     * @param burnRate Percentage of transactions to burn (scaled by 100)
     */
    function createTokenSink(
        uint256 sinkId,
        string memory name,
        uint256 burnRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(burnRate <= 10000, "Burn rate too high"); // Max 100%
        
        tokenSinks[sinkId] = TokenSink({
            name: name,
            dailyBurnAmount: 0,
            totalBurned: 0,
            isActive: true,
            burnRate: burnRate
        });
        
        emit TokenSinkActivated(sinkId, name, burnRate);
    }

    /**
     * @dev Record token burn from a sink
     * @param sinkId The sink identifier
     * @param amount Amount burned
     */
    function recordTokenBurn(
        uint256 sinkId,
        uint256 amount
    ) external onlyRole(GAME_ROLE) {
        require(tokenSinks[sinkId].isActive, "Sink not active");
        
        tokenSinks[sinkId].dailyBurnAmount += amount;
        tokenSinks[sinkId].totalBurned += amount;
    }

    /**
     * @dev Calculate dynamic quest reward based on current economic state
     * @param questId The quest identifier
     * @param baseReward The base reward amount
     * @param playerLevel The player's level
     * @return The calculated dynamic reward
     */
    function calculateQuestReward(
        uint256 questId,
        uint256 baseReward,
        uint256 playerLevel
    ) external view returns (uint256) {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 remainingBudget = dailyRewardBudget[currentDay];
        
        // If budget is exhausted, reduce rewards
        if (remainingBudget == 0) {
            return baseReward / 2; // 50% reduction
        }
        
        // Calculate inflation adjustment
        uint256 inflationAdjustment = _calculateInflationAdjustment();
        
        // Level-based multiplier (higher level = slightly higher rewards)
        uint256 levelMultiplier = 1000 + (playerLevel * 10); // +1% per level
        
        uint256 adjustedReward = (baseReward * inflationAdjustment * levelMultiplier) / (1000 * 1000);
        
        // Ensure we don't exceed remaining budget
        if (adjustedReward > remainingBudget) {
            adjustedReward = remainingBudget;
        }
        
        return adjustedReward;
    }

    /**
     * @dev Record player activity for economic tracking
     * @param player The player address
     */
    function recordPlayerActivity(address player) external onlyRole(GAME_ROLE) {
        uint256 currentDay = block.timestamp / 1 days;
        
        // Only count once per day per player
        if (lastActivityTimestamp[player] / 1 days < currentDay) {
            dailyActiveUsers[currentDay]++;
            lastActivityTimestamp[player] = block.timestamp;
            
            emit PlayerActivityRecorded(player, block.timestamp);
        }
    }

    /**
     * @dev Get current economic health score (0-100)
     * @return Health score based on various economic factors
     */
    function getEconomicHealthScore() external view returns (uint256) {
        // Calculate based on inflation rate, player activity, and token velocity
        uint256 currentInflation = _getCurrentInflationRate();
        uint256 targetInflation = targetInflationRate;
        
        uint256 inflationScore = currentInflation <= targetInflation ? 
            100 : (targetInflation * 100) / currentInflation;
        
        // Player activity score (more players = better)
        uint256 currentDay = block.timestamp / 1 days;
        uint256 activeToday = dailyActiveUsers[currentDay];
        uint256 activityScore = activeToday > 0 ? 
            (activeToday * 100) / economicMetrics.totalPlayersActive : 0;
        
        // Token velocity score (balanced burn/earn ratio)
        uint256 velocityScore = 50; // Placeholder - would need more complex calculation
        
        // Weighted average
        return (inflationScore * 40 + activityScore * 40 + velocityScore * 20) / 100;
    }

    // Internal functions
    function _adjustDailyRewardBudget() internal {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 healthScore = this.getEconomicHealthScore();
        
        // Adjust budget based on economic health
        uint256 baseBudget = maxDailyRewards;
        uint256 adjustedBudget = (baseBudget * healthScore) / 100;
        
        dailyRewardBudget[currentDay] = adjustedBudget;
    }

    function _calculateInflationAdjustment() internal view returns (uint256) {
        uint256 currentInflation = _getCurrentInflationRate();
        
        if (currentInflation > targetInflationRate) {
            // Reduce rewards to combat inflation
            return (targetInflationRate * 1000) / currentInflation;
        } else {
            // Can afford to increase rewards slightly
            return 1000 + ((targetInflationRate - currentInflation) * 2);
        }
    }

    function _getCurrentInflationRate() internal view returns (uint256) {
        if (economicMetrics.totalTokensInCirculation == 0) return 0;
        
        uint256 netInflation = economicMetrics.dailyTokensEarned > economicMetrics.dailyTokensBurned ?
            economicMetrics.dailyTokensEarned - economicMetrics.dailyTokensBurned : 0;
        
        return (netInflation * 36500) / economicMetrics.totalTokensInCirculation; // Annualized rate
    }

    // View functions
    function getCurrentPrice(uint256 itemId) external view returns (uint256) {
        DynamicPricing memory pricing = itemPricing[itemId];
        return (pricing.basePrice * pricing.currentMultiplier) / 1000;
    }

    function getTokenSink(uint256 sinkId) external view returns (TokenSink memory) {
        return tokenSinks[sinkId];
    }

    function getDailyActiveUsers(uint256 day) external view returns (uint256) {
        return dailyActiveUsers[day];
    }

    function getRemainingDailyBudget() external view returns (uint256) {
        uint256 currentDay = block.timestamp / 1 days;
        return dailyRewardBudget[currentDay];
    }
}

