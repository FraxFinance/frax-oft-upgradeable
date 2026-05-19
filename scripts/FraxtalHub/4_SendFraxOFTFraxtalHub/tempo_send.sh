#!/usr/bin/env bash
# Manual cast-based runner for SendFraxOFTTempoToFraxtal
# Bypasses forge because Tempo precompiles (TIP_FEE_MANAGER, TIP20 tokens) cannot
# be executed in forge's local EVM (OpcodeNotFound).
#
# Usage:
#   PK=0x... bash scripts/FraxtalHub/4_SendFraxOFTFraxtalHub/tempo_send.sh
#
# Optional env overrides:
#   RPC          (default https://rpc.tempo.xyz)
#   DST_EID      (default 30255 — Fraxtal)
#   RECIPIENT    (default deployer addr)
#   AMOUNT       (default 100000000000000  = 0.0001 ether)
#   GAS_TOKEN    (default frxUSD TIP20 = 0x20C0000000000000000000003554d28269E0f3c2)
#   SENDER_WALLET (default 0x741F0d8Bde14140f62107FC60A0EE122B37D4630)

set -euo pipefail

: "${PK:?PK env var required}"
RPC="${RPC:-https://rpc.tempo.xyz}"
DST_EID="${DST_EID:-30255}"
AMOUNT="${AMOUNT:-100000000000000}"            # 1e14
GAS_TOKEN="${GAS_TOKEN:-0x20C0000000000000000000003554d28269E0f3c2}"
SENDER_WALLET="${SENDER_WALLET:-0x741F0d8Bde14140f62107FC60A0EE122B37D4630}"
TIP_FEE_MANAGER="0xfeEC000000000000000000000000000000000000"

DEPLOYER=$(cast wallet address --private-key "$PK")
RECIPIENT="${RECIPIENT:-$DEPLOYER}"

# Tempo OFT addresses (from SendFraxOFTTempoToFraxtal.s.sol)
WFRAX_OFT=0x00000000E9CE0f293D1Ce552768b187eBA8a56D4
SFRXUSD_OFT=0x00000000fD8C4B8A413A06821456801295921a71
SFRXETH_OFT=0x00000000883279097A49dB1f2af954EAd0C77E3c
FRXUSD_OFT=0x00000000D61733e7A393A10A5B48c311AbE8f1E5
FRXETH_OFT=0x000000008c3930dCA540bB9B3A5D0ee78FcA9A4c
FPI_OFT=0x00000000bC4aEF4bA6363a437455Cb1af19e2aEb

OFTS=("$WFRAX_OFT" "$SFRXUSD_OFT" "$SFRXETH_OFT" "$FRXUSD_OFT" "$FRXETH_OFT" "$FPI_OFT")
LABELS=(WFRAX sfrxUSD sfrxETH frxUSD frxETH FPI)

# frxUSD is 6 decimals on Tempo — scale amount down 12 decimals
FRXUSD_AMOUNT=$((AMOUNT / 1000000000000))

# Pad recipient to bytes32
TO_BYTES32=$(cast --to-uint256 "$RECIPIENT")

echo "==== Tempo → Fraxtal batch bridge (cast) ===="
echo "Deployer      : $DEPLOYER"
echo "Sender wallet : $SENDER_WALLET"
echo "Recipient     : $RECIPIENT"
echo "DST EID       : $DST_EID"
echo "Amount        : $AMOUNT (frxUSD scaled: $FRXUSD_AMOUNT)"
echo "Gas token     : $GAS_TOKEN"
echo "RPC           : $RPC"
echo

# ---------------------------------------------------------------------------
# 1. Set deployer's preferred gas token in TIP_FEE_MANAGER
#    (so wallet's _resolveGasToken sees msg.sender=deployer and returns this)
# ---------------------------------------------------------------------------
echo "[1/4] Setting deployer userToken on TIP_FEE_MANAGER..."
cast send --rpc-url "$RPC" --private-key "$PK" \
    "$TIP_FEE_MANAGER" "setUserToken(address)" "$GAS_TOKEN" \
    >/dev/null
echo "      OK"
echo

# ---------------------------------------------------------------------------
# 2. Quote each OFT to compute total gas fee
#    SendParam tuple: (uint32 dstEid, bytes32 to, uint256 amountLD,
#                      uint256 minAmountLD, bytes extraOptions,
#                      bytes composeMsg, bytes oftCmd)
# ---------------------------------------------------------------------------
echo "[2/4] Quoting fees..."
TOTAL_FEE=0
FEES=()

for i in "${!OFTS[@]}"; do
    OFT="${OFTS[$i]}"
    LABEL="${LABELS[$i]}"
    if [[ "$LABEL" == "frxUSD" ]]; then
        AMT="$FRXUSD_AMOUNT"
    else
        AMT="$AMOUNT"
    fi

    PARAM="($DST_EID,$TO_BYTES32,$AMT,0,0x,0x,0x)"
    OUT=$(cast call --rpc-url "$RPC" "$OFT" \
        "quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)(uint256,uint256)" \
        "$PARAM" false | sed 's/\[.*\]//')
    NATIVE_FEE=$(echo "$OUT" | head -1 | tr -d '[:space:]')
    FEES+=("$NATIVE_FEE")
    TOTAL_FEE=$((TOTAL_FEE + NATIVE_FEE))
    printf "      %-8s fee=%s\n" "$LABEL" "$NATIVE_FEE"
done
echo "      TOTAL FEE: $TOTAL_FEE (gas-token units)"
echo

# ---------------------------------------------------------------------------
# 3. Approve wallet to pull totalFee of GAS_TOKEN from deployer
# ---------------------------------------------------------------------------
echo "[3/4] Approving wallet to pull $TOTAL_FEE of $GAS_TOKEN..."
cast send --rpc-url "$RPC" --private-key "$PK" \
    "$GAS_TOKEN" "approve(address,uint256)" "$SENDER_WALLET" "$TOTAL_FEE" \
    >/dev/null
echo "      OK"
echo

# ---------------------------------------------------------------------------
# 4. Build sendParams[] / ofts[] / destinations[] arrays and execute
# ---------------------------------------------------------------------------
echo "[4/4] Calling batchBridgeWithTIP20FeeFromWallet..."

# Build comma-separated array literals for cast
SEND_PARAMS_ARR=""
OFTS_ARR=""
DESTS_ARR=""
for i in "${!OFTS[@]}"; do
    OFT="${OFTS[$i]}"
    LABEL="${LABELS[$i]}"
    if [[ "$LABEL" == "frxUSD" ]]; then
        AMT="$FRXUSD_AMOUNT"
    else
        AMT="$AMOUNT"
    fi
    if [[ -n "$SEND_PARAMS_ARR" ]]; then
        SEND_PARAMS_ARR+=","
        OFTS_ARR+=","
        DESTS_ARR+=","
    fi
    SEND_PARAMS_ARR+="($DST_EID,$TO_BYTES32,$AMT,0,0x,0x,0x)"
    OFTS_ARR+="$OFT"
    DESTS_ARR+="$SENDER_WALLET"
done

cast send --rpc-url "$RPC" --private-key "$PK" \
    "$SENDER_WALLET" \
    "batchBridgeWithTIP20FeeFromWallet((uint32,bytes32,uint256,uint256,bytes,bytes,bytes)[],address[],address[])" \
    "[$SEND_PARAMS_ARR]" "[$OFTS_ARR]" "[$DESTS_ARR]"

echo
echo "==== Done ===="
