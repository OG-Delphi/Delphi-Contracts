# Delphi Smart Contracts

Decentralized binary prediction markets with automated settlement via Chainlink Automation.

## 📋 Overview

This protocol enables permissionless creation and trading of binary prediction markets (YES/NO) on any Chainlink-supported price feed. Markets use a Constant Product Market Maker (CPMM) with x*y=k formula and automatically resolve via Chainlink Automation.

## 🏗️ Architecture

### Core Contracts

1. **OutcomeToken.sol** - ERC-1155 token for YES/NO outcome shares
   - Hash-based token IDs: `keccak256(marketId, outcome)`
   - Only CPMM can mint/burn (access control)
   - Supports batch operations

2. **OracleRouter.sol** - Chainlink price feed integration
   - `getRoundAtOrBefore(feed, timestamp)` - Historical round lookup
   - Staleness checks (4-hour max)
   - Handles missing/gapped rounds gracefully

3. **BinaryMarketCPMM.sol** - CPMM for binary markets
   - Market states: Active → Locked → Resolved
   - Trading: `buy(marketId, outcome, collateralIn, minSharesOut)`
   - Redemption: 1:1 winning shares → USDC
   - Fee system: protocol + creator fees

4. **MarketScheduler.sol** - Chainlink Automation upkeep
   - Single upkeep manages all markets
   - Paged scan (MAX_BATCH=10 per call)
   - Two-phase settlement: Lock → Resolve
   - Cursor-based iteration

5. **MarketFactory.sol** - Market creation
   - Template: `PRICE_ABOVE_AT_TIME`
   - Whitelisted Chainlink feeds only
   - Creation fee (10 USDC) → LINK funding
   - Auto-registers with Scheduler

## 🧪 Testing

**Test Coverage: 53/53 tests passing ✅**

```bash
forge test
```

### Test Suites

- **OutcomeToken.t.sol** (13 tests) - Token minting, burning, access control
- **OracleRouter.t.sol** (19 tests) - Price feed queries, staleness, historical lookups
- **BinaryMarketCPMM.t.sol** (21 tests) - Trading, liquidity, fees, redemption

### Mock Contracts

- `MockERC20.sol` - USDC with 6 decimals
- `MockChainlinkFeed.sol` - Controllable price data for testing

## 🚀 Deployment

### Quick Start

1. **Install dependencies:**
```bash
forge install
```

2. **Configure environment:**
```bash
cp env.example .env
# Edit .env with your DEPLOYER_PRIVATE_KEY and RPC URLs
```

3. **Deploy to Base Sepolia:**
```bash
make deploy-sepolia
```

4. **Create a test market:**
```bash
make create-market
```

### Deployment Scripts

- **Deploy.s.sol** - Main deployment (deploys all contracts)
- **CreateMarket.s.sol** - Create a sample market
- **FundMarket.s.sol** - View market status
- **TradeMarket.s.sol** - Execute a test trade

See [DEPLOYMENT.md](./DEPLOYMENT.md) for full guide.

## 📁 Project Structure

```
contracts/
├── src/
│   ├── OutcomeToken.sol          # ERC-1155 outcome shares
│   ├── OracleRouter.sol           # Chainlink price feeds
│   ├── BinaryMarketCPMM.sol       # CPMM trading logic
│   ├── MarketScheduler.sol        # Automation upkeep
│   └── MarketFactory.sol          # Market creation
├── test/
│   ├── OutcomeToken.t.sol         # Token tests
│   ├── OracleRouter.t.sol         # Oracle tests
│   ├── BinaryMarketCPMM.t.sol     # CPMM tests
│   ├── helpers/
│   │   └── TestSetup.sol          # Test utilities
│   └── mocks/
│       ├── MockERC20.sol          # Mock USDC
│       └── MockChainlinkFeed.sol  # Mock price feed
├── script/
│   ├── Deploy.s.sol               # Main deployment
│   ├── CreateMarket.s.sol         # Create market
│   ├── FundMarket.s.sol           # View market
│   ├── TradeMarket.s.sol          # Trade
│   └── Config.sol                 # Network config
├── foundry.toml                   # Foundry configuration
├── Makefile                       # Deployment commands
├── DEPLOYMENT.md                  # Deployment guide
└── README.md                      # This file
```

