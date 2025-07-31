/**
 * LithosProtocol Web3 SDK
 * 
 * A comprehensive JavaScript SDK for interacting with LithosProtocol smart contracts.
 * Supports both browser and Node.js environments.
 */

import { ethers } from 'ethers';

// Contract ABIs (simplified for example - in production these would be imported from build artifacts)
const GOVERNANCE_TOKEN_ABI = [
  "function balanceOf(address owner) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function delegate(address delegatee)",
  "function getVotes(address account) view returns (uint256)",
  "function mint(address to, uint256 amount)",
  "function burn(uint256 amount)",
  "event Transfer(address indexed from, address indexed to, uint256 value)"
];

const UTILITY_TOKEN_ABI = [
  "function balanceOf(address owner) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function mint(address to, uint256 amount)",
  "function burn(uint256 amount)",
  "event Transfer(address indexed from, address indexed to, uint256 value)"
];

const GAME_LOGIC_ABI = [
  "function registerPlayer()",
  "function getPlayerData(address player) view returns (tuple(uint256 level, uint256 experience, uint256 pvpWins, uint256 pvpLosses, uint256 lastDailyQuestClaim, bool isActive))",
  "function completeQuest(uint256 questId)",
  "function craftItem(uint8 assetType, uint256 level, uint256[] resourceIds, uint256[] resourceAmounts, string metadataURI)",
  "function repairItem(uint256 tokenId)",
  "function recordPvPResult(address winner, address loser)",
  "event PlayerRegistered(address indexed player)",
  "event QuestCompleted(address indexed player, uint256 indexed questId, uint256 reward)",
  "event ItemCrafted(address indexed player, uint256 indexed tokenId, uint256 cost)"
];

const MARKETPLACE_ABI = [
  "function listItem(address nftContract, uint256 tokenId, uint256 amount, uint8 listingType, address paymentToken, uint256 price, uint256 endTime)",
  "function buyItem(uint256 listingId)",
  "function placeBid(uint256 listingId, uint256 amount)",
  "function delistItem(uint256 listingId)",
  "function getListing(uint256 listingId) view returns (tuple(uint256 id, address seller, address nftContract, uint256 tokenId, uint256 amount, uint8 assetType, uint8 listingType, address paymentToken, uint256 price, uint256 endTime, bool isActive, address highestBidder, uint256 highestBid))",
  "event ItemListed(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 amount, uint256 price, uint8 listingType)",
  "event ItemSold(uint256 indexed listingId, address indexed seller, address indexed buyer, uint256 price, uint256 fee)"
];

const STAKING_ABI = [
  "function stakeTokens(uint256 poolId, uint256 amount)",
  "function stakeNFT(uint256 poolId, uint256 tokenId)",
  "function unstakeTokens(uint256 poolId, uint256 amount)",
  "function unstakeNFT(uint256 poolId, uint256 tokenId)",
  "function claimRewards(uint256 poolId)",
  "function getUserStake(address user, uint256 poolId) view returns (tuple(uint256 amount, uint256 stakedAt, uint256 lockUntil, uint256 rewards))",
  "event TokensStaked(address indexed user, uint256 indexed poolId, uint256 amount)",
  "event RewardsClaimed(address indexed user, uint256 indexed poolId, uint256 amount)"
];

/**
 * Main SDK class for LithosProtocol
 */
export class LithosProtocolSDK {
  constructor(config = {}) {
    this.config = {
      network: config.network || 'sepolia',
      rpcUrl: config.rpcUrl,
      contracts: config.contracts || {},
      ...config
    };
    
    this.provider = null;
    this.signer = null;
    this.contracts = {};
    this.isInitialized = false;
  }

  /**
   * Initialize the SDK with a provider
   */
  async initialize(provider) {
    if (typeof provider === 'string') {
      // RPC URL provided
      this.provider = new ethers.JsonRpcProvider(provider);
    } else if (provider && provider.request) {
      // Web3 provider (MetaMask, etc.)
      this.provider = new ethers.BrowserProvider(provider);
      this.signer = await this.provider.getSigner();
    } else {
      throw new Error('Invalid provider');
    }

    await this._initializeContracts();
    this.isInitialized = true;
    
    return this;
  }

  /**
   * Connect to a wallet
   */
  async connectWallet() {
    if (!window.ethereum) {
      throw new Error('No Web3 wallet detected');
    }

    await window.ethereum.request({ method: 'eth_requestAccounts' });
    this.provider = new ethers.BrowserProvider(window.ethereum);
    this.signer = await this.provider.getSigner();
    
    await this._initializeContracts();
    return await this.signer.getAddress();
  }

