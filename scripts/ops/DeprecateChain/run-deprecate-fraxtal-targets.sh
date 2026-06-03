#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SCRIPT_PATH="scripts/ops/DeprecateChain/DeprecateChain.s.sol"
TX_DIR="scripts/ops/DeprecateChain/txs"
SESSION_FILES_MANIFEST="${SESSION_FILES_MANIFEST:-${TX_DIR}/.generated-this-session.txt}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900s}"
CLEAN_OUTPUT="${CLEAN_OUTPUT:-1}"
BYPASS_CHAIN_CALLS="${BYPASS_CHAIN_CALLS:-0}"
INCLUDE_SPOKES="${INCLUDE_SPOKES:-1}"

# Fraxtal disconnect targets requested by user
TARGET_EVM_CHAIN_IDS=(34443 534352 80094)
TARGET_NON_EVM_EIDS=(30108 30325)

usage() {
  echo "Usage: $0 [--no-clean] [--timeout <dur>] [--session-files <path>]"
  echo
  echo "Generates DeprecateChain Safe JSONs for Fraxtal <-> {Mode, Scroll, Berachain}."
  echo "Also validates whether Fraxtal->{Aptos,Movement} JSONs exist in this session output."
  echo
  echo "Options:"
  echo "  --no-clean             Keep existing Deprecate JSON files"
  echo "  --timeout <dur>        Timeout per chain run (default: ${TIMEOUT_SECONDS})"
  echo "  --session-files <p>    Output session manifest path"
  echo "  -h, --help             Show help"
  echo
  echo "Environment:"
  echo "  CLEAN_OUTPUT=0|1             Remove untracked Deprecate-*.json before run (default: 1)"
  echo "  TIMEOUT_SECONDS=<dur>        Timeout passed to timeout(1) per chain run"
  echo "  BYPASS_CHAIN_CALLS=0|1       Forwarded to forge script (default: 0)"
  echo "  INCLUDE_SPOKES=0|1           Forwarded to forge script (default: 1)"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

safe_clean_outputs() {
  local chain_id
  local f

  for chain_id in "${TARGET_EVM_CHAIN_IDS[@]}"; do
    while IFS= read -r f; do
      if git ls-files --error-unmatch "${f}" >/dev/null 2>&1; then
        continue
      fi
      rm -f "${f}"
    done < <(find "${TX_DIR}" -maxdepth 1 -type f \( -name "Deprecate-${chain_id}-252-*.json" -o -name "Deprecate-252-${chain_id}-*.json" \))
  done
}

rpc_for_chain() {
  local chain_id="$1"
  jq -er --argjson cid "${chain_id}" '[.Proxy[], .Legacy[]] | map(select(.chainid == $cid)) | .[0].RPC' scripts/L0Config.json 2>/dev/null
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-clean)
      CLEAN_OUTPUT=0
      ;;
    --timeout)
      shift
      TIMEOUT_SECONDS="${1:-}"
      [[ -n "${TIMEOUT_SECONDS}" ]] || { echo "--timeout requires a value" >&2; exit 2; }
      ;;
    --session-files)
      shift
      SESSION_FILES_MANIFEST="${1:-}"
      [[ -n "${SESSION_FILES_MANIFEST}" ]] || { echo "--session-files requires a value" >&2; exit 2; }
      ;;
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
  shift
done

require_cmd jq
require_cmd timeout
require_cmd forge

mkdir -p "${TX_DIR}"

if [[ "${CLEAN_OUTPUT}" == "1" ]]; then
  echo "Cleaning untracked Deprecate JSON outputs in ${TX_DIR}"
  safe_clean_outputs
fi

marker_file="$(mktemp)"

for chain_id in "${TARGET_EVM_CHAIN_IDS[@]}"; do
  rpc_url="$(rpc_for_chain "${chain_id}" || true)"
  if [[ -z "${rpc_url}" ]]; then
    echo "Could not resolve RPC for chain ${chain_id} from scripts/L0Config.json" >&2
    rm -f "${marker_file}"
    exit 1
  fi

  echo "Running ${SCRIPT_PATH} for chain ${chain_id}"
  echo "RPC: ${rpc_url}"

  BYPASS_CHAIN_CALLS="${BYPASS_CHAIN_CALLS}" INCLUDE_SPOKES="${INCLUDE_SPOKES}" RUST_LOG=error \
    timeout "${TIMEOUT_SECONDS}" forge script "${SCRIPT_PATH}" --rpc-url "${rpc_url}" --ffi --quiet --disable-labels

done

find "${TX_DIR}" -maxdepth 1 -type f -name "Deprecate-*.json" -newer "${marker_file}" | sort > "${SESSION_FILES_MANIFEST}"
rm -f "${marker_file}"

echo "Session manifest: ${SESSION_FILES_MANIFEST}"
echo "Session file count: $(wc -l < "${SESSION_FILES_MANIFEST}" | tr -d ' ')"

printf "\nGenerated files in this session:\n"
cat "${SESSION_FILES_MANIFEST}"

# Validate expected Fraxtal-side non-EVM files are present if supported by script logic.
missing_non_evm=0
for eid in "${TARGET_NON_EVM_EIDS[@]}"; do
  if ! grep -Eq "Deprecate-252-${eid}(-|\\.)" "${SESSION_FILES_MANIFEST}"; then
    echo "Warning: no Fraxtal->EID ${eid} file generated in this session."
    missing_non_evm=1
  fi
done

if [[ "${missing_non_evm}" == "1" ]]; then
  echo "Note: current ${SCRIPT_PATH} may not emit Aptos/Movement files; only EVM pair files were guaranteed."
fi

echo "Done."
