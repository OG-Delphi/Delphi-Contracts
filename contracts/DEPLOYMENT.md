# Deployment Guide

This guide covers deploying the prediction market contracts to Base Sepolia (testnet) and Base Mainnet.

## Prerequisites

1. **Foundry**: Install from [getfoundry.sh](https://getfoundry.sh)
2. **Base RPC**: Get free RPC endpoints from [Alchemy](https://alchemy.com) or [Infura](https://infura.io)
3. **Wallet**: Create a new wallet with ETH for gas (NEVER use a wallet with real funds for testnet)
4. **Basescan API Key**: Get from [basescan.org](https://basescan.org/apis) for contract verification

## Setup

1. Copy the example environment file:
```bash
cp env.example .env
```

2. Fill in your `.env` file:
```bash
DEPLOYER_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
BASE_SEPOLIA_RPC_URL=https://base-sepolia.g.alchemy.com/v2/YOUR_KEY
BASE_MAINNET_RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY
BASESCAN_API_KEY=YOUR_BASESCAN_API_KEY
```

3. Fund your deployer wallet:
   - **Base Sepolia**: Get testnet ETH from [Base Sepolia Faucet](https://www.coinbase.com/faucets/base-ethereum-goerli-faucet)
   - **Base Mainnet**: Send real ETH (estimate ~0.02 ETH for deployment)

## Deployment

### Local Testing (Anvil)

Test deployment locally first:

```bash
# Start local node
anvil

# In another terminal, deploy
forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast
```

### Base Sepolia (Testnet)

Deploy to Base Sepolia testnet:

```bash
# Deploy contracts
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY

# Deployment addresses will be saved to deployments/84532.json
```

### Base Mainnet (Production)

**⚠️ WARNING: This deploys to mainnet with real money. Triple-check everything!**

```bash
# Deploy contracts
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY

# Deployment addresses will be saved to deployments/8453.json
```

## Post-Deployment

### Create a Test Market

```bash
export MARKET_ADDRESS=$(cat deployments/84532.json | jq -r '.contracts.MarketFactory')

forge script script/CreateMarket.s.sol:CreateMarket \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast
```

### Fund Market with Liquidity

```bash
export MARKET_ADDRESS=0xYOUR_MARKET_ADDRESS
export LIQUIDITY_AMOUNT=1000000000  # 1000 USDC

forge script script/FundMarket.s.sol:FundMarket \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast
```

### Execute a Test Trade

```bash
export MARKET_ADDRESS=0xYOUR_MARKET_ADDRESS
export TRADE_AMOUNT=100000000  # 100 USDC
export BUY_YES=true

forge script script/TradeMarket.s.sol:TradeMarket \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast
```

## Deployment Checklist

Before mainnet deployment:

- [ ] All tests passing (`forge test`)
- [ ] Gas optimization review (`forge test --gas-report`)
- [ ] Contracts audited (recommend [Zellic](https://zellic.io) or [Trail of Bits](https://trailofbits.com))
- [ ] Testnet deployment successful
- [ ] Create test markets on testnet
- [ ] Trade on test markets
- [ ] Verify markets resolve correctly
- [ ] Check Chainlink Automation integration
- [ ] Review all contract addresses
- [ ] Verify contracts on Basescan
- [ ] Create deployments documentation
- [ ] Set up monitoring (Tenderly, OpenZeppelin Defender)

## Contract Verification

If verification fails during deployment, manually verify:

```bash
forge verify-contract \
  --chain-id 84532 \
  --compiler-version v0.8.24 \
  --constructor-args $(cast abi-encode "constructor(address)" "0xCPMM_ADDRESS") \
  0xYOUR_CONTRACT_ADDRESS \
  src/OutcomeToken.sol:OutcomeToken \
  --etherscan-api-key $BASESCAN_API_KEY
```

## Troubleshooting

### "Insufficient funds for gas"
- Check wallet balance: `cast balance $YOUR_ADDRESS --rpc-url $BASE_SEPOLIA_RPC_URL`
- Get more testnet ETH from faucet

### "Nonce too low"
- Reset nonce: Add `--legacy` flag or wait for pending transactions

### "Contract verification failed"
- Try manual verification (see above)
- Check compiler version matches (`solc --version`)
- Ensure constructor args are correct

### "RPC URL not responding"
- Check your RPC URL is correct
- Try alternative RPC provider
- Check if network is congested

## Network Information

### Base Sepolia
- Chain ID: `84532`
- RPC: `https://sepolia.base.org`
- Explorer: `https://sepolia.basescan.org`
- USDC: Will deploy mock (testnet doesn't have official USDC)

### Base Mainnet
- Chain ID: `8453`
- RPC: `https://mainnet.base.org`
- Explorer: `https://basescan.org`
- USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

## Security Notes

- **NEVER** commit your `.env` file
- **NEVER** reuse mainnet wallets for testnet
- Use a fresh wallet for anonymous mainnet deployment
- Contracts are **immutable** after deployment
- No admin keys or upgradeability (by design)
- Review all constructor parameters before deployment
- Monitor deployments with [Tenderly](https://tenderly.co)

## Next Steps

After successful deployment:

1. **Set up Chainlink Automation**:
   - Register upkeep at [automation.chain.link](https://automation.chain.link)
   - Fund upkeep with LINK tokens
   - Set gas limit (estimate: 500k-1M per batch)

2. **Set up The Graph Subgraph**:
   - Index market creation events
   - Index trade events
   - Index resolution events

3. **Build Chrome Extension**:
   - Point to deployed contract addresses
   - Connect to The Graph endpoint
   - Test on Base Sepolia first

4. **Community Launch**:
   - Open-source frontend on GitHub
   - Publish extension to IPFS
   - Publish to Chrome Web Store
   - Announce on Twitter/X

## Support

For issues or questions:
- GitHub Issues: [your-repo]
- Discord: [your-discord]
- Twitter: [@your-handle]

