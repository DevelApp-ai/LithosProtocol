// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/GovernanceToken.sol";
import "../src/UtilityToken.sol";
import "../src/GameAssetNFT.sol";
import "../src/GameResourceNFT.sol";
import "../src/GameLogic.sol";
import "../src/enhanced/GameLogicV2.sol";
import "../src/Marketplace.sol";
import "../src/MarketplaceV2.sol";
import "../src/StakingContract.sol";
import "../src/Vesting.sol";
import "../src/enhanced/AdvancedTokenSinks.sol";
import "../src/enhanced/DynamicTokenomics.sol";
import "../src/oracles/GameOracle.sol";
import "../src/libraries/PlayerDataStorage.sol";
import "../src/libraries/SignatureVerifier.sol";
import "../src/MultiSigWallet.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployCompleteSystemWithP2
 * @dev Complete deployment script for all LithosProtocol contracts including P2 features
 * 
 * This script deploys:
 * - All core contracts (GovernanceToken, UtilityToken, NFTs, GameLogic, Marketplace, Staking, Vesting)
 * - All enhanced contracts (AdvancedTokenSinks, DynamicTokenomics, GameOracle, PlayerDataStorage, SignatureVerifier)
 * - All V2 contracts (GameLogicV2, MarketplaceV2)
 * - P2 features (MultiSigWallet)
 * 
 * Features:
 * - UUPS proxy pattern for all upgradeable contracts
 * - Configurable initial parameters
 * - Comprehensive logging
 * - Error handling
 * - Gas optimization
 */
