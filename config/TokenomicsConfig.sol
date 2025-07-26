// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title TokenomicsConfig
 * @dev Configuration contract for Aetherium Prime tokenomics
 * Contains all economic parameters and can be used for governance-based updates
 */
library TokenomicsConfig {
    
    // Token Supply Configuration
    struct TokenSupply {
        uint256 governanceTokenTotal;     // Total GOV token supply
        uint256 teamAllocation;           // Team allocation (20%)
        uint256 communityAllocation;      // Community rewards (30%)
        uint256 stakingRewards;           // Staking rewards pool (25%)
        uint256 liquidityPool;            // Liquidity provision (15%)
        uint256 treasuryReserve;          // Treasury reserve (10%)
    }

    // Vesting Schedule Configuration
    struct VestingSchedule {
        uint256 teamVestingDuration;      // 4 years
        uint256 teamCliffPeriod;          // 1 year cliff
        uint256 communityVestingDuration; // 2 years
        uint256 stakingRewardsDuration;   // 5 years
    }

    // Game Economy Configuration
    struct GameEconomy {
        uint256 dailyQuestReward;         // Base daily quest reward
        uint256 pvpWinReward;             // PvP victory reward
        uint256 leaderboardReward;        // Weekly leaderboard reward
        uint256 craftingBaseCost;         // Base crafting cost
        uint256 repairBaseCost;           // Base repair cost
        uint256 tournamentEntryFee;       // Tournament entry fee
        uint256 marketplaceFee;           // Marketplace fee (basis points)
    }

    // Staking Configuration
    struct StakingConfig {
        uint256 govTokenStakingAPY;       // GOV token staking APY (basis points)
        uint256 nftStakingAPY;            // NFT staking APY (basis points)
        uint256 govTokenLockPeriod;       // GOV token lock period
        uint256 nftLockPeriod;            // NFT lock period
        uint256 maxNFTsPerUser;           // Max NFTs per user in staking
    }

    // Asset Rarity Configuration
    struct RarityConfig {
        uint256 commonDropRate;           // Common asset drop rate (basis points)
        uint256 uncommonDropRate;         // Uncommon asset drop rate
        uint256 rareDropRate;             // Rare asset drop rate
        uint256 epicDropRate;             // Epic asset drop rate
        uint256 legendaryDropRate;        // Legendary asset drop rate
    }

    /**
     * @dev Get default token supply configuration
     */
    function getDefaultTokenSupply() internal pure returns (TokenSupply memory) {
        uint256 totalSupply = 1000000 * 10**18; // 1M GOV tokens
        
        return TokenSupply({
            governanceTokenTotal: totalSupply,
            teamAllocation: (totalSupply * 20) / 100,        // 200K tokens
            communityAllocation: (totalSupply * 30) / 100,   // 300K tokens
            stakingRewards: (totalSupply * 25) / 100,        // 250K tokens
            liquidityPool: (totalSupply * 15) / 100,         // 150K tokens
            treasuryReserve: (totalSupply * 10) / 100        // 100K tokens
        });
    }

    /**
     * @dev Get default vesting schedule
     */
    function getDefaultVestingSchedule() internal pure returns (VestingSchedule memory) {
        return VestingSchedule({
            teamVestingDuration: 4 * 365 days,      // 4 years
            teamCliffPeriod: 365 days,              // 1 year cliff
            communityVestingDuration: 2 * 365 days, // 2 years
            stakingRewardsDuration: 5 * 365 days    // 5 years
        });
    }

    /**
     * @dev Get default game economy configuration
     */
    function getDefaultGameEconomy() internal pure returns (GameEconomy memory) {
        return GameEconomy({
            dailyQuestReward: 100 * 10**18,         // 100 PLAY tokens
            pvpWinReward: 50 * 10**18,              // 50 PLAY tokens
            leaderboardReward: 1000 * 10**18,       // 1000 PLAY tokens
            craftingBaseCost: 10 * 10**18,          // 10 PLAY tokens
            repairBaseCost: 5 * 10**18,             // 5 PLAY tokens
            tournamentEntryFee: 25 * 10**18,        // 25 PLAY tokens
            marketplaceFee: 250                     // 2.5% (250 basis points)
        });
    }

    /**
     * @dev Get default staking configuration
     */
    function getDefaultStakingConfig() internal pure returns (StakingConfig memory) {
        return StakingConfig({
            govTokenStakingAPY: 1000,               // 10% APY (1000 basis points)
            nftStakingAPY: 500,                     // 5% APY (500 basis points)
            govTokenLockPeriod: 30 days,            // 30 days lock
            nftLockPeriod: 7 days,                  // 7 days lock
            maxNFTsPerUser: 10                      // Max 10 NFTs per user
        });
    }

    /**
     * @dev Get default rarity configuration
     */
    function getDefaultRarityConfig() internal pure returns (RarityConfig memory) {
        return RarityConfig({
            commonDropRate: 5000,                   // 50% (5000 basis points)
            uncommonDropRate: 3000,                 // 30%
            rareDropRate: 1500,                     // 15%
            epicDropRate: 450,                      // 4.5%
            legendaryDropRate: 50                   // 0.5%
        });
    }

    /**
     * @dev Calculate APY to rewards per second
     * @param apy APY in basis points (e.g., 1000 = 10%)
     * @return rewardsPerSecond Rewards per second per unit staked
     */
    function apyToRewardsPerSecond(uint256 apy) internal pure returns (uint256) {
        // APY to per-second rate: (apy / 10000) / (365 * 24 * 3600)
        return (apy * 10**18) / (10000 * 365 * 24 * 3600);
    }

    /**
     * @dev Calculate rarity-based multipliers
     * @param rarity Rarity level (1-5)
     * @return multiplier Multiplier for rewards/costs
     */
    function getRarityMultiplier(uint256 rarity) internal pure returns (uint256) {
        if (rarity == 1) return 100;      // Common: 1x
        if (rarity == 2) return 150;      // Uncommon: 1.5x
        if (rarity == 3) return 250;      // Rare: 2.5x
        if (rarity == 4) return 500;      // Epic: 5x
        if (rarity == 5) return 1000;     // Legendary: 10x
        return 100; // Default to common
    }

    /**
     * @dev Calculate level-based experience requirements
     * @param level Target level
     * @return experience Experience required to reach level
     */
    function getExperienceForLevel(uint256 level) internal pure returns (uint256) {
        // Quadratic growth: level^2 * 100
        return level * level * 100;
    }

    /**
     * @dev Calculate crafting cost based on rarity and level
     * @param baseCost Base crafting cost
     * @param rarity Asset rarity (1-5)
     * @param level Asset level
     * @return totalCost Total crafting cost
     */
    function calculateCraftingCost(
        uint256 baseCost,
        uint256 rarity,
        uint256 level
    ) internal pure returns (uint256) {
        uint256 rarityMultiplier = getRarityMultiplier(rarity);
        uint256 levelMultiplier = 100 + (level - 1) * 10; // +10% per level above 1
        
        return (baseCost * rarityMultiplier * levelMultiplier) / (100 * 100);
    }

    /**
     * @dev Calculate staking rewards based on amount and time
     * @param amount Amount staked
     * @param stakingTime Time staked in seconds
     * @param rewardsPerSecond Rewards per second rate
     * @return rewards Total rewards earned
     */
    function calculateStakingRewards(
        uint256 amount,
        uint256 stakingTime,
        uint256 rewardsPerSecond
    ) internal pure returns (uint256) {
        return (amount * stakingTime * rewardsPerSecond) / 10**18;
    }

    /**
     * @dev Calculate marketplace fee
     * @param price Sale price
     * @param feeRate Fee rate in basis points
     * @return fee Marketplace fee
     */
    function calculateMarketplaceFee(
        uint256 price,
        uint256 feeRate
    ) internal pure returns (uint256) {
        return (price * feeRate) / 10000;
    }
}

