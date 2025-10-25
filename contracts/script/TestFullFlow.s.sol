// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MarketFactory.sol";
import "../src/BinaryMarketCPMM.sol";
import "../src/MarketScheduler.sol";
import "../src/OutcomeToken.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockChainlinkFeed.sol";

/// @title TestFullFlow
/// @notice Complete end-to-end test: create -> trade -> resolve -> redeem
contract TestFullFlow is Script {
    uint8 constant YES = 0;
    uint8 constant NO = 1;

    function run() external {
        console.log("=== DELPHI FULL FLOW TEST ===\n");

        // Load deployment addresses
        uint256 chainId = block.chainid;
        string memory deploymentFile = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        string memory json = vm.readFile(deploymentFile);

        address factoryAddr = vm.parseJsonAddress(json, ".contracts.MarketFactory");
        address cpmmAddr = vm.parseJsonAddress(json, ".contracts.BinaryMarketCPMM");
        address schedulerAddr = vm.parseJsonAddress(json, ".contracts.MarketScheduler");
        address outcomeTokenAddr = vm.parseJsonAddress(json, ".contracts.OutcomeToken");
        address usdcAddr = vm.parseJsonAddress(json, ".infrastructure.MockUSDC");
        address btcFeedAddr = vm.parseJsonAddress(json, ".infrastructure.BTC_USD_Feed");

        MarketFactory factory = MarketFactory(factoryAddr);
        BinaryMarketCPMM cpmm = BinaryMarketCPMM(cpmmAddr);
        MarketScheduler scheduler = MarketScheduler(schedulerAddr);
        OutcomeToken outcomeToken = OutcomeToken(outcomeTokenAddr);
        MockERC20 usdc = MockERC20(usdcAddr);
        MockChainlinkFeed btcFeed = MockChainlinkFeed(btcFeedAddr);

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // STEP 1: Create market with 2 hour settlement for testing
        console.log("STEP 1: Creating test market...");
        uint64 settleTs = uint64(block.timestamp + 2 hours);
        int256 strikePrice = 70000e8; // $70k BTC
        uint128 initialLiquidity = 500 * 10**6; // 500 USDC
        
        uint256 totalApproval = factory.creationFee() + (initialLiquidity * 2);
        usdc.approve(factoryAddr, totalApproval);
        
        bytes32 marketId = factory.createPriceAboveAtTime(
            btcFeedAddr,
            strikePrice,
            settleTs,
            150, // 1.5% fee
            50,  // 0.5% creator fee
            initialLiquidity
        );
        
        console.log("Market created:", vm.toString(marketId));
        console.log("Settle time:", settleTs);
        
        // STEP 2: Execute trades
        console.log("\nSTEP 2: Executing trades...");
        
        // Buy YES tokens
        usdc.approve(cpmmAddr, 100 * 10**6);
        uint256 yesShares = cpmm.buy(marketId, YES, 100 * 10**6, 50 * 10**6);
        console.log("Bought YES shares:", yesShares);
        
        uint256 yesPrice = cpmm.getYesPrice(marketId);
        console.log("YES price after buy:", yesPrice);
        
        // Buy NO tokens  
        usdc.approve(cpmmAddr, 80 * 10**6);
        uint256 noShares = cpmm.buy(marketId, NO, 80 * 10**6, 40 * 10**6);
        console.log("Bought NO shares:", noShares);
        
        console.log("Final YES price:", cpmm.getYesPrice(marketId));
        
        // STEP 3: Set BTC price and wait for settlement
        console.log("\nSTEP 3: Setting BTC price...");
        int256 finalPrice = 72000e8; // $72k - above strike, YES wins
        btcFeed.setLatestRoundData(finalPrice, block.timestamp, block.timestamp);
        console.log("BTC price set to:", vm.toString(finalPrice));
        console.log("Strike price:", vm.toString(strikePrice));
        console.log("YES should win!");
        
        // Fast forward time to settlement
        console.log("\nSTEP 4: Fast forwarding to settlement time...");
        vm.warp(settleTs + 1);
        console.log("Current time:", block.timestamp);
        
        // STEP 5: Trigger resolution
        console.log("\nSTEP 5: Resolving market...");
        (bool upkeepNeeded, bytes memory performData) = scheduler.checkUpkeep("");
        
        if (upkeepNeeded) {
            scheduler.performUpkeep(performData);
            console.log("Market resolved via automation!");
        } else {
            console.log("ERROR: Upkeep not needed");
        }
        
        // Check resolution
        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
        console.log("Market status:", uint256(market.status));
        console.log("Winning outcome:", market.winningOutcome);
        
        // STEP 6: Redeem winning shares
        if (market.status == BinaryMarketCPMM.MarketStatus.Resolved) {
            console.log("\nSTEP 6: Redeeming shares...");
            
            uint256 yesTokenId = outcomeToken.encodeTokenId(marketId, YES);
            uint256 noTokenId = outcomeToken.encodeTokenId(marketId, NO);
            
            uint256 yesBalance = outcomeToken.balanceOf(deployer, yesTokenId);
            uint256 noBalance = outcomeToken.balanceOf(deployer, noTokenId);
            
            console.log("YES balance:", yesBalance);
            console.log("NO balance:", noBalance);
            
            uint256 usdcBefore = usdc.balanceOf(deployer);
            
            // Redeem all shares (only winning shares pay out)
            uint256 payout = cpmm.redeem(marketId);
            console.log("Total payout:", payout);
            
            uint256 usdcAfter = usdc.balanceOf(deployer);
            console.log("\nTotal USDC received:", usdcAfter - usdcBefore);
            
            // Verify tokens were burned
            uint256 yesBalanceAfter = outcomeToken.balanceOf(deployer, yesTokenId);
            uint256 noBalanceAfter = outcomeToken.balanceOf(deployer, noTokenId);
            console.log("YES balance after:", yesBalanceAfter);
            console.log("NO balance after:", noBalanceAfter);
        }
        
        vm.stopBroadcast();
        
        console.log("\n=== TEST COMPLETE ===");
    }
}

