#!/bin/bash
# check_market.sh - Get info and links for any Delphi prediction market
# Usage: ./check_market.sh [MARKET_ID]
#        If no MARKET_ID provided, uses environment variable MARKET_ID

set -e

# Configuration - Update these for different networks
NETWORK="Base Sepolia"
CHAIN_ID="84532"
CPMM_ADDRESS="0x840Ab73b0950959d9b12c890B228EA30E7cbb653"
OUTCOME_TOKEN_ADDRESS="0x71F863f93bccb2db3D1F01FC2480e5066150DB0e"
ORACLE_ROUTER_ADDRESS="0xD17a88AAecCB84D0072B6227973Ac43C20f9De03"
BASESCAN_URL="https://sepolia.basescan.org"
CHAINLINK_AUTOMATION_URL="https://automation.chain.link"

# Get market ID from argument or environment
if [ -n "$1" ]; then
    MARKET_ID="$1"
elif [ -n "$MARKET_ID" ]; then
    MARKET_ID="$MARKET_ID"
else
    echo ""
    echo "❌ Error: No market ID provided"
    echo ""
    echo "Usage:"
    echo "  ./check_market.sh <MARKET_ID>"
    echo "  OR"
    echo "  export MARKET_ID=<market_id> && ./check_market.sh"
    echo ""
    echo "Example:"
    echo "  ./check_market.sh 0x1ad47bbfd7825699f4e2337b9243a1a02d6830e3295a78006006dc24ad47af8a"
    echo ""
    exit 1
fi

