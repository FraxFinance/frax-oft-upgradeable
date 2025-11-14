#!/bin/bash

CONFIG_FILE="scripts/L0Config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ $CONFIG_FILE not found!"
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <filename_prefix> [forge script args...]"
    exit 1
fi

BROADCAST_CHAIN_ID="$1"
FILENAME_PREFIX="$2"
shift
FORGE_ARGS=("$@")

TIMESTAMP=$(date +%s)
LOG_FILE="${FILENAME_PREFIX}_${TIMESTAMP}_logs.txt"

success_chains=()
failed_chains=()

echo "🧾 Forge Script Run - Started at $(date) (Unix timestamp: $TIMESTAMP)" | tee -a "$LOG_FILE"

count=$(jq '.Proxy | length' "$CONFIG_FILE")
for (( i=0; i<$count; i++ )); do
    RPC_URL=$(jq -r ".Proxy[$i].RPC" "$CONFIG_FILE")
    CHAIN_ID=$(jq -r ".Proxy[$i].chainid" "$CONFIG_FILE")

    echo "------------------------------------------" | tee -a "$LOG_FILE"
    echo "⏳ Processing Chain ID: $CHAIN_ID" | tee -a "$LOG_FILE"

    # Skip chainid 3637, 2741 and 324
    if [ -z "$CHAIN_ID" ] || [ "$CHAIN_ID" -eq ${BROADCAST_CHAIN_ID} ] || [ "$CHAIN_ID" -eq 1 ] || [ "$CHAIN_ID" -eq 3637 ] || [ "$CHAIN_ID" -eq 2741 ] || [ "$CHAIN_ID" -eq 324 ]; then
        echo "⏭️  Skipping chain ID $CHAIN_ID" | tee -a "$LOG_FILE"
        continue
    fi

    if [ -z "$RPC_URL" ] || [ "$RPC_URL" == "null" ]; then
        echo "❌ Missing RPC URL for chain ID $CHAIN_ID" | tee -a "$LOG_FILE"
        failed_chains+=("$CHAIN_ID (missing RPC)")
        continue
    fi

    # Add --legacy if chainid == 196 or 1313161554
    EXTRA_ARGS=()
    if [ "$CHAIN_ID" -eq 196 ] || [ "$CHAIN_ID" -eq 1313161554 ]; then
        EXTRA_ARGS+=(--legacy)
    fi


    # Add --slow if chainid == 1313161554 or 999
    if [ "$CHAIN_ID" -eq 1313161554 ] || [ "$CHAIN_ID" -eq 999 ] ; then
        EXTRA_ARGS+=(--slow)
    fi

    echo "🚀 Running forge script with RPC: $RPC_URL ${EXTRA_ARGS[*]}" | tee -a "$LOG_FILE"

    OUTPUT=$(mktemp)
    MAX_RETRIES=5
    ATTEMPT=1
    SUCCESS=0

    while [ $ATTEMPT -le $MAX_RETRIES ]; do
        echo "🔁 Attempt $ATTEMPT for chain ID $CHAIN_ID" | tee -a "$LOG_FILE"

        # Full command to run
        CMD=(forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url "$RPC_URL" "${EXTRA_ARGS[@]}" "${FORGE_ARGS[@]}")
        CMD_STRING="${CMD[@]}"

        echo "📦 Running command:" | tee -a "$LOG_FILE"
        echo "$CMD_STRING" | tee -a "$LOG_FILE"

        # Execute and capture
        if "${CMD[@]}" 2>&1 | tee -a "$LOG_FILE" | tee "$OUTPUT"; then
            if grep -qi "error" "$OUTPUT"; then
                echo "⚠️  Error detected in logs on attempt $ATTEMPT" | tee -a "$LOG_FILE"
            else
                echo "✅ Success for chain ID $CHAIN_ID on attempt $ATTEMPT" | tee -a "$LOG_FILE"
                success_chains+=("$CHAIN_ID")
                SUCCESS=1
                break
            fi
        else
            echo "❌ Forge exited with failure on attempt $ATTEMPT" | tee -a "$LOG_FILE"
        fi

        ((ATTEMPT++))
        sleep 1
    done

    if [ "$SUCCESS" -ne 1 ]; then
        echo "❌ All attempts failed for chain ID $CHAIN_ID" | tee -a "$LOG_FILE"
        failed_chains+=("$CHAIN_ID")
        failed_commands+=("$CMD_STRING")
    fi

    rm "$OUTPUT"
done

{
    echo "=========================================="
    echo "📝 Forge Script Summary:"
    echo "✅ Successful chains: ${#success_chains[@]}"
    for id in "${success_chains[@]}"; do
        echo "   - $id"
    done

    echo ""
    echo "❌ Failed chains: ${#failed_chains[@]}"
    for id in "${failed_chains[@]}"; do
        echo "   - $id"
    done

    if [ ${#failed_commands[@]} -gt 0 ]; then
        echo ""
        echo "🔁 Commands you can retry manually:"
        for cmd in "${failed_commands[@]}"; do
            echo ""
            echo "$cmd"
        done
    fi

    echo ""
    echo "📄 Full logs written to: $LOG_FILE"
    echo "🎉 Done."
} | tee -a "$LOG_FILE"
