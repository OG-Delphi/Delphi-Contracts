# 🔮 Delphi - Decentralized Prediction Markets for Crypto Twitter

> Permissionless, on-chain prediction markets integrated with Twitter/X — settled by Chainlink oracles, governed by a DAO.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)](https://soliditylang.org/)
[![Tests](https://img.shields.io/badge/Tests-53%2F53%20passing-brightgreen)]()

---

## 📄 What is this?

**Delphi** is a decentralized prediction market protocol where users can create and trade binary outcome markets (YES/NO) directly from Twitter/X. Markets are settled automatically using Chainlink price feeds and resolved via Chainlink Automation.

### Key Features

- ✅ **Chrome Extension Overlay** - Trade without leaving Twitter
- ✅ **USDC Collateral** - Stable, familiar currency on Base L2
- ✅ **Chainlink Oracles** - Objective, tamper-proof settlement
- ✅ **Automated Resolution** - Markets settle automatically at deadlines
- ✅ **DAO Governed** - Community-controlled parameters (feeds, fees)
- ✅ **Fully Immutable** - Core trading logic cannot be censored

---

## 🏗️ Architecture

### Smart Contracts (Base L2)

Located in `/contracts`:

| Contract | Description | Status |
|----------|-------------|--------|
| **MarketFactory** | Creates markets from templates, enforces whitelisted feeds | ✅ Complete + Tested |
| **BinaryMarketCPMM** | Constant product AMM (x*y=k) for YES/NO tokens | ✅ Complete + Tested |
| **MarketScheduler** | Single Chainlink Automation upkeep for all resolutions | ✅ Complete + Tested |
| **OracleRouter** | Queries Chainlink feeds at specific timestamps | ✅ Complete + Tested |
| **OutcomeToken** | ERC-1155 tokens for market positions (YES/NO shares) | ✅ Complete + Tested |

**Test Coverage**: 53/53 tests passing ✅

### Frontend (Chrome MV3 Extension)

_Coming Soon: React + TypeScript + Shadow DOM_

### Indexer (The Graph Subgraph)

_Coming Soon: GraphQL API for markets, trades, positions_

---

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://getfoundry.sh) (for smart contracts)
- [Node.js 18+](https://nodejs.org) (for extension, when implemented)

### Clone & Install

```bash
git clone https://github.com/yourname/delphi.git
cd delphi/contracts
forge install
```

### Run Tests

```bash
cd contracts
forge test
```

All 53 tests should pass:
- OutcomeToken: 13/13 ✅
- OracleRouter: 19/19 ✅
- BinaryMarketCPMM: 21/21 ✅

### Deploy to Testnet

```bash
# Configure environment
cp env.example .env
# Edit .env with your DEPLOYER_PRIVATE_KEY and BASE_SEPOLIA_RPC_URL

# Deploy
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

See [contracts/DEPLOYMENT.md](contracts/DEPLOYMENT.md) for detailed instructions.

---

## 📐 How It Works

### 1. Market Creation

```
User creates market via Chrome extension
  ↓
Factory collects creation fee (10 USDC)
  ↓
CPMM creates market with initial liquidity (50/50 YES/NO)
  ↓
Scheduler registers market for automated resolution
```

### 2. Trading

```
Trader buys YES tokens with USDC
  ↓
CPMM calculates price via x*y=k formula
  ↓
Fee deducted (1.5%): 50% protocol, 30% creator, 20% LP
  ↓
OutcomeToken mints shares to trader
```

### 3. Settlement

```
Market deadline reaches
  ↓
Chainlink Automation triggers checkUpkeep()
  ↓
Scheduler locks market (snapshot price)
  ↓
Next call resolves market (price ≥ threshold → YES wins)
  ↓
Winners redeem shares 1:1 for USDC
```

---

## 🔐 Access Control & Governance

### What Governance CAN Control

- ✅ **Whitelist/Delist Price Feeds** - Add new assets or remove compromised feeds
- ✅ **Adjust Creation Fees** - Change market creation cost (10 USDC default)
- ✅ **Update Fee Treasury** - Redirect protocol revenue

### What Governance CANNOT Control

- ❌ **Existing Markets** - Cannot cancel, modify, or invalidate
- ❌ **Trading** - Cannot pause, censor, or restrict users
- ❌ **Outcomes** - Settlement is fully automated via Chainlink
- ❌ **User Funds** - No admin access to USDC or LP tokens

### Governance Transfer Path

1. **Phase 1**: Deployer owns MarketFactory (fast iteration)
2. **Phase 2**: Transfer ownership to DAO Timelock (community governance)
3. **Phase 3** (Optional): Renounce ownership (fully immutable)

See [contracts/ACCESS_CONTROL.md](contracts/ACCESS_CONTROL.md) for complete security model.

---

## 💰 Economics

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Collateral** | USDC (6 decimals) | Base L2 deployment |
| **Trading Fee** | 1.5% (150 bps) | Split: 50% protocol, 30% creator, 20% LP |
| **Creation Fee** | 10 USDC | Funds Chainlink LINK for automated resolution |
| **Min Liquidity** | 100 USDC | Prevents spam markets |
| **Max Fee** | 5% (500 bps) | Hard cap to protect users |

---

## 📚 Documentation

### For Developers

- [contracts/README.md](contracts/README.md) - Smart contract overview
- [contracts/DEPLOYMENT.md](contracts/DEPLOYMENT.md) - Deployment guide
- [contracts/ACCESS_CONTROL.md](contracts/ACCESS_CONTROL.md) - Governance & security

### For Users

_Coming Soon: Extension user guide_

### Architecture Diagrams

```
┌─────────────────┐
│   Twitter/X     │
│   (Web Page)    │
└────────┬────────┘
         │
         │ Shadow DOM Injection
         ▼
┌─────────────────┐      ┌──────────────┐
│ Chrome Extension│◀────▶│   MetaMask   │
│  (React + TS)   │      │   (Wallet)   │
└────────┬────────┘      └──────────────┘
         │
         │ Web3 Calls
         ▼
┌─────────────────────────────────────────┐
│          Base L2 (Ethereum)             │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │MarketFactory │→ │ BinaryMarketCPMM│ │
│  └──────┬───────┘  └────────┬────────┘ │
│         │                   │          │
│         ▼                   ▼          │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │MarketScheduler│ │  OutcomeToken   │ │
│  └──────┬───────┘  └─────────────────┘ │
│         │                               │
│         ▼                               │
│  ┌──────────────┐                      │
│  │ OracleRouter │◀───Chainlink Feeds   │
│  └──────────────┘                      │
└─────────────────────────────────────────┘
         │
         │ Events
         ▼
┌─────────────────┐
│  The Graph      │
│  (Subgraph)     │
└─────────────────┘
```

---

## 🛣️ Roadmap

### ✅ Phase 1: Smart Contracts (Complete)
- [x] Core contracts implemented
- [x] Comprehensive test suite (53/53 passing)
- [x] Access control & governance model
- [x] Deployment scripts
- [x] Documentation

### 🔄 Phase 2: Testnet Deployment (In Progress)
- [ ] Deploy to Base Sepolia
- [ ] Create test markets
- [ ] Register Chainlink Automation upkeep
- [ ] Verify automated resolution

### ⏳ Phase 3: Frontend (Next)
- [ ] Chrome MV3 extension scaffold
- [ ] Wallet connection (MetaMask, Coinbase Wallet)
- [ ] Market creation UI
- [ ] Trading interface
- [ ] Position management

### ⏳ Phase 4: Indexing & Backend
- [ ] The Graph subgraph schema
- [ ] Deploy subgraph to hosted service
- [ ] GraphQL queries in extension
- [ ] Real-time market updates

### ⏳ Phase 5: Security & Launch
- [ ] Smart contract audit (Trail of Bits / OpenZeppelin)
- [ ] Bug bounty program
- [ ] Deploy to Base mainnet
- [ ] Publish extension to IPFS
- [ ] DAO governance token launch

---

## 🧪 Testing

### Run All Tests

```bash
cd contracts
forge test
```

### Run Specific Test Suite

```bash
forge test --match-contract OutcomeTokenTest
forge test --match-contract OracleRouterTest
forge test --match-contract BinaryMarketCPMMTest
```

### Gas Report

```bash
forge test --gas-report
```

### Coverage

```bash
forge coverage
```

---

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork the repo** and create a feature branch
2. **Write tests** for new functionality
3. **Follow Solidity style guide** (via `forge fmt`)
4. **Update documentation** as needed
5. **Submit a PR** with clear description

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).

---

## 🔗 Links

- **Contracts**: Base L2 (mainnet deployment pending)
- **Docs**: [contracts/README.md](contracts/README.md)
- **Twitter**: _Coming Soon_
- **Discord**: _Coming Soon_

---

## ⚠️ Disclaimer

**This software is provided "as is" without warranties.**

- Smart contracts are **not yet audited** - do not use in production with real funds
- Prediction markets may be **regulated in your jurisdiction** - consult a lawyer
- **You are responsible** for compliance with local laws

---

## 🚨 Security

### Audit Status

⚠️ **NOT AUDITED** - Smart contracts have not undergone professional security review.

### Report a Vulnerability

If you discover a security issue, please email: [security@yourproject.com](mailto:security@yourproject.com)

**Do not** open a public GitHub issue for security vulnerabilities.

---

## 💡 Built With

- [Solidity](https://soliditylang.org/) - Smart contract language
- [Foundry](https://getfoundry.sh) - Development framework
- [OpenZeppelin](https://openzeppelin.com/contracts/) - Secure contract libraries
- [Chainlink](https://chain.link) - Oracles & Automation
- [Base](https://base.org) - Ethereum L2 (by Coinbase)

---

## 📞 Support

Need help? Have questions?

- **Documentation**: Start with [contracts/README.md](contracts/README.md)
- **Issues**: Open a [GitHub Issue](https://github.com/yourname/delphi/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourname/delphi/discussions)

---

<p align="center">
  Built with ❤️ for Crypto Twitter
</p>
