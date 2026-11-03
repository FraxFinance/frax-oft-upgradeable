#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

TX_DIR="scripts/ops/DeprecateChain/txs"
CONFIG_PATH="scripts/L0Config.json"
SESSION_FILES_MANIFEST="${SESSION_FILES_MANIFEST:-${TX_DIR}/.generated-this-session.txt}"
STRICT_FROM="${STRICT_FROM:-1}"
VERBOSE="${VERBOSE:-0}"

usage() {
  echo "Usage: $0 [--tx-dir <dir>] [--config <path>] [--session-files <path>] [--from <address>] [--file <json>]... [--non-strict-from]"
  echo
  echo "Simulates Gnosis Safe JSON tx payloads on a stateful Anvil fork before queueing."
  echo
  echo "Options:"
  echo "  --tx-dir <dir>        Directory containing Deprecate-*.json (default: ${TX_DIR})"
  echo "  --config <path>       Path to L0Config.json with chain RPC mappings (default: ${CONFIG_PATH})"
  echo "  --session-files <p>   Newline-delimited file list generated in this session (default: ${SESSION_FILES_MANIFEST})"
  echo "  --from <address>      Force a single from address for all calls"
  echo "  --file <json>         Simulate only this file (can be passed multiple times)"
  echo "  --non-strict-from     If owner() cannot be resolved, continue with from=0x000...001"
  echo "  -h, --help            Show help"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd cast
require_cmd anvil

FORCED_FROM=""
declare -a ONLY_FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tx-dir)
      shift
      TX_DIR="${1:-}"
      [[ -n "${TX_DIR}" ]] || { echo "--tx-dir requires a value" >&2; exit 2; }
      ;;
    --config)
      shift
      CONFIG_PATH="${1:-}"
      [[ -n "${CONFIG_PATH}" ]] || { echo "--config requires a value" >&2; exit 2; }
      ;;
    --session-files)
      shift
      SESSION_FILES_MANIFEST="${1:-}"
      [[ -n "${SESSION_FILES_MANIFEST}" ]] || { echo "--session-files requires a value" >&2; exit 2; }
      ;;
    --from)
      shift
      FORCED_FROM="${1:-}"
      [[ -n "${FORCED_FROM}" ]] || { echo "--from requires a value" >&2; exit 2; }
      ;;
    --file)
      shift
      ONLY_FILES+=("${1:-}")
      [[ -n "${ONLY_FILES[-1]}" ]] || { echo "--file requires a value" >&2; exit 2; }
      ;;
    --non-strict-from)
      STRICT_FROM=0
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

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "Config file not found: ${CONFIG_PATH}" >&2
  exit 1
fi

rpc_for_chain() {
  local chain_id="$1"
  local var_name="RPC_URL_${chain_id}"
  local override="${!var_name:-}"
  if [[ -n "${override}" ]]; then
    echo "${override}"
    return 0
  fi

  local rpc
  rpc="$(jq -er --argjson cid "${chain_id}" '[.Proxy[], .Legacy[]] | map(select(.chainid == $cid and (.RPC | type == "string") and (.RPC | length > 0))) | .[0].RPC' "${CONFIG_PATH}" 2>/dev/null || true)"
  if [[ -n "${rpc}" ]]; then
    echo "${rpc}"
    return 0
  fi

  if [[ "${chain_id}" == "252" ]]; then
    echo "https://rpc.frax.com"
    return 0
  fi

  return 1
}

resolve_from_for_target() {
  local rpc="$1"
  local to="$2"
  local data="${3:-}"

  if [[ -n "${FORCED_FROM}" ]]; then
    echo "${FORCED_FROM}"
    return 0
  fi

  if [[ "${data}" =~ ^0x[0-9a-fA-F]{72,}$ ]]; then
    local arg0
    local oapp
    local delegate

    arg0="${data:10:64}"
    oapp="0x${arg0:24:40}"
    delegate="$(cast call --rpc-url "${rpc}" "${to}" "delegates(address)(address)" "${oapp}" 2>/dev/null || true)"
    if [[ -n "${delegate}" && "${delegate}" =~ ^0x[0-9a-fA-F]{40}$ && "${delegate}" != "0x0000000000000000000000000000000000000000" ]]; then
      echo "${delegate}"
      return 0
    fi
  fi

  local owner
  owner="$(cast call --rpc-url "${rpc}" "${to}" "owner()(address)" 2>/dev/null || true)"
  if [[ -n "${owner}" && "${owner}" =~ ^0x[0-9a-fA-F]{40}$ && "${owner}" != "0x0000000000000000000000000000000000000000" ]]; then
    echo "${owner}"
    return 0
  fi

  if [[ "${STRICT_FROM}" == "1" ]]; then
    return 1
  fi

  echo "0x0000000000000000000000000000000000000001"
}

simulate_tx() {
  local rpc="$1"
  local from="$2"
  local to="$3"
  local value_dec="$4"
  local data="$5"

  cast rpc --rpc-url "${rpc}" anvil_impersonateAccount "${from}" >/dev/null
  cast rpc --rpc-url "${rpc}" anvil_setBalance "${from}" "0x3635C9ADC5DEA00000" >/dev/null

  local out
  if out="$(cast send --rpc-url "${rpc}" --unlocked --from "${from}" --value "${value_dec}" --data "${data}" "${to}" 2>&1)"; then
    printf "%s" "${out}"
    return 0
  fi

  if grep -qi "eip1559" <<<"${out}"; then
    cast send --legacy --rpc-url "${rpc}" --unlocked --from "${from}" --value "${value_dec}" --data "${data}" "${to}"
    return 0
  fi

  printf "%s" "${out}"
  return 1
}

