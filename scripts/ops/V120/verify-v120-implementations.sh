#!/usr/bin/env bash
# Verify every V120 implementation deployed by a broadcast run on the chain's explorer.
#
# Usage:
#   scripts/ops/V120/verify-v120-implementations.sh <broadcast-run-latest.json>
#   scripts/ops/V120/verify-v120-implementations.sh --all      # every broadcast/UpgradeV120*/**/run-latest.json
#
# Env:
#   ETHERSCAN_API_KEY   required for Etherscan-v2 chains (one key covers all of them)
#   (no key needed for Blockscout, Sourcify or the zksync verifiers)
#
# Chain routing:
#   Etherscan v2 (single key): 1 10 56 130 137 143 146 252 480 988 999 1329 8453
#                              42161 43114 59144 81457 747474
#   Blockscout (keyless):      57073 Ink, 98866 Plume, 1313161554 Aurora, 5031 Somnia
#   Sourcify (keyless):        196 X-Layer  — also a fallback for any chain above
#   Tempo:                     4217 -> pnpm verify:tempo:mainnet <broadcast file>
#   zksync-stack:              324 zkSync Era, 2741 Abstract -> must run under
#                              foundry-zksync (foundryup-zksync), handled here with
#                              --verifier custom zksync endpoints; falls back to a
#                              printed manual command if the active forge lacks --zksync.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

for dep in jq cast forge; do
    command -v "$dep" >/dev/null || { echo "missing dependency: $dep" >&2; exit 1; }
done

fqn_for() {
    case "$1" in
        WFRAXTokenOFTUpgradeable) echo "contracts/WFRAXTokenOFTUpgradeable.sol:WFRAXTokenOFTUpgradeable" ;;
        SFrxUSDOFTUpgradeable) echo "contracts/frxUsd/SFrxUSDOFTUpgradeable.sol:SFrxUSDOFTUpgradeable" ;;
        FrxUSDOFTUpgradeable) echo "contracts/frxUsd/FrxUSDOFTUpgradeable.sol:FrxUSDOFTUpgradeable" ;;
        FraxOFTUpgradeable) echo "contracts/FraxOFTUpgradeable.sol:FraxOFTUpgradeable" ;;
        FraxOFTUpgradeableTempo) echo "contracts/FraxOFTUpgradeableTempo.sol:FraxOFTUpgradeableTempo" ;;
        FraxOFTAdapterUpgradeable) echo "contracts/FraxOFTAdapterUpgradeable.sol:FraxOFTAdapterUpgradeable" ;;
        FraxOFTMintableAdapterUpgradeable) echo "contracts/FraxOFTMintableAdapterUpgradeable.sol:FraxOFTMintableAdapterUpgradeable" ;;
        FraxOFTMintableAdapterUpgradeableTIP20) echo "contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol:FraxOFTMintableAdapterUpgradeableTIP20" ;;
        # externally linked module libraries (deployed once per chain by the same broadcast)
        RateLimiterLib|EIP3009Lib|PermitLib|FreezeThawLib|PauseLib|EIP712Lib|TempoAltTokenLib)
            echo "contracts/libraries/$1.sol:$1" ;;
        *) return 1 ;;
    esac
}

is_library() {
    case "$1" in
        RateLimiterLib|EIP3009Lib|PermitLib|FreezeThawLib|PauseLib|EIP712Lib|TempoAltTokenLib) return 0 ;;
        *) return 1 ;;
    esac
}

# Build --libraries flags from the library CREATEs recorded in the same broadcast file, so
# the linked implementation bytecode matches exactly during verification.
libraries_flags_from() {
    local file="$1" flags=""
    while IFS=$'\t' read -r name addr; do
        local fqn
        fqn="$(fqn_for "$name")" || continue
        is_library "$name" || continue
        flags="$flags --libraries ${fqn}:${addr}"
    done < <(jq -r '.transactions[] | select(.transactionType == "CREATE" or .transactionType == "CREATE2") | [.contractName, .contractAddress] | @tsv' "$file")
    echo "$flags"
}

ctor_sig_for() {
    case "$1" in
        FraxOFTAdapterUpgradeable|FraxOFTMintableAdapterUpgradeable|FraxOFTMintableAdapterUpgradeableTIP20)
            echo "constructor(address,address)" ;;
        *)  echo "constructor(address)" ;;
    esac
}

