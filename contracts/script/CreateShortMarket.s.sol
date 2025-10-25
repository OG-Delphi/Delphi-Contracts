// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MarketFactory.sol";
import "../test/mocks/MockERC20.sol";

/// @title CreateShortMarket
/// @notice Create a market with 1-hour settlement for testing Chainlink Automation
contract CreateShortMarket is Script {
    function run() external {
        console.log("=== CREATING 1-HOUR TEST MARKET ===\n");

        // Load deployment addresses
        uint256 chainId = block.chainid;
        string memory deploymentFile = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        string memory json = vm.readFile(deploymentFile);

        address factoryAddr = vm.parseJsonAddress(json, ".contracts.MarketFactory");
        address usdcAddr = vm.parseJsonAddress(json, ".infrastructure.MockUSDC");
        address btcFeedAddr = vm.parseJsonAddress(json, ".infrastructure.BTC_USD_Feed");

        console.log("Factory:", factoryAddr);
        console.log("USDC:", usdcAddr);
        console.log("BTC/USD Feed:", btcFeedAddr);

        MarketFactory factory = MarketFactory(factoryAddr);
        MockERC20 usdc = MockERC20(usdcAddr);

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Market: "Will BTC be above $100,000 in 1.5 hours?"
        uint64 settleTs = uint64(block.timestamp + 90 minutes);
        int256 strikePrice = 100000e8; // $100k
        uint128 initialLiquidity = 500 * 10**6; // 500 USDC
        
        console.log("\nMarket Parameters:");
        console.log("  Current time:", block.timestamp);
        console.log("  Settlement time:", settleTs);
        console.log("  Time until settlement: 1.5 hours (90 minutes)");
        console.log("  Strike price: $100,000");
        console.log("  Initial liquidity: 500 USDC");
        console.log("  Upkeep ID: 16991521484541824334947171272122570963095517890812872094682998296487861035976");

        // Approve total needed
        uint256 totalApproval = factory.creationFee() + (initialLiquidity * 2);
        usdc.approve(factoryAddr, totalApproval);
        
        // Create market
        bytes32 marketId = factory.createPriceAboveAtTime(
            btcFeedAddr,
            strikePrice,
            settleTs,
            150, // 1.5% fee
            50,  // 0.5% creator fee
            initialLiquidity
        );
        
        console.log("\n[SUCCESS] MARKET CREATED!");
        console.log("Market ID:", vm.toString(marketId));
        console.log("\nThis market will:");
        console.log("  1. Be tradeable for the next 90 minutes");
        console.log("  2. Lock automatically via Chainlink Automation");
        console.log("  3. Resolve based on BTC price at settlement");
        console.log("  4. Allow winners to redeem shares");
        
        console.log("\n[TIMER] CHECK BACK IN ~100 MINUTES");
        console.log("   (90 minutes + time for automation to execute)");

        vm.stopBroadcast();
    }
}

