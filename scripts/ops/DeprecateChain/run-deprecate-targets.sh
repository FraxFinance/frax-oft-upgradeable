#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SCRIPT_PATH="scripts/ops/DeprecateChain/DeprecateChain.s.sol"
MOVE_SCRIPT_PATH="scripts/ops/DeprecateChain/generate-move-side.ts"
CONFIG_PATH="scripts/L0Config.json"

DEPRECATE_CHAIN_ID="${DEPRECATE_CHAIN_ID:-}"
SKIP_DEPRECATE_CHAIN_SIM="${SKIP_DEPRECATE_CHAIN_SIM:-}"
TARGET_CHAIN_IDS="${TARGET_CHAIN_IDS:-}"
EXCLUDE_CHAIN_IDS="${EXCLUDE_CHAIN_IDS:-}"
KEEP_EXISTING="${KEEP_EXISTING:-true}"
CLEAN_EXISTING="${CLEAN_EXISTING:-false}"
SKIP_MOVE_SIDE="${SKIP_MOVE_SIDE:-${SKIP_APTOS_SIDE:-false}}"

OUT_DIR_ROOT="scripts/ops/DeprecateChain/txs"

usage() {
  echo "Usage: DEPRECATE_CHAIN_ID=<chainid> [SKIP_DEPRECATE_CHAIN_SIM=<true|1|chainid>] [TARGET_CHAIN_IDS=comma,separated] [EXCLUDE_CHAIN_IDS=comma,separated] $0"
  echo
  echo "Iterates TARGET_CHAIN_ID for DeprecateChain.s.sol and continues on failures."
  echo "Failures are printed to console."
  echo
  echo "Environment:"
  echo "  DEPRECATE_CHAIN_ID          Required. Deprecate source chain id."
  echo "  SKIP_DEPRECATE_CHAIN_SIM    Optional. Defaults to DEPRECATE_CHAIN_ID."
  echo "  TARGET_CHAIN_IDS            Optional comma-separated override list."
  echo "                             EVM default: all other Proxy and Non-EVM chain ids."
  echo "                             Non-EVM default: all Proxy execution-chain ids."
  echo "  EXCLUDE_CHAIN_IDS           Optional comma-separated chain ids to skip from the resolved targets."
  echo "  KEEP_EXISTING               Optional false/0 to delete prior generated JSONs for this deprecate chain."
  echo "                             Defaults to true."
  echo "  CLEAN_EXISTING              Optional true/1 alias to delete prior generated JSONs."
  echo "  SKIP_MOVE_SIDE              Optional true/1 to skip Aptos/Movement-side payload generation."
  echo "                             SKIP_APTOS_SIDE remains supported as a legacy alias."
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

resolve_deprecate_chain() {
  jq -er --argjson deprecate "${DEPRECATE_CHAIN_ID}" '
    if any(.Proxy[]; .chainid == $deprecate) then
      "evm"
    elif any(.["Non-EVM"][]; .chainid == $deprecate) then
      "non-evm"
    else
      error("chain not found")
    end
  ' "${CONFIG_PATH}"
}

default_target_chain_ids() {
  jq -r --argjson deprecate "${DEPRECATE_CHAIN_ID}" --arg kind "${deprecate_chain_kind}" '
    if $kind == "non-evm" then
      # A non-EVM destination cannot execute EVM calldata. Its targets are the
      # EVM chains on which the outbound route cleanup must be performed.
      [ .Proxy[] | .chainid ]
    else
      [ .Proxy[] | select(.chainid != $deprecate) | .chainid ] +
      [ .["Non-EVM"][] | select(.chainid != $deprecate) | .chainid ]
    end
    | unique
    | .[]
  ' "${CONFIG_PATH}"
}

is_zksync_chain() {
  case "$1" in
    2741|324)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

require_cmd jq
require_cmd forge

if [[ -z "${DEPRECATE_CHAIN_ID}" ]]; then
  if [[ -n "${EPRECATE_CHAIN_ID:-}" ]]; then
    echo "DEPRECATE_CHAIN_ID is required (did you mean DEPRECATE_CHAIN_ID instead of EPRECATE_CHAIN_ID?)." >&2
  else
    echo "DEPRECATE_CHAIN_ID is required." >&2
  fi
  usage
  exit 2
fi

if [[ ! "${DEPRECATE_CHAIN_ID}" =~ ^[0-9]+$ ]]; then
  echo "DEPRECATE_CHAIN_ID must be a numeric chain id: ${DEPRECATE_CHAIN_ID}" >&2
  exit 2
fi

if ! deprecate_chain_kind="$(resolve_deprecate_chain)"; then
  echo "DEPRECATE_CHAIN_ID ${DEPRECATE_CHAIN_ID} was not found in Proxy or Non-EVM config." >&2
  exit 2
fi

if [[ -z "${SKIP_DEPRECATE_CHAIN_SIM}" ]]; then
  SKIP_DEPRECATE_CHAIN_SIM="${DEPRECATE_CHAIN_ID}"
fi

if [[ "${deprecate_chain_kind}" == "non-evm" ]]; then
  # The configured chain id is a JSON placeholder, not an EVM RPC chain id.
  # DeprecateChain.s.sol will only simulate the EVM source-chain side.
  SKIP_DEPRECATE_CHAIN_SIM=true
  echo "Non-EVM deprecation target ${DEPRECATE_CHAIN_ID}: generating EVM-side cleanup only."
fi

mapfile -t allowed_targets < <(default_target_chain_ids)
declare -A allowed_target_chain_ids=()
for cid in "${allowed_targets[@]}"; do
  allowed_target_chain_ids["${cid}"]=1
done

declare -a targets=()
if [[ -n "${TARGET_CHAIN_IDS}" ]]; then
  IFS=',' read -r -a targets <<< "${TARGET_CHAIN_IDS}"
else
  targets=("${allowed_targets[@]}")
fi

declare -A excluded_chain_ids=()
if [[ -n "${EXCLUDE_CHAIN_IDS}" ]]; then
  IFS=',' read -r -a excluded <<< "${EXCLUDE_CHAIN_IDS}"
  for cid in "${excluded[@]}"; do
    cid="${cid//[[:space:]]/}"
    [[ -n "${cid}" ]] && excluded_chain_ids["${cid}"]=1
  done
fi

declare -A seen_target_chain_ids=()
declare -a filtered_targets=()
for cid in "${targets[@]}"; do
  cid="${cid//[[:space:]]/}"
  if [[ ! "${cid}" =~ ^[0-9]+$ ]]; then
    echo "Invalid TARGET_CHAIN_IDS entry: ${cid:-<empty>}" >&2
    exit 2
  fi
  if [[ -z "${allowed_target_chain_ids[$cid]:-}" ]]; then
    echo "TARGET_CHAIN_IDS entry ${cid} is not a valid counterpart for ${DEPRECATE_CHAIN_ID}." >&2
    exit 2
  fi
  if [[ -n "${excluded_chain_ids[$cid]:-}" || -n "${seen_target_chain_ids[$cid]:-}" ]]; then
    continue
  fi
  seen_target_chain_ids["${cid}"]=1
  filtered_targets+=("${cid}")
done
targets=("${filtered_targets[@]}")

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "No target chain ids resolved." >&2
  exit 1
fi

deprecate_out_dir="${OUT_DIR_ROOT}/deprecate-${DEPRECATE_CHAIN_ID}"
mkdir -p "${deprecate_out_dir}"

if [[ "${CLEAN_EXISTING}" =~ ^(true|TRUE|1)$ || "${KEEP_EXISTING}" =~ ^(false|FALSE|0)$ ]]; then
  find "${deprecate_out_dir}" -type f \( -name 'Deprecate-*.json' -o -name 'DeprecateAptos-*.json' -o -name 'DeprecateMovement-*.json' \) -delete
fi

failures=0
declare -a failed_targets=()
readonly -a forge_args=(script "${SCRIPT_PATH}" --ffi)
readonly -a zksync_forge_args=("${forge_args[@]}" --zksync)
readonly zksync_source_dir="$(dirname "${SCRIPT_PATH}")"

echo "Running ${#targets[@]} target chain(s)."
for target_chain_id in "${targets[@]}"; do
  echo
  echo "=== TARGET_CHAIN_ID=${target_chain_id} ==="

  if is_zksync_chain "${target_chain_id}"; then
    current_forge_args=("${zksync_forge_args[@]}")
    current_foundry_src="${zksync_source_dir}"
    echo "Using forge --zksync for ZKsync-family chain ${target_chain_id}."
  else
    current_forge_args=("${forge_args[@]}")
    current_foundry_src="${FOUNDRY_SRC:-${zksync_source_dir}}"
  fi

  # Full-project source discovery is unnecessarily large for this runner and can
  # exhaust or stall the compiler. Imports outside FOUNDRY_SRC remain included.
  if FOUNDRY_SRC="${current_foundry_src}" \
     DEPRECATE_CHAIN_ID="${DEPRECATE_CHAIN_ID}" \
     SKIP_DEPRECATE_CHAIN_SIM="${SKIP_DEPRECATE_CHAIN_SIM}" \
     TARGET_CHAIN_ID="${target_chain_id}" \
     forge "${current_forge_args[@]}"; then
    echo "OK  TARGET_CHAIN_ID=${target_chain_id}"
  else
    echo "FAIL TARGET_CHAIN_ID=${target_chain_id}" >&2
    failed_targets+=("${target_chain_id}")
    failures=$((failures + 1))
  fi
done

move_side_failed=0
if [[ "${DEPRECATE_CHAIN_ID}" =~ ^(22222222|33333333)$ && ! "${SKIP_MOVE_SIDE}" =~ ^(true|TRUE|1)$ ]]; then
  require_cmd pnpm
  target_csv="$(IFS=,; echo "${targets[*]}")"
  echo
  echo "=== MOVE-SIDE DEPRECATION (${DEPRECATE_CHAIN_ID}) ==="
  if ! pnpm exec ts-node "${MOVE_SCRIPT_PATH}" \
      --source-chain-id "${DEPRECATE_CHAIN_ID}" \
      --target-chain-ids "${target_csv}"; then
    echo "FAIL Move-side deprecation payload generation for ${DEPRECATE_CHAIN_ID}" >&2
    move_side_failed=1
  fi
fi

echo
if [[ ${failures} -gt 0 ]]; then
  echo "Failed TARGET_CHAIN_ID values:"
  printf '%s\n' "${failed_targets[@]}"
fi
if [[ ${failures} -gt 0 || ${move_side_failed} -ne 0 ]]; then
  exit 1
fi

echo "All TARGET_CHAIN_ID runs succeeded."