start_anvil_fork() {
  local upstream_rpc="$1"
  local port
  local pid
  local anvil_url

  for _ in {1..20}; do
    port="$((20000 + RANDOM % 20000))"
    anvil --silent --fork-url "${upstream_rpc}" --host 127.0.0.1 --port "${port}" >/tmp/deprecate-anvil-${port}.log 2>&1 &
    pid="$!"
    anvil_url="http://127.0.0.1:${port}"

    for _ in {1..120}; do
      if cast rpc --rpc-url "${anvil_url}" eth_chainId >/dev/null 2>&1; then
        echo "${pid} ${anvil_url}"
        return 0
      fi
    done

    kill "${pid}" >/dev/null 2>&1 || true
  done

  return 1
}

short_err() {
  local raw="$1"
  local line
  line="$(printf "%s\n" "${raw}" | grep -E 'execution reverted|Error:' | tail -n 1 || true)"
  if [[ -n "${line}" ]]; then
    echo "${line}"
  else
    printf "%s\n" "${raw}" | tail -n 1
  fi
}

declare -a FILES=()
if [[ ${#ONLY_FILES[@]} -gt 0 ]]; then
  FILES=("${ONLY_FILES[@]}")
else
  if [[ ! -f "${SESSION_FILES_MANIFEST}" ]]; then
    echo "Session manifest not found: ${SESSION_FILES_MANIFEST}" >&2
    echo "Run generation script first, or pass --file." >&2
    exit 1
  fi
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    FILES+=("${f}")
  done < "${SESSION_FILES_MANIFEST}"
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No Deprecate JSON files found." >&2
  exit 1
fi

total_files=0
passed_files=0
failed_files=0
total_txs=0
passed_txs=0
failed_txs=0
declare -a failed_messages=()

for file in "${FILES[@]}"; do
  if [[ ! -f "${file}" ]]; then
    failed_files=$((failed_files + 1))
    failed_messages+=("${file}: missing file")
    continue
  fi

  total_files=$((total_files + 1))
  chain_id="$(jq -er '.chainId' "${file}")"
  rpc="$(rpc_for_chain "${chain_id}" || true)"

  if [[ -z "${rpc}" ]]; then
    failed_files=$((failed_files + 1))
    failed_messages+=("${file}: no RPC found for chainId ${chain_id}")
    continue
  fi

  tx_count="$(jq -er '.transactions | length' "${file}")"
  file_failed=0
  anvil_info="$(start_anvil_fork "${rpc}" || true)"

  if [[ -z "${anvil_info}" ]]; then
    failed_files=$((failed_files + 1))
    failed_messages+=("${file}: failed to start anvil fork for rpc ${rpc}")
    continue
  fi

  anvil_pid="${anvil_info%% *}"
  anvil_rpc="${anvil_info#* }"

  echo
  echo "[simulate] ${file}"
  echo "  chainId: ${chain_id}"
  echo "  rpc: ${rpc}"
  echo "  fork: ${anvil_rpc}"
  echo "  txs: ${tx_count}"

  for ((i=0; i<tx_count; i++)); do
    total_txs=$((total_txs + 1))
    to="$(jq -er ".transactions[${i}].to" "${file}")"
    value="$(jq -er ".transactions[${i}].value" "${file}")"
    data="$(jq -er ".transactions[${i}].data" "${file}")"
    op="$(jq -er ".transactions[${i}].operation" "${file}")"

    if [[ "${op}" != "0" ]]; then
      failed_txs=$((failed_txs + 1))
      file_failed=1
      failed_messages+=("${file} tx[${i}]: unsupported operation=${op}")
      echo "  [fail] tx[${i}] unsupported operation=${op}"
      continue
    fi

    if [[ "${to}" == "0x0000000000000000000000000000000000000000" ]]; then
      from="${FORCED_FROM:-0x0000000000000000000000000000000000000001}"
    else
      from="$(resolve_from_for_target "${anvil_rpc}" "${to}" "${data}" || true)"
    fi

    if [[ -z "${from}" ]]; then
      failed_txs=$((failed_txs + 1))
      file_failed=1
      failed_messages+=("${file} tx[${i}]: unable to resolve from address")
      echo "  [fail] tx[${i}] cannot resolve from address"
      continue
    fi

    if output="$(simulate_tx "${anvil_rpc}" "${from}" "${to}" "${value}" "${data}" 2>&1)"; then
      passed_txs=$((passed_txs + 1))
      echo "  [ok]   tx[${i}] to=${to} from=${from}"
      if [[ "${VERBOSE}" == "1" ]]; then
        echo "         ${output}"
      fi
    else
      failed_txs=$((failed_txs + 1))
      file_failed=1
      failed_messages+=("${file} tx[${i}]: $(short_err "${output}")")
      echo "  [fail] tx[${i}] to=${to} from=${from}"
      if [[ "${VERBOSE}" == "1" ]]; then
        echo "         ${output}"
      fi
    fi
  done

  kill "${anvil_pid}" >/dev/null 2>&1 || true

  if [[ "${file_failed}" == "1" ]]; then
    failed_files=$((failed_files + 1))
  else
    passed_files=$((passed_files + 1))
  fi
done

echo
echo "========== Simulation Summary =========="
echo "Files: ${passed_files}/${total_files} passed, ${failed_files} failed"
echo "Txs:   ${passed_txs}/${total_txs} passed, ${failed_txs} failed"

if [[ ${#failed_messages[@]} -gt 0 ]]; then
  echo
  echo "Failures:"
  for msg in "${failed_messages[@]}"; do
    echo "- ${msg}"
  done
  exit 1
fi

echo "All simulated calls passed."
