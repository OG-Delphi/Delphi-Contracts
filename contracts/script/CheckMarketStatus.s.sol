// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/BinaryMarketCPMM.sol";
import "../src/OracleRouter.sol";

/// @title CheckMarketStatus
/// @notice Check the current status of a market and time until settlement
contract CheckMarketStatus is Script {
    function run() external view {
        bytes32 marketId = vm.envBytes32("MARKET_ID");
        
        console.log("=== MARKET STATUS CHECK ===\n");
        console.log("Market ID:", vm.toString(marketId));
        console.log("Current Time:", block.timestamp);

        // Load contracts
        uint256 chainId = block.chainid;
        string memory deploymentFile = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        string memory json = vm.readFile(deploymentFile);

        address cpmmAddr = vm.parseJsonAddress(json, ".contracts.BinaryMarketCPMM");
        address oracleRouterAddr = vm.parseJsonAddress(json, ".contracts.OracleRouter");

        BinaryMarketCPMM cpmm = BinaryMarketCPMM(cpmmAddr);
        OracleRouter oracleRouter = OracleRouter(oracleRouterAddr);

        // Check market
        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
        uint256 yesPrice = cpmm.getYesPrice(marketId);

        console.log("\n[MARKET INFO]");
        console.log("  Status:", uint8(market.status), "(0=ACTIVE, 1=LOCKED, 2=RESOLVED)");
        console.log("  Settlement Time:", market.settleTs);
        
        if (block.timestamp < market.settleTs) {
            uint256 timeRemaining = market.settleTs - block.timestamp;
            console.log("  Time Remaining:", timeRemaining, "seconds");
            console.log("                  ", timeRemaining / 60, "minutes");
        } else {
            uint256 timeOverdue = block.timestamp - market.settleTs;
            console.log("  Time Past Settlement:", timeOverdue, "seconds");
            console.log("  READY FOR AUTOMATION!");
        }

        console.log("\n[TRADING INFO]");
        console.log("  YES Price:", yesPrice);
        console.log("  YES Reserve:", market.yesReserve);
        console.log("  NO Reserve:", market.noReserve);
        console.log("  Total Volume:", market.totalVolume);

        if (market.status == BinaryMarketCPMM.MarketStatus.RESOLVED) {
            console.log("\n[RESOLUTION]");
            console.log("  Winning Outcome:", market.winningOutcome, "(0=YES, 1=NO)");
            
            // Get current oracle price
            (bytes32 templateId,) = cpmm.getMarketCondition(marketId);
            (int256 currentPrice,) = oracleRouter.getPrice(templateId);
            console.log("  Final BTC Price:", uint256(currentPrice) / 1e8);
        } else {
            console.log("\n[CURRENT ORACLE PRICE]");
            (bytes32 templateId,) = cpmm.getMarketCondition(marketId);
            (int256 currentPrice,) = oracleRouter.getPrice(templateId);
            console.log("  BTC Price:", uint256(currentPrice) / 1e8);
        }

        console.log("\n==========================================");
    }
}

