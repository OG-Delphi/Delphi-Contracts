// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/OracleRouter.sol";
import "./mocks/MockChainlinkFeed.sol";

contract OracleRouterTest is Test {
    OracleRouter public router;
    MockChainlinkFeed public feed;

    function setUp() public {
        // Warp to a reasonable timestamp to avoid underflow issues
        vm.warp(1700000000); // Nov 2023
        
        router = new OracleRouter();
        feed = new MockChainlinkFeed(8, "BTC/USD");
    }

    function test_GetLatestRound() public {
        uint256 timestamp = block.timestamp;
        feed.setLatestRoundData(70000e8, timestamp, timestamp);

        OracleRouter.RoundData memory data = router.getLatestRound(address(feed));

        assertEq(data.roundId, 1);
        assertEq(data.answer, 70000e8);
        assertEq(data.updatedAt, timestamp);
    }

    function test_GetLatestRoundRevertsOnZeroAddress() public {
        vm.expectRevert(OracleRouter.InvalidFeed.selector);
        router.getLatestRound(address(0));
    }

    function test_GetLatestRoundRevertsOnStaleData() public {
        // Set data 5 hours old (MAX_STALENESS is 4 hours)
        uint256 oldTimestamp = block.timestamp - 5 hours;
        feed.setLatestRoundData(70000e8, oldTimestamp, oldTimestamp);

        vm.expectRevert(OracleRouter.StaleData.selector);
        router.getLatestRound(address(feed));
    }

    function test_GetLatestRoundRevertsOnNegativePrice() public {
        feed.setLatestRoundData(-100, block.timestamp, block.timestamp);

        vm.expectRevert(OracleRouter.StaleData.selector);
        router.getLatestRound(address(feed));
    }

    function test_GetLatestRoundRevertsOnZeroUpdatedAt() public {
        // The mock will revert with "No data present" since updatedAt is 0
        // and the mock checks this before returning data
        feed.setRoundData(1, 70000e8, block.timestamp, 0);
        
        vm.expectRevert("No data present");
        router.getLatestRound(address(feed));
    }

    function test_GetRoundAtOrBefore_ExactMatch() public {
        uint256 targetTime = block.timestamp - 1 hours;

        // Set a round exactly at target time
        feed.setRoundData(1, 70000e8, targetTime, targetTime);

        OracleRouter.RoundData memory data = router.getRoundAtOrBefore(address(feed), targetTime);

        assertEq(data.roundId, 1);
        assertEq(data.answer, 70000e8);
        assertEq(data.updatedAt, targetTime);
    }

    function test_GetRoundAtOrBefore_BeforeTarget() public {
        uint256 targetTime = block.timestamp;
        uint256 roundTime = targetTime - 1 hours;

        // Round is 1 hour before target
        feed.setRoundData(1, 70000e8, roundTime, roundTime);

        OracleRouter.RoundData memory data = router.getRoundAtOrBefore(address(feed), targetTime);

        assertEq(data.roundId, 1);
        assertEq(data.updatedAt, roundTime);
    }

    function test_GetRoundAtOrBefore_MultipleRounds() public {
        uint256 currentTime = block.timestamp;

        // Set up multiple rounds
        feed.setRoundData(1, 68000e8, currentTime - 3 hours, currentTime - 3 hours);
        feed.setRoundData(2, 69000e8, currentTime - 2 hours, currentTime - 2 hours);
        feed.setRoundData(3, 70000e8, currentTime - 1 hours, currentTime - 1 hours);
        feed.setRoundData(4, 71000e8, currentTime, currentTime);

        // Query for time between round 2 and 3
        uint256 targetTime = currentTime - 90 minutes;
        OracleRouter.RoundData memory data = router.getRoundAtOrBefore(address(feed), targetTime);

        // Should return round 2 (last one <= target)
        assertEq(data.roundId, 2);
        assertEq(data.answer, 69000e8);
    }

    function test_GetRoundAtOrBefore_LatestRoundIsBeforeTarget() public {
        uint256 currentTime = block.timestamp;
        uint256 targetTime = currentTime; // Target is current time

        // Latest round is before target (1 hour ago)
        feed.setLatestRoundData(70000e8, currentTime - 1 hours, currentTime - 1 hours);

        OracleRouter.RoundData memory data = router.getRoundAtOrBefore(address(feed), targetTime);

        // Should return latest round since it's before target
        assertEq(data.roundId, 1);
        assertEq(data.answer, 70000e8);
    }

    function test_GetRoundAtOrBefore_RevertsOnZeroAddress() public {
        vm.expectRevert(OracleRouter.InvalidFeed.selector);
        router.getRoundAtOrBefore(address(0), block.timestamp);
    }

    function test_GetRoundAtOrBefore_RevertsOnFutureTimestamp() public {
        uint256 futureTime = block.timestamp + 1 days;

        vm.expectRevert(OracleRouter.InvalidTimestamp.selector);
        router.getRoundAtOrBefore(address(feed), futureTime);
    }

    function test_GetRoundAtOrBefore_RevertsOnZeroTimestamp() public {
        vm.expectRevert(OracleRouter.InvalidTimestamp.selector);
        router.getRoundAtOrBefore(address(feed), 0);
    }

    function test_GetRoundAtOrBefore_HandlesGaps() public {
        uint256 currentTime = block.timestamp;

        // Set rounds with gaps (round 2 missing)
        feed.setRoundData(1, 68000e8, currentTime - 3 hours, currentTime - 3 hours);
        // Round 2 is missing
        feed.setRoundData(3, 70000e8, currentTime - 1 hours, currentTime - 1 hours);

        // Query for time where round 2 would have been
        uint256 targetTime = currentTime - 2 hours;
        OracleRouter.RoundData memory data = router.getRoundAtOrBefore(address(feed), targetTime);

        // Should return round 1 (skips missing round 2)
        assertEq(data.roundId, 1);
        assertEq(data.answer, 68000e8);
    }

    function test_GetRoundData() public {
        uint256 timestamp = block.timestamp - 1 hours;
        feed.setRoundData(5, 70000e8, timestamp, timestamp);

        OracleRouter.RoundData memory data = router.getRoundData(address(feed), 5);

        assertEq(data.roundId, 5);
        assertEq(data.answer, 70000e8);
        assertEq(data.updatedAt, timestamp);
    }

    function test_GetDecimals() public view {
        uint8 decimals = router.getDecimals(address(feed));
        assertEq(decimals, 8);
    }

    function test_GetDescription() public view {
        string memory desc = router.getDescription(address(feed));
        assertEq(desc, "BTC/USD");
    }

    function test_PriceMovement_RealisticScenario() public {
        uint256 currentTime = block.timestamp;

        // Simulate BTC price movement over a day
        feed.setRoundData(1, 68000e8, currentTime - 24 hours, currentTime - 24 hours);  // $68,000
        feed.setRoundData(2, 68500e8, currentTime - 18 hours, currentTime - 18 hours);  // $68,500
        feed.setRoundData(3, 69000e8, currentTime - 12 hours, currentTime - 12 hours);  // $69,000
        feed.setRoundData(4, 70000e8, currentTime - 6 hours, currentTime - 6 hours);    // $70,000
        feed.setRoundData(5, 70500e8, currentTime, currentTime);                        // $70,500

        // Market question: "Will BTC be >= $69,500 at noon?"
        uint256 settlementTime = currentTime - 12 hours;
        OracleRouter.RoundData memory data = router.getRoundAtOrBefore(address(feed), settlementTime);

        // At 12 hours ago, price was $69,000 (round 3)
        assertEq(data.answer, 69000e8);

        // So "BTC >= $69,500" would be NO
        assertTrue(data.answer < 69500e8);
    }

    function testFuzz_GetLatestRound_ValidPrice(int256 price) public {
        // Bound to positive prices
        vm.assume(price > 0 && price < type(int256).max / 2);

        feed.setLatestRoundData(price, block.timestamp - 1 hours, block.timestamp);

        OracleRouter.RoundData memory data = router.getLatestRound(address(feed));

        assertEq(data.answer, price);
        assertGt(data.updatedAt, 0);
    }

    function testFuzz_GetRoundAtOrBefore(uint256 targetTimeOffset) public {
        // Bound offset to reasonable range (1 hour to 30 days ago)
        targetTimeOffset = bound(targetTimeOffset, 1 hours, 30 days);

        uint256 targetTime = block.timestamp - targetTimeOffset;
        uint256 roundTime = targetTime - 1 hours; // Round is 1 hour before target

        feed.setRoundData(1, 70000e8, roundTime, roundTime);

        OracleRouter.RoundData memory data = router.getRoundAtOrBefore(address(feed), targetTime);

        assertEq(data.roundId, 1);
        assertLe(data.updatedAt, targetTime);
    }
}

