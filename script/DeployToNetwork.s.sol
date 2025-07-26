// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "./DeployContracts.s.sol";

/**
 * @title DeployToNetwork
 * @dev Network-specific deployment script with environment-based configuration
 */
contract DeployToNetwork is DeployContracts {
    
    struct NetworkConfig {
        string name;
        uint256 chainId;
        bool isTestnet;
        uint256 gasPrice;
        uint256 gasLimit;
        address treasury;
        address multisig;
    }
    
    mapping(uint256 => NetworkConfig) public networkConfigs;
    
    function setUp() public {
        // Mainnet
        networkConfigs[1] = NetworkConfig({
            name: "Ethereum Mainnet",
            chainId: 1,
            isTestnet: false,
            gasPrice: 20 gwei,
            gasLimit: 8000000,
            treasury: vm.envAddress("TREASURY_ADDRESS"),
            multisig: vm.envAddress("MULTISIG_ADDRESS")
        });
        
        // Sepolia Testnet
        networkConfigs[11155111] = NetworkConfig({
            name: "Sepolia Testnet",
            chainId: 11155111,
            isTestnet: true,
            gasPrice: 10 gwei,
            gasLimit: 8000000,
            treasury: vm.envAddress("DEPLOYER_ADDRESS"),
            multisig: vm.envAddress("DEPLOYER_ADDRESS")
        });
        
        // Polygon Mainnet
        networkConfigs[137] = NetworkConfig({
            name: "Polygon Mainnet",
            chainId: 137,
            isTestnet: false,
            gasPrice: 30 gwei,
            gasLimit: 8000000,
            treasury: vm.envAddress("TREASURY_ADDRESS"),
            multisig: vm.envAddress("MULTISIG_ADDRESS")
        });
        
        // Arbitrum One
        networkConfigs[42161] = NetworkConfig({
            name: "Arbitrum One",
            chainId: 42161,
            isTestnet: false,
            gasPrice: 0.1 gwei,
            gasLimit: 32000000,
            treasury: vm.envAddress("TREASURY_ADDRESS"),
            multisig: vm.envAddress("MULTISIG_ADDRESS")
        });
    }
    
    function run() external override returns (DeployedContracts memory) {
        uint256 chainId = block.chainid;
        NetworkConfig memory config = networkConfigs[chainId];
        
        require(bytes(config.name).length > 0, "Unsupported network");
        
        console.log("Deploying to:", config.name);
        console.log("Chain ID:", config.chainId);
        console.log("Is Testnet:", config.isTestnet);
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer:", deployer);
        console.log("Treasury:", config.treasury);
        console.log("Multisig:", config.multisig);
        
        // Set gas configuration
        vm.txGasPrice(config.gasPrice);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy contracts with network-specific configuration
        DeployedContracts memory contracts = deployWithNetworkConfig(config, deployer);
        
        // Post-deployment configuration
        configureForNetwork(contracts, config);
        
        vm.stopBroadcast();
        
        // Save deployment addresses
        saveDeploymentAddresses(contracts, config);
        
        // Verify contracts if not local network
        if (chainId != 31337) {
            verifyContracts(contracts);
        }
        
        return contracts;
    }
    
    function deployWithNetworkConfig(
        NetworkConfig memory config,
        address deployer
    ) internal returns (DeployedContracts memory) {
        
        DeploymentConfig memory deployConfig = getNetworkDeploymentConfig(config);
        
        console.log("Deploying with configuration:");
        console.log("- GOV Token Supply:", deployConfig.govTokenSupply);
        console.log("- Marketplace Fee:", deployConfig.marketplaceFee);
        
        return deployAllContracts(deployConfig, deployer);
    }
    
    function getNetworkDeploymentConfig(
        NetworkConfig memory networkConfig
    ) internal view returns (DeploymentConfig memory) {
        
        if (networkConfig.isTestnet) {
            // Testnet configuration with smaller supplies
            return DeploymentConfig({
                govTokenName: vm.envString("GOV_TOKEN_NAME"),
                govTokenSymbol: vm.envString("GOV_TOKEN_SYMBOL"),
                govTokenSupply: 100000 * 10**18, // 100K for testnet
                utilityTokenName: vm.envString("UTILITY_TOKEN_NAME"),
                utilityTokenSymbol: vm.envString("UTILITY_TOKEN_SYMBOL"),
                utilityTokenSupply: vm.envUint("UTILITY_TOKEN_SUPPLY"),
                assetNFTName: vm.envString("ASSET_NFT_NAME"),
                assetNFTSymbol: vm.envString("ASSET_NFT_SYMBOL"),
                resourceNFTURI: vm.envString("RESOURCE_NFT_URI"),
                marketplaceFee: vm.envUint("MARKETPLACE_FEE")
            });
        } else {
            // Mainnet configuration
            return DeploymentConfig({
                govTokenName: vm.envString("GOV_TOKEN_NAME"),
                govTokenSymbol: vm.envString("GOV_TOKEN_SYMBOL"),
                govTokenSupply: vm.envUint("GOV_TOKEN_SUPPLY"),
                utilityTokenName: vm.envString("UTILITY_TOKEN_NAME"),
                utilityTokenSymbol: vm.envString("UTILITY_TOKEN_SYMBOL"),
                utilityTokenSupply: vm.envUint("UTILITY_TOKEN_SUPPLY"),
                assetNFTName: vm.envString("ASSET_NFT_NAME"),
                assetNFTSymbol: vm.envString("ASSET_NFT_SYMBOL"),
                resourceNFTURI: vm.envString("RESOURCE_NFT_URI"),
                marketplaceFee: vm.envUint("MARKETPLACE_FEE")
            });
        }
    }
    
    function configureForNetwork(
        DeployedContracts memory contracts,
        NetworkConfig memory config
    ) internal {
        console.log("Configuring contracts for network...");
        
        // Transfer ownership to multisig for mainnet
        if (!config.isTestnet && config.multisig != msg.sender) {
            console.log("Transferring ownership to multisig:", config.multisig);
            
            GovernanceToken(contracts.governanceToken).transferOwnership(config.multisig);
            UtilityToken(contracts.utilityToken).transferOwnership(config.multisig);
            GameAssetNFT(contracts.gameAssetNFT).transferOwnership(config.multisig);
            GameResourceNFT(contracts.gameResourceNFT).transferOwnership(config.multisig);
            GameLogic(contracts.gameLogic).transferOwnership(config.multisig);
            Marketplace(contracts.marketplace).transferOwnership(config.multisig);
            StakingContract(contracts.stakingContract).transferOwnership(config.multisig);
        }
        
        // Update fee recipient to treasury
        if (config.treasury != msg.sender) {
            Marketplace(contracts.marketplace).updateFeeRecipient(config.treasury);
        }
        
        // Pause contracts if specified
        if (vm.envBool("PAUSE_ON_DEPLOY")) {
            console.log("Pausing contracts as requested...");
            GovernanceToken(contracts.governanceToken).pause();
            UtilityToken(contracts.utilityToken).pause();
            GameAssetNFT(contracts.gameAssetNFT).pause();
            GameResourceNFT(contracts.gameResourceNFT).pause();
            GameLogic(contracts.gameLogic).pause();
            Marketplace(contracts.marketplace).pause();
            StakingContract(contracts.stakingContract).pause();
        }
    }
    
    function saveDeploymentAddresses(
        DeployedContracts memory contracts,
        NetworkConfig memory config
    ) internal {
        string memory deploymentFile = string(abi.encodePacked(
            "deployments/",
            vm.toString(config.chainId),
            ".json"
        ));
        
        string memory json = string(abi.encodePacked(
            '{\n',
            '  "network": "', config.name, '",\n',
            '  "chainId": ', vm.toString(config.chainId), ',\n',
            '  "timestamp": ', vm.toString(block.timestamp), ',\n',
            '  "contracts": {\n',
            '    "GovernanceToken": "', vm.toString(contracts.governanceToken), '",\n',
            '    "UtilityToken": "', vm.toString(contracts.utilityToken), '",\n',
            '    "GameAssetNFT": "', vm.toString(contracts.gameAssetNFT), '",\n',
            '    "GameResourceNFT": "', vm.toString(contracts.gameResourceNFT), '",\n',
            '    "GameLogic": "', vm.toString(contracts.gameLogic), '",\n',
            '    "Marketplace": "', vm.toString(contracts.marketplace), '",\n',
            '    "StakingContract": "', vm.toString(contracts.stakingContract), '"\n',
            '  }\n',
            '}'
        ));
        
        vm.writeFile(deploymentFile, json);
        console.log("Deployment addresses saved to:", deploymentFile);
    }
    
    function verifyContracts(DeployedContracts memory contracts) internal {
        console.log("Starting contract verification...");
        
        // Note: In a real deployment, you would use forge verify-contract
        // This is a placeholder for the verification process
        
        string[] memory verifyCommands = new string[](7);
        
        verifyCommands[0] = string(abi.encodePacked(
            "forge verify-contract ",
            vm.toString(contracts.governanceToken),
            " src/GovernanceToken.sol:GovernanceToken"
        ));
        
        verifyCommands[1] = string(abi.encodePacked(
            "forge verify-contract ",
            vm.toString(contracts.utilityToken),
            " src/UtilityToken.sol:UtilityToken"
        ));
        
        verifyCommands[2] = string(abi.encodePacked(
            "forge verify-contract ",
            vm.toString(contracts.gameAssetNFT),
            " src/GameAssetNFT.sol:GameAssetNFT"
        ));
        
        verifyCommands[3] = string(abi.encodePacked(
            "forge verify-contract ",
            vm.toString(contracts.gameResourceNFT),
            " src/GameResourceNFT.sol:GameResourceNFT"
        ));
        
        verifyCommands[4] = string(abi.encodePacked(
            "forge verify-contract ",
            vm.toString(contracts.gameLogic),
            " src/GameLogic.sol:GameLogic"
        ));
        
        verifyCommands[5] = string(abi.encodePacked(
            "forge verify-contract ",
            vm.toString(contracts.marketplace),
            " src/Marketplace.sol:Marketplace"
        ));
        
        verifyCommands[6] = string(abi.encodePacked(
            "forge verify-contract ",
            vm.toString(contracts.stakingContract),
            " src/StakingContract.sol:StakingContract"
        ));
        
        for (uint256 i = 0; i < verifyCommands.length; i++) {
            console.log("Verify command:", verifyCommands[i]);
        }
        
        console.log("Contract verification commands generated");
        console.log("Run these commands manually to verify contracts on Etherscan");
    }
}

