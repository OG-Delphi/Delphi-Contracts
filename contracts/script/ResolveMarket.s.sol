// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/BinaryMarketCPMM.sol";
import "../src/MarketScheduler.sol";
import "../src/OracleRouter.sol";
import "../test/mocks/MockChainlinkFeed.sol";

/// @title ResolveMarket
/// @notice Script to manually trigger market resolution for testing
contract ResolveMarket is Script {
    function run() external {
        bytes32 marketId = vm.envBytes32("MARKET_ID");
        
        console.log("Resolving market:", vm.toString(marketId));

        // Load deployment addresses
        uint256 chainId = block.chainid;
        string memory deploymentFile = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        string memory json = vm.readFile(deploymentFile);

        address cpmmAddr = vm.parseJsonAddress(json, ".contracts.BinaryMarketCPMM");
        address schedulerAddr = vm.parseJsonAddress(json, ".contracts.MarketScheduler");
        
        BinaryMarketCPMM cpmm = BinaryMarketCPMM(cpmmAddr);
        MarketScheduler scheduler = MarketScheduler(schedulerAddr);

        // Get deployer key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Get market details
        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
        console.log("Market settle time:", market.settleTimestamp);
        console.log("Current time:", block.timestamp);
        console.log("Market status:", uint256(market.status));

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Lock the market (only scheduler can do this)
        // For testing, we'll try to manually call checkUpkeep and performUpkeep
        console.log("\nChecking if market can be locked...");
        
        (bool upkeepNeeded, bytes memory performData) = scheduler.checkUpkeep("");
        
        if (upkeepNeeded) {
            console.log("Upkeep needed, performing...");
            scheduler.performUpkeep(performData);
            console.log("Market locked!");
        } else {
            console.log("No upkeep needed - market may need to wait for settle time");
            console.log("Or manually lock for testing purposes");
            
            // For testing: force time forward or manually resolve
            // In production, this would be done by Chainlink Automation
        }

        // Check market status after
        market = cpmm.getMarket(marketId);
        console.log("\nFinal market status:", uint256(market.status));
        
        if (market.status == BinaryMarketCPMM.MarketStatus.Resolved) {
            console.log("Market resolved!");
            console.log("Winning outcome:", market.winningOutcome);
        }

        vm.stopBroadcast();
    }
}

