.PHONY: help install build test clean deploy-local deploy-sepolia deploy-mainnet verify

# Load environment variables
include .env
export

help:
	@echo "Delphi Deployment Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make install       Install dependencies"
	@echo "  make build         Compile contracts"
	@echo "  make test          Run tests"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-local      Deploy to local Anvil"
	@echo "  make deploy-sepolia    Deploy to Base Sepolia"
	@echo "  make deploy-mainnet    Deploy to Base Mainnet"
	@echo ""
	@echo "Post-Deployment:"
	@echo "  make create-market     Create test market"
	@echo "  make fund-market       Fund market with liquidity"
	@echo "  make trade-market      Execute test trade"
	@echo ""
	@echo "Utilities:"
	@echo "  make verify            Verify contracts on Basescan"
	@echo "  make clean             Clean build artifacts"
	@echo "  make gas-report        Generate gas usage report"

install:
	@echo "Installing dependencies..."
	forge install

build:
	@echo "Compiling contracts..."
	forge build

test:
	@echo "Running tests..."
	forge test -vv

test-gas:
	@echo "Running tests with gas report..."
	forge test --gas-report

clean:
	@echo "Cleaning build artifacts..."
	forge clean
	rm -rf cache out

# Local deployment
deploy-local:
	@echo "Deploying to local Anvil..."
	forge script script/Deploy.s.sol:Deploy \
		--rpc-url http://localhost:8545 \
		--broadcast \
		-vvvv

# Base Sepolia deployment
deploy-sepolia:
	@echo "Deploying to Base Sepolia..."
	@echo "⚠️  Make sure your wallet has testnet ETH!"
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	forge script script/Deploy.s.sol:Deploy \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--broadcast \
		--verify \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		-vvvv

# Base Mainnet deployment
deploy-mainnet:
	@echo "⚠️  WARNING: Deploying to BASE MAINNET with REAL MONEY!"
	@echo "⚠️  Have you completed ALL items on the deployment checklist?"
	@echo "⚠️  Have contracts been audited?"
	@read -p "Type 'DEPLOY' to continue: " confirm && [ "$$confirm" = "DEPLOY" ] || exit 1
	forge script script/Deploy.s.sol:Deploy \
		--rpc-url $(BASE_MAINNET_RPC_URL) \
		--broadcast \
		--verify \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		-vvvv

# Create test market
create-market:
	@echo "Creating test market on Base Sepolia..."
	forge script script/CreateMarket.s.sol:CreateMarket \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--broadcast \
		-vvvv

# Fund market with liquidity
fund-market:
	@echo "Funding market at $(MARKET_ADDRESS)..."
	@echo "Amount: $(LIQUIDITY_AMOUNT) USDC"
	forge script script/FundMarket.s.sol:FundMarket \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--broadcast \
		-vvvv

# Execute test trade
trade-market:
	@echo "Trading on market at $(MARKET_ADDRESS)..."
	@echo "Amount: $(TRADE_AMOUNT) USDC"
	@echo "Direction: $(BUY_YES)"
	forge script script/TradeMarket.s.sol:TradeMarket \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--broadcast \
		-vvvv

# Verify all contracts
verify:
	@echo "Verifying contracts on Basescan..."
	@echo "Not implemented yet - use forge verify-contract manually"

# Gas optimization report
gas-report:
	@echo "Generating gas report..."
	forge test --gas-report > gas-report.txt
	@echo "Gas report saved to gas-report.txt"

# Show deployment info
info-sepolia:
	@echo "Base Sepolia Deployment Info:"
	@cat deployments/84532.json | jq .

info-mainnet:
	@echo "Base Mainnet Deployment Info:"
	@cat deployments/8453.json | jq .

