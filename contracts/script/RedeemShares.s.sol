// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/BinaryMarketCPMM.sol";
import "../src/OutcomeToken.sol";

/// @title RedeemShares
/// @notice Redeem shares after market resolution
contract RedeemShares is Script {
    uint8 constant YES = 0;
    uint8 constant NO = 1;

    function run() external {
        bytes32 marketId = vm.envBytes32("MARKET_ID");
        
        console.log("=== REDEEMING SHARES ===\n");
        console.log("Market ID:", vm.toString(marketId));

        // Load contracts
        uint256 chainId = block.chainid;
        string memory deploymentFile = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        string memory json = vm.readFile(deploymentFile);

        address cpmmAddr = vm.parseJsonAddress(json, ".contracts.BinaryMarketCPMM");
        address outcomeTokenAddr = vm.parseJsonAddress(json, ".contracts.OutcomeToken");

        BinaryMarketCPMM cpmm = BinaryMarketCPMM(cpmmAddr);
        OutcomeToken outcomeToken = OutcomeToken(outcomeTokenAddr);

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Check market status
        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
        
        console.log("\n[MARKET STATUS]");
        console.log("  Status:", uint8(market.status));
        console.log("  Winning Outcome:", market.winningOutcome);
        console.log("  Settlement Time:", market.settleTs);
        console.log("  Current Time:", block.timestamp);

        if (market.status != BinaryMarketCPMM.MarketStatus.RESOLVED) {
            console.log("\n[ERROR] Market not yet resolved!");
            console.log("Market status:", uint8(market.status));
            console.log("0=ACTIVE, 1=LOCKED, 2=RESOLVED");
            return;
        }

        // Check holdings
        uint256 yesTokenId = outcomeToken.encodeTokenId(marketId, YES);
        uint256 noTokenId = outcomeToken.encodeTokenId(marketId, NO);
        uint256 yesBalance = outcomeToken.balanceOf(deployer, yesTokenId);
        uint256 noBalance = outcomeToken.balanceOf(deployer, noTokenId);

        console.log("\n[YOUR HOLDINGS]");
        console.log("  YES tokens:", yesBalance);
        console.log("  NO tokens:", noBalance);

        if (market.winningOutcome == YES) {
            console.log("\n[WINNER: YES]");
            console.log("  Expected payout:", yesBalance, "USDC");
        } else {
            console.log("\n[WINNER: NO]");
            console.log("  Expected payout:", noBalance, "USDC");
        }

        vm.startBroadcast(deployerPrivateKey);

        // Redeem
        console.log("\n[REDEEMING...]");
        uint256 payout = cpmm.redeem(marketId);
        
        console.log("\n[SUCCESS]");
        console.log("  Total payout received:", payout);
        console.log("  Transaction complete!");

        vm.stopBroadcast();
    }
}