  /**
   * Initialize contract instances
   */
  async _initializeContracts() {
    const contractAddresses = this.config.contracts;
    
    if (contractAddresses.governanceToken) {
      this.contracts.governanceToken = new ethers.Contract(
        contractAddresses.governanceToken,
        GOVERNANCE_TOKEN_ABI,
        this.signer || this.provider
      );
    }

    if (contractAddresses.utilityToken) {
      this.contracts.utilityToken = new ethers.Contract(
        contractAddresses.utilityToken,
        UTILITY_TOKEN_ABI,
        this.signer || this.provider
      );
    }

    if (contractAddresses.gameLogic) {
      this.contracts.gameLogic = new ethers.Contract(
        contractAddresses.gameLogic,
        GAME_LOGIC_ABI,
        this.signer || this.provider
      );
    }

    if (contractAddresses.marketplace) {
      this.contracts.marketplace = new ethers.Contract(
        contractAddresses.marketplace,
        MARKETPLACE_ABI,
        this.signer || this.provider
      );
    }

    if (contractAddresses.staking) {
      this.contracts.staking = new ethers.Contract(
        contractAddresses.staking,
        STAKING_ABI,
        this.signer || this.provider
      );
    }
  }

  /**
   * Token operations
   */
  async getGovernanceTokenBalance(address) {
    if (!this.contracts.governanceToken) throw new Error('Governance token contract not initialized');
    return await this.contracts.governanceToken.balanceOf(address);
  }

  async getUtilityTokenBalance(address) {
    if (!this.contracts.utilityToken) throw new Error('Utility token contract not initialized');
    return await this.contracts.utilityToken.balanceOf(address);
  }

