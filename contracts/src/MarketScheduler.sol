// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BinaryMarketCPMM.sol";
import "./OracleRouter.sol";

/// @title MarketScheduler
/// @notice Single Chainlink Automation upkeep managing all market resolutions
/// @dev Implements custom logic upkeep with paged scan of pending markets
/// @dev Uses Ownable2Step for secure governance transfer (deployer → DAO)
contract MarketScheduler is AutomationCompatibleInterface, Ownable2Step {
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

    // Time-bucket storage: markets grouped by settlement day
    mapping(uint256 => bytes32[]) public marketsByDay;
    
    // Track which days have pending markets (for efficient iteration)
    uint256[] public activeDays;
    mapping(uint256 => bool) public isDayActive;
    
    // Current day cursor for round-robin scanning
    uint256 public dayCursor;

    // Track snapshot data per market
    mapping(bytes32 => SnapshotData) public snapshots;

    // Market metadata
    mapping(bytes32 => bytes32) public marketTemplates;
    
    // Track market status for cleanup
    mapping(bytes32 => bool) public isMarketResolved;

    // Automated cleanup configuration
    bool public autoCleanupEnabled;
    uint256 public cleanupMinAgeDays; // Minimum age before cleanup (default: 7 days)
    uint256 public cleanupBatchSize; // Max days to clean per upkeep (default: 3)
    uint256 public cleanupCursor; // Track position for round-robin cleanup

    // Events
    event MarketRegistered(bytes32 indexed marketId, uint64 settleTs, bytes32 templateId);
    event MarketRemoved(bytes32 indexed marketId);
    event SnapshotLocked(bytes32 indexed marketId, uint80 roundId, int256 price, uint256 timestamp);
    event MarketProcessed(bytes32 indexed marketId, uint8 outcome);
    event BatchProcessed(uint256 marketsProcessed, uint256 newCursor);
    event DayBucketCleaned(uint256 indexed dayBucket, uint256 marketsCleaned);
    event CleanupConfigUpdated(bool enabled, uint256 minAgeDays, uint256 batchSize);

    // Errors
    error MarketAlreadyRegistered();
    error InvalidTemplate();
    error InvalidParams();
    error SnapshotNotLocked();
    error OracleDataUnavailable();
    error Unauthorized();

    constructor(address _cpmm, address _oracleRouter, address initialOwner)
        Ownable(initialOwner)
    {
        cpmm = BinaryMarketCPMM(_cpmm);
        oracleRouter = OracleRouter(_oracleRouter);
        
        // Default cleanup configuration
        autoCleanupEnabled = true;
        cleanupMinAgeDays = 7;
        cleanupBatchSize = 3;
    }

    /// @notice Set the MarketFactory address (one-time setup)
    /// @param _marketFactory Address of the MarketFactory contract
    /// @dev Can only be called once, immediately after deployment
    function setMarketFactory(address _marketFactory) external {
        if (marketFactory != address(0)) revert Unauthorized();
        marketFactory = _marketFactory;
    }

    /// @notice Configure automated cleanup parameters
    /// @param enabled Whether automated cleanup is enabled
    /// @param minAgeDays Minimum age in days before a bucket can be cleaned
    /// @param batchSize Maximum number of day buckets to clean per upkeep
    /// @dev Only callable by owner. Use this to manage bandwidth/gas costs
    function setCleanupConfig(bool enabled, uint256 minAgeDays, uint256 batchSize) external onlyOwner {
        if (minAgeDays < 1) revert InvalidParams(); // At least 1 day
        if (batchSize == 0 || batchSize > 10) revert InvalidParams(); // 1-10 days per batch
        
        autoCleanupEnabled = enabled;
        cleanupMinAgeDays = minAgeDays;
        cleanupBatchSize = batchSize;
        
        emit CleanupConfigUpdated(enabled, minAgeDays, batchSize);
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
        
        // Calculate day bucket (markets grouped by settlement day)
        uint256 dayBucket = settleTs / 1 days;
        
        // Add market to day bucket
        marketsByDay[dayBucket].push(marketId);
        
        // Track this day as active if not already
        if (!isDayActive[dayBucket]) {
            isDayActive[dayBucket] = true;
            activeDays.push(dayBucket);
        }

        emit MarketRegistered(marketId, settleTs, templateId);
    }

    /// @notice Chainlink Automation calls this to check if upkeep is needed
    /// @param /* checkData */ Unused in this implementation
    /// @return upkeepNeeded True if there are markets due for processing or cleanup needed
    /// @return performData Encoded data: type (0=resolve, 1=cleanup) + relevant data
    function checkUpkeep(bytes calldata /* checkData */)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // Priority 1: Check for markets that need resolution
        bytes32[] memory dueMarkets = new bytes32[](MAX_BATCH);
        uint256 count = 0;
        
        if (activeDays.length > 0) {
            // Calculate current day and previous day buckets
            uint256 currentDay = block.timestamp / 1 days;
            uint256 lookbackDays = 2; // Check today and yesterday
            
            // Scan relevant day buckets (today and recent past)
            for (uint256 dayOffset = 0; dayOffset < lookbackDays && count < MAX_BATCH; dayOffset++) {
                if (currentDay < dayOffset) break; // Avoid underflow
                
                uint256 checkDay = currentDay - dayOffset;
                bytes32[] memory marketsInDay = marketsByDay[checkDay];
                
                // Scan markets in this day bucket
                for (uint256 i = 0; i < marketsInDay.length && count < MAX_BATCH; i++) {
                    bytes32 marketId = marketsInDay[i];
                    
                    if (marketId == bytes32(0)) continue; // Skip removed
                    if (isMarketResolved[marketId]) continue; // Skip resolved
                    
                    BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);
                    
                    // Skip if already processed
                    if (market.status != BinaryMarketCPMM.MarketStatus.Active && 
                        market.status != BinaryMarketCPMM.MarketStatus.Locked) {
                        continue;
                    }
                    
                    // Check if market is due (settleTs reached or passed)
                    if (market.settleTs <= block.timestamp + LOOKAHEAD_WINDOW) {
                        dueMarkets[count] = marketId;
                        count++;
                    }
                }
            }
        }

        // If we found markets to resolve, return them (priority 1)
        if (count > 0) {
            bytes32[] memory trimmedMarkets = new bytes32[](count);
            for (uint256 i = 0; i < count; i++) {
                trimmedMarkets[i] = dueMarkets[i];
            }
            // Type 0 = resolution
            return (true, abi.encode(uint8(0), trimmedMarkets));
        }

        // Priority 2: Check if cleanup is needed (only if no resolutions pending)
        if (autoCleanupEnabled && activeDays.length > 0) {
            uint256 currentDay = block.timestamp / 1 days;
            uint256[] memory daysToClean = new uint256[](cleanupBatchSize);
            uint256 cleanupCount = 0;
            
            // Scan activeDays array starting from cleanupCursor
            for (uint256 i = 0; i < activeDays.length && cleanupCount < cleanupBatchSize; i++) {
                uint256 index = (cleanupCursor + i) % activeDays.length;
                uint256 dayBucket = activeDays[index];
                
                // Check if day is old enough and still active
                if (isDayActive[dayBucket] && dayBucket + cleanupMinAgeDays < currentDay) {
                    // Check if all markets in this day are resolved
                    bytes32[] memory marketsInDay = marketsByDay[dayBucket];
                    bool allResolved = true;
                    
                    for (uint256 j = 0; j < marketsInDay.length; j++) {
                        bytes32 marketId = marketsInDay[j];
                        if (marketId != bytes32(0) && !isMarketResolved[marketId]) {
                            allResolved = false;
                            break;
                        }
                    }
                    
                    if (allResolved && marketsInDay.length > 0) {
                        daysToClean[cleanupCount] = dayBucket;
                        cleanupCount++;
                    }
                }
            }
            
            if (cleanupCount > 0) {
                // Trim array
                uint256[] memory trimmedDays = new uint256[](cleanupCount);
                for (uint256 i = 0; i < cleanupCount; i++) {
                    trimmedDays[i] = daysToClean[i];
                }
                // Type 1 = cleanup
                return (true, abi.encode(uint8(1), trimmedDays));
            }
        }

        return (false, "");
    }

    /// @notice Chainlink Automation calls this to perform upkeep
    /// @param performData Encoded data: type (0=resolve, 1=cleanup) + relevant data
    function performUpkeep(bytes calldata performData) external override {
        // Decode type byte
        uint8 upkeepType;
        
        // Try to decode as new format (with type byte)
        if (performData.length > 0) {
            upkeepType = abi.decode(performData, (uint8));
        }
        
        if (upkeepType == 0) {
            // Resolution upkeep
            (, bytes32[] memory marketIds) = abi.decode(performData, (uint8, bytes32[]));
            _performResolution(marketIds);
        } else if (upkeepType == 1) {
            // Cleanup upkeep
            (, uint256[] memory daysToClean) = abi.decode(performData, (uint8, uint256[]));
            _performCleanup(daysToClean);
        }
    }

    /// @dev Perform market resolution
    function _performResolution(bytes32[] memory marketIds) private {
        uint256 processed = 0;

        for (uint256 i = 0; i < marketIds.length && i < MAX_BATCH; i++) {
            bytes32 marketId = marketIds[i];
            if (marketId == bytes32(0)) continue;
            if (isMarketResolved[marketId]) continue;

            BinaryMarketCPMM.Market memory market = cpmm.getMarket(marketId);

            // Skip if market not active/locked or not due yet
            if (market.status != BinaryMarketCPMM.MarketStatus.Active && 
                market.status != BinaryMarketCPMM.MarketStatus.Locked) {
                isMarketResolved[marketId] = true;
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
                    isMarketResolved[marketId] = true;
                    processed++;
                }
            }
        }

        emit BatchProcessed(processed, dayCursor);
    }

    /// @dev Perform cleanup of old day buckets
    function _performCleanup(uint256[] memory daysToClean) private {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 totalCleaned = 0;

        for (uint256 i = 0; i < daysToClean.length && i < cleanupBatchSize; i++) {
            uint256 dayBucket = daysToClean[i];
            
            // Safety checks
            if (!isDayActive[dayBucket]) continue;
            if (dayBucket + cleanupMinAgeDays >= currentDay) continue;
            
            bytes32[] storage marketsInDay = marketsByDay[dayBucket];
            
            // Verify all markets are resolved
            bool canClean = true;
            for (uint256 j = 0; j < marketsInDay.length; j++) {
                bytes32 marketId = marketsInDay[j];
                if (marketId != bytes32(0) && !isMarketResolved[marketId]) {
                    canClean = false;
                    break;
                }
            }
            
            if (canClean && marketsInDay.length > 0) {
                uint256 marketCount = marketsInDay.length;
                
                // Delete the day bucket
                delete marketsByDay[dayBucket];
                isDayActive[dayBucket] = false;
                
                totalCleaned += marketCount;
                emit DayBucketCleaned(dayBucket, marketCount);
            }
        }
        
        // Advance cleanup cursor for next round
        if (activeDays.length > 0) {
            cleanupCursor = (cleanupCursor + cleanupBatchSize) % activeDays.length;
        }
        
        emit BatchProcessed(totalCleaned, cleanupCursor);
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


    /// @notice Get snapshot data for a market
    /// @param marketId The market to query
    /// @return snapshot The snapshot data
    function getSnapshot(bytes32 marketId) external view returns (SnapshotData memory snapshot) {
        return snapshots[marketId];
    }

    /// @notice Get number of pending markets across all day buckets
    /// @return count The number of unresolved markets
    function getPendingCount() external view returns (uint256 count) {
        uint256 totalCount = 0;
        
        // Scan recent day buckets (last 7 days)
        uint256 currentDay = block.timestamp / 1 days;
        uint256 lookbackDays = 7;
        
        for (uint256 dayOffset = 0; dayOffset < lookbackDays; dayOffset++) {
            if (currentDay < dayOffset) break;
            
            uint256 checkDay = currentDay - dayOffset;
            bytes32[] memory marketsInDay = marketsByDay[checkDay];
            
            for (uint256 i = 0; i < marketsInDay.length; i++) {
                bytes32 marketId = marketsInDay[i];
                if (marketId != bytes32(0) && !isMarketResolved[marketId]) {
                    totalCount++;
                }
            }
        }
        
        return totalCount;
    }

    /// @notice Get pending markets for a specific day
    /// @param dayTimestamp Any timestamp within the day to query
    /// @return markets Array of market IDs for that day
    function getPendingMarketsForDay(uint256 dayTimestamp) external view returns (bytes32[] memory markets) {
        uint256 dayBucket = dayTimestamp / 1 days;
        bytes32[] memory allMarkets = marketsByDay[dayBucket];
        
        // Count unresolved markets
        uint256 unresolvedCount = 0;
        for (uint256 i = 0; i < allMarkets.length; i++) {
            if (allMarkets[i] != bytes32(0) && !isMarketResolved[allMarkets[i]]) {
                unresolvedCount++;
            }
        }
        
        // Build result array
        markets = new bytes32[](unresolvedCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allMarkets.length; i++) {
            if (allMarkets[i] != bytes32(0) && !isMarketResolved[allMarkets[i]]) {
                markets[index] = allMarkets[i];
                index++;
            }
        }
        
        return markets;
    }

    /// @notice Get all active day buckets
    /// @return dayBuckets Array of day bucket numbers with registered markets
    function getActiveDays() external view returns (uint256[] memory dayBuckets) {
        return activeDays;
    }
    
    /// @notice Get total number of markets in a day bucket (resolved + unresolved)
    /// @param dayTimestamp Any timestamp within the day to query
    /// @return count Number of markets in that day bucket
    function getMarketCountForDay(uint256 dayTimestamp) external view returns (uint256 count) {
        uint256 dayBucket = dayTimestamp / 1 days;
        return marketsByDay[dayBucket].length;
    }

    /// @notice Clean up old day buckets to save gas (optional maintenance)
    /// @param dayTimestamp The day bucket to clean up (must be >7 days old)
    /// @dev Can be called by anyone to help maintain the contract
    /// @dev Only cleans up days where all markets are resolved
    function cleanupOldDay(uint256 dayTimestamp) external {
        uint256 dayBucket = dayTimestamp / 1 days;
        uint256 currentDay = block.timestamp / 1 days;
        
        // Only allow cleanup of day buckets older than 7 days
        require(dayBucket + 7 < currentDay, "Day too recent");
        
        bytes32[] storage marketsInDay = marketsByDay[dayBucket];
        
        // Check if all markets in this day are resolved
        for (uint256 i = 0; i < marketsInDay.length; i++) {
            bytes32 marketId = marketsInDay[i];
            if (marketId != bytes32(0) && !isMarketResolved[marketId]) {
                revert("Day has unresolved markets");
            }
        }
        
        // Delete the day bucket
        delete marketsByDay[dayBucket];
        isDayActive[dayBucket] = false;
        
        emit MarketRemoved(bytes32(uint256(dayBucket))); // Use dayBucket as event ID
    }
}

