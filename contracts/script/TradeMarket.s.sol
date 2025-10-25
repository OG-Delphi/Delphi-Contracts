// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/BinaryMarketCPMM.sol";
import "../test/mocks/MockERC20.sol";

/// @title TradeMarket
/// @notice Script to execute a test trade on a market
contract TradeMarket is Script {
    uint8 constant YES = 0;
    uint8 constant NO = 1;

    function run() external {
        // Get parameters from environment
        bytes32 marketId = vm.envBytes32("MARKET_ID");
        bool buyYes = vm.envOr("BUY_YES", true); // Default to buying YES
        uint256 amount = vm.envOr("TRADE_AMOUNT", uint256(100 * 10**6)); // Default 100 USDC

        console.log("Trading on market:");
        console.log("Market ID:", vm.toString(marketId));
        console.log("Buying:", buyYes ? "YES" : "NO");
        console.log("Amount:", amount);

        // Load deployment addresses
        uint256 chainId = block.chainid;
        string memory deploymentFile = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        string memory json = vm.readFile(deploymentFile);

        address cpmmAddr = vm.parseJsonAddress(json, ".contracts.BinaryMarketCPMM");
        BinaryMarketCPMM cpmm = BinaryMarketCPMM(cpmmAddr);
        
        MockERC20 usdc = MockERC20(address(cpmm.collateral()));

        // Get deployer key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Approve CPMM to take USDC
        console.log("Approving USDC...");
        usdc.approve(cpmmAddr, amount);

        // Get current price before trade
        uint256 priceBeforeYes = cpmm.getYesPrice(marketId);
        console.log("Current YES price:", priceBeforeYes);

        // Execute trade with 5% slippage tolerance
        // NOTE: We don't have a quote function, so we set a reasonable minOut
        uint256 minOut = 1; // Accept any non-zero output for demo
        
        uint8 outcome = buyYes ? YES : NO;
        uint256 sharesOut = cpmm.buy(marketId, outcome, amount, minOut);

        console.log("\nTrade executed!");
        console.log("Shares received:", sharesOut);

        // Get market state after trade
        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
        uint256 priceAfterYes = cpmm.getYesPrice(marketId);
        
        console.log("\nMarket after trade:");
        console.log("  YES Reserves:", market.yesReserve);
        console.log("  NO Reserves:", market.noReserve);
        console.log("  YES Price:", priceAfterYes);
        console.log("  Price change:", int256(priceAfterYes) - int256(priceBeforeYes));

        vm.stopBroadcast();
    }
}

