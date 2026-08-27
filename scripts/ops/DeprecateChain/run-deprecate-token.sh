#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SCRIPT_PATH="scripts/ops/DeprecateChain/DeprecateToken.s.sol"
CONFIG_PATH="scripts/L0Config.json"

DEPRECATE_TOKEN="${DEPRECATE_TOKEN:-}"
SOURCE_CHAIN_IDS="${SOURCE_CHAIN_IDS:-}"
EXCLUDE_CHAIN_IDS="${EXCLUDE_CHAIN_IDS:-}"
KEEP_EXISTING="${KEEP_EXISTING:-true}"
CLEAN_EXISTING="${CLEAN_EXISTING:-false}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-0}"
RETRIES="${RETRIES:-1}"

OUT_DIR_ROOT="scripts/ops/DeprecateChain/txs"

usage() {
  echo "Usage: DEPRECATE_TOKEN=<SYMBOL> [SOURCE_CHAIN_IDS=csv] [EXCLUDE_CHAIN_IDS=csv] $0"
  echo
  echo "Deprecates one token across the mesh, one source chain per forge invocation."
  echo "Each chunk forks exactly one RPC, so a rate-limited or dead chain fails only its"
  echo "own chunk. Failures are collected and reported at the end; the run continues."
  echo
  echo "Environment:"
  echo "  DEPRECATE_TOKEN     Required. WFRAX|SFRXUSD|SFRXETH|FRXUSD|FRXETH|FPI."
  echo "  SOURCE_CHAIN_IDS    Optional csv override. Defaults to all Proxy chain ids."
  echo "  EXCLUDE_CHAIN_IDS   Optional csv of chain ids to skip."
  echo "  KEEP_EXISTING       Optional false/0 to delete prior JSONs for this token. Default true."
  echo "  CLEAN_EXISTING      Optional true/1 alias for the above."
  echo "  RETRIES             Attempts per chain before recording a failure. Default 1."
  echo "  SLEEP_BETWEEN       Seconds to sleep between chains. Use to pace free-tier RPCs."
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

# ZKsync-family chains need the zksync codegen path, matching run-deprecate-targets.sh.
is_zksync_chain() {
  case "$1" in
    2741|324) return 0 ;;
    *) return 1 ;;
  esac
}

# `forge --zksync` reverts inside the vm.serialize* cheatcodes, so SafeTxUtil cannot write files
# at all on ZKsync-family chains. There it logs the equivalent JSON instead (SAFE_TX_CONSOLE_JSON),
# and this extracts those blocks into the same files a normal chain would have written.
EXTRACTOR="scripts/ops/DeprecateChain/extract-console-safe-json.py"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

require_cmd jq
require_cmd forge

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

mapfile -t allowed_sources < <(jq -r '[ .Proxy[] | .chainid ] | unique | .[]' "${CONFIG_PATH}")
declare -A allowed_source_chain_ids=()
for cid in "${allowed_sources[@]}"; do
  allowed_source_chain_ids["${cid}"]=1
done

declare -a sources=()
if [[ -n "${SOURCE_CHAIN_IDS}" ]]; then
  IFS=',' read -r -a sources <<< "${SOURCE_CHAIN_IDS}"
else
  sources=("${allowed_sources[@]}")
fi

declare -A excluded_chain_ids=()
if [[ -n "${EXCLUDE_CHAIN_IDS}" ]]; then
  IFS=',' read -r -a excluded <<< "${EXCLUDE_CHAIN_IDS}"
  for cid in "${excluded[@]}"; do
    cid="${cid//[[:space:]]/}"
    [[ -n "${cid}" ]] && excluded_chain_ids["${cid}"]=1
  done
fi

declare -A seen_source_chain_ids=()
declare -a filtered_sources=()
for cid in "${sources[@]}"; do
  cid="${cid//[[:space:]]/}"
  if [[ ! "${cid}" =~ ^[0-9]+$ ]]; then
    echo "Invalid SOURCE_CHAIN_IDS entry: ${cid:-<empty>}" >&2
    exit 2
  fi
  if [[ -z "${allowed_source_chain_ids[$cid]:-}" ]]; then
    echo "SOURCE_CHAIN_IDS entry ${cid} is not a Proxy chain id." >&2
    exit 2
  fi
  if [[ -n "${excluded_chain_ids[$cid]:-}" || -n "${seen_source_chain_ids[$cid]:-}" ]]; then
    continue
  fi
  seen_source_chain_ids["${cid}"]=1
  filtered_sources+=("${cid}")
done
sources=("${filtered_sources[@]}")

