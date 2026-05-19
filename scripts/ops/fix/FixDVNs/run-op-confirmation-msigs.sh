#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OUTPUT_DIR="scripts/ops/fix/FixDVNs/generated/canary-nethermind/evm"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600s}"
START_ROUTE="${START_ROUTE:-}"
START_ROUTE_SEEN=0

usage() {
  echo "Usage: $0 [fresh]"
  echo
  echo "Generate all Canary + Nethermind Safe JSON batches into ${OUTPUT_DIR}."
  echo
  echo "Environment:"
  echo "  START_ROUTE=1329-252    skip earlier routes and resume generation at this route"
  echo "  TIMEOUT_SECONDS=600s    per-forge-script timeout"
  echo
  echo "  fresh    remove all generated Safe JSON from ${OUTPUT_DIR} before regenerating"
}

mkdir -p "${OUTPUT_DIR}"

case "${1:-}" in
  "")
    ;;
  "fresh")
    echo "Removing stale Safe JSON from ${OUTPUT_DIR}"
    find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "*.json" -delete
    ;;
  "-h"|"--help")
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

rpc_for_chain() {
  local chain_id="$1"

  jq -er \
    --argjson chain_id "${chain_id}" \
    '[.Proxy[], .Legacy[]] | map(select(.chainid == $chain_id)) | .[0].RPC' \
    scripts/L0Config.json
}

clean_step_route() {
  local step_name="$1"
  local source_chain_id="$2"
  local dst_chain_id="$3"

  find "${OUTPUT_DIR}" \
    -maxdepth 1 \
    -type f \
    -name "*-${step_name}-${source_chain_id}-to-${dst_chain_id}.json" \
    -delete
}

run_route() {
  local step_name="$1"
  local script="$2"
  local source_chain_id="$3"
  local dst_chain_id="$4"
  local rpc_url

  rpc_url="$(rpc_for_chain "${source_chain_id}")"

  echo "${step_name}: ${source_chain_id} -> ${dst_chain_id}"
  clean_step_route "${step_name}" "${source_chain_id}" "${dst_chain_id}"
  SOURCE_CHAIN_ID="${source_chain_id}" \
  DST_CHAIN_ID="${dst_chain_id}" \
  RUST_LOG=error \
  timeout "${TIMEOUT_SECONDS}" \
    forge script "${script}" \
      --rpc-url "${rpc_url}" \
      --ffi \
      --quiet \
      --disable-labels
}

run_evm_route() {
  local source_chain_id="$1"
  local dst_chain_id="$2"

  run_route "1a_SetBlockSendLibEVM" "scripts/ops/fix/FixDVNs/1a_SetBlockSendLibEVM.s.sol" "${source_chain_id}" "${dst_chain_id}"
  run_route "2a_FixDVNsEVM" "scripts/ops/fix/FixDVNs/2a_FixDVNsEVM.s.sol" "${source_chain_id}" "${dst_chain_id}"
  run_route "3a_SetSendLibEVM" "scripts/ops/fix/FixDVNs/3a_SetSendLibEVM.s.sol" "${source_chain_id}" "${dst_chain_id}"
}

run_solana_route() {
  local source_chain_id="$1"
  local dst_chain_id="$2"

  run_route "1c_SetBlockSendLibSolana" "scripts/ops/fix/FixDVNs/1c_SetBlockSendLibSolana.s.sol" "${source_chain_id}" "${dst_chain_id}"
  run_route "2c_FixDVNsSolana" "scripts/ops/fix/FixDVNs/2c_FixDVNsSolana.s.sol" "${source_chain_id}" "${dst_chain_id}"
  run_route "3c_SetSendLibSolana" "scripts/ops/fix/FixDVNs/3c_SetSendLibSolana.s.sol" "${source_chain_id}" "${dst_chain_id}"
}

run_movement_aptos_route() {
  local source_chain_id="$1"
  local dst_chain_id="$2"

  run_route "1d_SetBlockSendLibMovementAptos" "scripts/ops/fix/FixDVNs/1d_SetBlockSendLibMovementAptos.s.sol" "${source_chain_id}" "${dst_chain_id}"
  run_route "2d_FixDVNsMovementAptos" "scripts/ops/fix/FixDVNs/2d_FixDVNsMovementAptos.s.sol" "${source_chain_id}" "${dst_chain_id}"
  run_route "3d_SetSendLibMovementAptos" "scripts/ops/fix/FixDVNs/3d_SetSendLibMovementAptos.s.sol" "${source_chain_id}" "${dst_chain_id}"
}

run_zk_manual_batches() {
  echo "manual ZK batches"
  node scripts/ops/fix/FixDVNs/generate-zk-manual-batches.js
}

should_run_route() {
  local source_chain_id="$1"
  local dst_chain_id="$2"

  if [[ -z "${START_ROUTE}" || "${START_ROUTE_SEEN}" == "1" ]]; then
    return 0
  fi

  if [[ "${source_chain_id}-${dst_chain_id}" == "${START_ROUTE}" ]]; then
    START_ROUTE_SEEN=1
    return 0
  fi

  return 1
}

EVM_ROUTES=(
  "1 252"
  "10 252"
  "56 252"
  "130 252"
  "137 252"
  "143 252"
  "146 252"
  "196 252"
  "252 1"
  "252 10"
  "252 130"
  "252 1313161554"
  "252 1329"
  "252 137"
  "252 143"
  "252 146"
  "252 196"
  "252 2741"
  "252 324"
  "252 34443"
  "252 42161"
  "252 4217"
  "252 43114"
  "252 480"
  "252 5031"
  "252 534352"
  "252 56"
  "252 57073"
  "252 59144"
  "252 747474"
  "252 80094"
  "252 8453"
  "252 988"
  "252 98866"
  "252 999"
  "480 252"
  "988 252"
  "999 252"
  "1329 252"
  "4217 252"
  "5031 252"
  "8453 252"
  "34443 252"
  "42161 252"
  "43114 252"
  "57073 252"
  "59144 252"
  "80094 252"
  "98866 252"
  "534352 252"
  "747474 252"
  "1313161554 252"
)

SOLANA_ROUTES=(
  "252 111111111"
  "1 111111111"
)

MOVEMENT_APTOS_ROUTES=(
  "252 22222222"
  "252 33333333"
)

for route in "${EVM_ROUTES[@]}"; do
  read -r source_chain_id dst_chain_id <<< "${route}"
  if should_run_route "${source_chain_id}" "${dst_chain_id}"; then
    run_evm_route "${source_chain_id}" "${dst_chain_id}"
  fi
done

for route in "${SOLANA_ROUTES[@]}"; do
  read -r source_chain_id dst_chain_id <<< "${route}"
  if should_run_route "${source_chain_id}" "${dst_chain_id}"; then
    run_solana_route "${source_chain_id}" "${dst_chain_id}"
  fi
done

for route in "${MOVEMENT_APTOS_ROUTES[@]}"; do
  read -r source_chain_id dst_chain_id <<< "${route}"
  if should_run_route "${source_chain_id}" "${dst_chain_id}"; then
    run_movement_aptos_route "${source_chain_id}" "${dst_chain_id}"
  fi
done

if [[ -n "${START_ROUTE}" && "${START_ROUTE_SEEN}" == "0" ]]; then
  echo "START_ROUTE ${START_ROUTE} was not found" >&2
  exit 1
fi

run_zk_manual_batches
