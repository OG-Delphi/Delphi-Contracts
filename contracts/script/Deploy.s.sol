// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/OutcomeToken.sol";
import "../src/OracleRouter.sol";
import "../src/BinaryMarketCPMM.sol";
import "../src/MarketScheduler.sol";
import "../src/MarketFactory.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockChainlinkFeed.sol";
import "./Config.sol";

/// @title Deploy
/// @notice Main deployment script for prediction market protocol
contract Deploy is Script {
    // Deployed contracts
    OutcomeToken public outcomeToken;
    OracleRouter public oracleRouter;
    BinaryMarketCPMM public cpmm;
    MarketScheduler public scheduler;
    MarketFactory public factory;

    // Infrastructure
    MockERC20 public usdc;
    MockChainlinkFeed public btcFeed;
    MockChainlinkFeed public ethFeed;
    MockChainlinkFeed public solFeed;

    // Configuration
    address public feeTreasury;
    uint256 public creationFee = 10 * 10**6; // 10 USDC

    function run() external {
        // Get network config
        uint256 chainId = block.chainid;
        Config.NetworkConfig memory config = getConfig(chainId);

        // Use deployer private key from environment or config
        uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", config.deployerPrivateKey);
        require(deployerPrivateKey != 0, "DEPLOYER_PRIVATE_KEY not set");

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deploying from:", deployer);
        console.log("Chain ID:", chainId);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Set fee treasury (deployer for now, can be changed to DAO later)
        feeTreasury = deployer;

        // Step 1: Deploy or use existing USDC
        if (config.usdc == address(0)) {
            console.log("Deploying Mock USDC...");
            usdc = new MockERC20("USD Coin", "USDC", 6);
            console.log("Mock USDC deployed at:", address(usdc));
            
            // Mint some test USDC to deployer
            usdc.mint(deployer, 1000000 * 10**6); // 1M USDC
            console.log("Minted 1M test USDC to deployer");
        } else {
            console.log("Using existing USDC at:", config.usdc);
        }

        // Step 2: Deploy or use existing Chainlink feeds
        if (config.btcUsdFeed == address(0)) {
            console.log("Deploying Mock BTC/USD feed...");
            btcFeed = new MockChainlinkFeed(8, "BTC/USD");
            btcFeed.setLatestRoundData(70000e8, block.timestamp, block.timestamp);
            console.log("Mock BTC/USD feed deployed at:", address(btcFeed));
        }

        if (config.ethUsdFeed == address(0)) {
            console.log("Deploying Mock ETH/USD feed...");
            ethFeed = new MockChainlinkFeed(8, "ETH/USD");
            ethFeed.setLatestRoundData(3500e8, block.timestamp, block.timestamp);
            console.log("Mock ETH/USD feed deployed at:", address(ethFeed));
        }

        if (config.solUsdFeed == address(0)) {
            console.log("Deploying Mock SOL/USD feed...");
            solFeed = new MockChainlinkFeed(8, "SOL/USD");
            solFeed.setLatestRoundData(150e8, block.timestamp, block.timestamp);
            console.log("Mock SOL/USD feed deployed at:", address(solFeed));
        }

        // Step 3: Deploy OracleRouter
        console.log("\nDeploying OracleRouter...");
        oracleRouter = new OracleRouter();
        console.log("OracleRouter deployed at:", address(oracleRouter));

        // Step 4: Deploy OutcomeToken with predicted CPMM address
        // We need to compute the address CPMM will have
        console.log("\nComputing future CPMM address...");
        address predictedCPMM = computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        console.log("Predicted CPMM address:", predictedCPMM);

        console.log("Deploying OutcomeToken...");
        outcomeToken = new OutcomeToken(predictedCPMM);
        console.log("OutcomeToken deployed at:", address(outcomeToken));

        // Step 5: Deploy CPMM (this must be the next deployment to match predicted address)
        console.log("\nDeploying BinaryMarketCPMM...");
        address usdcAddress = config.usdc == address(0) ? address(usdc) : config.usdc;
        
        // Use deployer as scheduler temporarily, will update after MarketScheduler is deployed
        cpmm = new BinaryMarketCPMM(
            usdcAddress,
            address(outcomeToken),
            deployer // Temporary scheduler
        );
        console.log("BinaryMarketCPMM deployed at:", address(cpmm));
        require(address(cpmm) == predictedCPMM, "CPMM address mismatch!");

        // Step 6: Deploy MarketScheduler
        console.log("\nDeploying MarketScheduler...");
        scheduler = new MarketScheduler(address(cpmm), address(oracleRouter));
        console.log("MarketScheduler deployed at:", address(scheduler));

        // Step 7: Deploy MarketFactory
        console.log("\nDeploying MarketFactory...");
        factory = new MarketFactory(
            address(cpmm),
            address(scheduler),
            usdcAddress,
            feeTreasury,
            deployer // Initial owner (can be transferred to DAO later)
        );
        console.log("MarketFactory deployed at:", address(factory));

        // Step 8: Wire up access control
        console.log("\nSetting up access control...");
        cpmm.setMarketFactory(address(factory));
        console.log("CPMM: MarketFactory access granted");
        
        scheduler.setMarketFactory(address(factory));
        console.log("Scheduler: MarketFactory access granted");

        // Step 9: Whitelist price feeds in factory
        console.log("\nWhitelisting price feeds...");
        address btcFeedAddr = config.btcUsdFeed == address(0) ? address(btcFeed) : config.btcUsdFeed;
        address ethFeedAddr = config.ethUsdFeed == address(0) ? address(ethFeed) : config.ethUsdFeed;
        address solFeedAddr = config.solUsdFeed == address(0) ? address(solFeed) : config.solUsdFeed;

        if (btcFeedAddr != address(0)) {
            factory.whitelistFeed(btcFeedAddr, "BTC/USD");
            console.log("Whitelisted BTC/USD feed");
        }
        if (ethFeedAddr != address(0)) {
            factory.whitelistFeed(ethFeedAddr, "ETH/USD");
            console.log("Whitelisted ETH/USD feed");
        }
        if (solFeedAddr != address(0)) {
            factory.whitelistFeed(solFeedAddr, "SOL/USD");
            console.log("Whitelisted SOL/USD feed");
        }

        vm.stopBroadcast();

        // Print deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Network:", getNetworkName(chainId));
        console.log("Deployer:", deployer);
        console.log("Fee Treasury:", feeTreasury);
        console.log("\nCore Contracts:");
        console.log("  OutcomeToken:", address(outcomeToken));
        console.log("  OracleRouter:", address(oracleRouter));
        console.log("  BinaryMarketCPMM:", address(cpmm));
        console.log("  MarketScheduler:", address(scheduler));
        console.log("  MarketFactory:", address(factory));
        console.log("\nGovernance:");
        console.log("  Factory Owner:", factory.owner());
        console.log("  CPMM.marketFactory:", cpmm.marketFactory());
        console.log("  Scheduler.marketFactory:", scheduler.marketFactory());
        console.log("\nInfrastructure:");
        console.log("  USDC:", usdcAddress);
        console.log("  BTC/USD Feed:", btcFeedAddr);
        console.log("  ETH/USD Feed:", ethFeedAddr);
        console.log("  SOL/USD Feed:", solFeedAddr);
        console.log("\n=========================");

        // Save deployment addresses to file
        saveDeployment(chainId);
    }

    function getConfig(uint256 chainId) internal pure returns (Config.NetworkConfig memory) {
        if (chainId == 84532) {
            // Base Sepolia
            return Config.getBaseSepoliaConfig();
        } else if (chainId == 8453) {
            // Base Mainnet
            return Config.getBaseMainnetConfig();
        } else if (chainId == 31337) {
            // Anvil local
            return Config.getAnvilConfig();
        } else {
            revert("Unsupported network");
        }
    }

    function getNetworkName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 84532) return "Base Sepolia";
        if (chainId == 8453) return "Base Mainnet";
        if (chainId == 31337) return "Anvil (Local)";
        return "Unknown";
    }


    function saveDeployment(uint256 chainId) internal {
        string memory json = string(abi.encodePacked(
            '{\n',
            '  "chainId": ', vm.toString(chainId), ',\n',
            '  "network": "', getNetworkName(chainId), '",\n',
            '  "timestamp": ', vm.toString(block.timestamp), ',\n',
            '  "deployer": "', vm.toString(msg.sender), '",\n',
            '  "contracts": {\n',
            '    "OutcomeToken": "', vm.toString(address(outcomeToken)), '",\n',
            '    "OracleRouter": "', vm.toString(address(oracleRouter)), '",\n',
            '    "BinaryMarketCPMM": "', vm.toString(address(cpmm)), '",\n',
            '    "MarketScheduler": "', vm.toString(address(scheduler)), '",\n',
            '    "MarketFactory": "', vm.toString(address(factory)), '"\n',
            '  }\n',
            '}'
        ));

        string memory filename = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        vm.writeFile(filename, json);
        console.log("\nDeployment saved to:", filename);
    }
}

