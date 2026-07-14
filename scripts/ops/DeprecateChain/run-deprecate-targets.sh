#!/usr/bin/env bash
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

SCRIPT_PATH="scripts/ops/DeprecateChain/DeprecateChain.s.sol"
CONFIG_PATH="scripts/L0Config.json"

DEPRECATE_CHAIN_ID="${DEPRECATE_CHAIN_ID:-}"
SKIP_DEPRECATE_CHAIN_SIM="${SKIP_DEPRECATE_CHAIN_SIM:-}"
TARGET_CHAIN_IDS="${TARGET_CHAIN_IDS:-}"
EXCLUDE_CHAIN_IDS="${EXCLUDE_CHAIN_IDS:-}"
KEEP_EXISTING="${KEEP_EXISTING:-true}"
CLEAN_EXISTING="${CLEAN_EXISTING:-false}"

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
  echo "                             Default: all Proxy peers except DEPRECATE_CHAIN_ID, plus all Non-EVM chain ids."
  echo "  EXCLUDE_CHAIN_IDS           Optional comma-separated chain ids to skip from the resolved targets."
  echo "  KEEP_EXISTING               Optional false/0 to delete prior generated JSONs for this deprecate chain."
  echo "                             Defaults to true."
  echo "  CLEAN_EXISTING              Optional true/1 alias to delete prior generated JSONs."
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

target_chain_ids_from_config() {
  jq -r --argjson deprecate "${DEPRECATE_CHAIN_ID}" '
    (
      [ .Proxy[] | select(.chainid != $deprecate) | .chainid ] +
      [ .["Non-EVM"][] | .chainid ]
    )
    | unique
    | .[]
  ' "${CONFIG_PATH}"
}

contains_chain_id() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
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
  echo "DEPRECATE_CHAIN_ID is required." >&2
  usage
  exit 2
fi

if [[ -z "${SKIP_DEPRECATE_CHAIN_SIM}" ]]; then
  SKIP_DEPRECATE_CHAIN_SIM="${DEPRECATE_CHAIN_ID}"
fi

deprecate_out_dir="${OUT_DIR_ROOT}/deprecate-${DEPRECATE_CHAIN_ID}"
mkdir -p "${deprecate_out_dir}"

case "${CLEAN_EXISTING}" in
  true|TRUE|1)
    find "${deprecate_out_dir}" -maxdepth 1 -type f -name 'Deprecate-*.json' -delete
    ;;
  *)
    case "${KEEP_EXISTING}" in
      false|FALSE|0)
        find "${deprecate_out_dir}" -maxdepth 1 -type f -name 'Deprecate-*.json' -delete
        ;;
    esac
    ;;
esac

declare -a targets=()
if [[ -n "${TARGET_CHAIN_IDS}" ]]; then
  IFS=',' read -r -a targets <<< "${TARGET_CHAIN_IDS}"
else
  while IFS= read -r cid; do
    [[ -n "${cid}" ]] && targets+=("${cid}")
  done < <(target_chain_ids_from_config)
fi

if [[ -n "${EXCLUDE_CHAIN_IDS}" ]]; then
  IFS=',' read -r -a excluded <<< "${EXCLUDE_CHAIN_IDS}"
  declare -a filtered=()
  for cid in "${targets[@]}"; do
    if ! contains_chain_id "${cid}" "${excluded[@]}"; then
      filtered+=("${cid}")
    fi
  done
  targets=("${filtered[@]}")
fi

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "No target chain ids resolved." >&2
  exit 1
fi

failures=0
declare -a failed_targets=()
for target_chain_id in "${targets[@]}"; do
  echo
  echo "=== TARGET_CHAIN_ID=${target_chain_id} ==="
  if DEPRECATE_CHAIN_ID="${DEPRECATE_CHAIN_ID}" \
     SKIP_DEPRECATE_CHAIN_SIM="${SKIP_DEPRECATE_CHAIN_SIM}" \
     TARGET_CHAIN_ID="${target_chain_id}" \
     forge script "${SCRIPT_PATH}" --ffi; then
    echo "OK  TARGET_CHAIN_ID=${target_chain_id}"
  else
    echo "FAIL TARGET_CHAIN_ID=${target_chain_id}" >&2
    failed_targets+=("${target_chain_id}")
    failures=$((failures + 1))
  fi
done

echo
if [[ ${failures} -gt 0 ]]; then
  echo "Failed TARGET_CHAIN_ID values:"
  printf '%s\n' "${failed_targets[@]}"
  exit 1
fi

echo "All TARGET_CHAIN_ID runs succeeded."
