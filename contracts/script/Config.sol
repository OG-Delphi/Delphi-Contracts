// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Config
/// @notice Configuration for deployments across different networks
library Config {
    // Base Sepolia addresses
    struct NetworkConfig {
        address usdc;
        address linkToken;
        address automationRegistrar;
        address btcUsdFeed;
        address ethUsdFeed;
        address solUsdFeed;
        uint256 deployerPrivateKey;
    }

    /// @notice Get configuration for Base Sepolia
    function getBaseSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            // Base Sepolia USDC (you'll need to deploy a mock or use testnet USDC)
            usdc: address(0), // Will deploy MockUSDC if zero
            // Chainlink on Base Sepolia
            linkToken: address(0), // Base Sepolia LINK (check Chainlink docs)
            automationRegistrar: address(0), // Base Sepolia Automation Registrar
            // Price feeds on Base Sepolia (check Chainlink docs for real addresses)
            btcUsdFeed: address(0), // Will use mock if zero
            ethUsdFeed: address(0), // Will use mock if zero
            solUsdFeed: address(0), // Will use mock if zero
            deployerPrivateKey: 0 // Set via environment variable
        });
    }

    /// @notice Get configuration for Base Mainnet
    function getBaseMainnetConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            // Base Mainnet USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            // Chainlink on Base Mainnet
            linkToken: 0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196, // LINK on Base
            automationRegistrar: address(0), // Check Chainlink docs
            // Price feeds on Base Mainnet (from Chainlink docs)
            btcUsdFeed: 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F, // BTC/USD on Base
            ethUsdFeed: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70, // ETH/USD on Base
            solUsdFeed: address(0), // SOL/USD (check if available on Base)
            deployerPrivateKey: 0 // Set via environment variable
        });
    }

    /// @notice Get configuration for local testing (Anvil)
    function getAnvilConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc: address(0), // Will deploy mock
            linkToken: address(0), // Will deploy mock
            automationRegistrar: address(0), // Not needed for local
            btcUsdFeed: address(0), // Will deploy mock
            ethUsdFeed: address(0), // Will deploy mock
            solUsdFeed: address(0), // Will deploy mock
            deployerPrivateKey: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 // Anvil default key
        });
    }
}

