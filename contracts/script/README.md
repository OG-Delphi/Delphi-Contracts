# Delphi Scripts

This directory contains deployment and interaction scripts for the Delphi protocol.

## 📜 Deployment Scripts

### Core Deployment
- **`Deploy.s.sol`** - Main deployment script for all contracts
- **`Config.sol`** - Network configuration (RPC URLs, addresses, etc.)

### Test Market Scripts
- **`CreateMarket.s.sol`** - Create a new prediction market
- **`CreateShortMarket.s.sol`** - Create a market with short settlement time for testing
- **`FundMarket.s.sol`** - Add liquidity to an existing market

## 📊 Market Interaction Scripts

### Trading
- **`TradeMarket.s.sol`** - Buy or sell outcome tokens
- **`SellMarket.s.sol`** - Sell outcome tokens
- **`SimulateUserActivity.s.sol`** - Simulate realistic trading patterns

### Resolution & Redemption
- **`ResolveMarket.s.sol`** - Manually trigger market resolution (for testing)
- **`RedeemShares.s.sol`** - Redeem winning shares after market resolution

## 🛠️ Utility Scripts

### Market Monitoring
- **`check_market.sh`** 🌟 - View market info and get useful links
  ```bash
  # With market ID argument
  ./script/check_market.sh 0x1ad47bbf...
  
  # Or with environment variable
  export MARKET_ID=0x1ad47bbf...
  ./script/check_market.sh
  ```

### Status Checking
- **`CheckMarketStatus.s.sol`** - Check market status (requires Foundry tools working)

## 🚀 Quick Start

### 1. Set Up Environment

Create a `.env` file in the contracts directory:
```bash
# Required
DEPLOYER_PRIVATE_KEY=your_private_key
BASE_SEPOLIA_RPC_URL=your_rpc_url

# Optional for specific scripts
MARKET_ID=0x...
BUY_YES=true
BUY_AMOUNT=50000000
```

### 2. Deploy Contracts

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

### 3. Create a Market

```bash
forge script script/CreateMarket.s.sol:CreateMarket \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast
```

### 4. Check Market Info

```bash
./script/check_market.sh <MARKET_ID>
```

### 5. Trade on Market

```bash
export MARKET_ID=<your_market_id>
export BUY_YES=true
export BUY_AMOUNT=50000000  # 50 USDC

forge script script/TradeMarket.s.sol:TradeMarket \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast
```

### 6. Redeem After Resolution

```bash
export MARKET_ID=<your_market_id>

forge script script/RedeemShares.s.sol:RedeemShares \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast
```

## 📖 Script Parameters

Most scripts use environment variables for configuration:

| Variable | Description | Example |
|----------|-------------|---------|
| `DEPLOYER_PRIVATE_KEY` | Your wallet private key | `0xabc...` |
| `BASE_SEPOLIA_RPC_URL` | RPC endpoint | `https://...` |
| `MARKET_ID` | Target market identifier | `0x1ad47bbf...` |
| `BUY_YES` | Buy YES (true) or NO (false) | `true` |
| `BUY_AMOUNT` | Amount in USDC (6 decimals) | `50000000` |
| `SELL_YES` | Sell YES (true) or NO (false) | `true` |
| `SELL_AMOUNT` | Amount in tokens (6 decimals) | `45000000` |

## 🔍 Finding Market IDs

Market IDs are emitted in the `MarketCreated` event when you create a market.

You can find them:
1. In the script output after creating a market
2. On BaseScan in the transaction events
3. By querying the `MarketFactory` contract

Use `check_market.sh` to get detailed info about any market!

## 💡 Tips

- **Use `--slow` flag** on testnets to avoid nonce issues
- **Check gas prices** before broadcasting on mainnet
- **Verify contracts** with `--verify` flag on deployment
- **Test thoroughly** on testnet before mainnet deployment
- **Use `check_market.sh`** to explore any market without writing code

## 🐛 Troubleshooting

**"ERC20InsufficientAllowance" error:**
- Increase approval amount in the script
- Market creation needs: `creationFee + (initialLiquidity * 2)`

**"SlippageExceeded" error:**
- Increase slippage tolerance (`minOut` parameter)
- CPMMs have non-linear pricing, especially for large trades

**"Market not found" error:**
- Double-check the market ID
- Ensure you're on the correct network
- Use `check_market.sh` to view market on BaseScan

## 📚 More Info

- Main docs: [../README.md](../README.md)
- Quick reference: See internal-docs for QUICK_REFERENCE.md
- Deployment info: [../deployments/](../deployments/)

---

**Need help?** Check BaseScan events or use `check_market.sh <MARKET_ID>` for any market!

