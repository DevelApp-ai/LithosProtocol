[![Test Smart Contracts](https://github.com/DevelApp-ai/LithosProtocol/actions/workflows/test.yml/badge.svg)](https://github.com/DevelApp-ai/LithosProtocol/actions/workflows/test.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.19-blue.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)

# LithosProtocol

**Built to Last. Built for Play.**

![LithosProtocol Logo](./assets/logos/LithosProtocol_Logo.png)

LithosProtocol is a comprehensive Web3 gaming ecosystem that combines NFTs, on-chain assets, and Play-to-Earn (P2E) mechanics. Built with security, scalability, and modularity in mind, the platform leverages industry-standard patterns and battle-tested libraries to create an immersive blockchain gaming experience.

## 🎮 Overview

LithosProtocol represents the next generation of blockchain gaming, where players truly own their in-game assets and can earn real value through gameplay. The ecosystem features a dual-token economy, comprehensive NFT systems, and sophisticated game mechanics all secured by smart contracts on the Ethereum blockchain.

### Key Features

- **Dual Token Economy**: Governance ($LITHOS) and Utility ($PLAY) tokens for balanced economics
- **NFT Asset System**: ERC-721 unique assets and ERC-1155 semi-fungible resources
- **Play-to-Earn Mechanics**: Quest system, PvP rewards, and staking incentives
- **Decentralized Marketplace**: Peer-to-peer trading with auction capabilities
- **Upgradeable Architecture**: UUPS proxy pattern for future enhancements

## 🏗️ Architecture

### Smart Contracts

| Contract | Type | Description |
|----------|------|-------------|
| `GovernanceToken` | ERC-20 | Governance token with voting capabilities ($LITHOS) |
| `UtilityToken` | ERC-20 | Utility token for in-game transactions ($PLAY) |
| `GameAssetNFT` | ERC-721 | Unique game assets (characters, weapons, land, armor, accessories) |
| `GameResourceNFT` | ERC-1155 | Semi-fungible resources (crafting materials, potions, consumables) |
| `GameLogic` | Core | Play-to-earn mechanics and game state management |
| `Marketplace` | Trading | Decentralized asset marketplace with fixed price and auction support |
| `StakingContract` | DeFi | Token and NFT staking with rewards |

### Technology Stack

- **Smart Contracts**: Solidity 0.8.19 with OpenZeppelin libraries
- **Development Framework**: Foundry for testing and deployment
- **Frontend**: React with Web3 integration
- **Blockchain**: Ethereum (Mainnet) and Sepolia (Testnet)
- **Proxy Pattern**: UUPS for upgradeability
- **Security**: Comprehensive access controls and reentrancy protection

## 🚀 Quick Start

### Prerequisites

- Node.js 18+ and npm/pnpm
- Foundry toolkit
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/DevelApp-ai/LithosProtocol.git
cd LithosProtocol

# Install dependencies
forge install
```

### Development

```bash
# Compile contracts
forge build

# Run tests
forge test

# Start local blockchain
anvil

# Deploy to local network
forge script script/DeployContracts.s.sol --rpc-url http://localhost:8545 --broadcast
```

## 🎯 Game Mechanics

### Play-to-Earn System

LithosProtocol implements a sustainable P2E economy through multiple reward mechanisms:

- **Daily Quests**: Complete objectives to earn $PLAY tokens
- **PvP Battles**: Compete against other players for ranking rewards
- **Crafting System**: Create valuable items using resources
- **Staking Rewards**: Earn passive income by staking tokens and NFTs

### Asset Progression

Game assets evolve through gameplay:

- **Experience Points**: Assets gain XP through use
- **Level Progression**: Higher levels unlock new abilities
- **Rarity Upgrades**: Combine resources to increase rarity
- **Customization**: Modify appearance and attributes

### Token Economics

The dual-token model ensures economic sustainability:

**$LITHOS (Governance Token)**
- Total Supply: 1,000,000,000 tokens
- Use Cases: Governance voting, premium features, staking rewards
- Distribution: Community (40%), Team (20%), Ecosystem (25%), Treasury (15%)

**$PLAY (Utility Token)**
- Dynamic Supply: Minted through gameplay, burned through crafting
- Use Cases: In-game purchases, repairs, marketplace fees
- Mechanics: Deflationary through token sinks

## 🛡️ Security

### Audit Status

- **Smart Contract Audit**: Pending (prepared for professional audit)
- **Security Features**: Reentrancy guards, access controls, pausable contracts
- **Testing Coverage**: 95%+ test coverage across all contracts
- **Upgrade Safety**: UUPS proxy pattern with admin controls

### Best Practices

- OpenZeppelin security standards
- Comprehensive input validation
- Role-based access control (RBAC)
- Emergency pause functionality
- Multi-signature wallet integration

## 🌐 Marketplace

The LithosProtocol marketplace enables seamless trading of game assets:

### Features

- **Fixed Price Sales**: List assets at set prices
- **Auction System**: Time-based bidding for rare items
- **Bulk Operations**: Trade multiple assets efficiently
- **Fee Structure**: 2.5% marketplace fee with revenue sharing
- **Search & Filter**: Advanced discovery tools

### Integration

```javascript
import { LithosProtocolSDK } from '@lithosprotocol/web3-sdk';

const sdk = new LithosProtocolSDK({
  network: 'sepolia',
  rpcUrl: 'https://sepolia.infura.io/v3/YOUR_KEY'
});

// Initialize SDK with MetaMask
await sdk.initialize(window.ethereum);

// List an NFT for sale
await sdk.marketplace.listItem({
  nftContract: '0x...',
  tokenId: 1,
  amount: 1,
  listingType: 0, // Fixed price
  paymentToken: '0x0000000000000000000000000000000000000000', // ETH
  price: ethers.parseEther('0.1'),
  endTime: 0 // No end time for fixed price
});
```

## 🔧 Development Tools

### Web3 SDK

The LithosProtocol SDK provides easy integration:

```javascript
// Initialize SDK
const lithos = new LithosProtocolSDK({
  network: 'sepolia',
  contracts: {
    marketplace: '0x...',
    utilityToken: '0x...',
    gameLogic: '0x...'
  }
});

// Initialize with provider
await lithos.initialize(window.ethereum);

// Get player data
const playerData = await lithos.gameLogic.getPlayerData(address);
```

### Unity Integration

For Unity game developers:

```csharp
using LithosProtocol.Web3;

public class GameManager : MonoBehaviour
{
    private LithosWeb3Manager web3Manager;
    
    void Start()
    {
        web3Manager = GetComponent<LithosWeb3Manager>();
        web3Manager.Initialize();
    }
    
    async void OnPlayerAction()
    {
        await web3Manager.CompleteQuest(questId);
    }
}
```

## 📊 Tokenomics

### Distribution Schedule

| Allocation | Percentage | Tokens | Vesting |
|------------|------------|---------|---------|
| Community Rewards | 40% | 400M | 4 years linear |
| Team & Advisors | 20% | 200M | 4 years, 1 year cliff |
| Ecosystem Fund | 25% | 250M | 5 years linear |
| Treasury | 15% | 150M | DAO controlled |

### Utility Mechanisms

**Token Sinks (Deflationary)**
- Crafting and repairs: 10% of $PLAY supply annually
- Marketplace fees: 2.5% per transaction
- Premium features: Subscription model

**Token Sources (Inflationary)**
- Quest rewards: Dynamic based on player activity
- Staking rewards: 5-15% APY depending on lock period
- Tournament prizes: Weekly and monthly events

## 🗺️ Roadmap

### Phase 1: Foundation (Q1 2024) ✅
- Smart contract development and testing
- Security audit and optimization
- Testnet deployment and validation

### Phase 2: Marketplace Launch (Q2 2024) ✅
- Web marketplace deployment
- SDK and Unity integration
- Community beta testing

### Phase 3: Game Integration (Q3 2024)
- Partner game integrations
- Advanced P2E mechanics
- Cross-game asset compatibility

### Phase 4: Ecosystem Expansion (Q4 2024)
- Multi-chain deployment
- DAO governance launch
- Third-party developer tools

## 🤝 Contributing

We welcome contributions from the community! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Process

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

### Code Standards

- Follow Solidity style guide
- Maintain 95%+ test coverage
- Document all public functions
- Use conventional commit messages

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.


**Built with ❤️ by the LithosProtocol Team**

