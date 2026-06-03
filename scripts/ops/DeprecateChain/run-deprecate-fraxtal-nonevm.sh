#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SCRIPT_PATH="scripts/ops/DeprecateChain/DeprecateChainNonEvm.s.sol"
TX_DIR="scripts/ops/DeprecateChain/txs"
SESSION_FILES_MANIFEST="${SESSION_FILES_MANIFEST:-${TX_DIR}/.generated-nonevm-this-session.txt}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900s}"
CLEAN_OUTPUT="${CLEAN_OUTPUT:-1}"
RPC_URL="${RPC_URL:-}"

usage() {
  echo "Usage: $0 [--rpc-url <url>] [--no-clean]"
  echo
  echo "Runs DeprecateChainNonEvm forge script to generate Fraxtal->Aptos/Movement Safe tx JSON files."
  echo
  echo "Options:"
  echo "  --rpc-url <url>   RPC URL to use (default: fraxtal RPC from scripts/L0Config.json, then https://rpc.frax.com)"
  echo "  --no-clean        Keep existing non-EVM Deprecate JSON files"
  echo "  -h, --help        Show help"
}

clean_nonevm_outputs() {
  local f
  while IFS= read -r f; do
    if git ls-files --error-unmatch "${f}" >/dev/null 2>&1; then
      continue
    fi
    rm -f "${f}"
  done < <(find "${TX_DIR}" -maxdepth 1 -type f \( -name "Deprecate-252-30108-*.json" -o -name "Deprecate-252-30325-*.json" \))
}

write_session_manifest() {
  local marker="$1"
  find "${TX_DIR}" -maxdepth 1 -type f \( -name "Deprecate-252-30108-*.json" -o -name "Deprecate-252-30325-*.json" \) -newer "${marker}" | sort > "${SESSION_FILES_MANIFEST}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc-url)
      shift
      RPC_URL="${1:-}"
      if [[ -z "${RPC_URL}" ]]; then
        echo "--rpc-url requires a value" >&2
        exit 2
      fi
      ;;
    --no-clean)
      CLEAN_OUTPUT=0
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

if [[ -z "${RPC_URL}" ]]; then
  if command -v jq >/dev/null 2>&1 && [[ -f scripts/L0Config.json ]]; then
    RPC_URL="$(jq -er '[.Proxy[], .Legacy[]] | map(select(.chainid == 252)) | .[0].RPC' scripts/L0Config.json 2>/dev/null || true)"
  fi
fi

if [[ -z "${RPC_URL}" ]]; then
  RPC_URL="https://rpc.frax.com"
fi

mkdir -p "${TX_DIR}"

if [[ "${CLEAN_OUTPUT}" == "1" ]]; then
  echo "Cleaning untracked non-EVM Deprecate JSON outputs in ${TX_DIR}"
  clean_nonevm_outputs
fi

echo "Running ${SCRIPT_PATH}"
echo "RPC: ${RPC_URL}"

marker_file="$(mktemp)"

RUST_LOG=error \
  timeout "${TIMEOUT_SECONDS}" \
  forge script "${SCRIPT_PATH}" \
    --rpc-url "${RPC_URL}" \
    --ffi \
    --quiet \
    --disable-labels

write_session_manifest "${marker_file}"
rm -f "${marker_file}"

echo "Session manifest: ${SESSION_FILES_MANIFEST}"
echo "Session file count: $(wc -l < "${SESSION_FILES_MANIFEST}" | tr -d ' ')"

echo "Done. Generated non-EVM files:"
cat "${SESSION_FILES_MANIFEST}"