verifier_args_for_chain() {
    local cid="$1"
    case "$cid" in
        1|10|56|130|137|143|146|252|480|988|999|1329|8453|42161|43114|59144|81457|747474)
            echo "--verifier etherscan --verifier-url https://api.etherscan.io/v2/api?chainid=${cid} --etherscan-api-key ${ETHERSCAN_API_KEY:?ETHERSCAN_API_KEY not set}" ;;
        57073)      echo "--verifier blockscout --verifier-url https://explorer.inkonchain.com/api" ;;
        98866)      echo "--verifier blockscout --verifier-url https://explorer.plume.org/api" ;;
        1313161554) echo "--verifier blockscout --verifier-url https://explorer.mainnet.aurora.dev/api" ;;
        5031)       echo "--verifier blockscout --verifier-url https://explorer.somnia.network/api" ;;
        # X-Layer: OKLink requires a paid API key; Sourcify supports chain 196 and needs none.
        196)        echo "--verifier sourcify --verifier-url https://sourcify.dev/server" ;;
        *) return 1 ;;
    esac
}

verify_broadcast_file() {
    local file="$1"
    local cid
    cid="$(jq -r '.chain' "$file")"
    echo "== ${file} (chain ${cid}) =="

    if [[ "$cid" == "4217" ]]; then
        echo "Tempo chain: routing to verify-tempo-contracts.ts"
        pnpm verify:tempo:mainnet "$file"
        return
    fi

    local zksync=""
    if [[ "$cid" == "324" || "$cid" == "2741" ]]; then
        if ! forge build --help 2>/dev/null | grep -q -- --zksync; then
            echo "chain ${cid} is zksync-stack: run 'foundryup-zksync' first, then re-run this script." >&2
            return 1
        fi
        zksync="--zksync"
    fi

    local rc=0
    local lib_flags
    lib_flags="$(libraries_flags_from "$file")"
    while IFS=$'\t' read -r name addr args_json; do
        local fqn ctor_sig ctor_args=""
        fqn="$(fqn_for "$name")" || { echo "skip unknown contract ${name} @ ${addr}"; continue; }
        if is_library "$name"; then
            ctor_sig=""
        else
            ctor_sig="$(ctor_sig_for "$name")"
        fi
        if [[ -n "$ctor_sig" && "$args_json" != "null" && "$args_json" != "[]" ]]; then
            # shellcheck disable=SC2046
            ctor_args="$(cast abi-encode "$ctor_sig" $(jq -r '.[]' <<<"$args_json"))"
        fi
        local vargs
        if [[ "$cid" == "324" ]]; then
            vargs="--verifier zksync --verifier-url https://zksync2-mainnet-explorer.zksync.io/contract_verification"
        elif [[ "$cid" == "2741" ]]; then
            vargs="--verifier zksync --verifier-url https://api-explorer-verify.mainnet.abs.xyz/contract_verification"
        else
            vargs="$(verifier_args_for_chain "$cid")" || { echo "no verifier route for chain ${cid}" >&2; return 1; }
        fi
        echo "-- verifying ${name} @ ${addr}"
        # shellcheck disable=SC2086
        if ! forge verify-contract "$addr" "$fqn" \
                --chain "$cid" $zksync $vargs $lib_flags \
                ${ctor_args:+--constructor-args "$ctor_args"} \
                --watch; then
            echo "FAILED: ${name} @ ${addr} on chain ${cid}" >&2
            rc=1
        fi
    done < <(jq -r '.transactions[] | select(.transactionType == "CREATE" or .transactionType == "CREATE2") | [.contractName, .contractAddress, (.arguments | tojson)] | @tsv' "$file")
    return $rc
}

overall=0
if [[ "${1:-}" == "--all" ]]; then
    found=0
    while IFS= read -r f; do
        found=1
        verify_broadcast_file "$f" || overall=1
    done < <(find broadcast -path "*UpgradeV120*" -name run-latest.json ! -path "*dry-run*" | sort)
    [[ $found == 1 ]] || { echo "no UpgradeV120 broadcast files found" >&2; exit 1; }
else
    [[ $# -ge 1 && -f "$1" ]] || { echo "usage: $0 <run-latest.json> | --all" >&2; exit 1; }
    verify_broadcast_file "$1" || overall=1
fi
exit $overall
