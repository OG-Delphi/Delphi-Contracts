// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/BinaryMarketCPMM.sol";
import "../src/OutcomeToken.sol";
import "../test/mocks/MockERC20.sol";

/// @title SellMarket
/// @notice Script to test selling outcome tokens
contract SellMarket is Script {
    uint8 constant YES = 0;
    uint8 constant NO = 1;

    function run() external {
        // Get parameters from environment
        bytes32 marketId = vm.envBytes32("MARKET_ID");
        bool sellYes = vm.envOr("SELL_YES", true);
        uint256 amount = vm.envOr("SELL_AMOUNT", uint256(50 * 10**6)); // Default 50 tokens

        console.log("Selling tokens on market:");
        console.log("Market ID:", vm.toString(marketId));
        console.log("Selling:", sellYes ? "YES" : "NO");
        console.log("Amount:", amount);

        // Load deployment addresses
        uint256 chainId = block.chainid;
        string memory deploymentFile = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        string memory json = vm.readFile(deploymentFile);

        address cpmmAddr = vm.parseJsonAddress(json, ".contracts.BinaryMarketCPMM");
        address outcomeTokenAddr = vm.parseJsonAddress(json, ".contracts.OutcomeToken");
        
        BinaryMarketCPMM cpmm = BinaryMarketCPMM(cpmmAddr);
        OutcomeToken outcomeToken = OutcomeToken(outcomeTokenAddr);

        // Get deployer key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get current price before trade
        uint256 priceBeforeYes = cpmm.getYesPrice(marketId);
        console.log("Current YES price:", priceBeforeYes);

        // Check token balance
        uint8 outcome = sellYes ? YES : NO;
        uint256 tokenId = outcomeToken.encodeTokenId(marketId, outcome);
        uint256 balance = outcomeToken.balanceOf(deployer, tokenId);
        console.log("Token balance:", balance);
        
        require(balance >= amount, "Insufficient token balance");

        vm.startBroadcast(deployerPrivateKey);

        // Approve CPMM to burn tokens
        console.log("Approving outcome tokens...");
        outcomeToken.setApprovalForAll(cpmmAddr, true);

        // Calculate minimum output (accept 25% slippage)
        uint256 minOut = (amount * 75) / 100;
        console.log("Min collateral (25% slippage):", minOut);

        // Execute sell
        uint256 collateralOut = cpmm.sell(marketId, outcome, amount, minOut);

        console.log("\nSell executed!");
        console.log("Collateral received:", collateralOut);

        // Get market state after trade
        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
        uint256 priceAfterYes = cpmm.getYesPrice(marketId);
        
        console.log("\nMarket after sell:");
        console.log("  YES Reserves:", market.yesReserve);
        console.log("  NO Reserves:", market.noReserve);
        console.log("  YES Price:", priceAfterYes);
        console.log("  Price change:", int256(priceAfterYes) - int256(priceBeforeYes));

        vm.stopBroadcast();
    }
}