if [[ ${#sources[@]} -eq 0 ]]; then
  echo "No source chain ids resolved." >&2
  exit 1
fi

token_out_dir="${OUT_DIR_ROOT}/deprecate-${DEPRECATE_TOKEN}"
mkdir -p "${token_out_dir}"

if [[ "${CLEAN_EXISTING}" =~ ^(true|TRUE|1)$ || "${KEEP_EXISTING}" =~ ^(false|FALSE|0)$ ]]; then
  find "${token_out_dir}" -type f -name 'Deprecate-*.json' -delete
fi

failures=0
declare -a failed_sources=()
declare -a skipped_unforkable=()
readonly -a base_forge_args=(script "${SCRIPT_PATH}" --ffi)
readonly zksync_source_dir="$(dirname "${SCRIPT_PATH}")"

echo "Deprecating ${DEPRECATE_TOKEN} across ${#sources[@]} source chain(s)."
for source_chain_id in "${sources[@]}"; do
  echo
  echo "=== SOURCE_CHAIN_ID=${source_chain_id} ==="

  # ZKsync Era / Abstract revert under `forge --zksync` before any batch is produced, for a
  # reason that is still undiagnosed (console.log and string.concat were both ruled out).
  # Rather than emit a passing-looking chunk that silently wrote nothing, skip them here and
  # point at the generator that reads their state over plain eth_calls.
  if is_zksync_chain "${source_chain_id}"; then
    echo "SKIP SOURCE_CHAIN_ID=${source_chain_id}: cannot be fork-simulated."
    echo "     generate with: python3 scripts/ops/DeprecateChain/generate-unforkable-batches.py --write"
    skipped_unforkable+=("${source_chain_id}")
    continue
  fi

  console_json=false
  current_forge_args=("${base_forge_args[@]}")
  current_foundry_src="${FOUNDRY_SRC:-scripts}"

  attempt=1
  ok=0
  while [[ ${attempt} -le ${RETRIES} ]]; do
    if [[ ${attempt} -gt 1 ]]; then
      echo "retry ${attempt}/${RETRIES} for ${source_chain_id}"
    fi
    if [[ "${console_json}" == "true" ]]; then
      # Capture stdout so the logged JSON can be extracted. Extraction runs on failure too:
      # a chunk that dies partway still logged complete blocks for the routes it finished.
      run_log="$(mktemp)"
      if FOUNDRY_SRC="${current_foundry_src}" \
         DEPRECATE_TOKEN="${DEPRECATE_TOKEN}" \
         SOURCE_CHAIN_ID="${source_chain_id}" \
         SAFE_TX_CONSOLE_JSON=true \
         forge "${current_forge_args[@]}" >"${run_log}" 2>&1; then
        python3 "${EXTRACTOR}" <"${run_log}"
        rm -f "${run_log}"
        ok=1
        break
      fi
      python3 "${EXTRACTOR}" <"${run_log}" || true
      tail -5 "${run_log}" >&2
      rm -f "${run_log}"
    else
      if FOUNDRY_SRC="${current_foundry_src}" \
         DEPRECATE_TOKEN="${DEPRECATE_TOKEN}" \
         SOURCE_CHAIN_ID="${source_chain_id}" \
         forge "${current_forge_args[@]}"; then
        ok=1
        break
      fi
    fi
    attempt=$((attempt + 1))
    [[ ${attempt} -le ${RETRIES} ]] && sleep "${SLEEP_BETWEEN:-0}"
  done

  if [[ ${ok} -eq 1 ]]; then
    echo "OK  SOURCE_CHAIN_ID=${source_chain_id}"
  else
    echo "FAIL SOURCE_CHAIN_ID=${source_chain_id}" >&2
    failed_sources+=("${source_chain_id}")
    failures=$((failures + 1))
  fi

  [[ "${SLEEP_BETWEEN}" != "0" ]] && sleep "${SLEEP_BETWEEN}"
done

echo
echo "Batches written: $(find "${token_out_dir}" -type f -name 'Deprecate-*.json' | wc -l)"
if [[ ${#skipped_unforkable[@]} -gt 0 ]]; then
  echo "Not fork-simulatable (generate separately): ${skipped_unforkable[*]}"
fi
if [[ ${failures} -gt 0 ]]; then
  echo "Failed SOURCE_CHAIN_ID values:"
  printf '%s\n' "${failed_sources[@]}"
  echo
  echo "Re-run just those with:"
  echo "  DEPRECATE_TOKEN=${DEPRECATE_TOKEN} SOURCE_CHAIN_IDS=$(IFS=,; echo "${failed_sources[*]}") $0"
  exit 1
fi

echo "All SOURCE_CHAIN_ID runs succeeded."
