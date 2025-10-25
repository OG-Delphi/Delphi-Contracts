// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MarketFactory.sol";
import "../test/mocks/MockERC20.sol";

/// @title CreateMarket
/// @notice Script to create a test market on deployed contracts
contract CreateMarket is Script {
    function run() external {
        // Load deployment addresses
        uint256 chainId = block.chainid;
        string memory deploymentFile = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        string memory json = vm.readFile(deploymentFile);

        address factoryAddr = vm.parseJsonAddress(json, ".contracts.MarketFactory");
        address usdcAddr = vm.parseJsonAddress(json, ".infrastructure.USDC");

        console.log("Creating market on chain:", chainId);
        console.log("Factory:", factoryAddr);
        console.log("USDC:", usdcAddr);

        // Get deployer key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        MarketFactory factory = MarketFactory(factoryAddr);
        MockERC20 usdc = MockERC20(usdcAddr);

        // Approve factory to take creation fee
        uint256 creationFee = factory.creationFee();
        console.log("Approving creation fee:", creationFee);
        usdc.approve(factoryAddr, creationFee);

        // Get whitelisted feeds
        address[] memory feeds = factory.getWhitelistedFeeds();
        require(feeds.length > 0, "No whitelisted feeds");
        
        address feed = feeds[0]; // Use first whitelisted feed
        console.log("Using feed:", feed);

        // Create a test market: "Will BTC be above $75,000 in 30 days?"
        uint64 settleTs = uint64(block.timestamp + 30 days);
        int256 strikePrice = 75000e8; // $75,000 with 8 decimals
        uint16 feeBps = 150; // 1.5% fee
        uint16 creatorFeeBps = 50; // 0.5% to creator
        uint128 initialLiquidity = 1000 * 10**6; // 1000 USDC

        console.log("\nCreating market:");
        console.log("  Settle time:", settleTs);
        console.log("  Strike price:", vm.toString(strikePrice));
        console.log("  Initial liquidity:", initialLiquidity);

        // Approve initial liquidity
        usdc.approve(factoryAddr, initialLiquidity);
        
        bytes32 marketId = factory.createPriceAboveAtTime(
            feed,
            strikePrice,
            settleTs,
            feeBps,
            creatorFeeBps,
            initialLiquidity
        );

        console.log("\nMarket created with ID:", vm.toString(marketId));

        vm.stopBroadcast();
    }
}

