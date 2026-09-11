#!/usr/bin/env bash
# simulate-safe-batches.sh — replay the built batches end-to-end on an Anvil fork:
#   impersonate <threshold> owners -> approveHash(safeTxHash) -> execTransaction from a non-owner EOA,
#   assert success + nonce advance, then check on-chain post-conditions for EVERY inner call.
#
# Usage: scripts/ops/SafeOnchainExec/simulate-safe-batches.sh [config.json] [--port 8546] [--only NN]
#   env: RPC=<override fork rpc>
# Requires: anvil, cast, jq. Writes <outDir>/SIMULATION.md
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE=scripts/ops/SafeOnchainExec
source "$HERE/lib.sh"
require_cmd anvil

CFG_ARG=""; PORT=8546; ONLY=""
while [[ $# -gt 0 ]]; do case "$1" in
  --port) PORT="$2"; shift 2;; --only) ONLY="$2"; shift 2;; *) CFG_ARG="$1"; shift;; esac; done
load_config "${CFG_ARG:-$HERE/config/34443-0x6336.json}"
FORK_RPC="$RPC"; L="http://127.0.0.1:$PORT"

anvil --fork-url "$FORK_RPC" --port "$PORT" --silent --gas-limit 60000000 --code-size-limit 100000 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
for i in $(seq 1 60); do cast chain-id --rpc-url "$L" >/dev/null 2>&1 && break; sleep 0.5; done
[[ "$(cast chain-id --rpc-url "$L")" == "$CHAIN_ID" ]] || { echo "fork chain id mismatch" >&2; exit 1; }

OWNERS=$(cast call "$SAFE" 'getOwners()(address[])' --rpc-url "$L" | tr -d '[] ' | tr ',' '\n')
THRESHOLD=$(cast call "$SAFE" 'getThreshold()(uint256)' --rpc-url "$L")
APPROVERS=$(echo "$OWNERS" | head -n "$THRESHOLD")
EXECUTOR=0x70997970C51812dc3A010C7d01b50e0d17dc79C8   # anvil default account #1 (NOT a Safe owner)
echo "fork: $L  safe: $SAFE  threshold: $THRESHOLD  executor(non-owner): $EXECUTOR"
echo "approvers (impersonated): $(echo "$APPROVERS" | tr '\n' ' ')"
for o in $APPROVERS; do cast rpc anvil_impersonateAccount "$o" --rpc-url "$L" >/dev/null; cast rpc anvil_setBalance "$o" 0x8AC7230489E80000 --rpc-url "$L" >/dev/null; done
cast rpc anvil_setBalance "$EXECUTOR" 0x8AC7230489E80000 --rpc-url "$L" >/dev/null
EXEC_SUCCESS_TOPIC=$(cast keccak 'ExecutionSuccess(bytes32,uint256)')

SIM="$OUT_DIR/SIMULATION.md"
{ echo "# Anvil fork simulation — $SAFE on chain $CHAIN_ID"; echo; echo "Fork of \`$FORK_RPC\` at block $(cast block-number --rpc-url "$L"), $(date -u +%Y-%m-%dT%H:%MZ). Approvers impersonated: $(echo "$APPROVERS" | tr '\n' ' '). Executor: $EXECUTOR (non-owner)."; echo
  echo "| batch | nonce | safeTxHash | exec status | gasUsed | post-condition checks | failed checks |"; echo "|---|---|---|---|---|---|---|"; } > "$SIM"

