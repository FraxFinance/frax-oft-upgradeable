#!/usr/bin/env bash
# decode-multisend.sh — independently decode a Safe MultiSend batch and recompute its safeTxHash.
# Feed it either a built batch JSON, or raw multiSend(bytes) calldata (e.g. copied from the explorer /
# your hardware wallet), or a file containing that hex.
#
# Usage: scripts/ops/SafeOnchainExec/decode-multisend.sh <config.json> (<batch.json> | <0x8d80ff0a...> | <hexfile>) [--nonce N]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE=scripts/ops/SafeOnchainExec
source "$HERE/lib.sh"
[[ $# -ge 2 ]] || { sed -n 2,7p "$0"; exit 2; }
load_config "$1"; SRC="$2"; shift 2; NONCE=""
[[ "${1:-}" == "--nonce" ]] && NONCE="$2"
ZERO=0x0000000000000000000000000000000000000000
if [[ -f "$SRC" && "$SRC" == *.json ]]; then cd_hex=$(jq -r .safeTx.data "$SRC"); NONCE=${NONCE:-$(jq -r .nonce "$SRC")}; emb=$(jq -r .safeTxHash "$SRC"); to=$(jq -r .safeTx.to "$SRC")
elif [[ -f "$SRC" ]]; then cd_hex=$(tr -d ' \n' < "$SRC"); emb=""; to="$MULTISEND"
else cd_hex="$SRC"; emb=""; to="$MULTISEND"; fi
echo "multiSend calldata: $(( (${#cd_hex}-2)/2 )) bytes, keccak256 $(cast keccak "$cd_hex")"
echo; echo "| # | target | value | function | decoded |"; echo "|---|---|---|---|---|"
i=0; while IFS=$'\t' read -r op cto val cdata; do
  [[ "$op" == "0" ]] || echo "WARNING: inner call $i has operation=$op (DELEGATECALL) — MultiSendCallOnly would revert" >&2
  dec=$(decode_call "$cto" "$cdata"); printf '| %d | %s | %s | %s | %s |\n' "$i" "$(label "$cto")" "$val" "${dec%% |*}" "${dec#*| }"; i=$((i+1))
done < <(parse_multisend "$cd_hex")
echo; echo "inner calls: $i"
if [[ -n "$NONCE" ]]; then
  h=$(safe_tx_hash_offline "$to" 0 "$cd_hex" 1 0 0 0 $ZERO $ZERO "$NONCE")
  echo "safeTxHash (offline, to=$to op=1 nonce=$NONCE): $h"
  [[ -n "$emb" ]] && { [[ "$emb" == "$h" ]] && echo "matches embedded safeTxHash in $SRC" || echo "MISMATCH vs embedded $emb"; }
  if [[ "${OFFLINE:-0}" != "1" ]]; then h2=$(safe_tx_hash_onchain "$to" 0 "$cd_hex" 1 0 0 0 $ZERO $ZERO "$NONCE"); [[ "$h2" == "$h" ]] && echo "matches Safe.getTransactionHash on-chain" || echo "MISMATCH vs on-chain $h2"; fi
else echo "(pass --nonce N to also compute the safeTxHash)"; fi
