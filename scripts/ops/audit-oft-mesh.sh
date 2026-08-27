#!/usr/bin/env bash

set -u
set -o pipefail

usage() {
    echo "Usage: $0 <source-chain-id> <adapter> [destination-chain-ids]" >&2
    echo "Example: $0 1 0xE41228a455700cAF09E551805A8aB37caa39D08c 8453,81457,252" >&2
    exit 1
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage
fi

SOURCE_CHAIN_ID="$1"
ADAPTER="$2"
DESTINATION_CHAIN_IDS="${3:-}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
L0_CONFIG="${L0_CONFIG:-$PROJECT_ROOT/scripts/L0Config.json}"
RPC_FALLBACKS="${RPC_FALLBACKS:-$PROJECT_ROOT/../scripts/data/rpc-fallbacks.json}"

for command_name in cast jq; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name" >&2
        exit 1
    fi
done

if [[ ! -f "$L0_CONFIG" || ! -f "$RPC_FALLBACKS" ]]; then
    echo "Missing L0 config or RPC fallback file" >&2
    exit 1
fi

config_rpc() {
    jq -r --argjson chain_id "$1" \
        '.Proxy[] | select(.chainid == $chain_id) | .RPC' "$L0_CONFIG" | head -n 1
}

rpc_candidates() {
    config_rpc "$1"
    jq -r --arg chain_id "$1" '.chains[$chain_id][]? // empty' "$RPC_FALLBACKS"
}

call_chain() {
    local chain_id="$1"
    local target="$2"
    local signature="$3"
    shift 3

    local rpc result
    while IFS= read -r rpc; do
        [[ -z "$rpc" || "$rpc" == "Solana" ]] && continue
        if result=$(cast call "$target" "$signature" "$@" --rpc-url "$rpc" 2>/dev/null); then
            printf '%s\n' "$result"
            return 0
        fi
    done < <(rpc_candidates "$chain_id" | awk '!seen[$0]++')

    return 1
}

source_eid=$(jq -r --argjson chain_id "$SOURCE_CHAIN_ID" \
    '.Proxy[] | select(.chainid == $chain_id) | .eid' "$L0_CONFIG" | head -n 1)

if [[ -z "$source_eid" || "$source_eid" == "null" ]]; then
    echo "Source chain $SOURCE_CHAIN_ID is absent from $L0_CONFIG" >&2
    exit 1
fi

token=$(call_chain "$SOURCE_CHAIN_ID" "$ADAPTER" 'token()(address)') || {
    echo "Unable to read adapter $ADAPTER on chain $SOURCE_CHAIN_ID" >&2
    exit 1
}
owner=$(call_chain "$SOURCE_CHAIN_ID" "$ADAPTER" 'owner()(address)' || echo unavailable)
endpoint=$(call_chain "$SOURCE_CHAIN_ID" "$ADAPTER" 'endpoint()(address)' || echo unavailable)
token_symbol=$(call_chain "$SOURCE_CHAIN_ID" "$token" 'symbol()(string)' || echo unavailable)
locked_balance=$(call_chain "$SOURCE_CHAIN_ID" "$token" 'balanceOf(address)(uint256)' "$ADAPTER" || echo unavailable)

echo "source_chain_id=$SOURCE_CHAIN_ID"
echo "source_eid=$source_eid"
echo "adapter=$ADAPTER"
echo "token=$token"
echo "token_symbol=$token_symbol"
echo "locked_balance=$locked_balance"
echo "owner=$owner"
echo "endpoint=$endpoint"
echo
printf 'chain_id\teid\tpeer\tsend_library\tremote_symbol\treverse_peer\n'

while IFS=$'\t' read -r chain_id eid rpc; do
    [[ "$chain_id" == "$SOURCE_CHAIN_ID" ]] && continue

    peer=$(call_chain "$SOURCE_CHAIN_ID" "$ADAPTER" 'peers(uint32)(bytes32)' "$eid" || echo unavailable)
    [[ "$peer" == "0x0000000000000000000000000000000000000000000000000000000000000000" ]] && continue

    send_library=unavailable
    if [[ "$endpoint" != "unavailable" ]]; then
        send_library=$(call_chain "$SOURCE_CHAIN_ID" "$endpoint" \
            'getSendLibrary(address,uint32)(address)' "$ADAPTER" "$eid" || echo unavailable)
    fi

    remote_symbol=non-evm
    reverse_peer=non-evm
    if [[ "$peer" =~ ^0x000000000000000000000000[0-9a-fA-F]{40}$ && "$rpc" != "Solana" ]]; then
        peer_address="0x${peer: -40}"
        remote_symbol=$(call_chain "$chain_id" "$peer_address" 'symbol()(string)' || echo unavailable)
        reverse_peer=$(call_chain "$chain_id" "$peer_address" \
            'peers(uint32)(bytes32)' "$source_eid" || echo unavailable)
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$chain_id" "$eid" "$peer" "$send_library" "$remote_symbol" "$reverse_peer"
done < <(jq -r --arg chainids "$DESTINATION_CHAIN_IDS" \
    '(if $chainids == "" then [] else ($chainids | split(",") | map(tonumber)) end) as $ids
     | .Proxy[]
     | select($chainids == "" or (.chainid as $id | $ids | index($id)))
     | [.chainid, .eid, .RPC]
     | @tsv' "$L0_CONFIG")
