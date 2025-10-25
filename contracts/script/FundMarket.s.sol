// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/BinaryMarketCPMM.sol";
import "../test/mocks/MockERC20.sol";

/// @title FundMarket
/// @notice Script to check market liquidity and reserves
/// @dev NOTE: Liquidity is set during market creation via MarketFactory.createPriceAboveAtTime()
/// @dev This script is for viewing market state, not adding liquidity post-creation
contract FundMarket is Script {
    function run() external view {
        // Get market ID from environment
        bytes32 marketId = vm.envBytes32("MARKET_ID");

        console.log("Checking market liquidity:");
        console.log("Market ID:", vm.toString(marketId));

        // Load deployment addresses
        uint256 chainId = block.chainid;
        string memory deploymentFile = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        string memory json = vm.readFile(deploymentFile);

        address cpmmAddr = vm.parseJsonAddress(json, ".contracts.BinaryMarketCPMM");
        BinaryMarketCPMM cpmm = BinaryMarketCPMM(cpmmAddr);

        // Get market info
        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);

        console.log("\nMarket Status:");
        console.log("  Template:", vm.toString(market.templateId));
        console.log("  YES Reserves:", market.yesReserve);
        console.log("  NO Reserves:", market.noReserve);
        console.log("  Total Collateral:", market.yesReserve + market.noReserve);
        console.log("  YES Price:", cpmm.getYesPrice(marketId));
        console.log("  Fee (bps):", market.feeBps);
        console.log("  Settle Time:", market.settleTs);
        console.log("  Status:", uint8(market.status));
    }
}

