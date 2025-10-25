// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title MockChainlinkFeed
/// @notice Mock Chainlink price feed for testing
contract MockChainlinkFeed is AggregatorV3Interface {
    uint8 public decimals;
    string public description;
    uint256 public version = 1;

    struct RoundData {
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    mapping(uint80 => RoundData) private rounds;
    uint80 public latestRound;

    constructor(uint8 _decimals, string memory _description) {
        decimals = _decimals;
        description = _description;
    }

    function setRoundData(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt) external {
        rounds[roundId] = RoundData({
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: roundId
        });

        if (roundId > latestRound) {
            latestRound = roundId;
        }
    }

    function setLatestRoundData(int256 answer, uint256 startedAt, uint256 updatedAt) external {
        latestRound++;
        rounds[latestRound] = RoundData({
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: latestRound
        });
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory round = rounds[_roundId];
        require(round.updatedAt > 0, "No data present");
        return (_roundId, round.answer, round.startedAt, round.updatedAt, round.answeredInRound);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory round = rounds[latestRound];
        require(round.updatedAt > 0, "No data present");
        return (latestRound, round.answer, round.startedAt, round.updatedAt, round.answeredInRound);
    }
}

