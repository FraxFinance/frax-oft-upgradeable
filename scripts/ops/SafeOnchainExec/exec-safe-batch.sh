#!/usr/bin/env bash
# exec-safe-batch.sh — build (and optionally send) the Safe execTransaction for one built batch,
# using the approved-hash signature scheme (each approver's "signature" is r=owner, s=0, v=1).
#
# Usage:
#   scripts/ops/SafeOnchainExec/exec-safe-batch.sh <config.json> <NN> --approvers 0xA,0xB,0xC [--sender 0xS] [--gas-limit N] [--send <cast send opts...>]
#
#   --approvers  comma-separated owners that already called approveHash(safeTxHash) on-chain (verified here)
#   --sender     the EOA that will send execTransaction. If it is a Safe owner it counts as an approval
#                WITHOUT needing approveHash (Safe checks msg.sender==owner for v=1 sigs). Required for simulation.
#   --send ...   actually broadcast; everything after --send is passed to `cast send` (e.g. --ledger, --account me)
# Without --send: verifies approvals, eth_call-simulates, estimates gas and prints the raw calldata only.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE=scripts/ops/SafeOnchainExec
source "$HERE/lib.sh"
[[ $# -ge 2 ]] || { sed -n 2,14p "$0"; exit 2; }
load_config "$1"; NUM="$2"; shift 2
APPROVERS=""; SENDER=""; GAS_LIMIT=""; SEND=0; SEND_OPTS=()
while [[ $# -gt 0 ]]; do case "$1" in
  --approvers) APPROVERS="$2"; shift 2;; --sender) SENDER="$2"; shift 2;; --gas-limit) GAS_LIMIT="$2"; shift 2;;
  --send) SEND=1; shift; SEND_OPTS=("$@"); break;; *) echo "unknown arg $1" >&2; exit 2;; esac; done

bf=$(ls "$OUT_DIR"/batch-"$NUM"-*.json 2>/dev/null | head -1); [[ -f "$bf" ]] || { echo "no built batch $NUM in $OUT_DIR (run build-safe-batches.sh)" >&2; exit 1; }
name=$(jq -r .batch "$bf"); nonce=$(jq -r .nonce "$bf"); hash=$(jq -r .safeTxHash "$bf"); to=$(jq -r .safeTx.to "$bf"); data=$(jq -r .safeTx.data "$bf")
ZERO=0x0000000000000000000000000000000000000000
echo "batch $NUM ($name) nonce=$nonce safeTxHash=$hash"

# 1) nonce + hash must still match on-chain
cur=$(cast call "$SAFE" 'nonce()(uint256)' --rpc-url "$RPC")
[[ "$cur" == "$nonce" ]] || { echo "ERROR: Safe nonce is $cur but this batch is for nonce $nonce. Execute earlier batches first, or rebuild." >&2; exit 1; }
h2=$(safe_tx_hash_onchain "$to" 0 "$data" 1 0 0 0 $ZERO $ZERO "$nonce"); [[ "$h2" == "$hash" ]] || { echo "ERROR: on-chain getTransactionHash $h2 != $hash" >&2; exit 1; }
# 2) approvals
OWNERS=$(cast call "$SAFE" 'getOwners()(address[])' --rpc-url "$RPC" | tr -d '[] ' | tr ',' '\n' | tr 'A-F' 'a-f')
THRESHOLD=$(cast call "$SAFE" 'getThreshold()(uint256)' --rpc-url "$RPC")
SIGNERS=""
for a in $(echo "$APPROVERS" | tr ',' '\n' | tr 'A-F' 'a-f'); do [[ -z "$a" ]] && continue
  echo "$OWNERS" | grep -qx "$a" || { echo "ERROR: $a is not a Safe owner" >&2; exit 1; }
  ap=$(cast call "$SAFE" 'approvedHashes(address,bytes32)(uint256)' "$a" "$hash" --rpc-url "$RPC")
  [[ "$ap" == "1" ]] || { echo "ERROR: $a has NOT approved $hash on-chain (approvedHashes=$ap)" >&2; exit 1; }
  echo "  approved: $a"; SIGNERS="$SIGNERS $a"
done
if [[ -n "$SENDER" ]]; then s=$(echo "$SENDER" | tr 'A-F' 'a-f')
  if echo "$OWNERS" | grep -qx "$s" && ! echo "$SIGNERS" | grep -q "$s"; then echo "  sender $s is an owner -> counts as approval (msg.sender rule)"; SIGNERS="$SIGNERS $s"; fi; fi
n=$(echo $SIGNERS | wc -w | tr -d ' '); [[ $n -ge $THRESHOLD ]] || { echo "ERROR: only $n approvals, threshold is $THRESHOLD" >&2; exit 1; }
sigs=$(pack_approved_sigs $SIGNERS)
calldata=$(cast calldata 'execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)' "$to" 0 "$data" 1 0 0 0 $ZERO $ZERO "$sigs")
# 3) simulate + estimate
FROM=${SENDER:-$(echo $SIGNERS | awk '{print $1}')}
res=$(cast call "$SAFE" "$calldata" --from "$FROM" --rpc-url "$RPC") || { echo "ERROR: eth_call simulation of execTransaction REVERTED" >&2; exit 1; }
[[ "$res" =~ 1$ ]] || { echo "ERROR: execTransaction simulation returned $res (expected true)" >&2; exit 1; }
est=$(cast estimate "$SAFE" "$calldata" --from "$FROM" --rpc-url "$RPC")
GAS_LIMIT=${GAS_LIMIT:-$(( est * 13 / 10 ))}
echo "  simulation OK from $FROM; estimated gas $est; using --gas-limit $GAS_LIMIT"
echo "  signatures blob: $sigs"
echo "  execTransaction calldata ($(( (${#calldata}-2)/2 )) bytes):"; echo "$calldata"
if [[ $SEND -eq 1 ]]; then
  echo; echo "Broadcasting execTransaction to $SAFE ..."
  cast send "$SAFE" "$calldata" --rpc-url "$RPC" --gas-limit "$GAS_LIMIT" "${SEND_OPTS[@]}"
else
  echo; echo "(dry run — add --send <cast send opts> to broadcast)"
fi