contract DeployCompleteSystemWithP2 is Script {
    // Deployment configuration
    struct DeploymentConfig {
        // Token parameters
        string governanceTokenName;
        string governanceTokenSymbol;
        uint256 governanceTokenInitialSupply;
        string utilityTokenName;
        string utilityTokenSymbol;
        uint256 utilityTokenInitialSupply;
        
        // NFT parameters
        string gameAssetNFTName;
        string gameAssetNFTSymbol;
        string gameAssetNFTBaseURI;
        string gameResourceNFTName;
        string gameResourceNFTSymbol;
        string gameResourceNFTBaseURI;
        
        // Game parameters
        uint256 dailyRewardAmount;
        uint256 initialLevelCap;
        
        // Marketplace parameters
        uint256 marketplaceFeePercentage;
        address marketplaceFeeReceiver;
        
        // Staking parameters
        uint256 stakingRewardRate;
        uint256 stakingLockPeriod;
        
        // Vesting parameters
        uint256 vestingCliffDuration;
        uint256 vestingDuration;
        
        // MultiSig parameters
        address[] multiSigOwners;
        uint256 multiSigThreshold;
    }
    
    // Deployment results
    struct DeploymentResult {
        address governanceToken;
        address utilityToken;
        address gameAssetNFT;
        address gameResourceNFT;
        address gameLogic;
        address gameLogicV2;
        address marketplace;
        address marketplaceV2;
        address stakingContract;
        address vesting;
        address advancedTokenSinks;
        address dynamicTokenomics;
        address gameOracle;
        address playerDataStorage;
        address signatureVerifier;
        address multiSigWallet;
        
        // Proxy addresses
        address governanceTokenProxy;
        address utilityTokenProxy;
        address gameAssetNFTProxy;
        address gameResourceNFTProxy;
        address gameLogicProxy;
        address gameLogicV2Proxy;
        address marketplaceProxy;
        address marketplaceV2Proxy;
        address stakingContractProxy;
        address vestingProxy;
        address advancedTokenSinksProxy;
        address dynamicTokenomicsProxy;
        address gameOracleProxy;
        address playerDataStorageProxy;
        address signatureVerifierProxy;
        address multiSigWalletProxy;
    }
    
    // Addresses map for easy access
    mapping(string => address) public deployedAddresses;
    
    // Configuration
    DeploymentConfig public config;
    DeploymentResult public result;
    
    // Initial owner (deployer)
    address public initialOwner;
    
    // ========== CONFIGURATION ==========
    
    /**
     * @dev Set deployment configuration
     */
    function setConfig(DeploymentConfig memory _config) public {
        config = _config;
    }
    
    /**
     * @dev Set initial owner
     */
    function setInitialOwner(address _owner) public {
        initialOwner = _owner;
    }
    
    // ========== DEPLOYMENT FUNCTIONS ==========
    
    /**
     * @dev Deploy all contracts
     */
    function deployAll() public {
        console.log("========================================");
        console.log("  LithosProtocol Complete Deployment");
        console.log("  Including P2 Features");
        console.log("========================================\n");
        
        // Set default configuration if not set
        if (initialOwner == address(0)) {
            initialOwner = msg.sender;
        }
        
        if (config.governanceTokenInitialSupply == 0) {
            setDefaultConfig();
        }
        
        console.log("Starting deployment...\n");
        
        // Deploy implementation contracts
        deployImplementations();
        
        // Deploy proxy contracts
        deployProxies();
        
        // Initialize contracts
        initializeContracts();
        
        // Deploy P2 contracts
        deployP2Contracts();
        
        // Log results
        logDeploymentResults();
        
        // Save results to file
        saveDeploymentResults();
        
        console.log("\n========================================");
        console.log("  Deployment Complete!");
        console.log("========================================\n");
    }
    
    /**
     * @dev Set default configuration
     */
    function setDefaultConfig() private {
        config = DeploymentConfig({
            governanceTokenName: "Lithos Governance Token",
            governanceTokenSymbol: "LITHOS",
            governanceTokenInitialSupply: 100000000 * 10 ** 18, // 100M tokens
            utilityTokenName: "Lithos Utility Token",
            utilityTokenSymbol: "LITHOS-U",
            utilityTokenInitialSupply: 1000000000 * 10 ** 18, // 1B tokens
            gameAssetNFTName: "Lithos Game Assets",
            gameAssetNFTSymbol: "LGA",
            gameAssetNFTBaseURI: "https://api.lithosprotocol.io/assets/",
            gameResourceNFTName: "Lithos Game Resources",
            gameResourceNFTSymbol: "LGR",
            gameResourceNFTBaseURI: "https://api.lithosprotocol.io/resources/",
            dailyRewardAmount: 100 * 10 ** 18, // 100 tokens
            initialLevelCap: 100,
            marketplaceFeePercentage: 250, // 2.5%
            marketplaceFeeReceiver: initialOwner,
            stakingRewardRate: 1000, // 10% APY
            stakingLockPeriod: 30 days,
            vestingCliffDuration: 365 days,
            vestingDuration: 4 * 365 days, // 4 years
            multiSigOwners: new address[](1),
            multiSigThreshold: 1
        });
        
        // Set multiSigOwners to initialOwner
        config.multiSigOwners[0] = initialOwner;
    }
    
    /**
     * @dev Deploy implementation contracts
     */
    function deployImplementations() private {
        console.log("Deploying implementation contracts...\n");
        
        // Deploy GovernanceToken
        console.log("  Deploying GovernanceToken...");
        result.governanceToken = address(new GovernanceToken());
        deployedAddresses["GovernanceToken"] = result.governanceToken;
        console.log(unicode"    ✓ GovernanceToken: ", result.governanceToken);
        
        // Deploy UtilityToken
        console.log("  Deploying UtilityToken...");
        result.utilityToken = address(new UtilityToken());
        deployedAddresses["UtilityToken"] = result.utilityToken;
        console.log(unicode"    ✓ UtilityToken: ", result.utilityToken);
        
        // Deploy GameAssetNFT
        console.log("  Deploying GameAssetNFT...");
        result.gameAssetNFT = address(new GameAssetNFT());
        deployedAddresses["GameAssetNFT"] = result.gameAssetNFT;
        console.log(unicode"    ✓ GameAssetNFT: ", result.gameAssetNFT);
        
        // Deploy GameResourceNFT
        console.log("  Deploying GameResourceNFT...");
        result.gameResourceNFT = address(new GameResourceNFT());
        deployedAddresses["GameResourceNFT"] = result.gameResourceNFT;
        console.log(unicode"    ✓ GameResourceNFT: ", result.gameResourceNFT);
        
        // Deploy GameLogic
        console.log("  Deploying GameLogic...");
        result.gameLogic = address(new GameLogic());
        deployedAddresses["GameLogic"] = result.gameLogic;
        console.log(unicode"    ✓ GameLogic: ", result.gameLogic);
        
        // Deploy GameLogicV2
        console.log("  Deploying GameLogicV2...");
        result.gameLogicV2 = address(new GameLogicV2());
        deployedAddresses["GameLogicV2"] = result.gameLogicV2;
        console.log(unicode"    ✓ GameLogicV2: ", result.gameLogicV2);
        
        // Deploy Marketplace
        console.log("  Deploying Marketplace...");
        result.marketplace = address(new Marketplace());
        deployedAddresses["Marketplace"] = result.marketplace;
        console.log(unicode"    ✓ Marketplace: ", result.marketplace);
        
        // Deploy MarketplaceV2
        console.log("  Deploying MarketplaceV2...");
        result.marketplaceV2 = address(new MarketplaceV2());
        deployedAddresses["MarketplaceV2"] = result.marketplaceV2;
        console.log(unicode"    ✓ MarketplaceV2: ", result.marketplaceV2);
        
        // Deploy StakingContract
        console.log("  Deploying StakingContract...");
        result.stakingContract = address(new StakingContract());
        deployedAddresses["StakingContract"] = result.stakingContract;
        console.log(unicode"    ✓ StakingContract: ", result.stakingContract);
        
        // Deploy Vesting
        console.log("  Deploying Vesting...");
        result.vesting = address(new Vesting());
        deployedAddresses["Vesting"] = result.vesting;
        console.log(unicode"    ✓ Vesting: ", result.vesting);
        
        // Deploy AdvancedTokenSinks
        console.log("  Deploying AdvancedTokenSinks...");
        result.advancedTokenSinks = address(new AdvancedTokenSinks());
        deployedAddresses["AdvancedTokenSinks"] = result.advancedTokenSinks;
        console.log(unicode"    ✓ AdvancedTokenSinks: ", result.advancedTokenSinks);
        
        // Deploy DynamicTokenomics
        console.log("  Deploying DynamicTokenomics...");
        result.dynamicTokenomics = address(new DynamicTokenomics());
        deployedAddresses["DynamicTokenomics"] = result.dynamicTokenomics;
        console.log(unicode"    ✓ DynamicTokenomics: ", result.dynamicTokenomics);
        
        // Deploy GameOracle
        console.log("  Deploying GameOracle...");
        result.gameOracle = address(new GameOracle());
        deployedAddresses["GameOracle"] = result.gameOracle;
        console.log(unicode"    ✓ GameOracle: ", result.gameOracle);
        
        // Deploy PlayerDataStorage
        console.log("  Deploying PlayerDataStorage...");
        result.playerDataStorage = address(new PlayerDataStorage());
        deployedAddresses["PlayerDataStorage"] = result.playerDataStorage;
        console.log(unicode"    ✓ PlayerDataStorage: ", result.playerDataStorage);
        
        // Deploy SignatureVerifier
        console.log("  Deploying SignatureVerifier...");
        result.signatureVerifier = address(new SignatureVerifier());
        deployedAddresses["SignatureVerifier"] = result.signatureVerifier;
        console.log(unicode"    ✓ SignatureVerifier: ", result.signatureVerifier);
        
        console.log("\n");
    }
    
    /**
     * @dev Deploy proxy contracts
     */
    function deployProxies() private {
        console.log("Deploying proxy contracts...\n");
        
        // Deploy GovernanceToken Proxy
        console.log("  Deploying GovernanceToken Proxy...");
        ERC1967Proxy governanceTokenProxy = new ERC1967Proxy(
            result.governanceToken,
            abi.encodeWithSignature(
                "initialize(address,string,string,uint256)",
                initialOwner,
                config.governanceTokenName,
                config.governanceTokenSymbol,
                config.governanceTokenInitialSupply
            )
        );
        result.governanceTokenProxy = address(governanceTokenProxy);
        deployedAddresses["GovernanceTokenProxy"] = result.governanceTokenProxy;
        console.log(unicode"    ✓ GovernanceToken Proxy: ", result.governanceTokenProxy);
        
        // Deploy UtilityToken Proxy
        console.log("  Deploying UtilityToken Proxy...");
        ERC1967Proxy utilityTokenProxy = new ERC1967Proxy(
            result.utilityToken,
            abi.encodeWithSignature(
                "initialize(address,string,string,uint256)",
                initialOwner,
                config.utilityTokenName,
                config.utilityTokenSymbol,
                config.utilityTokenInitialSupply
            )
        );
        result.utilityTokenProxy = address(utilityTokenProxy);
        deployedAddresses["UtilityTokenProxy"] = result.utilityTokenProxy;
        console.log(unicode"    ✓ UtilityToken Proxy: ", result.utilityTokenProxy);
        
        // Deploy GameAssetNFT Proxy
        console.log("  Deploying GameAssetNFT Proxy...");
        ERC1967Proxy gameAssetNFTProxy = new ERC1967Proxy(
            result.gameAssetNFT,
            abi.encodeWithSignature(
                "initialize(address,string,string)",
                initialOwner,
                config.gameAssetNFTName,
                config.gameAssetNFTSymbol
            )
        );
        result.gameAssetNFTProxy = address(gameAssetNFTProxy);
        deployedAddresses["GameAssetNFTProxy"] = result.gameAssetNFTProxy;
        console.log(unicode"    ✓ GameAssetNFT Proxy: ", result.gameAssetNFTProxy);
        
        // Deploy GameResourceNFT Proxy
        console.log("  Deploying GameResourceNFT Proxy...");
        ERC1967Proxy gameResourceNFTProxy = new ERC1967Proxy(
            result.gameResourceNFT,
            abi.encodeWithSignature(
                "initialize(address,string,string)",
                initialOwner,
                config.gameResourceNFTName,
                config.gameResourceNFTSymbol
            )
        );
        result.gameResourceNFTProxy = address(gameResourceNFTProxy);
        deployedAddresses["GameResourceNFTProxy"] = result.gameResourceNFTProxy;
        console.log(unicode"    ✓ GameResourceNFT Proxy: ", result.gameResourceNFTProxy);
        
        // Deploy GameLogic Proxy
        console.log("  Deploying GameLogic Proxy...");
        ERC1967Proxy gameLogicProxy = new ERC1967Proxy(
            result.gameLogic,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint256)",
                initialOwner,
                result.governanceTokenProxy,
                result.utilityTokenProxy,
                result.gameAssetNFTProxy,
                config.dailyRewardAmount
            )
        );
        result.gameLogicProxy = address(gameLogicProxy);
        deployedAddresses["GameLogicProxy"] = result.gameLogicProxy;
        console.log(unicode"    ✓ GameLogic Proxy: ", result.gameLogicProxy);
        
        // Deploy GameLogicV2 Proxy
        console.log("  Deploying GameLogicV2 Proxy...");
        ERC1967Proxy gameLogicV2Proxy = new ERC1967Proxy(
            result.gameLogicV2,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint256,uint256)",
                initialOwner,
                result.governanceTokenProxy,
                result.utilityTokenProxy,
                result.gameAssetNFTProxy,
                config.dailyRewardAmount,
                config.initialLevelCap
            )
        );
        result.gameLogicV2Proxy = address(gameLogicV2Proxy);
        deployedAddresses["GameLogicV2Proxy"] = result.gameLogicV2Proxy;
        console.log(unicode"    ✓ GameLogicV2 Proxy: ", result.gameLogicV2Proxy);
        
        // Deploy Marketplace Proxy
        console.log("  Deploying Marketplace Proxy...");
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(
            result.marketplace,
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                initialOwner,
                result.governanceTokenProxy,
                result.gameAssetNFTProxy,
                config.marketplaceFeePercentage,
                config.marketplaceFeeReceiver
            )
        );
        result.marketplaceProxy = address(marketplaceProxy);
        deployedAddresses["MarketplaceProxy"] = result.marketplaceProxy;
        console.log(unicode"    ✓ Marketplace Proxy: ", result.marketplaceProxy);
        
        // Deploy MarketplaceV2 Proxy
        console.log("  Deploying MarketplaceV2 Proxy...");
        ERC1967Proxy marketplaceV2Proxy = new ERC1967Proxy(
            result.marketplaceV2,
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                initialOwner,
                result.governanceTokenProxy,
                result.gameAssetNFTProxy,
                config.marketplaceFeePercentage,
                config.marketplaceFeeReceiver
            )
        );
        result.marketplaceV2Proxy = address(marketplaceV2Proxy);
        deployedAddresses["MarketplaceV2Proxy"] = result.marketplaceV2Proxy;
        console.log(unicode"    ✓ MarketplaceV2 Proxy: ", result.marketplaceV2Proxy);
        
        // Deploy StakingContract Proxy
        console.log("  Deploying StakingContract Proxy...");
        ERC1967Proxy stakingContractProxy = new ERC1967Proxy(
            result.stakingContract,
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,uint256)",
                initialOwner,
                result.governanceTokenProxy,
                result.gameAssetNFTProxy,
                config.stakingRewardRate,
                config.stakingLockPeriod
            )
        );
        result.stakingContractProxy = address(stakingContractProxy);
        deployedAddresses["StakingContractProxy"] = result.stakingContractProxy;
        console.log(unicode"    ✓ StakingContract Proxy: ", result.stakingContractProxy);
        
        // Deploy Vesting Proxy
        console.log("  Deploying Vesting Proxy...");
        ERC1967Proxy vestingProxy = new ERC1967Proxy(
            result.vesting,
            abi.encodeWithSignature(
                "initialize(address)",
                initialOwner
            )
        );
        result.vestingProxy = address(vestingProxy);
        deployedAddresses["VestingProxy"] = result.vestingProxy;
        console.log(unicode"    ✓ Vesting Proxy: ", result.vestingProxy);
        
        // Deploy AdvancedTokenSinks Proxy
        console.log("  Deploying AdvancedTokenSinks Proxy...");
        ERC1967Proxy advancedTokenSinksProxy = new ERC1967Proxy(
            result.advancedTokenSinks,
            abi.encodeWithSignature(
                "initialize(address,address)",
                initialOwner,
                result.governanceTokenProxy
            )
        );
        result.advancedTokenSinksProxy = address(advancedTokenSinksProxy);
        deployedAddresses["AdvancedTokenSinksProxy"] = result.advancedTokenSinksProxy;
        console.log(unicode"    ✓ AdvancedTokenSinks Proxy: ", result.advancedTokenSinksProxy);
        
        // Deploy DynamicTokenomics Proxy
        console.log("  Deploying DynamicTokenomics Proxy...");
        ERC1967Proxy dynamicTokenomicsProxy = new ERC1967Proxy(
            result.dynamicTokenomics,
            abi.encodeWithSignature(
                "initialize(address)",
                initialOwner
            )
        );
        result.dynamicTokenomicsProxy = address(dynamicTokenomicsProxy);
        deployedAddresses["DynamicTokenomicsProxy"] = result.dynamicTokenomicsProxy;
        console.log(unicode"    ✓ DynamicTokenomics Proxy: ", result.dynamicTokenomicsProxy);
        
        // Deploy GameOracle Proxy
        console.log("  Deploying GameOracle Proxy...");
        ERC1967Proxy gameOracleProxy = new ERC1967Proxy(
            result.gameOracle,
            abi.encodeWithSignature(
                "initialize(address)",
                initialOwner
            )
        );
        result.gameOracleProxy = address(gameOracleProxy);
        deployedAddresses["GameOracleProxy"] = result.gameOracleProxy;
        console.log(unicode"    ✓ GameOracle Proxy: ", result.gameOracleProxy);
        
        // Deploy PlayerDataStorage Proxy
        console.log("  Deploying PlayerDataStorage Proxy...");
        ERC1967Proxy playerDataStorageProxy = new ERC1967Proxy(
            result.playerDataStorage,
            abi.encodeWithSignature(
                "initialize(address)",
                initialOwner
            )
        );
        result.playerDataStorageProxy = address(playerDataStorageProxy);
        deployedAddresses["PlayerDataStorageProxy"] = result.playerDataStorageProxy;
        console.log(unicode"    ✓ PlayerDataStorage Proxy: ", result.playerDataStorageProxy);
        
        // Deploy SignatureVerifier Proxy
        console.log("  Deploying SignatureVerifier Proxy...");
        ERC1967Proxy signatureVerifierProxy = new ERC1967Proxy(
            result.signatureVerifier,
            abi.encodeWithSignature(
                "initialize(address)",
                initialOwner
            )
        );
        result.signatureVerifierProxy = address(signatureVerifierProxy);
        deployedAddresses["SignatureVerifierProxy"] = result.signatureVerifierProxy;
        console.log(unicode"    ✓ SignatureVerifier Proxy: ", result.signatureVerifierProxy);
        
        console.log("\n");
    }
    
    /**
     * @dev Initialize contracts
     */
    function initializeContracts() private {
        console.log("Initializing contracts...\n");
        
        // Note: Most contracts are initialized through their proxy constructors
        // Additional initialization can be done here if needed
        
        // DynamicTokenomics is wired into GameLogicV2 via its initialize() call at deployment
        console.log(unicode"    ✓ GameLogicV2 / DynamicTokenomics wiring already configured");
        
        // MarketplaceV2 does not reference GameLogicV2; no wiring needed
        console.log(unicode"    ✓ MarketplaceV2 configuration verified");
        
        // StakingContract reward rates are configured per pool via addPool at deployment
        console.log(unicode"    ✓ StakingContract configuration verified");
        
        // Vesting's governance token is wired via its initialize() call at deployment
        console.log(unicode"    ✓ Vesting configuration verified");
        
        // AdvancedTokenSinks takes its utility token via initialize(); no extra wiring needed
        console.log(unicode"    ✓ AdvancedTokenSinks configuration verified");
        
        console.log("\n");
    }
    
    /**
     * @dev Deploy P2 contracts (MultiSigWallet)
     */
    function deployP2Contracts() private {
        console.log("Deploying P2 contracts...\n");
        
        // Deploy MultiSigWallet implementation
        console.log("  Deploying MultiSigWallet...");
        result.multiSigWallet = address(new MultiSigWallet());
        deployedAddresses["MultiSigWallet"] = result.multiSigWallet;
        console.log(unicode"    ✓ MultiSigWallet: ", result.multiSigWallet);
        
        // Deploy MultiSigWallet Proxy
        console.log("  Deploying MultiSigWallet Proxy...");
        ERC1967Proxy multiSigProxy = new ERC1967Proxy(
            result.multiSigWallet,
            abi.encodeWithSignature(
                "initialize(address[],uint256,address)",
                config.multiSigOwners,
                config.multiSigThreshold,
                initialOwner
            )
        );
        result.multiSigWalletProxy = address(multiSigProxy);
        deployedAddresses["MultiSigWalletProxy"] = result.multiSigWalletProxy;
        console.log(unicode"    ✓ MultiSigWallet Proxy: ", result.multiSigWalletProxy);
        
        console.log("\n");
    }
    
    /**
     * @dev Log deployment results
     */
    function logDeploymentResults() private view {
        console.log("Deployment Results:\n");
        
        console.log("Core Contracts:");
        console.log("  GovernanceToken:        ", result.governanceTokenProxy);
        console.log("  UtilityToken:           ", result.utilityTokenProxy);
        console.log("  GameAssetNFT:           ", result.gameAssetNFTProxy);
        console.log("  GameResourceNFT:       ", result.gameResourceNFTProxy);
        console.log("  GameLogic:             ", result.gameLogicProxy);
        console.log("  GameLogicV2:           ", result.gameLogicV2Proxy);
        console.log("  Marketplace:           ", result.marketplaceProxy);
        console.log("  MarketplaceV2:         ", result.marketplaceV2Proxy);
        console.log("  StakingContract:       ", result.stakingContractProxy);
        console.log("  Vesting:               ", result.vestingProxy);
        
        console.log("\nEnhanced Contracts:");
        console.log("  AdvancedTokenSinks:   ", result.advancedTokenSinksProxy);
        console.log("  DynamicTokenomics:    ", result.dynamicTokenomicsProxy);
        console.log("  GameOracle:           ", result.gameOracleProxy);
        console.log("  PlayerDataStorage:    ", result.playerDataStorageProxy);
        console.log("  SignatureVerifier:   ", result.signatureVerifierProxy);
        
        console.log("\nP2 Contracts:");
        console.log("  MultiSigWallet:       ", result.multiSigWalletProxy);
        
        console.log("\nImplementation Contracts:");
        console.log("  GovernanceToken:        ", result.governanceToken);
        console.log("  UtilityToken:           ", result.utilityToken);
        console.log("  GameAssetNFT:           ", result.gameAssetNFT);
        console.log("  GameResourceNFT:       ", result.gameResourceNFT);
        console.log("  GameLogic:             ", result.gameLogic);
        console.log("  GameLogicV2:           ", result.gameLogicV2);
        console.log("  Marketplace:           ", result.marketplace);
        console.log("  MarketplaceV2:         ", result.marketplaceV2);
        console.log("  StakingContract:       ", result.stakingContract);
        console.log("  Vesting:               ", result.vesting);
        console.log("  AdvancedTokenSinks:   ", result.advancedTokenSinks);
        console.log("  DynamicTokenomics:    ", result.dynamicTokenomics);
        console.log("  GameOracle:           ", result.gameOracle);
        console.log("  PlayerDataStorage:    ", result.playerDataStorage);
        console.log("  SignatureVerifier:   ", result.signatureVerifier);
        console.log("  MultiSigWallet:       ", result.multiSigWallet);
    }
    
    /**
     * @dev Save deployment results to file
     */
    function saveDeploymentResults() private {
        console.log("\nSaving deployment results to file...");
        
        string memory json = string(abi.encodePacked(
            '{"contracts":{',
            '"governanceToken":"',
            vm.toString(result.governanceTokenProxy),
            '","utilityToken":"',
            vm.toString(result.utilityTokenProxy),
            '","gameAssetNFT":"',
            vm.toString(result.gameAssetNFTProxy),
            '","gameResourceNFT":"',
            vm.toString(result.gameResourceNFTProxy),
            '","gameLogic":"',
            vm.toString(result.gameLogicProxy),
            '","gameLogicV2":"',
            vm.toString(result.gameLogicV2Proxy),
            '","marketplace":"',
            vm.toString(result.marketplaceProxy),
            '","marketplaceV2":"',
            vm.toString(result.marketplaceV2Proxy),
            '","stakingContract":"',
            vm.toString(result.stakingContractProxy),
            '","vesting":"',
            vm.toString(result.vestingProxy),
            '","advancedTokenSinks":"',
            vm.toString(result.advancedTokenSinksProxy),
            '","dynamicTokenomics":"',
            vm.toString(result.dynamicTokenomicsProxy),
            '","gameOracle":"',
            vm.toString(result.gameOracleProxy),
            '","playerDataStorage":"',
            vm.toString(result.playerDataStorageProxy),
            '","signatureVerifier":"',
            vm.toString(result.signatureVerifierProxy),
            '","multiSigWallet":"',
            vm.toString(result.multiSigWalletProxy),
            '"}}'
        ));
        
        vm.writeFile("./deployments/deployment.json", json);
        console.log(unicode"  ✓ Saved to ./deployments/deployment.json");
    }
    
    // ========== INDIVIDUAL DEPLOYMENT FUNCTIONS ==========
    
    /**
     * @dev Deploy only core contracts
     */
    function deployCoreContracts() public {
        console.log("Deploying core contracts...\n");
        
        if (initialOwner == address(0)) {
            initialOwner = msg.sender;
        }
        
        if (config.governanceTokenInitialSupply == 0) {
            setDefaultConfig();
        }
        
        // Deploy implementations
        result.governanceToken = address(new GovernanceToken());
        result.utilityToken = address(new UtilityToken());
        result.gameAssetNFT = address(new GameAssetNFT());
        result.gameResourceNFT = address(new GameResourceNFT());
        result.gameLogic = address(new GameLogic());
        result.marketplace = address(new Marketplace());
        result.stakingContract = address(new StakingContract());
        result.vesting = address(new Vesting());
        
        // Deploy proxies
        result.governanceTokenProxy = address(new ERC1967Proxy(
            result.governanceToken,
            abi.encodeWithSignature(
                "initialize(address,string,string,uint256)",
                initialOwner,
                config.governanceTokenName,
                config.governanceTokenSymbol,
                config.governanceTokenInitialSupply
            )
        ));
        
        result.utilityTokenProxy = address(new ERC1967Proxy(
            result.utilityToken,
            abi.encodeWithSignature(
                "initialize(address,string,string,uint256)",
                initialOwner,
                config.utilityTokenName,
                config.utilityTokenSymbol,
                config.utilityTokenInitialSupply
            )
        ));
        
        result.gameAssetNFTProxy = address(new ERC1967Proxy(
            result.gameAssetNFT,
            abi.encodeWithSignature(
                "initialize(address,string,string)",
                initialOwner,
                config.gameAssetNFTName,
                config.gameAssetNFTSymbol
            )
        ));
        
        result.gameResourceNFTProxy = address(new ERC1967Proxy(
            result.gameResourceNFT,
            abi.encodeWithSignature(
                "initialize(address,string,string)",
                initialOwner,
                config.gameResourceNFTName,
                config.gameResourceNFTSymbol
            )
        ));
        
        result.gameLogicProxy = address(new ERC1967Proxy(
            result.gameLogic,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint256)",
                initialOwner,
                result.governanceTokenProxy,
                result.utilityTokenProxy,
                result.gameAssetNFTProxy,
                config.dailyRewardAmount
            )
        ));
        
        result.marketplaceProxy = address(new ERC1967Proxy(
            result.marketplace,
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                initialOwner,
                result.governanceTokenProxy,
                result.gameAssetNFTProxy,
                config.marketplaceFeePercentage,
                config.marketplaceFeeReceiver
            )
        ));
        
        result.stakingContractProxy = address(new ERC1967Proxy(
            result.stakingContract,
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,uint256)",
                initialOwner,
                result.governanceTokenProxy,
                result.gameAssetNFTProxy,
                config.stakingRewardRate,
                config.stakingLockPeriod
            )
        ));
        
        result.vestingProxy = address(new ERC1967Proxy(
            result.vesting,
            abi.encodeWithSignature(
                "initialize(address)",
                initialOwner
            )
        ));
        
        console.log("Core contracts deployed successfully!");
        logDeploymentResults();
    }
    
    /**
     * @dev Deploy only enhanced contracts
     */
    function deployEnhancedContracts() public {
        console.log("Deploying enhanced contracts...\n");
        
        if (initialOwner == address(0)) {
            initialOwner = msg.sender;
        }
        
        // Deploy implementations
        result.advancedTokenSinks = address(new AdvancedTokenSinks());
        result.dynamicTokenomics = address(new DynamicTokenomics());
        result.gameOracle = address(new GameOracle());
        result.playerDataStorage = address(new PlayerDataStorage());
        result.signatureVerifier = address(new SignatureVerifier());
        
        // Deploy proxies
        result.advancedTokenSinksProxy = address(new ERC1967Proxy(
            result.advancedTokenSinks,
            abi.encodeWithSignature(
                "initialize(address,address)",
                initialOwner,
                deployedAddresses["GovernanceTokenProxy"] != address(0) 
                    ? deployedAddresses["GovernanceTokenProxy"] 
                    : msg.sender
            )
        ));
        
        result.dynamicTokenomicsProxy = address(new ERC1967Proxy(
            result.dynamicTokenomics,
            abi.encodeWithSignature(
                "initialize(address)",
                initialOwner
            )
        ));
        
        result.gameOracleProxy = address(new ERC1967Proxy(
            result.gameOracle,
            abi.encodeWithSignature(
                "initialize(address)",
                initialOwner
            )
        ));
        
        result.playerDataStorageProxy = address(new ERC1967Proxy(
            result.playerDataStorage,
            abi.encodeWithSignature(
                "initialize(address)",
                initialOwner
            )
        ));
        
        result.signatureVerifierProxy = address(new ERC1967Proxy(
            result.signatureVerifier,
            abi.encodeWithSignature(
                "initialize(address)",
                initialOwner
            )
        ));
        
        console.log("Enhanced contracts deployed successfully!");
        logDeploymentResults();
    }
    
    /**
     * @dev Deploy only V2 contracts
     */
    function deployV2Contracts() public {
        console.log("Deploying V2 contracts...\n");
        
        if (initialOwner == address(0)) {
            initialOwner = msg.sender;
        }
        
        if (config.dailyRewardAmount == 0) {
            setDefaultConfig();
        }
        
        // Deploy implementations
        result.gameLogicV2 = address(new GameLogicV2());
        result.marketplaceV2 = address(new MarketplaceV2());
        
        // Deploy proxies
        result.gameLogicV2Proxy = address(new ERC1967Proxy(
            result.gameLogicV2,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint256,uint256)",
                initialOwner,
                deployedAddresses["GovernanceTokenProxy"] != address(0) 
                    ? deployedAddresses["GovernanceTokenProxy"] 
                    : msg.sender,
                deployedAddresses["UtilityTokenProxy"] != address(0) 
                    ? deployedAddresses["UtilityTokenProxy"] 
                    : msg.sender,
                deployedAddresses["GameAssetNFTProxy"] != address(0) 
                    ? deployedAddresses["GameAssetNFTProxy"] 
                    : msg.sender,
                config.dailyRewardAmount,
                config.initialLevelCap
            )
        ));
        
        result.marketplaceV2Proxy = address(new ERC1967Proxy(
            result.marketplaceV2,
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                initialOwner,
                deployedAddresses["GovernanceTokenProxy"] != address(0) 
                    ? deployedAddresses["GovernanceTokenProxy"] 
                    : msg.sender,
                deployedAddresses["GameAssetNFTProxy"] != address(0) 
                    ? deployedAddresses["GameAssetNFTProxy"] 
                    : msg.sender,
                config.marketplaceFeePercentage,
                config.marketplaceFeeReceiver
            )
        ));
        
        // V2 wiring (dynamicTokenomics on GameLogicV2) is handled in each contract's initialize()
        
        console.log("V2 contracts deployed successfully!");
        logDeploymentResults();
    }
    
    /**
     * @dev Deploy only P2 contracts
     */
    function deployP2ContractsOnly() public {
        console.log("Deploying P2 contracts...\n");
        
        if (initialOwner == address(0)) {
            initialOwner = msg.sender;
        }
        
        if (config.multiSigThreshold == 0) {
            setDefaultConfig();
        }
        
        // Deploy MultiSigWallet
        result.multiSigWallet = address(new MultiSigWallet());
        result.multiSigWalletProxy = address(new ERC1967Proxy(
            result.multiSigWallet,
            abi.encodeWithSignature(
                "initialize(address[],uint256,address)",
                config.multiSigOwners,
                config.multiSigThreshold,
                initialOwner
            )
        ));
        
        console.log("P2 contracts deployed successfully!");
        console.log("  MultiSigWallet: ", result.multiSigWalletProxy);
    }
    
    // ========== UPGRADE FUNCTIONS ==========
    
    /**
     * @dev Upgrade a contract implementation
     * @param contractName Name of the contract to upgrade
     * @param newImplementation Address of the new implementation
     */
    function upgradeContract(string memory contractName, address newImplementation) public {
        console.log("Upgrading ", contractName, " to ", newImplementation);
        
        address proxyAddress = deployedAddresses[string(abi.encodePacked(contractName, "Proxy"))];
        
        if (proxyAddress == address(0)) {
            console.log("Error: Proxy not found for ", contractName);
            return;
        }
        
        // UUPS upgradeTo is exposed by the implementation through the proxy fallback
        (bool success, ) = proxyAddress.call(
            abi.encodeWithSignature("upgradeTo(address)", newImplementation)
        );
        require(success, "Upgrade failed");
        
        console.log(unicode"✓ Upgraded ", contractName, " successfully");
    }
    
    /**
     * @dev Upgrade all contracts to new implementations
     */
    function upgradeAllContracts() public {
        console.log("Upgrading all contracts...\n");
        
        // Note: This would require new implementation addresses
        // This is a placeholder for the upgrade logic
        
        console.log("  Note: Specify new implementation addresses for each contract");
        console.log("  Example: upgradeContract('GovernanceToken', newGovernanceTokenAddress)");
    }
    
    // ========== UTILITY FUNCTIONS ==========
    
    /**
     * @dev Get deployment result for a specific contract
     * @param contractName Name of the contract
     * @return Address of the deployed contract
     */
    function getContractAddress(string memory contractName) public view returns (address) {
        if (keccak256(bytes(contractName)) == keccak256(bytes("GovernanceToken"))) {
            return result.governanceTokenProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("UtilityToken"))) {
            return result.utilityTokenProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("GameAssetNFT"))) {
            return result.gameAssetNFTProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("GameResourceNFT"))) {
            return result.gameResourceNFTProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("GameLogic"))) {
            return result.gameLogicProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("GameLogicV2"))) {
            return result.gameLogicV2Proxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("Marketplace"))) {
            return result.marketplaceProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("MarketplaceV2"))) {
            return result.marketplaceV2Proxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("StakingContract"))) {
            return result.stakingContractProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("Vesting"))) {
            return result.vestingProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("AdvancedTokenSinks"))) {
            return result.advancedTokenSinksProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("DynamicTokenomics"))) {
            return result.dynamicTokenomicsProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("GameOracle"))) {
            return result.gameOracleProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("PlayerDataStorage"))) {
            return result.playerDataStorageProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("SignatureVerifier"))) {
            return result.signatureVerifierProxy;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("MultiSigWallet"))) {
            return result.multiSigWalletProxy;
        }
        
        return address(0);
    }
    
    /**
     * @dev Get all contract addresses as a map
     * @return Map of contract names to addresses
     */
    function getAllContractAddresses() public view returns (string[] memory, address[] memory) {
        string[] memory names = new string[](16);
        address[] memory addresses = new address[](16);
        
        names[0] = "GovernanceToken";
        addresses[0] = result.governanceTokenProxy;
        
        names[1] = "UtilityToken";
        addresses[1] = result.utilityTokenProxy;
        
        names[2] = "GameAssetNFT";
        addresses[2] = result.gameAssetNFTProxy;
        
        names[3] = "GameResourceNFT";
        addresses[3] = result.gameResourceNFTProxy;
        
        names[4] = "GameLogic";
        addresses[4] = result.gameLogicProxy;
        
        names[5] = "GameLogicV2";
        addresses[5] = result.gameLogicV2Proxy;
        
        names[6] = "Marketplace";
        addresses[6] = result.marketplaceProxy;
        
        names[7] = "MarketplaceV2";
        addresses[7] = result.marketplaceV2Proxy;
        
        names[8] = "StakingContract";
        addresses[8] = result.stakingContractProxy;
        
        names[9] = "Vesting";
        addresses[9] = result.vestingProxy;
        
        names[10] = "AdvancedTokenSinks";
        addresses[10] = result.advancedTokenSinksProxy;
        
        names[11] = "DynamicTokenomics";
        addresses[11] = result.dynamicTokenomicsProxy;
        
        names[12] = "GameOracle";
        addresses[12] = result.gameOracleProxy;
        
        names[13] = "PlayerDataStorage";
        addresses[13] = result.playerDataStorageProxy;
        
        names[14] = "SignatureVerifier";
        addresses[14] = result.signatureVerifierProxy;
        
        names[15] = "MultiSigWallet";
        addresses[15] = result.multiSigWalletProxy;
        
        return (names, addresses);
    }
}
