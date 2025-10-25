// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/BinaryMarketCPMM.sol";
import "../src/OutcomeToken.sol";
import "./mocks/MockERC20.sol";
import "./helpers/TestSetup.sol";

contract BinaryMarketCPMMTest is TestSetup {
    BinaryMarketCPMM public cpmm;
    OutcomeToken public outcomeToken;
    MockERC20 public usdc;
    
    address public scheduler;
    address public creator;
    address public trader1;
    address public trader2;

    bytes32 constant TEMPLATE_ID = keccak256("PRICE_ABOVE_AT_TIME");
    bytes32 marketId;
    uint64 settleTs;
    uint128 constant INITIAL_LIQUIDITY = 1000 * 10**6; // 1000 USDC
    uint16 constant FEE_BPS = 150; // 1.5%
    uint16 constant CREATOR_FEE_BPS = 50; // 0.5% to creator

    function setUp() public {
        // Warp to reasonable timestamp
        vm.warp(1700000000); // Nov 2023
        
        scheduler = makeAddr("scheduler");
        creator = makeAddr("creator");
        trader1 = makeAddr("trader1");
        trader2 = makeAddr("trader2");

        // Deploy USDC first
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // Use helper to deploy CPMM and OutcomeToken with correct circular reference
        (cpmm, outcomeToken) = deploySystem(address(usdc), scheduler);

        // Setup test market
        settleTs = uint64(block.timestamp + 7 days);
        marketId = keccak256(abi.encodePacked("test-market", block.timestamp));

        // Fund creator with USDC
        usdc.mint(creator, INITIAL_LIQUIDITY * 2);
        
        // Fund traders
        usdc.mint(trader1, 10000 * 10**6);
        usdc.mint(trader2, 10000 * 10**6);
    }

    /// @notice Helper to set up market - replicates what Factory does
    function setupMarket() internal {
        bytes memory params = abi.encode(address(0x123), int256(70000e8));
        
        vm.startPrank(creator);
        usdc.transfer(address(this), INITIAL_LIQUIDITY * 2);
        vm.stopPrank();
        
        usdc.approve(address(cpmm), INITIAL_LIQUIDITY * 2);
        cpmm.createMarket(marketId, TEMPLATE_ID, params, settleTs, FEE_BPS, CREATOR_FEE_BPS, creator, INITIAL_LIQUIDITY);
    }

    function test_CreateMarket() public {
        bytes memory params = abi.encode(address(0x123), int256(70000e8));

        // Transfer USDC from creator to test contract (acting as factory)
        vm.prank(creator);
        usdc.transfer(address(this), INITIAL_LIQUIDITY * 2);
        
        // Test contract acts as factory to create market
        usdc.approve(address(cpmm), INITIAL_LIQUIDITY * 2);
        cpmm.createMarket(marketId, TEMPLATE_ID, params, settleTs, FEE_BPS, CREATOR_FEE_BPS, creator, INITIAL_LIQUIDITY);

        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
        
        assertEq(market.marketId, marketId);
        assertEq(market.templateId, TEMPLATE_ID);
        assertEq(market.creator, creator);
        assertEq(market.settleTs, settleTs);
        assertEq(market.feeBps, FEE_BPS);
        assertEq(uint8(market.status), uint8(BinaryMarketCPMM.MarketStatus.Active));
        assertEq(market.yesReserve, INITIAL_LIQUIDITY);
        assertEq(market.noReserve, INITIAL_LIQUIDITY);
        assertEq(market.winningOutcome, 255); // UNRESOLVED
    }

    function test_CreateMarketMintsLPTokens() public {
        bytes memory params = abi.encode(address(0x123), int256(70000e8));

        vm.prank(creator);
        usdc.transfer(address(this), INITIAL_LIQUIDITY * 2);
        
        usdc.approve(address(cpmm), INITIAL_LIQUIDITY * 2);
        cpmm.createMarket(marketId, TEMPLATE_ID, params, settleTs, FEE_BPS, CREATOR_FEE_BPS, creator, INITIAL_LIQUIDITY);

        uint256 yesTokenId = outcomeToken.encodeTokenId(marketId, 0);
        uint256 noTokenId = outcomeToken.encodeTokenId(marketId, 1);

        assertEq(outcomeToken.balanceOf(creator, yesTokenId), INITIAL_LIQUIDITY);
        assertEq(outcomeToken.balanceOf(creator, noTokenId), INITIAL_LIQUIDITY);
    }

    function test_CreateMarketRevertsIfInsufficientLiquidity() public {
        bytes memory params = abi.encode(address(0x123), int256(70000e8));
        uint128 tooLow = 50 * 10**6; // Less than MIN_LIQUIDITY (100 USDC)

        vm.prank(creator);
        usdc.transfer(address(this), tooLow * 2);
        
        usdc.approve(address(cpmm), tooLow * 2);
        
        vm.expectRevert(BinaryMarketCPMM.InsufficientLiquidity.selector);
        cpmm.createMarket(marketId, TEMPLATE_ID, params, settleTs, FEE_BPS, CREATOR_FEE_BPS, creator, tooLow);
    }

    function test_CreateMarketRevertsIfAlreadyExists() public {
        bytes memory params = abi.encode(address(0x123), int256(70000e8));

        // Mint enough USDC for 2 markets
        usdc.mint(creator, INITIAL_LIQUIDITY * 2);
        
        vm.prank(creator);
        usdc.transfer(address(this), INITIAL_LIQUIDITY * 4);
        
        usdc.approve(address(cpmm), INITIAL_LIQUIDITY * 4);
        cpmm.createMarket(marketId, TEMPLATE_ID, params, settleTs, FEE_BPS, CREATOR_FEE_BPS, creator, INITIAL_LIQUIDITY);
        
        vm.expectRevert(BinaryMarketCPMM.MarketAlreadyExists.selector);
        cpmm.createMarket(marketId, TEMPLATE_ID, params, settleTs, FEE_BPS, CREATOR_FEE_BPS, creator, INITIAL_LIQUIDITY);
    }

    function _createTestMarket() internal {
        bytes memory params = abi.encode(address(0x123), int256(70000e8));
        
        vm.prank(creator);
        usdc.transfer(address(this), INITIAL_LIQUIDITY * 2);
        
        usdc.approve(address(cpmm), INITIAL_LIQUIDITY * 2);
        cpmm.createMarket(marketId, TEMPLATE_ID, params, settleTs, FEE_BPS, CREATOR_FEE_BPS, creator, INITIAL_LIQUIDITY);
    }

    function test_BuyYESTokens() public {
        _createTestMarket();

        uint256 collateralIn = 100 * 10**6; // 100 USDC
        
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), collateralIn);
        
        uint256 sharesBefore = outcomeToken.balanceOf(trader1, outcomeToken.encodeTokenId(marketId, 0));
        uint256 sharesOut = cpmm.buy(marketId, 0, collateralIn, 0);
        vm.stopPrank();

        uint256 sharesAfter = outcomeToken.balanceOf(trader1, outcomeToken.encodeTokenId(marketId, 0));
        assertEq(sharesAfter - sharesBefore, sharesOut);
        assertGt(sharesOut, 0);
    }

    function test_BuyNOTokens() public {
        _createTestMarket();

        uint256 collateralIn = 100 * 10**6;
        
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), collateralIn);
        uint256 sharesOut = cpmm.buy(marketId, 1, collateralIn, 0);
        vm.stopPrank();

        assertGt(sharesOut, 0);
        uint256 noBalance = outcomeToken.balanceOf(trader1, outcomeToken.encodeTokenId(marketId, 1));
        assertEq(noBalance, sharesOut);
    }

    function test_BuyMovesPrice() public {
        _createTestMarket();

        uint256 priceBefore = cpmm.getYesPrice(marketId);
        assertEq(priceBefore, 5000); // 50% initially (50/50 reserves)

        // Buy YES tokens (should increase YES price)
        uint256 collateralIn = 500 * 10**6;
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), collateralIn);
        cpmm.buy(marketId, 0, collateralIn, 0);
        vm.stopPrank();

        uint256 priceAfter = cpmm.getYesPrice(marketId);
        assertGt(priceAfter, priceBefore); // YES price increased
    }

    function test_CPMMInvariant() public {
        _createTestMarket();

        BinaryMarketCPMM.Market memory marketBefore = cpmm.getMarket(marketId);
        uint256 kBefore = uint256(marketBefore.yesReserve) * uint256(marketBefore.noReserve);

        // Execute trade
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), 100 * 10**6);
        cpmm.buy(marketId, 0, 100 * 10**6, 0);
        vm.stopPrank();

        BinaryMarketCPMM.Market memory marketAfter = cpmm.getMarket(marketId);
        uint256 kAfter = uint256(marketAfter.yesReserve) * uint256(marketAfter.noReserve);

        // k can decrease very slightly due to integer division rounding
        // but should stay close (within 0.01%)
        // Since fees stay in pool, k should actually be equal or slightly lower due to rounding
        uint256 kDiff = kBefore > kAfter ? kBefore - kAfter : kAfter - kBefore;
        assertLt(kDiff, kBefore / 10000); // Within 0.01%
    }

    function test_SellTokens() public {
        _createTestMarket();

        // First buy tokens
        uint256 buyAmount = 100 * 10**6;
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), buyAmount);
        uint256 sharesOut = cpmm.buy(marketId, 0, buyAmount, 0);
        
        // Then sell half back
        uint256 sellShares = sharesOut / 2;
        uint256 usdcBefore = usdc.balanceOf(trader1);
        uint256 collateralOut = cpmm.sell(marketId, 0, sellShares, 0);
        uint256 usdcAfter = usdc.balanceOf(trader1);
        vm.stopPrank();

        assertEq(usdcAfter - usdcBefore, collateralOut);
        assertGt(collateralOut, 0);
    }

    function test_SlippageProtectionOnBuy() public {
        _createTestMarket();

        uint256 collateralIn = 100 * 10**6;
        uint256 unrealisticMinShares = 200 * 10**6; // Expecting way more than possible

        vm.startPrank(trader1);
        usdc.approve(address(cpmm), collateralIn);
        
        vm.expectRevert(BinaryMarketCPMM.SlippageExceeded.selector);
        cpmm.buy(marketId, 0, collateralIn, unrealisticMinShares);
        vm.stopPrank();
    }

    function test_SlippageProtectionOnSell() public {
        _createTestMarket();

        // Buy first
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), 100 * 10**6);
        uint256 shares = cpmm.buy(marketId, 0, 100 * 10**6, 0);
        
        // Try to sell with unrealistic min collateral
        vm.expectRevert(BinaryMarketCPMM.SlippageExceeded.selector);
        cpmm.sell(marketId, 0, shares, 1000 * 10**6); // Expecting 1000 USDC back (impossible)
        vm.stopPrank();
    }

    function test_LockMarket() public {
        _createTestMarket();

        vm.prank(scheduler);
        cpmm.lockMarket(marketId);

        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
        assertEq(uint8(market.status), uint8(BinaryMarketCPMM.MarketStatus.Locked));
    }

    function test_LockMarketRevertsFromNonScheduler() public {
        _createTestMarket();

        vm.prank(trader1);
        vm.expectRevert(BinaryMarketCPMM.Unauthorized.selector);
        cpmm.lockMarket(marketId);
    }

    function test_CannotTradeInLockedMarket() public {
        _createTestMarket();

        vm.prank(scheduler);
        cpmm.lockMarket(marketId);

        vm.startPrank(trader1);
        usdc.approve(address(cpmm), 100 * 10**6);
        
        vm.expectRevert(BinaryMarketCPMM.MarketNotActive.selector);
        cpmm.buy(marketId, 0, 100 * 10**6, 0);
        vm.stopPrank();
    }

    function test_ResolveMarket() public {
        _createTestMarket();

        vm.startPrank(scheduler);
        cpmm.lockMarket(marketId);
        cpmm.resolveMarket(marketId, 0); // YES wins
        vm.stopPrank();

        BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
        assertEq(uint8(market.status), uint8(BinaryMarketCPMM.MarketStatus.Resolved));
        assertEq(market.winningOutcome, 0);
    }

    function test_ResolveMarketRevertsIfNotLocked() public {
        _createTestMarket();

        vm.prank(scheduler);
        vm.expectRevert(BinaryMarketCPMM.MarketNotLocked.selector);
        cpmm.resolveMarket(marketId, 0);
    }

    function test_RedeemWinningShares() public {
        _createTestMarket();

        // Trader buys YES tokens
        uint256 buyAmount = 100 * 10**6;
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), buyAmount);
        uint256 shares = cpmm.buy(marketId, 0, buyAmount, 0);
        vm.stopPrank();

        // Lock and resolve with YES winning
        vm.startPrank(scheduler);
        cpmm.lockMarket(marketId);
        cpmm.resolveMarket(marketId, 0); // YES wins
        vm.stopPrank();

        // Redeem
        uint256 usdcBefore = usdc.balanceOf(trader1);
        vm.prank(trader1);
        uint256 payout = cpmm.redeem(marketId);
        uint256 usdcAfter = usdc.balanceOf(trader1);

        assertEq(payout, shares); // 1:1 redemption
        assertEq(usdcAfter - usdcBefore, payout);
    }

    function test_RedeemBurnsTokens() public {
        _createTestMarket();

        // Buy and resolve
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), 100 * 10**6);
        cpmm.buy(marketId, 0, 100 * 10**6, 0);
        vm.stopPrank();

        vm.startPrank(scheduler);
        cpmm.lockMarket(marketId);
        cpmm.resolveMarket(marketId, 0);
        vm.stopPrank();

        uint256 yesTokenId = outcomeToken.encodeTokenId(marketId, 0);
        uint256 sharesBefore = outcomeToken.balanceOf(trader1, yesTokenId);

        vm.prank(trader1);
        cpmm.redeem(marketId);

        uint256 sharesAfter = outcomeToken.balanceOf(trader1, yesTokenId);
        assertEq(sharesAfter, 0);
        assertGt(sharesBefore, 0);
    }

    function test_LosingSharesWorthNothing() public {
        _createTestMarket();

        // Trader buys NO tokens
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), 100 * 10**6);
        cpmm.buy(marketId, 1, 100 * 10**6, 0); // NO
        vm.stopPrank();

        // YES wins
        vm.startPrank(scheduler);
        cpmm.lockMarket(marketId);
        cpmm.resolveMarket(marketId, 0); // YES wins
        vm.stopPrank();

        // Try to redeem NO shares
        vm.prank(trader1);
        vm.expectRevert(BinaryMarketCPMM.InsufficientShares.selector);
        cpmm.redeem(marketId);
    }

    function test_MultipleTraders() public {
        _createTestMarket();

        // Trader 1 buys YES
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), 200 * 10**6);
        uint256 shares1 = cpmm.buy(marketId, 0, 200 * 10**6, 0);
        vm.stopPrank();

        // Trader 2 buys NO
        vm.startPrank(trader2);
        usdc.approve(address(cpmm), 150 * 10**6);
        uint256 shares2 = cpmm.buy(marketId, 1, 150 * 10**6, 0);
        vm.stopPrank();

        // Resolve YES wins
        vm.startPrank(scheduler);
        cpmm.lockMarket(marketId);
        cpmm.resolveMarket(marketId, 0);
        vm.stopPrank();

        // Trader 1 redeems
        vm.prank(trader1);
        uint256 payout1 = cpmm.redeem(marketId);
        assertEq(payout1, shares1);

        // Trader 2 cannot redeem (has losing shares)
        vm.prank(trader2);
        vm.expectRevert(BinaryMarketCPMM.InsufficientShares.selector);
        cpmm.redeem(marketId);
    }

    function test_BuySellRoundtrip_SmallTrade() public {
        _createTestMarket();

        uint256 amount = 50 * 10**6; // 50 USDC (5% of pool)

        // Buy
        vm.startPrank(trader1);
        usdc.approve(address(cpmm), amount);
        uint256 shares = cpmm.buy(marketId, 0, amount, 0);
        
        // Sell all back
        uint256 collateralOut = cpmm.sell(marketId, 0, shares, 0);
        vm.stopPrank();

        // Due to fees (1.5% x 2) and slippage, expect ~80%+ recovery
        assertLt(collateralOut, amount);
        assertGt(collateralOut, (amount * 80) / 100);
    }
}