# Validate market ID format
if [[ ! "$MARKET_ID" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo ""
    echo "❌ Error: Invalid market ID format"
    echo ""
    echo "Market ID must be a 32-byte hex string starting with 0x"
    echo "Example: 0x1ad47bbfd7825699f4e2337b9243a1a02d6830e3295a78006006dc24ad47af8a"
    echo ""
    exit 1
fi

echo ""
echo "============================================================"
echo "🔍 DELPHI MARKET INFO"
echo "============================================================"
echo ""
echo "📋 Market ID: $MARKET_ID"
echo "🔗 Network: $NETWORK (Chain ID: $CHAIN_ID)"
echo "⏰ Checked: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "------------------------------------------------------------"
echo "📡 Querying on-chain data..."
echo ""

# Load RPC URL from environment
if [ -f .env ]; then
    source .env
elif [ -f ../.env ]; then
    source ../.env
fi

if [ -z "$BASE_SEPOLIA_RPC_URL" ]; then
    echo "⚠️  Warning: BASE_SEPOLIA_RPC_URL not set"
    echo "   Set it in .env to query live data"
    echo ""
fi

# Check if cast is available
CAST_AVAILABLE=false
if command -v cast &> /dev/null; then
    CAST_AVAILABLE=true
fi

# Get YES price (10000 basis points = 100%)
YES_PRICE=""
QUERY_ERROR=false

if [ "$CAST_AVAILABLE" = true ] && [ -n "$BASE_SEPOLIA_RPC_URL" ]; then
    sleep 0.5  # Small delay to be nice to RPC
    YES_PRICE_HEX=$(cast call $CPMM_ADDRESS "getYesPrice(bytes32)" $MARKET_ID --rpc-url $BASE_SEPOLIA_RPC_URL 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$YES_PRICE_HEX" ]; then
        YES_PRICE=$((16#${YES_PRICE_HEX:2}))
    else
        QUERY_ERROR=true
    fi
fi

# Get market data
MARKET_EXISTS=false
MARKET_STATUS=""
YES_RESERVE=""
NO_RESERVE=""
TOTAL_VOLUME=""
SETTLE_TS=""
CREATED_AT=""

if [ "$CAST_AVAILABLE" = true ] && [ -n "$BASE_SEPOLIA_RPC_URL" ] && [ "$QUERY_ERROR" = false ]; then
    sleep 0.5  # Small delay between calls
    MARKET_DATA=$(cast call $CPMM_ADDRESS "getMarket(bytes32)" $MARKET_ID --rpc-url $BASE_SEPOLIA_RPC_URL 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$MARKET_DATA" ]; then
        MARKET_EXISTS=true
        
        # Remove 0x prefix for easier parsing
        DATA="${MARKET_DATA:2}"
        
        # Each field is 64 hex chars (32 bytes)
        # Field 0 (0-63):   marketId
        # Field 1 (64-127): templateId
        # Field 2 (128-191): creator address (20 bytes, right-padded)
        # Field 3 (192-255): settleTs (uint64, right-padded to 32 bytes)
        # Field 4 (256-319): createdAt (uint64, right-padded to 32 bytes)
        # Field 5 (320-383): feeBps (uint16)
        # Field 6 (384-447): creatorFeeBps (uint16)
        # Field 7 (448-511): status (uint8)
        # Field 8 (512-575): winningOutcome (uint8)
        # Field 9 (576-639): yesReserve (uint128)
        # Field 10 (640-703): noReserve (uint128)
        # Field 11 (704-767): totalVolume (uint256)
        
        # Parse settleTs (field 3, last 8 bytes = 16 hex chars)
        SETTLE_HEX=${DATA:240:16}
        if [ ! -z "$SETTLE_HEX" ]; then
            SETTLE_TS=$((16#$SETTLE_HEX))
        fi
        
        # Parse createdAt (field 4, last 8 bytes = 16 hex chars)
        CREATED_HEX=${DATA:304:16}
        if [ ! -z "$CREATED_HEX" ]; then
            CREATED_AT=$((16#$CREATED_HEX))
        fi
        
        # Parse market status (field 7, last byte)
        STATUS_HEX=${DATA:510:2}
        if [ ! -z "$STATUS_HEX" ]; then
            MARKET_STATUS=$((16#$STATUS_HEX))
        fi
        
        # Parse YES reserve (field 9, uint128 = 32 hex chars)
        YES_HEX=${DATA:608:32}
        if [ ! -z "$YES_HEX" ]; then
            YES_RESERVE=$((16#$YES_HEX))
        fi
        
        # Parse NO reserve (field 10, uint128 = 32 hex chars)
        NO_HEX=${DATA:672:32}
        if [ ! -z "$NO_HEX" ]; then
            NO_RESERVE=$((16#$NO_HEX))
        fi
        
        # Parse total volume (field 11, uint256 = 64 hex chars)
        VOL_HEX=${DATA:704:64}
        if [ ! -z "$VOL_HEX" ]; then
            TOTAL_VOLUME=$((16#$VOL_HEX))
        fi
    fi
fi

echo "============================================================"
echo ""
echo "📊 MARKET DATA"
echo ""

# Display market status
if [ "$CAST_AVAILABLE" = false ]; then
    echo "⚠️  Foundry 'cast' not found"
    echo ""
    echo "   Install Foundry to query live market data:"
    echo "   curl -L https://foundry.paradigm.xyz | bash"
    echo "   foundryup"
    echo ""
    echo "   Or check BaseScan events below for market info."
elif [ -z "$BASE_SEPOLIA_RPC_URL" ]; then
    echo "⚠️  RPC URL not configured"
    echo ""
    echo "   Set BASE_SEPOLIA_RPC_URL in .env to query live data."
    echo "   Or check BaseScan events below for market info."
elif [ "$QUERY_ERROR" = true ]; then
    echo "⚠️  Could not query market"
    echo ""
    echo "   The market may be invalid or there's an RPC issue."
    echo "   Check BaseScan events below to see market history."
elif [ "$MARKET_EXISTS" = true ]; then
    # Determine market status
    STATUS_TEXT="UNKNOWN"
    if [ "$MARKET_STATUS" = "0" ]; then
        STATUS_TEXT="ACTIVE"
    elif [ "$MARKET_STATUS" = "1" ]; then
        STATUS_TEXT="LOCKED"
    elif [ "$MARKET_STATUS" = "2" ]; then
        STATUS_TEXT="RESOLVED"
    fi
    
    echo "Status: $STATUS_TEXT"
    echo ""
    
    # Show timing information
    if [ ! -z "$CREATED_AT" ] && [ ! -z "$SETTLE_TS" ]; then
        CURRENT_TIME=$(date +%s)
        
        echo "Created:    $(date -r $CREATED_AT '+%Y-%m-%d %H:%M:%S')"
        echo "Settles At: $(date -r $SETTLE_TS '+%Y-%m-%d %H:%M:%S')"
        
        if [ $CURRENT_TIME -lt $SETTLE_TS ]; then
            TIME_LEFT=$((SETTLE_TS - CURRENT_TIME))
            HOURS=$((TIME_LEFT / 3600))
            MINUTES=$(((TIME_LEFT % 3600) / 60))
            SECONDS=$((TIME_LEFT % 60))
            
            if [ $HOURS -gt 0 ]; then
                echo "Time Left:  ${HOURS}h ${MINUTES}m ${SECONDS}s"
            else
                echo "Time Left:  ${MINUTES}m ${SECONDS}s"
            fi
        else
            TIME_PAST=$((CURRENT_TIME - SETTLE_TS))
            HOURS=$((TIME_PAST / 3600))
            MINUTES=$(((TIME_PAST % 3600) / 60))
            
            if [ $HOURS -gt 0 ]; then
                echo "Overdue:    ${HOURS}h ${MINUTES}m"
            else
                echo "Overdue:    ${MINUTES}m"
            fi
        fi
        echo ""
    fi
    
    if [ ! -z "$YES_PRICE" ]; then
        YES_PERCENT=$(echo "scale=2; $YES_PRICE / 100" | bc)
        NO_PRICE=$((10000 - YES_PRICE))
        NO_PERCENT=$(echo "scale=2; $NO_PRICE / 100" | bc)
        
        echo "YES: $YES_PERCENT%"
        echo "NO:  $NO_PERCENT%"
    fi
    
    # Show volume if available
    if [ ! -z "$TOTAL_VOLUME" ]; then
        echo ""
        echo "Total Volume: $(echo "scale=2; $TOTAL_VOLUME / 1000000" | bc) USDC"
    fi
else
    echo "⚠️  Could not query market data"
    echo ""
    echo "   Check BaseScan events to verify market status."
fi

echo ""
echo "============================================================"
echo ""
