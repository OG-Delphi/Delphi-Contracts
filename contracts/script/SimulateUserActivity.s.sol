// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/BinaryMarketCPMM.sol";
import "../src/OutcomeToken.sol";
import "../test/mocks/MockERC20.sol";

/// @title SimulateUserActivity
/// @notice Simulate realistic trading patterns on the test market
contract SimulateUserActivity is Script {
    uint8 constant YES = 0;
    uint8 constant NO = 1;

    function run() external {
        bytes32 marketId = vm.envBytes32("MARKET_ID");
        
        console.log("=== SIMULATING USER ACTIVITY ===\n");
        console.log("Market ID:", vm.toString(marketId));

        // Load contracts
        uint256 chainId = block.chainid;
        string memory deploymentFile = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        string memory json = vm.readFile(deploymentFile);

        address cpmmAddr = vm.parseJsonAddress(json, ".contracts.BinaryMarketCPMM");
        address outcomeTokenAddr = vm.parseJsonAddress(json, ".contracts.OutcomeToken");
        address usdcAddr = vm.parseJsonAddress(json, ".infrastructure.MockUSDC");

        BinaryMarketCPMM cpmm = BinaryMarketCPMM(cpmmAddr);
        OutcomeToken outcomeToken = OutcomeToken(outcomeTokenAddr);
        MockERC20 usdc = MockERC20(usdcAddr);

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Check initial state
        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
        uint256 yesPrice = cpmm.getYesPrice(marketId);
        
        console.log("\n[INITIAL STATE]");
        console.log("  YES Reserves:", market.yesReserve);
        console.log("  NO Reserves:", market.noReserve);
        console.log("  YES Price:", yesPrice);
        console.log("  Total Volume:", market.totalVolume);

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n[TRADE 1: Small YES buy - bullish trader]");
        usdc.approve(cpmmAddr, 50 * 10**6);
        uint256 shares1 = cpmm.buy(marketId, YES, 50 * 10**6, 1);
        console.log("  Bought YES tokens:", shares1);
        console.log("  New YES price:", cpmm.getYesPrice(marketId));

        console.log("\n[TRADE 2: Medium NO buy - bearish trader]");
        usdc.approve(cpmmAddr, 75 * 10**6);
        uint256 shares2 = cpmm.buy(marketId, NO, 75 * 10**6, 1);
        console.log("  Bought NO tokens:", shares2);
        console.log("  New YES price:", cpmm.getYesPrice(marketId));

        console.log("\n[TRADE 3: Large YES buy - very bullish]");
        usdc.approve(cpmmAddr, 100 * 10**6);
        uint256 shares3 = cpmm.buy(marketId, YES, 100 * 10**6, 1);
        console.log("  Bought YES tokens:", shares3);
        console.log("  New YES price:", cpmm.getYesPrice(marketId));

        console.log("\n[TRADE 4: Small NO buy - slight doubt]");
        usdc.approve(cpmmAddr, 30 * 10**6);
        uint256 shares4 = cpmm.buy(marketId, NO, 30 * 10**6, 1);
        console.log("  Bought NO tokens:", shares4);
        console.log("  New YES price:", cpmm.getYesPrice(marketId));

        console.log("\n[TRADE 5: Profit taking - sell some YES]");
        uint256 yesTokenId = outcomeToken.encodeTokenId(marketId, YES);
        uint256 yesBalance = outcomeToken.balanceOf(deployer, yesTokenId);
        console.log("  Current YES balance:", yesBalance);
        
        outcomeToken.setApprovalForAll(cpmmAddr, true);
        uint256 sellAmount = yesBalance / 4; // Sell 25%
        uint256 collateralOut = cpmm.sell(marketId, YES, sellAmount, 1);
        console.log("  Sold YES tokens:", sellAmount);
        console.log("  Received USDC:", collateralOut);
        console.log("  New YES price:", cpmm.getYesPrice(marketId));

        console.log("\n[TRADE 6: Final small YES buy]");
        usdc.approve(cpmmAddr, 40 * 10**6);
        uint256 shares6 = cpmm.buy(marketId, YES, 40 * 10**6, 1);
        console.log("  Bought YES tokens:", shares6);
        
        // Final state
        market = cpmm.getMarket(marketId);
        yesPrice = cpmm.getYesPrice(marketId);
        
        console.log("\n[FINAL STATE]");
        console.log("  YES Reserves:", market.yesReserve);
        console.log("  NO Reserves:", market.noReserve);
        console.log("  YES Price:", yesPrice);
        console.log("  Total Volume:", market.totalVolume);
        
        // Show holdings
        uint256 finalYesBalance = outcomeToken.balanceOf(deployer, yesTokenId);
        uint256 noTokenId = outcomeToken.encodeTokenId(marketId, NO);
        uint256 noBalance = outcomeToken.balanceOf(deployer, noTokenId);
        
        console.log("\n[USER HOLDINGS]");
        console.log("  YES tokens:", finalYesBalance);
        console.log("  NO tokens:", noBalance);
        console.log("  Total invested: 295 USDC");
        console.log("  Profit/loss will be determined at resolution!");

        vm.stopBroadcast();
        
        console.log("\n[ACTIVITY COMPLETE]");
        console.log("Market now has realistic trading activity.");
        console.log("Waiting for Chainlink Automation to resolve...");
    }
}

