// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./BinaryMarketCPMM.sol";
import "./MarketScheduler.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MarketFactory
/// @notice Factory contract for creating prediction markets and registering them with the scheduler
/// @dev Provides template-based market creation with validation
/// @dev Uses Ownable2Step for secure governance transfer (deployer → DAO)
contract MarketFactory is Ownable2Step {
    using SafeERC20 for IERC20;

    // Template constants
    bytes32 public constant PRICE_ABOVE_AT_TIME = keccak256("PRICE_ABOVE_AT_TIME");

    // Core contracts
    BinaryMarketCPMM public immutable cpmm;
    MarketScheduler public immutable scheduler;
    IERC20 public immutable collateral;

    // Market creation fee (paid in USDC, funds LINK pool)
    uint256 public creationFee = 10 * 10**6; // 10 USDC (6 decimals)

    // Fee treasury (for LINK funding, protocol costs)
    address public feeTreasury;

    // Whitelisted Chainlink feeds (feed address => allowed)
    mapping(address => bool) public whitelistedFeeds;
    address[] private whitelistedFeedsList; // Array to track whitelisted feeds

    // Nonce for generating unique market IDs
    uint256 private nonce;

    // Events
    event MarketCreatedAndRegistered(
        bytes32 indexed marketId,
        address indexed creator,
        bytes32 indexed templateId,
        uint64 settleTs,
        uint128 initialLiquidity
    );

    event FeedWhitelisted(address indexed feed, string description);
    event FeedDelisted(address indexed feed);
    event CreationFeeUpdated(uint256 newFee);
    event FeeTreasuryUpdated(address newTreasury);

    // Errors
    error InvalidTemplate();
    error FeedNotWhitelisted();
    error InvalidStrikePrice();
    error InvalidSettleTime();
    error InvalidLiquidity();
    error InsufficientCreationFee();
    error ZeroAddress();

    constructor(address _cpmm, address _scheduler, address _collateral, address _feeTreasury, address initialOwner)
        Ownable(initialOwner)
    {
        if (_cpmm == address(0) || _scheduler == address(0) || _collateral == address(0) || _feeTreasury == address(0)) {
            revert ZeroAddress();
        }

        cpmm = BinaryMarketCPMM(_cpmm);
        scheduler = MarketScheduler(_scheduler);
        collateral = IERC20(_collateral);
        feeTreasury = _feeTreasury;
    }

    /// @notice Create a PRICE_ABOVE_AT_TIME market
    /// @param feed Chainlink price feed address
    /// @param strikePrice The strike price (in feed decimals, e.g., 8 decimals for BTC/USD)
    /// @param settleTs Timestamp when market settles
    /// @param feeBps Trading fee in basis points (e.g., 150 = 1.5%)
    /// @param creatorFeeBps Creator's share of fees in basis points
    /// @param initialLiquidity Initial USDC liquidity (will be split 50/50 YES/NO)
    /// @return marketId The unique identifier for the created market
    function createPriceAboveAtTime(
        address feed,
        int256 strikePrice,
        uint64 settleTs,
        uint16 feeBps,
        uint16 creatorFeeBps,
        uint128 initialLiquidity
    ) external returns (bytes32 marketId) {
        // Validation
        if (!whitelistedFeeds[feed]) revert FeedNotWhitelisted();
        if (strikePrice <= 0) revert InvalidStrikePrice();
        if (settleTs <= block.timestamp + 1 hours) revert InvalidSettleTime(); // At least 1 hour in future
        if (settleTs > block.timestamp + 365 days) revert InvalidSettleTime(); // Max 1 year
        if (initialLiquidity < 100 * 10**6) revert InvalidLiquidity(); // Min 100 USDC

        // Generate unique market ID
        marketId = keccak256(abi.encodePacked(
            msg.sender,
            feed,
            strikePrice,
            settleTs,
            nonce++,
            block.timestamp
        ));

        // Encode params for this template
        bytes memory params = abi.encode(feed, strikePrice);

        // Collect creation fee
        if (creationFee > 0) {
            collateral.transferFrom(msg.sender, feeTreasury, creationFee);
        }

        // Transfer initial liquidity from creator to this factory
        collateral.safeTransferFrom(msg.sender, address(this), initialLiquidity * 2);
        
        // Approve CPMM to take the liquidity
        collateral.approve(address(cpmm), initialLiquidity * 2);
        
        // Create market in CPMM (passing creator address for LP tokens)
        cpmm.createMarket(
            marketId,
            PRICE_ABOVE_AT_TIME,
            params,
            settleTs,
            feeBps,
            creatorFeeBps,
            msg.sender, // creator
            initialLiquidity
        );

        // Register with scheduler for automated resolution
        scheduler.registerMarket(marketId, settleTs, PRICE_ABOVE_AT_TIME);

        emit MarketCreatedAndRegistered(marketId, msg.sender, PRICE_ABOVE_AT_TIME, settleTs, initialLiquidity);
    }

    /// @notice Whitelist a Chainlink price feed
    /// @param feed The feed address to whitelist
    /// @param description Human-readable description (e.g., "BTC/USD")
    /// @dev Only callable by owner (deployer → DAO)
    function whitelistFeed(address feed, string calldata description) external onlyOwner {
        if (!whitelistedFeeds[feed]) {
            whitelistedFeeds[feed] = true;
            whitelistedFeedsList.push(feed);
            emit FeedWhitelisted(feed, description);
        }
    }

    /// @notice Delist a Chainlink price feed
    /// @param feed The feed address to delist
    /// @dev Only callable by owner (deployer → DAO)
    function delistFeed(address feed) external onlyOwner {
        whitelistedFeeds[feed] = false;
        emit FeedDelisted(feed);
    }

    /// @notice Update creation fee
    /// @param newFee The new creation fee in USDC (with 6 decimals)
    /// @dev Only callable by owner (deployer → DAO)
    function updateCreationFee(uint256 newFee) external onlyOwner {
        creationFee = newFee;
        emit CreationFeeUpdated(newFee);
    }

    /// @notice Update fee treasury address
    /// @param newTreasury The new treasury address
    /// @dev Only callable by owner (deployer → DAO)
    function updateFeeTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        feeTreasury = newTreasury;
        emit FeeTreasuryUpdated(newTreasury);
    }

    /// @notice Preview a market creation (calculate market ID without creating)
    /// @param feed Chainlink price feed address
    /// @param strikePrice The strike price
    /// @param settleTs Settlement timestamp
    /// @return marketId The predicted market ID
    function previewMarketId(address feed, int256 strikePrice, uint64 settleTs)
        external
        view
        returns (bytes32 marketId)
    {
        marketId = keccak256(abi.encodePacked(
            msg.sender,
            feed,
            strikePrice,
            settleTs,
            nonce,
            block.timestamp
        ));
    }

    /// @notice Check if a feed is whitelisted
    /// @param feed The feed address to check
    /// @return True if whitelisted
    function isFeedWhitelisted(address feed) external view returns (bool) {
        return whitelistedFeeds[feed];
    }

    /// @notice Get all whitelisted feeds
    /// @return Array of whitelisted feed addresses
    function getWhitelistedFeeds() external view returns (address[] memory) {
        return whitelistedFeedsList;
    }
}