  async transferGovernanceTokens(to, amount) {
    if (!this.contracts.governanceToken) throw new Error('Governance token contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.governanceToken.transfer(to, amount);
    return await tx.wait();
  }

  async transferUtilityTokens(to, amount) {
    if (!this.contracts.utilityToken) throw new Error('Utility token contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.utilityToken.transfer(to, amount);
    return await tx.wait();
  }

  async delegateVotes(delegatee) {
    if (!this.contracts.governanceToken) throw new Error('Governance token contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.governanceToken.delegate(delegatee);
    return await tx.wait();
  }

  async getVotingPower(address) {
    if (!this.contracts.governanceToken) throw new Error('Governance token contract not initialized');
    return await this.contracts.governanceToken.getVotes(address);
  }

  /**
   * Game operations
   */
  async registerPlayer() {
    if (!this.contracts.gameLogic) throw new Error('Game logic contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.gameLogic.registerPlayer();
    return await tx.wait();
  }

  async getPlayerData(address) {
    if (!this.contracts.gameLogic) throw new Error('Game logic contract not initialized');
    return await this.contracts.gameLogic.getPlayerData(address);
  }

  async completeQuest(questId) {
    if (!this.contracts.gameLogic) throw new Error('Game logic contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.gameLogic.completeQuest(questId);
    return await tx.wait();
  }

  async craftItem(assetType, level, resourceIds, resourceAmounts, metadataURI) {
    if (!this.contracts.gameLogic) throw new Error('Game logic contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.gameLogic.craftItem(
      assetType,
      level,
      resourceIds,
      resourceAmounts,
      metadataURI
    );
    return await tx.wait();
  }

  /**
   * Marketplace operations
   */
  async listItem(nftContract, tokenId, amount, listingType, paymentToken, price, endTime) {
    if (!this.contracts.marketplace) throw new Error('Marketplace contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.marketplace.listItem(
      nftContract,
      tokenId,
      amount,
      listingType,
      paymentToken,
      price,
      endTime
    );
    return await tx.wait();
  }

  async buyItem(listingId) {
    if (!this.contracts.marketplace) throw new Error('Marketplace contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.marketplace.buyItem(listingId);
    return await tx.wait();
  }

  async placeBid(listingId, amount) {
    if (!this.contracts.marketplace) throw new Error('Marketplace contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.marketplace.placeBid(listingId, amount);
    return await tx.wait();
  }

  async getListing(listingId) {
    if (!this.contracts.marketplace) throw new Error('Marketplace contract not initialized');
    return await this.contracts.marketplace.getListing(listingId);
  }

  /**
   * Staking operations
   */
  async stakeTokens(poolId, amount) {
    if (!this.contracts.staking) throw new Error('Staking contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.staking.stakeTokens(poolId, amount);
    return await tx.wait();
  }

  async stakeNFT(poolId, tokenId) {
    if (!this.contracts.staking) throw new Error('Staking contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.staking.stakeNFT(poolId, tokenId);
    return await tx.wait();
  }

  async unstakeTokens(poolId, amount) {
    if (!this.contracts.staking) throw new Error('Staking contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.staking.unstakeTokens(poolId, amount);
    return await tx.wait();
  }

  async claimRewards(poolId) {
    if (!this.contracts.staking) throw new Error('Staking contract not initialized');
    if (!this.signer) throw new Error('No signer available');
    
    const tx = await this.contracts.staking.claimRewards(poolId);
    return await tx.wait();
  }

  async getUserStake(address, poolId) {
    if (!this.contracts.staking) throw new Error('Staking contract not initialized');
    return await this.contracts.staking.getUserStake(address, poolId);
  }

  /**
   * Event listening
   */
  onPlayerRegistered(callback) {
    if (!this.contracts.gameLogic) throw new Error('Game logic contract not initialized');
    this.contracts.gameLogic.on('PlayerRegistered', callback);
  }

  onQuestCompleted(callback) {
    if (!this.contracts.gameLogic) throw new Error('Game logic contract not initialized');
    this.contracts.gameLogic.on('QuestCompleted', callback);
  }

  onItemListed(callback) {
    if (!this.contracts.marketplace) throw new Error('Marketplace contract not initialized');
    this.contracts.marketplace.on('ItemListed', callback);
  }

  onItemSold(callback) {
    if (!this.contracts.marketplace) throw new Error('Marketplace contract not initialized');
    this.contracts.marketplace.on('ItemSold', callback);
  }

  onTokensStaked(callback) {
    if (!this.contracts.staking) throw new Error('Staking contract not initialized');
    this.contracts.staking.on('TokensStaked', callback);
  }

  /**
   * Utility functions
   */
  formatTokenAmount(amount, decimals = 18) {
    return ethers.formatUnits(amount, decimals);
  }

  parseTokenAmount(amount, decimals = 18) {
    return ethers.parseUnits(amount.toString(), decimals);
  }

  async getTransactionReceipt(txHash) {
    return await this.provider.getTransactionReceipt(txHash);
  }

  async waitForTransaction(txHash, confirmations = 1) {
    return await this.provider.waitForTransaction(txHash, confirmations);
  }

  /**
   * Network utilities
   */
  async getNetwork() {
    return await this.provider.getNetwork();
  }

  async getBlockNumber() {
    return await this.provider.getBlockNumber();
  }

  async getGasPrice() {
    return await this.provider.getFeeData();
  }

  /**
   * Error handling
   */
  handleError(error) {
    if (error.code === 'CALL_EXCEPTION') {
      return { type: 'CONTRACT_ERROR', message: error.reason || 'Contract call failed' };
    } else if (error.code === 'INSUFFICIENT_FUNDS') {
      return { type: 'INSUFFICIENT_FUNDS', message: 'Insufficient funds for transaction' };
    } else if (error.code === 'USER_REJECTED') {
      return { type: 'USER_REJECTED', message: 'Transaction rejected by user' };
    } else if (error.code === 'NETWORK_ERROR') {
      return { type: 'NETWORK_ERROR', message: 'Network connection error' };
    } else {
      return { type: 'UNKNOWN_ERROR', message: error.message || 'Unknown error occurred' };
    }
  }
}

/**
 * Factory function for easy SDK creation
 */
export function createLithosProtocolSDK(config) {
  return new LithosProtocolSDK(config);
}

/**
 * Default configurations for different networks
 */
export const NETWORK_CONFIGS = {
  mainnet: {
    network: 'mainnet',
    rpcUrl: 'https://mainnet.infura.io/v3/YOUR_INFURA_KEY',
    contracts: {
      // Will be populated after mainnet deployment
    }
  },
  sepolia: {
    network: 'sepolia',
    rpcUrl: 'https://sepolia.infura.io/v3/YOUR_INFURA_KEY',
    contracts: {
      // Will be populated after testnet deployment
    }
  },
  polygon: {
    network: 'polygon',
    rpcUrl: 'https://polygon-mainnet.infura.io/v3/YOUR_INFURA_KEY',
    contracts: {
      // Will be populated after polygon deployment
    }
  },
  local: {
    network: 'localhost',
    rpcUrl: 'http://localhost:8545',
    contracts: {
      // Local development addresses
    }
  }
};

// Export for CommonJS compatibility
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { LithosProtocolSDK, createLithosProtocolSDK, NETWORK_CONFIGS };
}