## 🔧 Configuration

### Networks

- **Base Sepolia** (Chain ID: 84532) - Testnet
  - Deploys mock USDC and Chainlink feeds
  - Free testnet ETH from [Base faucet](https://www.coinbase.com/faucets/base-ethereum-goerli-faucet)

- **Base Mainnet** (Chain ID: 8453) - Production
  - Uses real USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
  - Real Chainlink feeds (BTC/USD, ETH/USD, etc.)

- **Anvil** (Chain ID: 31337) - Local testing
  - All mock contracts
  - Default private key included

### Gas Optimization

- Solidity 0.8.24 with optimizer (200 runs)
- Via-IR compilation enabled (avoids stack-too-deep)
- Estimated costs on Base L2:
  - Create market: ~200k gas (~$0.20)
  - Buy/sell: ~100k gas (~$0.10)
  - Redeem: ~50k gas (~$0.05)

## 🔐 Security

### Access Control

- **OutcomeToken**: Only CPMM can mint/burn
- **BinaryMarketCPMM**: Only Scheduler can lock/resolve
- **MarketFactory**: Whitelisted feeds only (admin can add/remove)

### Audit Status

⚠️ **NOT AUDITED** - Do not use in production without professional security audit.

Recommended auditors:
- [Zellic](https://zellic.io)
- [Trail of Bits](https://trailofbits.com)
- [OpenZeppelin](https://openzeppelin.com/security-audits)

### Known Limitations

1. No admin keys for upgrades (immutable by design)
2. No pause mechanism (markets cannot be stopped once created)
3. No invalid market state (oracle failure handling TBD)
4. Liquidity only set at creation (no add/remove post-creation)

## 📚 Documentation

- [DEPLOYMENT.md](./DEPLOYMENT.md) - Full deployment guide
- [BUILD_STATUS.md](../BUILD_STATUS.md) - Project progress
- [GeneralContext.md](../GeneralContext.md) - Architecture overview
- [FEEDBACK.md](../FEEDBACK.md) - Design decisions
- [DECENTRALIZATION_STRATEGY.md](../DECENTRALIZATION_STRATEGY.md) - Legal strategy

## 🛠️ Development

### Build

```bash
forge build
```

### Test

```bash
forge test                    # Run all tests
forge test -vvv               # Verbose output
forge test --gas-report       # Gas usage report
forge test --match-test test_CPMMInvariant  # Run specific test
```

### Format

```bash
forge fmt
```

### Coverage

```bash
forge coverage
```

## 🌐 Base Network

- **Chain ID**: 8453 (mainnet), 84532 (testnet)
- **RPC**: `https://mainnet.base.org` / `https://sepolia.base.org`
- **Explorer**: [basescan.org](https://basescan.org)
- **Gas**: Ultra-low fees (<$0.01 per tx)
- **Finality**: ~2 seconds

## 📞 Support

For issues or questions:
- Open a GitHub issue
- Check [DEPLOYMENT.md](./DEPLOYMENT.md) troubleshooting section

## 📄 License

MIT License - See LICENSE file for details

## 🚀 Next Steps

1. **Deploy to Base Sepolia** - Test on mainnet-like environment
2. **Register Chainlink Automation** - Set up automated resolution
3. **Build Chrome Extension** - User interface for trading
4. **Deploy The Graph Subgraph** - Index events for UI
5. **Security Audit** - Before mainnet deployment
6. **Mainnet Launch** - Anonymous deployment to Base

---

**Built with:**
- Foundry - Ethereum development toolkit
- Solidity 0.8.24 - Smart contract language
- Chainlink - Oracles + Automation
- Base L2 - Low-cost Ethereum layer 2
- OpenZeppelin - Secure contract libraries
