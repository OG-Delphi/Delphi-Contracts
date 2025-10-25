# Delphi Smart Contracts

Permissionless, on-chain binary prediction markets using a Constant Product Market Maker (CPMM) with Chainlink oracle integration.

## 🎯 Overview

Delphi allows anyone to create and trade on binary prediction markets for any price feed supported by Chainlink. Markets use an automated market maker (AMM) with a constant product formula (x*y=k) for decentralized price discovery.

**Key Features:**
- ✅ Permissionless market creation
- ✅ CPMM for instant liquidity
- ✅ Chainlink oracles for trustless resolution
- ✅ ERC-1155 outcome tokens
- ✅ Time-locked market settlement
- ✅ No admin keys or upgradeability

## 📦 Contracts

| Contract | Description | Address (Base Sepolia) |
|----------|-------------|------------------------|
| **MarketFactory** | Create new prediction markets | `0xbaCB64f7Fcc27914B3F52E164BCfDD38bd0847e7` |
| **BinaryMarketCPMM** | Core AMM for trading | `0x840Ab73b0950959d9b12c890B228EA30E7cbb653` |
| **OutcomeToken** | ERC-1155 for YES/NO tokens | `0x71F863f93bccb2db3D1F01FC2480e5066150DB0e` |
| **OracleRouter** | Chainlink oracle integration | `0xD17a88AAecCB84D0072B6227973Ac43C20f9De03` |
| **MarketScheduler** | Automated market resolution | `0x695fFc186eAcC7C4CD56441c0ce31b820f767E10` |

**✨ Now using real Chainlink price feeds!** [View on BaseScan](https://sepolia.basescan.org/address/0xbaCB64f7Fcc27914B3F52E164BCfDD38bd0847e7)

## 🚀 Quick Start

### 🔍 Check Any Market

Get info and links for any market:
```bash
cd contracts
./script/check_market.sh <MARKET_ID>
```

This shows you BaseScan links, contract addresses, and commands to interact with the market!

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone repository
git clone https://github.com/OG_Delphi/Delphi-Smart-Contracts.git
cd Delphi-Smart-Contracts/contracts

# Install dependencies
forge install
```

### Setup

```bash
# Copy environment template
cp env.example .env

# Add your private key and RPC URL
# DEPLOYER_PRIVATE_KEY=0x...
# BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
```

### Compile

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run with gas reporting
forge test --gas-report

# Run specific test
forge test --match-test test_BuyYESTokens -vvv
```

## 📖 Usage Examples

### Create a Market

```solidity
// Example: "Will BTC be above $75,000 on Jan 1, 2026?"
bytes32 marketId = marketFactory.createPriceAboveAtTime(
    btcUsdFeed,           // Chainlink BTC/USD feed
    75000e8,              // Strike price: $75,000
    1735689600,           // Settlement: Jan 1, 2026
    150,                  // 1.5% trading fee
    50,                   // 0.5% creator fee
    1000 * 10**6          // 1000 USDC initial liquidity
);
```

### Buy YES Tokens

```solidity
// Buy YES tokens with 100 USDC
usdc.approve(address(cpmm), 100 * 10**6);
uint256 shares = cpmm.buy(
    marketId,
    0,                 // 0 = YES, 1 = NO
    100 * 10**6,       // 100 USDC
    90 * 10**6         // Min 90 shares (slippage protection)
);
```

### Sell Tokens

```solidity
// Sell 50 YES tokens
outcomeToken.setApprovalForAll(address(cpmm), true);
uint256 collateral = cpmm.sell(
    marketId,
    0,              // YES tokens
    50 * 10**6,     // 50 shares
    45 * 10**6      // Min 45 USDC
);
```

### Redeem Winning Shares

```solidity
// After market resolves, redeem winning shares
uint256 payout = cpmm.redeem(marketId);
```

## 🧪 Testing

Our contracts have comprehensive test coverage:

```bash
# Unit tests
forge test

# Fork tests (requires RPC_URL)
forge test --fork-url $BASE_SEPOLIA_RPC_URL

# Coverage report
forge coverage
```

**Test Results:**
- ✅ 53/53 tests passing
- ✅ All CPMM mechanics verified
- ✅ Oracle integration validated
- ✅ Edge cases covered

## 🔧 Scripts

Interact with deployed contracts using Forge scripts:

```bash
# Create a market
forge script script/CreateMarket.s.sol:CreateMarket \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast

# Execute a trade
export MARKET_ID=0x...
export BUY_YES=true
export TRADE_AMOUNT=100000000
forge script script/TradeMarket.s.sol:TradeMarket \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast
```

## 🏗️ Architecture

### CPMM Formula

Markets use a constant product formula:

```
x * y = k

where:
- x = YES token reserve
- y = NO token reserve  
- k = constant product

sharesOut = y - (k / (x + collateralIn))
```

### Market Lifecycle

1. **Creation** - Factory deploys market with initial liquidity
2. **Trading** - Users buy/sell YES/NO tokens via CPMM
3. **Settlement** - Market locks at specified timestamp
4. **Resolution** - Chainlink Automation queries oracle
5. **Redemption** - Winners redeem shares for collateral

### Fee Structure

- **Trading Fee**: 1.5% (150 bps) - stays in pool as liquidity
- **Creator Fee**: 0.5% (50 bps) - goes to market creator
- **Creation Fee**: 10 USDC - goes to treasury

## 🔒 Security

- ✅ No admin keys or upgradeability
- ✅ All contracts verified on BaseScan
- ✅ Reentrancy guards on all external calls
- ✅ SafeERC20 for token operations
- ✅ Time-locks prevent premature resolution
- ✅ Slippage protection on all trades

**Audit Status:** Pending (recommended before mainnet)

## 📚 Documentation

- [Deployment Guide](./DEPLOYMENT.md) - Deploy to any EVM chain
- [API Reference](./src/) - Full NatSpec documentation
- [Test Guide](./test/) - Writing and running tests

## 🌐 Networks

### Base Sepolia (Testnet)
- Chain ID: 84532
- RPC: https://sepolia.base.org
- Explorer: https://sepolia.basescan.org
- Faucet: [Coinbase Faucet](https://www.coinbase.com/faucets/base-ethereum-goerli-faucet)

### Base Mainnet (Coming Soon)
- Chain ID: 8453
- RPC: https://mainnet.base.org
- Explorer: https://basescan.org

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
# Format code
forge fmt

# Lint
forge fmt --check

# Gas snapshot
forge snapshot

# Update dependencies
forge update
```

## 📄 License

MIT License - see [LICENSE](../LICENSE) for details

## 🔗 Links

- **GitHub**: [github.com/OG_Delphi/Delphi-Smart-Contracts](https://github.com/OG_Delphi/Delphi-Smart-Contracts)
- **Documentation**: [docs.delphi.markets](https://docs.delphi.markets) *(coming soon)*
- **Twitter**: [@DelphiMarkets](https://twitter.com/DelphiMarkets) *(coming soon)*

## ⚠️ Disclaimer

This software is provided "as is" without warranty. Use at your own risk. Prediction markets may be subject to legal restrictions in your jurisdiction.

---

**Built with ❤️ using Foundry**
