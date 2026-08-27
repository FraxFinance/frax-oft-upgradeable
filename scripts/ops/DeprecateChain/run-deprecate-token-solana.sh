#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CONFIG_PATH="scripts/L0Config.json"
TASK="lz:oft:solana:deprecate-peer:squads"

DEPRECATE_TOKEN="${DEPRECATE_TOKEN:-}"
TARGET_CHAIN_IDS="${TARGET_CHAIN_IDS:-}"
EXCLUDE_CHAIN_IDS="${EXCLUDE_CHAIN_IDS:-}"
DRY_RUN="${DRY_RUN:-false}"
SOLANA_EID="${SOLANA_EID:-30168}"

OUT_DIR_ROOT="scripts/ops/DeprecateChain/txs"

usage() {
  echo "Usage: DEPRECATE_TOKEN=<SYMBOL> [TARGET_CHAIN_IDS=csv] [DRY_RUN=true] $0"
  echo
  echo "Generates the Solana-side (Solana -> EVM) half of a token deprecation, one Squads"
  echo "transaction per remote chain. The EVM -> Solana half comes from run-deprecate-token.sh;"
  echo "both halves are needed to fully sever a route."
  echo
  echo "The underlying task self-guards: routes with nothing left to do report SKIP and write"
  echo "no file, so running across every chain is safe."
  echo
  echo "Environment:"
  echo "  DEPRECATE_TOKEN    Required. WFRAX|SFRXUSD|SFRXETH|FRXUSD|FRXETH|FPI."
  echo "  TARGET_CHAIN_IDS   Optional csv of remote EVM chain ids. Defaults to all Proxy chains."
  echo "  EXCLUDE_CHAIN_IDS  Optional csv of chain ids to skip."
  echo "  DRY_RUN            true to plan without writing files. Default false."
  echo "  SOLANA_EID         Source Solana endpoint id. Default 30168 (mainnet)."
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

require_cmd jq
require_cmd pnpm

if [[ -z "${DEPRECATE_TOKEN}" ]]; then
  echo "DEPRECATE_TOKEN is required." >&2
  usage
  exit 2
fi

case "${DEPRECATE_TOKEN}" in
  WFRAX|SFRXUSD|SFRXETH|FRXUSD|FRXETH|FPI) ;;
  *)
    echo "DEPRECATE_TOKEN must be one of WFRAX|SFRXUSD|SFRXETH|FRXUSD|FRXETH|FPI: ${DEPRECATE_TOKEN}" >&2
    exit 2
    ;;
esac

# The Solana task names tokens in lowercase (see TOKEN_DEPLOYMENTS in deprecatePeerSquads.ts).
solana_token="$(echo "${DEPRECATE_TOKEN}" | tr '[:upper:]' '[:lower:]')"
out_dir="${OUT_DIR_ROOT}/deprecate-${DEPRECATE_TOKEN}/solana"

declare -A excluded_chain_ids=()
if [[ -n "${EXCLUDE_CHAIN_IDS}" ]]; then
  IFS=',' read -r -a excluded <<< "${EXCLUDE_CHAIN_IDS}"
  for cid in "${excluded[@]}"; do
    cid="${cid//[[:space:]]/}"
    [[ -n "${cid}" ]] && excluded_chain_ids["${cid}"]=1
  done
fi

# Emit "chainid eid" pairs so the task gets the eid while output stays named by chain id.
mapfile -t chain_eid_pairs < <(jq -r '.Proxy[] | "\(.chainid) \(.eid)"' "${CONFIG_PATH}")

declare -a selected=()
if [[ -n "${TARGET_CHAIN_IDS}" ]]; then
  IFS=',' read -r -a wanted <<< "${TARGET_CHAIN_IDS}"
  declare -A wanted_ids=()
  for cid in "${wanted[@]}"; do
    cid="${cid//[[:space:]]/}"
    [[ -n "${cid}" ]] && wanted_ids["${cid}"]=1
  done
  for pair in "${chain_eid_pairs[@]}"; do
    cid="${pair%% *}"
    [[ -n "${wanted_ids[$cid]:-}" ]] && selected+=("${pair}")
  done
else
  selected=("${chain_eid_pairs[@]}")
fi

declare -a targets=()
for pair in "${selected[@]}"; do
  cid="${pair%% *}"
  [[ -n "${excluded_chain_ids[$cid]:-}" ]] && continue
  targets+=("${pair}")
done

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "No target chain ids resolved." >&2
  exit 1
fi

[[ "${DRY_RUN}" =~ ^(true|TRUE|1)$ ]] && dry_flag="--dry-run" || dry_flag=""
[[ -n "${dry_flag}" ]] || mkdir -p "${out_dir}"

failures=0
declare -a failed_targets=()
declare -a wrote=()
declare -a skipped=()

echo "Solana-side ${DEPRECATE_TOKEN} deprecation across ${#targets[@]} remote chain(s).${dry_flag:+ (dry run)}"
for pair in "${targets[@]}"; do
  chain_id="${pair%% *}"
  eid="${pair##* }"
  echo
  echo "=== toChainId=${chain_id} toEid=${eid} ==="

  # shellcheck disable=SC2086
  if output="$(pnpm hardhat "${TASK}" \
       --to-eid "${eid}" \
       --to-chain-id "${chain_id}" \
       --tokens "${solana_token}" \
       --out-dir "${out_dir}" \
       ${dry_flag} 2>&1)"; then
    echo "${output}" | grep -E "^(PLAN|WRITE|SKIP) " || true
    if echo "${output}" | grep -qE "^(PLAN|WRITE) "; then
      wrote+=("${chain_id}")
    else
      skipped+=("${chain_id}")
    fi
  else
    echo "FAIL toChainId=${chain_id}" >&2
    echo "${output}" | tail -5 >&2
    failed_targets+=("${chain_id}")
    failures=$((failures + 1))
  fi
done

echo
echo "Solana-side routes needing action: ${#wrote[@]}${wrote:+ (${wrote[*]})}"
echo "Already clean / nothing to do:     ${#skipped[@]}"
if [[ ${failures} -gt 0 ]]; then
  echo "Failed chain ids:"
  printf '%s\n' "${failed_targets[@]}"
  echo
  echo "Re-run just those with:"
  echo "  DEPRECATE_TOKEN=${DEPRECATE_TOKEN} TARGET_CHAIN_IDS=$(IFS=,; echo "${failed_targets[*]}") $0"
  exit 1
fi

echo "All Solana-side runs completed."
