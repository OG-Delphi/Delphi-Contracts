// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import "./BinaryMarketCPMM.sol";
import "./OracleRouter.sol";

/// @title MarketScheduler
/// @notice Single Chainlink Automation upkeep managing all market resolutions
/// @dev Implements custom logic upkeep with paged scan of pending markets
contract MarketScheduler is AutomationCompatibleInterface {
    // Template types
    bytes32 public constant PRICE_ABOVE_AT_TIME = keccak256("PRICE_ABOVE_AT_TIME");

    // Maximum markets to process per performUpkeep call
    uint256 public constant MAX_BATCH = 10;

    // Maximum time to look ahead for due markets (1 hour)
    uint256 private constant LOOKAHEAD_WINDOW = 1 hours;

    struct PendingMarket {
        bytes32 marketId;
        uint64 settleTs;
        bool exists;
    }

    struct SnapshotData {
        bool locked;
        uint80 roundId;
        int256 price;
        uint256 timestamp;
    }

    BinaryMarketCPMM public immutable cpmm;
    OracleRouter public immutable oracleRouter;
    address public marketFactory; // Only this address can register markets

    // Pending markets storage (simple array + cursor)
    bytes32[] public pendingMarketIds;
    uint256 public cursor;

    // Track snapshot data per market
    mapping(bytes32 => SnapshotData) public snapshots;

    // Market metadata
    mapping(bytes32 => bytes32) public marketTemplates;

    // Events
    event MarketRegistered(bytes32 indexed marketId, uint64 settleTs, bytes32 templateId);
    event MarketRemoved(bytes32 indexed marketId);
    event SnapshotLocked(bytes32 indexed marketId, uint80 roundId, int256 price, uint256 timestamp);
    event MarketProcessed(bytes32 indexed marketId, uint8 outcome);
    event BatchProcessed(uint256 marketsProcessed, uint256 newCursor);

    // Errors
    error MarketAlreadyRegistered();
    error InvalidTemplate();
    error InvalidParams();
    error SnapshotNotLocked();
    error OracleDataUnavailable();
    error Unauthorized();

    constructor(address _cpmm, address _oracleRouter) {
        cpmm = BinaryMarketCPMM(_cpmm);
        oracleRouter = OracleRouter(_oracleRouter);
    }

    /// @notice Set the MarketFactory address (one-time setup)
    /// @param _marketFactory Address of the MarketFactory contract
    /// @dev Can only be called once, immediately after deployment
    function setMarketFactory(address _marketFactory) external {
        if (marketFactory != address(0)) revert Unauthorized();
        marketFactory = _marketFactory;
    }

    /// @notice Register a new market for automated resolution
    /// @param marketId Unique identifier for the market
    /// @param settleTs Timestamp when market should settle
    /// @param templateId Template type
    /// @dev Only callable by MarketFactory
    function registerMarket(bytes32 marketId, uint64 settleTs, bytes32 templateId) external {
        if (msg.sender != marketFactory) revert Unauthorized();
        if (marketTemplates[marketId] != bytes32(0)) revert MarketAlreadyRegistered();
        if (templateId != PRICE_ABOVE_AT_TIME) revert InvalidTemplate();

        marketTemplates[marketId] = templateId;
        pendingMarketIds.push(marketId);

        emit MarketRegistered(marketId, settleTs, templateId);
    }

    /// @notice Chainlink Automation calls this to check if upkeep is needed
    /// @param /* checkData */ Unused in this implementation
    /// @return upkeepNeeded True if there are markets due for processing
    /// @return performData Encoded array of market IDs to process
    function checkUpkeep(bytes calldata /* checkData */)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        bytes32[] memory dueMarkets = new bytes32[](MAX_BATCH);
        uint256 count = 0;
        uint256 currentCursor = cursor;
        uint256 totalPending = pendingMarketIds.length;

        if (totalPending == 0) {
            return (false, "");
        }

        // Scan from cursor, wrapping around
        for (uint256 i = 0; i < totalPending && count < MAX_BATCH; i++) {
            uint256 index = (currentCursor + i) % totalPending;
            bytes32 marketId = pendingMarketIds[index];

            if (marketId == bytes32(0)) continue; // Skip removed markets

            BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);

            // Check if market is due (settleTs reached or passed)
            if (market.settleTs <= block.timestamp + LOOKAHEAD_WINDOW) {
                dueMarkets[count] = marketId;
                count++;
            }
        }

        if (count > 0) {
            // Trim array to actual count
            bytes32[] memory trimmedMarkets = new bytes32[](count);
            for (uint256 i = 0; i < count; i++) {
                trimmedMarkets[i] = dueMarkets[i];
            }
            return (true, abi.encode(trimmedMarkets));
        }

        return (false, "");
    }

    /// @notice Chainlink Automation calls this to perform upkeep
    /// @param performData Encoded array of market IDs to process
    function performUpkeep(bytes calldata performData) external override {
        bytes32[] memory marketIds = abi.decode(performData, (bytes32[]));

        uint256 processed = 0;

        for (uint256 i = 0; i < marketIds.length && i < MAX_BATCH; i++) {
            bytes32 marketId = marketIds[i];
            if (marketId == bytes32(0)) continue;

            BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);

            // Skip if market not active or not due yet
            if (market.status != BinaryMarketCPMM.MarketStatus.Active) {
                _removeFromPending(marketId);
                continue;
            }

            if (market.settleTs > block.timestamp) {
                continue; // Not due yet
            }

            bytes32 templateId = marketTemplates[marketId];

            // Two-phase process: lock snapshot → resolve
            if (!snapshots[marketId].locked) {
                // Phase 1: Lock snapshot
                bool locked = _lockSnapshot(marketId, market, templateId);
                if (locked) processed++;
            } else {
                // Phase 2: Resolve market
                bool resolved = _resolveMarket(marketId, market, templateId);
                if (resolved) {
                    _removeFromPending(marketId);
                    processed++;
                }
            }
        }

        // Advance cursor
        cursor = (cursor + MAX_BATCH) % (pendingMarketIds.length > 0 ? pendingMarketIds.length : 1);

        emit BatchProcessed(processed, cursor);
    }

    /// @dev Lock price snapshot for a market
    function _lockSnapshot(bytes32 marketId, BinaryMarketCPMM.Market memory market, bytes32 templateId)
        private
        returns (bool success)
    {
        if (templateId == PRICE_ABOVE_AT_TIME) {
            // Decode params: (feedAddress, strikePrice)
            bytes memory params = cpmm.getMarketParams(marketId);
            (address feed,) = abi.decode(params, (address, int256));

            try oracleRouter.getRoundAtOrBefore(feed, market.settleTs) returns (
                OracleRouter.RoundData memory roundData
            ) {
                // Store snapshot
                snapshots[marketId] = SnapshotData({
                    locked: true,
                    roundId: roundData.roundId,
                    price: roundData.answer,
                    timestamp: roundData.updatedAt
                });

                // Lock market in CPMM
                cpmm.lockMarket(marketId);

                emit SnapshotLocked(marketId, roundData.roundId, roundData.answer, roundData.updatedAt);
                return true;
            } catch {
                // Oracle data not available yet, will retry next call
                return false;
            }
        }

        return false;
    }

    /// @dev Resolve market using locked snapshot
    function _resolveMarket(bytes32 marketId, BinaryMarketCPMM.Market memory market, bytes32 templateId)
        private
        returns (bool success)
    {
        SnapshotData memory snapshot = snapshots[marketId];
        if (!snapshot.locked) revert SnapshotNotLocked();

        if (templateId == PRICE_ABOVE_AT_TIME) {
            // Decode params: (feedAddress, strikePrice)
            bytes memory params = cpmm.getMarketParams(marketId);
            (, int256 strikePrice) = abi.decode(params, (address, int256));

            // Determine outcome: price >= strike → YES (0), else NO (1)
            uint8 outcome = (snapshot.price >= strikePrice) ? 0 : 1;

            // Resolve in CPMM
            cpmm.resolveMarket(marketId, outcome);

            emit MarketProcessed(marketId, outcome);
            return true;
        }

        return false;
    }

    /// @dev Remove market from pending list
    function _removeFromPending(bytes32 marketId) private {
        for (uint256 i = 0; i < pendingMarketIds.length; i++) {
            if (pendingMarketIds[i] == marketId) {
                // Set to zero instead of removing to avoid array reorg
                pendingMarketIds[i] = bytes32(0);
                emit MarketRemoved(marketId);
                break;
            }
        }
    }

    /// @notice Get snapshot data for a market
    /// @param marketId The market to query
    /// @return snapshot The snapshot data
    function getSnapshot(bytes32 marketId) external view returns (SnapshotData memory snapshot) {
        return snapshots[marketId];
    }

    /// @notice Get number of pending markets
    /// @return count The number of pending markets
    function getPendingCount() external view returns (uint256 count) {
        uint256 totalCount = 0;
        for (uint256 i = 0; i < pendingMarketIds.length; i++) {
            if (pendingMarketIds[i] != bytes32(0)) {
                totalCount++;
            }
        }
        return totalCount;
    }

    /// @notice Get all pending market IDs
    /// @return markets Array of pending market IDs (may include zeros for removed markets)
    function getPendingMarkets() external view returns (bytes32[] memory markets) {
        return pendingMarketIds;
    }
}

