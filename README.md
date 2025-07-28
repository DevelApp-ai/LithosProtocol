# Aetherium Prime - Web3 Gaming Ecosystem (Alpha State)

[![Test Smart Contracts](https://github.com/DevelApp-ai/AetheriumPrime/actions/workflows/test.yml/badge.svg)](https://github.com/DevelApp-ai/AetheriumPrime/actions/workflows/test.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.19-blue.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)

Aetherium Prime is a comprehensive Web3 gaming ecosystem that combines NFTs, on-chain assets, and Play-to-Earn (P2E) mechanics. Built with security, scalability, and modularity in mind, the platform leverages industry-standard patterns and battle-tested libraries to create an immersive blockchain gaming experience.

## 🎮 Overview

Aetherium Prime represents the next generation of blockchain gaming, where players truly own their in-game assets and can earn real value through gameplay. The ecosystem features a dual-token economy, comprehensive NFT systems, and sophisticated game mechanics all secured by smart contracts on the Ethereum blockchain.

### Key Features

- **Dual Token Economy**: Governance ($GOV) and Utility ($PLAY) tokens for balanced economics
- **NFT Asset System**: ERC-721 unique assets and ERC-1155 semi-fungible resources
- **Play-to-Earn Mechanics**: Quest system, PvP rewards, and staking incentives
- **Decentralized Marketplace**: Peer-to-peer trading with auction capabilities
- **Upgradeable Architecture**: UUPS proxy pattern for future enhancements
- **Comprehensive Security**: OpenZeppelin standards with extensive testing

## 🏗️ Architecture

The Aetherium Prime ecosystem is built on a modular smart contract architecture that ensures security, upgradeability, and efficient gas usage.

### Core Contracts

| Contract | Purpose | Standard |
|----------|---------|----------|
| `GovernanceToken` | Governance and voting rights | ERC-20 + ERC-20Votes |
| `UtilityToken` | In-game currency and rewards | ERC-20 |
| `GameAssetNFT` | Unique game assets (characters, land) | ERC-721 |
| `GameResourceNFT` | Semi-fungible resources (materials) | ERC-1155 |
| `GameLogic` | Core game mechanics and P2E | Custom |
| `Marketplace` | Asset trading and auctions | Custom |
| `StakingContract` | Token and NFT staking rewards | Custom |

### Token Economics

The dual-token model separates governance from utility, ensuring long-term sustainability:

**Governance Token ($GOV)**
- Fixed supply of 1,000,000 tokens
- Used for DAO governance and high-value transactions
- Stakeable for additional rewards
- 4-year team vesting with 1-year cliff

**Utility Token ($PLAY)**
- Inflationary supply earned through gameplay
- Primary in-game currency
- Token sinks through crafting, repairs, and fees
- Mintable through P2E mechanics

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) - Ethereum development toolkit
- [Node.js](https://nodejs.org/) v18+ - For frontend integration
- [Git](https://git-scm.com/) - Version control

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/DevelApp-ai/AetheriumPrime.git
   cd AetheriumPrime
   ```

2. **Install dependencies**
   ```bash
   forge install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Compile contracts**
   ```bash
   forge build
   ```

5. **Run tests**
   ```bash
   forge test
   ```

### Local Development

Start a local blockchain for development:

```bash
# Terminal 1: Start Anvil
anvil

# Terminal 2: Deploy contracts
forge script script/DeployContracts.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

## 🧪 Testing

The project includes comprehensive test coverage for all smart contracts:

```bash
# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run tests with coverage
forge coverage

# Run specific test file
forge test --match-contract GovernanceTokenTest

# Run with verbosity for debugging
forge test -vvv
```

### Test Coverage

Current test coverage targets 95%+ for all contracts:

- ✅ GovernanceToken: Comprehensive ERC-20 and governance testing
- ✅ UtilityToken: Role-based access and minting mechanics
- ✅ GameAssetNFT: NFT minting, metadata, and staking integration
- ✅ GameResourceNFT: Multi-token management and game integration
- ✅ GameLogic: P2E mechanics, quest system, and player progression
- ✅ Marketplace: Trading, auctions, and fee collection
- ✅ StakingContract: Reward distribution and lock mechanisms

## 🚢 Deployment

### Testnet Deployment

Deploy to Sepolia testnet:

```bash
forge script script/DeployToNetwork.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

### Mainnet Deployment

For production deployment:

```bash
# Dry run first
forge script script/DeployToNetwork.s.sol --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --verify --dry-run

# Actual deployment
forge script script/DeployToNetwork.s.sol --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

### Deployment Verification

After deployment, verify contracts on Etherscan:

```bash
forge verify-contract <CONTRACT_ADDRESS> src/GovernanceToken.sol:GovernanceToken --etherscan-api-key $ETHERSCAN_API_KEY
```

## 🎯 Game Mechanics

### Play-to-Earn System

Players earn $PLAY tokens through various activities:

- **Daily Quests**: Complete daily challenges for consistent rewards
- **PvP Battles**: Win player-vs-player matches for bonus tokens
- **Leaderboards**: Top performers receive weekly rewards
- **Staking**: Lock tokens and NFTs for passive income

### Crafting System

Transform resources into valuable assets:

1. **Gather Resources**: Collect materials through gameplay
2. **Spend PLAY Tokens**: Pay crafting costs in utility tokens
3. **Create Assets**: Mint new NFTs with varying rarity levels
4. **Level Progression**: Gain experience and unlock new recipes

### Asset Management

All in-game assets are true NFTs with on-chain metadata:

- **Characters**: Unique avatars with stats and abilities
- **Land**: Virtual real estate for building and farming
- **Weapons & Armor**: Equipment with rarity and level systems
- **Resources**: Crafting materials and consumables

## 🔒 Security

Security is paramount in the Aetherium Prime ecosystem:

### Security Measures

- **OpenZeppelin Standards**: All contracts inherit from battle-tested libraries
- **Access Control**: Role-based permissions for administrative functions
- **Reentrancy Protection**: Guards against common attack vectors
- **Pausable Contracts**: Emergency stop functionality
- **Upgradeable Proxies**: UUPS pattern for secure upgrades
- **Comprehensive Testing**: 95%+ test coverage with edge case handling

### Audit Preparation

The codebase is prepared for professional security audits:

- Clean, well-documented code
- Comprehensive test suite
- Static analysis integration (Slither)
- Gas optimization analysis
- Formal verification readiness

## 🌐 Integration

### Frontend Integration

Connect to the smart contracts using Web3 libraries:

```javascript
import { ethers } from 'ethers';
import GameLogicABI from './abis/GameLogic.json';

const provider = new ethers.providers.Web3Provider(window.ethereum);
const gameLogic = new ethers.Contract(GAME_LOGIC_ADDRESS, GameLogicABI, provider);

// Register player
await gameLogic.registerPlayer();

// Complete quest
await gameLogic.completeQuest(questId);
```

### The Graph Integration

Index blockchain events for efficient querying:

```graphql
query GetPlayerData($playerAddress: String!) {
  player(id: $playerAddress) {
    level
    experience
    questsCompleted
    assetsOwned {
      id
      assetType
      rarity
    }
  }
}
```

## 📊 Tokenomics

### Token Distribution

| Allocation | Percentage | Amount | Vesting |
|------------|------------|---------|---------|
| Team | 20% | 200K GOV | 4 years, 1 year cliff |
| Community Rewards | 30% | 300K GOV | 2 years |
| Staking Rewards | 25% | 250K GOV | 5 years |
| Liquidity Pool | 15% | 150K GOV | Immediate |
| Treasury Reserve | 10% | 100K GOV | DAO controlled |

### Economic Incentives

The tokenomics are designed to create sustainable value:

- **Token Sinks**: Crafting, repairs, and marketplace fees
- **Staking Rewards**: Incentivize long-term holding
- **Governance Participation**: Vote on protocol upgrades
- **Play-to-Earn**: Reward active gameplay

## 🛣️ Roadmap

### Phase 1: Foundation (Completed)
- ✅ Core smart contract development
- ✅ Comprehensive testing suite
- ✅ Security audit preparation
- ✅ Deployment infrastructure

### Phase 2: Testnet Launch (In Progress)
- 🔄 Sepolia testnet deployment
- 🔄 Community testing program
- 🔄 Bug fixes and optimizations
- 🔄 Security audit execution

### Phase 3: Mainnet Preparation
- 📋 Audit completion and fixes
- 📋 Frontend application development
- 📋 Subgraph deployment
- 📋 Liquidity pool setup

### Phase 4: Public Launch
- 📋 Mainnet contract deployment
- 📋 Token generation event
- 📋 Game client release
- 📋 Marketing campaign

## 🤝 Contributing

We welcome contributions from the community! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

### Code Standards

- Follow Solidity style guide
- Maintain 95%+ test coverage
- Include comprehensive documentation
- Use meaningful commit messages

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

---

**Built with ❤️ by the Aetherium Prime Team**

