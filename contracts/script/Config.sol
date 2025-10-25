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
            // Base Sepolia USDC (using mock for testing)
            usdc: address(0), // Will deploy MockUSDC if zero
            // Chainlink on Base Sepolia
            linkToken: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410,
            automationRegistrar: 0xf28D56F3A707E25B71Ce529a21AF388751E1CF2A,
            // Official Chainlink Price Feeds on Base Sepolia
            btcUsdFeed: 0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298,
            ethUsdFeed: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1,
            solUsdFeed: 0xb113F5A928BCfF189C998ab20d753a47F9dE5A61, // Using LINK/USD as alternative
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