ZERO=0x0000000000000000000000000000000000000000
fail_total=0
for bf in $(ls "$OUT_DIR"/batch-*.json | sort); do
  num=$(basename "$bf" | cut -d- -f2); [[ -n "$ONLY" && "$ONLY" != "$num" ]] && continue
  name=$(jq -r .batch "$bf"); nonce=$(jq -r .nonce "$bf"); hash=$(jq -r .safeTxHash "$bf")
  to=$(jq -r .safeTx.to "$bf"); data=$(jq -r .safeTx.data "$bf")
  echo; echo "== batch $num $name nonce=$nonce hash=$hash"
  cur=$(cast call "$SAFE" 'nonce()(uint256)' --rpc-url "$L")
  [[ "$cur" == "$nonce" ]] || { echo "ERROR: fork Safe nonce is $cur, batch expects $nonce (run batches in order / rebuild with correct startNonce)" >&2; exit 1; }
  # re-derive the hash on the fork (guards against stale out/ files)
  h2=$(cast call "$SAFE" 'getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)(bytes32)' "$to" 0 "$data" 1 0 0 0 $ZERO $ZERO "$nonce" --rpc-url "$L")
  [[ "$h2" == "$hash" ]] || { echo "ERROR: batch file hash $hash != fork getTransactionHash $h2" >&2; exit 1; }
  for o in $APPROVERS; do cast send --unlocked --from "$o" "$SAFE" 'approveHash(bytes32)' "$hash" --rpc-url "$L" >/dev/null; done
  sigs=$(pack_approved_sigs $APPROVERS)
  rcpt=$(cast send --unlocked --from "$EXECUTOR" "$SAFE" 'execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)' \
           "$to" 0 "$data" 1 0 0 0 $ZERO $ZERO "$sigs" --gas-limit 30000000 --rpc-url "$L" --json)
  status=$(echo "$rcpt" | jq -r .status); gas=$(cast to-dec "$(echo "$rcpt" | jq -r .gasUsed)")
  ok_evt=$(echo "$rcpt" | jq -r --arg t "$EXEC_SUCCESS_TOPIC" '[.logs[] | select(.topics[0]==$t)] | length')
  newnonce=$(cast call "$SAFE" 'nonce()(uint256)' --rpc-url "$L")
  echo "   execTransaction status=$status gasUsed=$gas ExecutionSuccess events=$ok_evt nonce now=$newnonce"
  [[ "$status" == "0x1" && "$ok_evt" == "1" && "$newnonce" == "$((nonce+1))" ]] || { echo "ERROR: execution failed (status=$status, ExecutionSuccess=$ok_evt). If status=0x1 but no ExecutionSuccess, the inner batch reverted (GS013)." >&2; exit 1; }

  # ---- post-conditions per inner call ----
  checks=0; fails=0
  ncalls=$(jq '.calls|length' "$bf")
  for (( ci=0; ci<ncalls; ci++ )); do
    cto=$(jq -r ".calls[$ci].to" "$bf"); cdata=$(jq -r ".calls[$ci].data" "$bf"); sel=${cdata:0:10}
    case "$sel" in
      0x6a14d715) set -- $(cast calldata-decode 'setReceiveLibrary(address,uint32,address,uint256)' "$cdata" | sed 's/ \[.*\]//'); oapp=$1; eid=$2; lib=$3
        got=$(cast call "$cto" 'getReceiveLibrary(address,uint32)(address,bool)' "$oapp" "$eid" --rpc-url "$L" | paste -sd' ' -); checks=$((checks+1))
        if [[ "$lib" == "$ZERO" ]]; then exp="true"; [[ "$got" == *"$exp" ]] || { fails=$((fails+1)); echo "   FAIL #$ci setReceiveLibrary $oapp eid $eid: isDefault expected true, got '$got'"; }
        else [[ "$(echo "$got" | tr 'A-F' 'a-f')" == "$(echo "$lib false" | tr 'A-F' 'a-f')" ]] || { fails=$((fails+1)); echo "   FAIL #$ci setReceiveLibrary: got '$got' expected '$lib false'"; }; fi;;
      0x9535ff30) set -- $(cast calldata-decode 'setSendLibrary(address,uint32,address)' "$cdata" | sed 's/ \[.*\]//'); oapp=$1; eid=$2; lib=$3; checks=$((checks+1))
        if [[ "$lib" == "$ZERO" ]]; then got=$(cast call "$cto" 'isDefaultSendLibrary(address,uint32)(bool)' "$oapp" "$eid" --rpc-url "$L"); [[ "$got" == "true" ]] || { fails=$((fails+1)); echo "   FAIL #$ci setSendLibrary default: got $got"; }
        else got=$(cast call "$cto" 'getSendLibrary(address,uint32)(address)' "$oapp" "$eid" --rpc-url "$L"); [[ "$(echo "$got" | tr 'A-F' 'a-f')" == "$(echo "$lib" | tr 'A-F' 'a-f')" ]] || { fails=$((fails+1)); echo "   FAIL #$ci setSendLibrary: got $got expected $lib"; }; fi;;
      0xb98bd070) params=$(cast calldata-decode 'setEnforcedOptions((uint32,uint16,bytes)[])' "$cdata" | sed 's/ \[[^]]*\]//g' | sed 's/^\[//; s/\]$//' | sed 's/), (/)\
(/g' | tr -d '()')
        while IFS=', ' read -r eid mt opts; do [[ -z "$eid" ]] && continue; checks=$((checks+1))
          got=$(cast call "$cto" 'enforcedOptions(uint32,uint16)(bytes)' "$eid" "$mt" --rpc-url "$L"); [[ "$got" == "$opts" ]] || { fails=$((fails+1)); echo "   FAIL #$ci enforcedOptions($eid,$mt): got $got expected $opts"; }
        done <<< "$params";;
      0x6dbd9f90) dec=$(cast calldata-decode 'setConfig(address,address,(uint32,uint32,bytes)[])' "$cdata"); oapp=$(echo "$dec" | sed -n 1p); lib=$(echo "$dec" | sed -n 2p)
        params=$(echo "$dec" | sed -n 3p | sed 's/ \[[^]]*\]//g' | sed 's/^\[//; s/\]$//' | sed 's/), (/)\
(/g' | tr -d '()')
        while IFS=', ' read -r eid ctype cfg; do [[ -z "$eid" ]] && continue
          if [[ "$ctype" == "2" ]]; then checks=$((checks+1)); exp=$(cast abi-decode 'f()((uint64,uint8,uint8,uint8,address[],address[]))' "$cfg" | tr -d '\n')
            got=$(cast call "$lib" 'getAppUlnConfig(address,uint32)((uint64,uint8,uint8,uint8,address[],address[]))' "$oapp" "$eid" --rpc-url "$L" | tr -d '\n')
            [[ "$got" == "$exp" ]] || { fails=$((fails+1)); echo "   FAIL #$ci getAppUlnConfig($oapp,$eid) on $lib: got $got expected $exp"; }
          else echo "   (skip) #$ci setConfig configType=$ctype not checked"; fi
        done <<< "$params";;
      0x3400288b) set -- $(cast calldata-decode 'setPeer(uint32,bytes32)' "$cdata" | sed 's/ \[.*\]//'); checks=$((checks+1))
        got=$(cast call "$cto" 'peers(uint32)(bytes32)' "$1" --rpc-url "$L"); [[ "$got" == "$2" ]] || { fails=$((fails+1)); echo "   FAIL #$ci peers($1): got $got expected $2"; };;
      0x9623609d) d=$(cast calldata-decode 'upgradeAndCall(address,address,bytes)' "$cdata"); proxy=$(echo "$d" | sed -n 1p); impl=$(echo "$d" | sed -n 2p); checks=$((checks+1))
        got=$(cast implementation "$proxy" --rpc-url "$L"); [[ "$(echo "$got" | tr 'A-F' 'a-f')" == "$(echo "$impl" | tr 'A-F' 'a-f')" ]] || { fails=$((fails+1)); echo "   FAIL #$ci implementation($proxy): got $got expected $impl"; };;
      0x2f2ff15d) d=$(cast calldata-decode 'grantRole(bytes32,address)' "$cdata"); role=$(echo "$d" | sed -n 1p); acct=$(echo "$d" | sed -n 2p); checks=$((checks+1))
        got=$(cast call "$cto" 'hasRole(bytes32,address)(bool)' "$role" "$acct" --rpc-url "$L"); [[ "$got" == "true" ]] || { fails=$((fails+1)); echo "   FAIL #$ci hasRole: got $got"; };;
      *) echo "   (skip) #$ci unknown selector $sel not checked";;
    esac
  done
  echo "   post-conditions: $checks checked, $fails failed"
  fail_total=$((fail_total+fails))
  printf '| %s | %d | `%s` | %s | %d | %d | %d |\n' "$num $name" "$nonce" "$hash" "$([[ $status == 0x1 ]] && echo OK || echo FAIL)" "$gas" "$checks" "$fails" >> "$SIM"
done
echo; echo "Wrote $SIM"; [[ $fail_total -eq 0 ]] && echo "ALL POST-CONDITIONS PASSED" || { echo "$fail_total POST-CONDITION FAILURES" >&2; exit 1; }
