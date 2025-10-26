// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./OutcomeToken.sol";

/// @title BinaryMarketCPMM
/// @notice Constant Product Market Maker for binary prediction markets
/// @dev Implements x*y=k AMM for YES/NO outcome tokens with USDC collateral
/// @dev Uses Ownable2Step for secure governance transfer (deployer → DAO)
contract BinaryMarketCPMM is Ownable2Step {
    using SafeERC20 for IERC20;

    // Market states
    enum MarketStatus {
        Active,      // Trading is open
        Locked,      // Snapshot locked, awaiting resolution
        Resolved,    // Outcome determined, users can redeem
        Invalid      // Market cancelled/invalid
    }

    struct Market {
        bytes32 marketId;
        bytes32 templateId;
        address creator;
        uint64 settleTs;
        uint64 createdAt;
        uint16 feeBps;           // Fee in basis points (100 = 1%)
        uint16 creatorFeeBps;    // Creator's share of fees
        MarketStatus status;
        uint8 winningOutcome;    // 0=YES, 1=NO, 255=unresolved
        uint128 yesReserve;      // Reserve of YES tokens
        uint128 noReserve;       // Reserve of NO tokens
        uint256 totalVolume;     // Cumulative trading volume
    }

    // Constants
    uint256 private constant BPS_BASE = 10000;
    uint256 private constant MIN_LIQUIDITY = 100 * 10**6; // 100 USDC minimum (6 decimals)
    uint8 private constant YES = 0;
    uint8 private constant NO = 1;
    uint8 private constant UNRESOLVED = 255;

    // State variables
    IERC20 public immutable collateral; // USDC
    OutcomeToken public immutable outcomeToken;
    address public marketScheduler; // Chainlink Automation Forwarder address
    address public marketFactory; // Only this address can create markets
    uint256 public totalReserves; // Total USDC locked in all market reserves

    mapping(bytes32 => Market) public markets;
    mapping(bytes32 => bytes) public marketParams; // Template-specific parameters

    // Events
    event MarketCreated(
        bytes32 indexed marketId,
        bytes32 indexed templateId,
        address indexed creator,
        uint64 settleTs,
        uint16 feeBps,
        uint128 initialLiquidity
    );

    event Trade(
        bytes32 indexed marketId,
        address indexed trader,
        uint8 outcome,
        uint256 collateralIn,
        uint256 sharesOut,
        uint256 newPrice // Price in BPS after trade
    );

    event LiquidityAdded(
        bytes32 indexed marketId,
        address indexed provider,
        uint256 collateralAmount,
        uint256 yesShares,
        uint256 noShares
    );

    event LiquidityRemoved(
        bytes32 indexed marketId,
        address indexed provider,
        uint256 yesShares,
        uint256 noShares,
        uint256 collateralOut
    );

    event MarketLocked(bytes32 indexed marketId);

    event MarketResolved(bytes32 indexed marketId, uint8 winningOutcome);

    event Redeemed(
        bytes32 indexed marketId,
        address indexed user,
        uint256 payout
    );

    event MarketSchedulerUpdated(address indexed oldScheduler, address indexed newScheduler);

    event FeesClaimed(address indexed owner, address indexed recipient, uint256 amount);

    // Errors
    error MarketNotActive();
    error MarketNotResolved();
    error InvalidOutcome();
    error InsufficientLiquidity();
    error InsufficientShares();
    error SlippageExceeded();
    error Unauthorized();
    error InvalidMarketParams();
    error MarketAlreadyExists();
    error MarketNotLocked();
    error InvalidAddress();
    error NoFeesToClaim();

    modifier onlyScheduler() {
        if (msg.sender != marketScheduler) revert Unauthorized();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != marketFactory) revert Unauthorized();
        _;
    }

    constructor(address _collateral, address _outcomeToken, address _marketScheduler, address initialOwner)
        Ownable(initialOwner)
    {
        collateral = IERC20(_collateral);
        outcomeToken = OutcomeToken(_outcomeToken);
        marketScheduler = _marketScheduler;
    }

    /// @notice Set the MarketFactory address (one-time setup)
    /// @param _marketFactory Address of the MarketFactory contract
    /// @dev Can only be called once, immediately after deployment
    function setMarketFactory(address _marketFactory) external {
        if (marketFactory != address(0)) revert Unauthorized();
        marketFactory = _marketFactory;
    }

    /// @notice Update the market scheduler address (Chainlink Automation Forwarder)
    /// @param _newScheduler Address of the new scheduler
    /// @dev Only callable by owner, typically set to Chainlink Automation Forwarder
    function setMarketScheduler(address _newScheduler) external onlyOwner {
        if (_newScheduler == address(0)) revert InvalidAddress();
        address oldScheduler = marketScheduler;
        marketScheduler = _newScheduler;
        emit MarketSchedulerUpdated(oldScheduler, _newScheduler);
    }

    /// @notice Claim accumulated protocol fees
    /// @param recipient Address to receive the fees
    /// @dev Only callable by owner. Claims fees = contract balance - total reserves
    function claimFees(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidAddress();
        
        // Calculate claimable fees: contract balance minus locked reserves
        uint256 contractBalance = collateral.balanceOf(address(this));
        if (contractBalance <= totalReserves) revert NoFeesToClaim();
        
        uint256 claimableAmount = contractBalance - totalReserves;
        
        // Transfer fees to recipient
        collateral.safeTransfer(recipient, claimableAmount);
        
        emit FeesClaimed(owner(), recipient, claimableAmount);
    }

    /// @notice Create a new prediction market
    /// @param marketId Unique identifier for the market
    /// @param templateId Template type (e.g., PRICE_ABOVE_AT_TIME)
    /// @param params Template-specific parameters (encoded)
    /// @param settleTs Timestamp when market should settle
    /// @param feeBps Fee in basis points
    /// @param creatorFeeBps Creator's share of fees in basis points
    /// @param creator Address of the market creator (receives LP tokens)
    /// @param initialLiquidity Initial USDC to seed the market (50/50 YES/NO)
    /// @dev Only callable by MarketFactory, which handles USDC transfer and passes it through
    function createMarket(
        bytes32 marketId,
        bytes32 templateId,
        bytes calldata params,
        uint64 settleTs,
        uint16 feeBps,
        uint16 creatorFeeBps,
        address creator,
        uint128 initialLiquidity
    ) external onlyFactory {
        if (markets[marketId].marketId != bytes32(0)) revert MarketAlreadyExists();
        if (settleTs <= block.timestamp) revert InvalidMarketParams();
        if (feeBps > 500) revert InvalidMarketParams(); // Max 5% fee
        if (creatorFeeBps > feeBps) revert InvalidMarketParams();
        if (initialLiquidity < MIN_LIQUIDITY) revert InsufficientLiquidity();

        // Create market struct
        markets[marketId] = Market({
            marketId: marketId,
            templateId: templateId,
            creator: creator,
            settleTs: settleTs,
            createdAt: uint64(block.timestamp),
            feeBps: feeBps,
            creatorFeeBps: creatorFeeBps,
            status: MarketStatus.Active,
            winningOutcome: UNRESOLVED,
            yesReserve: initialLiquidity,
            noReserve: initialLiquidity,
            totalVolume: 0
        });

        marketParams[marketId] = params;

        // Transfer collateral from factory (factory receives it from creator first)
        collateral.safeTransferFrom(msg.sender, address(this), initialLiquidity * 2);

        // Track reserves
        totalReserves += initialLiquidity * 2;

        // Mint initial LP tokens (YES and NO) to creator
        uint256 yesTokenId = outcomeToken.encodeTokenId(marketId, YES);
        uint256 noTokenId = outcomeToken.encodeTokenId(marketId, NO);
        outcomeToken.mint(creator, yesTokenId, initialLiquidity);
        outcomeToken.mint(creator, noTokenId, initialLiquidity);

        emit MarketCreated(marketId, templateId, creator, settleTs, feeBps, initialLiquidity);
    }

    /// @notice Buy outcome tokens (YES or NO)
    /// @param marketId The market to trade in
    /// @param outcome The outcome to buy (0=YES, 1=NO)
    /// @param collateralIn Amount of USDC to spend
    /// @param minSharesOut Minimum shares to receive (slippage protection)
    /// @return sharesOut Amount of outcome tokens received
    function buy(bytes32 marketId, uint8 outcome, uint256 collateralIn, uint256 minSharesOut)
        external
        returns (uint256 sharesOut)
    {
        Market storage market = markets[marketId];
        if (market.status != MarketStatus.Active) revert MarketNotActive();
        if (outcome > 1) revert InvalidOutcome();

        // Calculate fee
        uint256 feeAmount = (collateralIn * market.feeBps) / BPS_BASE;
        uint256 collateralAfterFee = collateralIn - feeAmount;

        // Calculate shares out using CPMM formula: dy = y - (k / (x + dx))
        uint128 reserveIn = (outcome == YES) ? market.yesReserve : market.noReserve;
        uint128 reserveOut = (outcome == YES) ? market.noReserve : market.yesReserve;

        uint256 k = uint256(reserveIn) * uint256(reserveOut);
        uint256 newReserveIn = uint256(reserveIn) + collateralAfterFee;
        uint256 newReserveOut = k / newReserveIn;
        sharesOut = uint256(reserveOut) - newReserveOut;

        if (sharesOut < minSharesOut) revert SlippageExceeded();

        // Update reserves
        if (outcome == YES) {
            market.yesReserve = uint128(newReserveIn);
            market.noReserve = uint128(newReserveOut);
        } else {
            market.noReserve = uint128(newReserveIn);
            market.yesReserve = uint128(newReserveOut);
        }

        market.totalVolume += collateralIn;

        // Transfer collateral from user
        collateral.safeTransferFrom(msg.sender, address(this), collateralIn);

        // Distribute fees (could be sent to protocol treasury & creator)
        // For now, fees stay in contract as additional liquidity

        // Mint outcome tokens to user
        uint256 tokenId = outcomeToken.encodeTokenId(marketId, outcome);
        outcomeToken.mint(msg.sender, tokenId, sharesOut);

        // Calculate new price for event
        uint256 newPrice = (uint256(market.yesReserve) * BPS_BASE) /
            (uint256(market.yesReserve) + uint256(market.noReserve));

        emit Trade(marketId, msg.sender, outcome, collateralIn, sharesOut, newPrice);
    }

    /// @notice Sell outcome tokens back to the pool
    /// @param marketId The market to trade in
    /// @param outcome The outcome to sell (0=YES, 1=NO)
    /// @param sharesIn Amount of outcome tokens to sell
    /// @param minCollateralOut Minimum USDC to receive (slippage protection)
    /// @return collateralOut Amount of USDC received
    function sell(bytes32 marketId, uint8 outcome, uint256 sharesIn, uint256 minCollateralOut)
        external
        returns (uint256 collateralOut)
    {
        Market storage market = markets[marketId];
        if (market.status != MarketStatus.Active) revert MarketNotActive();
        if (outcome > 1) revert InvalidOutcome();

        // Calculate collateral out using CPMM formula: dx = x - (k / (y + dy))
        uint128 reserveIn = (outcome == YES) ? market.noReserve : market.yesReserve;
        uint128 reserveOut = (outcome == YES) ? market.yesReserve : market.noReserve;

        uint256 k = uint256(reserveIn) * uint256(reserveOut);
        uint256 newReserveOut = uint256(reserveOut) + sharesIn;
        uint256 newReserveIn = k / newReserveOut;
        uint256 collateralGross = uint256(reserveIn) - newReserveIn;

        // Calculate fee
        uint256 feeAmount = (collateralGross * market.feeBps) / BPS_BASE;
        collateralOut = collateralGross - feeAmount;

        if (collateralOut < minCollateralOut) revert SlippageExceeded();

        // Update reserves
        if (outcome == YES) {
            market.yesReserve = uint128(newReserveOut);
            market.noReserve = uint128(newReserveIn);
        } else {
            market.noReserve = uint128(newReserveOut);
            market.yesReserve = uint128(newReserveIn);
        }

        market.totalVolume += collateralGross;

        // Burn outcome tokens from user
        uint256 tokenId = outcomeToken.encodeTokenId(marketId, outcome);
        outcomeToken.burn(msg.sender, tokenId, sharesIn);

        // Transfer collateral to user
        collateral.safeTransfer(msg.sender, collateralOut);

        // Calculate new price for event
        uint256 newPrice = (uint256(market.yesReserve) * BPS_BASE) /
            (uint256(market.yesReserve) + uint256(market.noReserve));

        emit Trade(marketId, msg.sender, outcome, collateralOut, sharesIn, newPrice);
    }

    /// @notice Get current price for YES outcome in basis points
    /// @param marketId The market to query
    /// @return price Price of YES in BPS (5000 = 50%)
    function getYesPrice(bytes32 marketId) external view returns (uint256 price) {
        Market memory market = markets[marketId];
        if (market.yesReserve == 0 && market.noReserve == 0) return 5000; // 50% default

        price = (uint256(market.yesReserve) * BPS_BASE) /
            (uint256(market.yesReserve) + uint256(market.noReserve));
    }

    /// @notice Lock market (called by scheduler at settleTs)
    /// @param marketId The market to lock
    function lockMarket(bytes32 marketId) external onlyScheduler {
        Market storage market = markets[marketId];
        if (market.status != MarketStatus.Active) revert MarketNotActive();

        market.status = MarketStatus.Locked;
        emit MarketLocked(marketId);
    }

    /// @notice Resolve market with winning outcome (called by scheduler)
    /// @param marketId The market to resolve
    /// @param winningOutcome The winning outcome (0=YES, 1=NO)
    function resolveMarket(bytes32 marketId, uint8 winningOutcome) external onlyScheduler {
        Market storage market = markets[marketId];
        if (market.status != MarketStatus.Locked) revert MarketNotLocked();
        if (winningOutcome > 1) revert InvalidOutcome();

        market.status = MarketStatus.Resolved;
        market.winningOutcome = winningOutcome;

        emit MarketResolved(marketId, winningOutcome);
    }

    /// @notice Redeem winning shares for USDC
    /// @param marketId The market to redeem from
    function redeem(bytes32 marketId) external returns (uint256 payout) {
        Market memory market = markets[marketId];
        if (market.status != MarketStatus.Resolved) revert MarketNotResolved();

        uint256 winningTokenId = outcomeToken.encodeTokenId(marketId, market.winningOutcome);
        uint256 winningShares = outcomeToken.balanceOf(msg.sender, winningTokenId);

        if (winningShares == 0) revert InsufficientShares();

        // Each winning share is worth 1 USDC (1:1 redemption)
        payout = winningShares;

        // Burn winning shares
        outcomeToken.burn(msg.sender, winningTokenId, winningShares);

        // Decrease total reserves
        totalReserves -= payout;

        // Transfer USDC payout
        collateral.safeTransfer(msg.sender, payout);

        emit Redeemed(marketId, msg.sender, payout);
    }

    /// @notice Get market details
    /// @param marketId The market to query
    /// @return market The market struct
    function getMarket(bytes32 marketId) external view returns (Market memory market) {
        return markets[marketId];
    }

    /// @notice Get market parameters
    /// @param marketId The market to query
    /// @return params The encoded parameters
    function getMarketParams(bytes32 marketId) external view returns (bytes memory params) {
        return marketParams[marketId];
    }

    /// @notice Get claimable fees available to admin
    /// @return claimable Amount of USDC fees available to claim
    function getClaimableFees() external view returns (uint256 claimable) {
        uint256 contractBalance = collateral.balanceOf(address(this));
        if (contractBalance <= totalReserves) {
            return 0;
        }
        return contractBalance - totalReserves;
    }

    /// @notice Get current price for NO outcome in basis points
    /// @param marketId The market to query
    /// @return price Price of NO in BPS (5000 = 50%)
    function getNoPrice(bytes32 marketId) external view returns (uint256 price) {
        Market memory market = markets[marketId];
        if (market.yesReserve == 0 && market.noReserve == 0) return 5000; // 50% default

        price = (uint256(market.noReserve) * BPS_BASE) /
            (uint256(market.yesReserve) + uint256(market.noReserve));
    }

    /// @notice Get both YES and NO reserves for a market
    /// @param marketId The market to query
    /// @return yesReserve YES token reserve
    /// @return noReserve NO token reserve
    function getMarketReserves(bytes32 marketId) external view returns (uint128 yesReserve, uint128 noReserve) {
        Market memory market = markets[marketId];
        return (market.yesReserve, market.noReserve);
    }

    /// @notice Calculate shares received for a buy (preview)
    /// @param marketId The market to query
    /// @param outcome The outcome to buy (0=YES, 1=NO)
    /// @param collateralIn Amount of USDC to spend
    /// @return sharesOut Expected shares to receive (after fees)
    /// @return priceImpact Price impact in BPS
    function calculateBuyShares(bytes32 marketId, uint8 outcome, uint256 collateralIn)
        external
        view
        returns (uint256 sharesOut, uint256 priceImpact)
    {
        Market memory market = markets[marketId];
        if (outcome > 1) return (0, 0);

        // Calculate fee
        uint256 feeAmount = (collateralIn * market.feeBps) / BPS_BASE;
        uint256 collateralAfterFee = collateralIn - feeAmount;

        // Calculate shares using CPMM formula
        uint128 reserveIn = (outcome == YES) ? market.yesReserve : market.noReserve;
        uint128 reserveOut = (outcome == YES) ? market.noReserve : market.yesReserve;

        uint256 k = uint256(reserveIn) * uint256(reserveOut);
        uint256 newReserveIn = uint256(reserveIn) + collateralAfterFee;
        uint256 newReserveOut = k / newReserveIn;
        sharesOut = uint256(reserveOut) - newReserveOut;

        // Calculate price impact
        uint256 oldPrice = (uint256(market.yesReserve) * BPS_BASE) /
            (uint256(market.yesReserve) + uint256(market.noReserve));
        
        uint128 newYesReserve = (outcome == YES) ? uint128(newReserveIn) : uint128(newReserveOut);
        uint128 newNoReserve = (outcome == YES) ? uint128(newReserveOut) : uint128(newReserveIn);
        
        uint256 newPrice = (uint256(newYesReserve) * BPS_BASE) /
            (uint256(newYesReserve) + uint256(newNoReserve));
        
        priceImpact = (outcome == YES) ? (newPrice > oldPrice ? newPrice - oldPrice : 0) :
                                          (oldPrice > newPrice ? oldPrice - newPrice : 0);
    }

    /// @notice Calculate collateral received for a sell (preview)
    /// @param marketId The market to query
    /// @param outcome The outcome to sell (0=YES, 1=NO)
    /// @param sharesIn Amount of shares to sell
    /// @return collateralOut Expected USDC to receive (after fees)
    function calculateSellReturn(bytes32 marketId, uint8 outcome, uint256 sharesIn)
        external
        view
        returns (uint256 collateralOut)
    {
        Market memory market = markets[marketId];
        if (outcome > 1) return 0;

        // Calculate collateral using CPMM formula
        uint128 reserveIn = (outcome == YES) ? market.noReserve : market.yesReserve;
        uint128 reserveOut = (outcome == YES) ? market.yesReserve : market.noReserve;

        uint256 k = uint256(reserveIn) * uint256(reserveOut);
        uint256 newReserveOut = uint256(reserveOut) + sharesIn;
        uint256 newReserveIn = k / newReserveOut;
        uint256 collateralGross = uint256(reserveIn) - newReserveIn;

        // Calculate fee
        uint256 feeAmount = (collateralGross * market.feeBps) / BPS_BASE;
        collateralOut = collateralGross - feeAmount;
    }

    /// @notice Check if a market is actively trading
    /// @param marketId The market to query
    /// @return active True if market status is Active
    function isMarketActive(bytes32 marketId) external view returns (bool active) {
        return markets[marketId].status == MarketStatus.Active;
    }

    /// @notice Get total USDC balance in contract
    /// @return balance Total USDC held by contract
    function getTotalContractBalance() external view returns (uint256 balance) {
        return collateral.balanceOf(address(this));
    }

    /// @notice Get user's shares for both outcomes
    /// @param marketId The market to query
    /// @param user Address of the user
    /// @return yesShares User's YES token balance
    /// @return noShares User's NO token balance
    function getUserShares(bytes32 marketId, address user)
        external
        view
        returns (uint256 yesShares, uint256 noShares)
    {
        uint256 yesTokenId = outcomeToken.encodeTokenId(marketId, YES);
        uint256 noTokenId = outcomeToken.encodeTokenId(marketId, NO);
        
        yesShares = outcomeToken.balanceOf(user, yesTokenId);
        noShares = outcomeToken.balanceOf(user, noTokenId);
    }
}

