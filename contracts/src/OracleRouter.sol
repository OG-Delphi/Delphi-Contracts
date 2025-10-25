// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title OracleRouter
/// @notice Helper contract for querying Chainlink price feeds and finding historical rounds
/// @dev Implements binary search to find "latest round ≤ timestamp"
contract OracleRouter {
    error InvalidFeed();
    error InvalidTimestamp();
    error RoundNotFound();
    error StaleData();

    uint256 private constant MAX_STALENESS = 4 hours;

    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
    }

    /// @notice Get the latest round data from a Chainlink feed
    /// @param feed The Chainlink price feed address
    /// @return data The latest round data
    function getLatestRound(address feed) public view returns (RoundData memory data) {
        if (feed == address(0)) revert InvalidFeed();

        AggregatorV3Interface aggregator = AggregatorV3Interface(feed);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt,) = aggregator.latestRoundData();

        // Check for stale data
        if (updatedAt == 0 || updatedAt > block.timestamp) revert StaleData();
        if (block.timestamp - updatedAt > MAX_STALENESS) revert StaleData();
        if (answer <= 0) revert StaleData();

        data = RoundData({
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt
        });
    }

    /// @notice Find the latest round at or before a specific timestamp
    /// @param feed The Chainlink price feed address
    /// @param targetTimestamp The target timestamp to search for
    /// @return data The round data at or before the timestamp
    function getRoundAtOrBefore(address feed, uint256 targetTimestamp) external view returns (RoundData memory data) {
        if (feed == address(0)) revert InvalidFeed();
        if (targetTimestamp == 0 || targetTimestamp > block.timestamp) revert InvalidTimestamp();

        AggregatorV3Interface aggregator = AggregatorV3Interface(feed);

        // Get latest round first
        (uint80 latestRoundId,,,uint256 latestUpdatedAt,) = aggregator.latestRoundData();

        // If latest round is before target, return it
        if (latestUpdatedAt <= targetTimestamp) {
            return _getRoundData(aggregator, latestRoundId);
        }

        // Binary search for the right round
        // Note: This is simplified - in production you'd need more robust search
        // Chainlink rounds can have gaps, so we walk backwards from latest
        uint80 searchRoundId = latestRoundId;
        uint256 maxIterations = 500; // Prevent infinite loops

        for (uint256 i = 0; i < maxIterations; i++) {
            try aggregator.getRoundData(searchRoundId) returns (
                uint80 roundId,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 /* answeredInRound */
            ) {
                // Found a round at or before target
                if (updatedAt <= targetTimestamp && updatedAt > 0 && answer > 0) {
                    return RoundData({
                        roundId: roundId,
                        answer: answer,
                        startedAt: startedAt,
                        updatedAt: updatedAt
                    });
                }

                // Keep going back
                if (searchRoundId == 0) break;
                searchRoundId--;
            } catch {
                // Skip missing rounds
                if (searchRoundId == 0) break;
                searchRoundId--;
            }
        }

        revert RoundNotFound();
    }

    /// @notice Get data for a specific round ID
    /// @param feed The Chainlink price feed address
    /// @param roundId The round ID to query
    /// @return data The round data
    function getRoundData(address feed, uint80 roundId) external view returns (RoundData memory data) {
        if (feed == address(0)) revert InvalidFeed();
        AggregatorV3Interface aggregator = AggregatorV3Interface(feed);
        return _getRoundData(aggregator, roundId);
    }

    /// @notice Get decimals for a price feed
    /// @param feed The Chainlink price feed address
    /// @return The number of decimals
    function getDecimals(address feed) external view returns (uint8) {
        if (feed == address(0)) revert InvalidFeed();
        return AggregatorV3Interface(feed).decimals();
    }

    /// @notice Get description for a price feed
    /// @param feed The Chainlink price feed address
    /// @return The feed description
    function getDescription(address feed) external view returns (string memory) {
        if (feed == address(0)) revert InvalidFeed();
        return AggregatorV3Interface(feed).description();
    }

    /// @dev Internal helper to get round data
    function _getRoundData(AggregatorV3Interface aggregator, uint80 roundId)
        private
        view
        returns (RoundData memory data)
    {
        (uint80 rId, int256 answer, uint256 startedAt, uint256 updatedAt,) = aggregator.getRoundData(roundId);

        if (updatedAt == 0 || answer <= 0) revert StaleData();

        data = RoundData({
            roundId: rId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt
        });
    }
}

