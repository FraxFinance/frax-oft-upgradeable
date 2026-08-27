#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

MODE="${MODE:-full}"
GENERATED_DIR="${FIX_DVNS_GENERATED_DIR:-scripts/ops/fix/FixDVNs/generated/canary-nethermind}"
OUTPUT_DIR="${GENERATED_DIR}/evm"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600s}"
START_ROUTE="${START_ROUTE:-}"
START_ROUTE_SEEN=0
DO_FRESH=0
declare -A RPC_ARG_OVERRIDES=()
export FOUNDRY_DISABLE_NIGHTLY_WARNING="${FOUNDRY_DISABLE_NIGHTLY_WARNING:-1}"

usage() {
  echo "Usage: $0 [fresh] [set-config-only] [SOURCE_CHAIN_ID-DST_CHAIN_ID] [rpc:CHAIN_ID=URL ...]"
  echo
  echo "Generate all Canary + Nethermind Safe JSON batches into ${GENERATED_DIR}."
  echo
  echo "Environment:"
  echo "  MODE=set-config-only     generate only direct setConfig batches"
  echo "  FIX_DVNS_GENERATED_DIR=  override generated output directory"
  echo "  START_ROUTE=1329-252    skip earlier routes and resume generation at this route"
  echo "  RPC_1329=https://...    override the RPC URL for a chain"
  echo "  TIMEOUT_SECONDS=600s    per-forge-script timeout"
  echo
  echo "Arguments:"
  echo "  fresh                         remove all generated Safe JSON from ${GENERATED_DIR} before regenerating"
  echo "  set-config-only               generate only setConfig JSON into generated/canary-nethermind-set-config-only"
  echo "  1329-252                      skip earlier routes and resume generation at this route"
  echo "  rpc:1329=https://...          override the RPC URL for a chain"
}

for arg in "$@"; do
  case "${arg}" in
    "set-config-only")
      MODE="set-config-only"
      if [[ -z "${FIX_DVNS_GENERATED_DIR:-}" ]]; then
        GENERATED_DIR="scripts/ops/fix/FixDVNs/generated/canary-nethermind-set-config-only"
        OUTPUT_DIR="${GENERATED_DIR}/evm"
      fi
      ;;
    "fresh")
      DO_FRESH=1
      ;;
    [0-9]*-[0-9]*)
      START_ROUTE="${arg}"
      ;;
    rpc:*=*)
      rpc_override="${arg#rpc:}"
      RPC_ARG_OVERRIDES["${rpc_override%%=*}"]="${rpc_override#*=}"
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
done

if [[ "${DO_FRESH}" == "1" ]]; then
  echo "Removing stale Safe JSON from ${GENERATED_DIR}"
  find "${GENERATED_DIR}" -type f -name "*.json" -delete
fi

mkdir -p "${OUTPUT_DIR}"

rpc_for_chain() {
  local chain_id="$1"

  jq -er \
    --argjson chain_id "${chain_id}" \
    '[.Proxy[], .Legacy[]] | map(select(.chainid == $chain_id)) | .[0].RPC' \
    scripts/L0Config.json
}

preferred_rpcs_for_chain() {
  local chain_id="$1"

  case "${chain_id}" in
    252)
      echo "https://rpc.frax.com"
      ;;
    1329)
      echo "https://evm-rpc.sei-apis.com"
      ;;
    130)
      echo "https://mainnet.unichain.org"
      ;;
    34443)
      echo "https://mainnet.mode.network"
      ;;
    480)
      echo "https://worldchain-mainnet.g.alchemy.com/public"
      ;;
    5031)
      echo "https://5031.rpc.thirdweb.com"
      ;;
    57073)
      echo "https://rpc-gel.inkonchain.com"
      ;;
    747474)
      echo "https://rpc.katana.network"
      ;;
    80094)
      echo "https://rpc.berachain-apis.com"
      ;;
  esac
}

fallback_rpcs_for_chain() {
  local chain_id="$1"

  case "${chain_id}" in
    137)
      echo "https://polygon.drpc.org"
      ;;
    252)
      echo "https://rpc.frax.com"
      echo "https://fraxtal.drpc.org"
      echo "https://fraxtal-rpc.publicnode.com"
      ;;
    1329)
      echo "https://evm-rpc.sei-apis.com"
      echo "https://sei.drpc.org"
      echo "https://sei-evm-rpc.publicnode.com"
      ;;
    130)
      echo "https://mainnet.unichain.org"
      echo "https://unichain-rpc.publicnode.com"
      echo "https://unichain.drpc.org"
      ;;
    34443)
      echo "https://mainnet.mode.network"
      ;;
    480)
      echo "https://worldchain-mainnet.g.alchemy.com/public"
      ;;
    42161)
      echo "https://arbitrum.gateway.tenderly.co"
      echo "https://1rpc.io/arb"
      echo "https://arbitrum.drpc.org"
      echo "https://arbitrum-one-rpc.publicnode.com"
      echo "https://arbitrum-one.public.blastapi.io"
      echo "https://arb-pokt.nodies.app"
      ;;
    4217)
      echo "https://rpc.mainnet.tempo.xyz"
      echo "https://rpc.tempo.xyz"
      echo "https://1rpc.io/tempo"
      ;;
    43114)
      echo "https://api.avax.network/ext/bc/C/rpc"
      echo "https://avalanche-c-chain-rpc.publicnode.com"
      ;;
    5031)
      echo "https://5031.rpc.thirdweb.com"
      ;;
    534352)
      echo "https://rpc.scroll.io"
      echo "https://scroll-rpc.publicnode.com"
      ;;
    57073)
      echo "https://rpc-gel.inkonchain.com"
      ;;
    59144)
      echo "https://rpc.linea.build"
      echo "https://linea-rpc.publicnode.com"
      ;;
    747474)
      echo "https://rpc.katana.network"
      ;;
    80094)
      echo "https://berachain.drpc.org"
      echo "https://berachain-rpc.publicnode.com"
      echo "https://rpc.berachain-apis.com"
      echo "https://berachain-mainnet.gateway.tatum.io"
      ;;
    8453)
      echo "https://mainnet.base.org"
      echo "https://base-rpc.publicnode.com"
      ;;
    98866)
      echo "https://98866.rpc.thirdweb.com"
      echo "https://rpc.plume.org"
      ;;
    999)
      echo "https://rpc.hyperliquid.xyz/evm"
      echo "https://rpc.hypurrscan.io"
      echo "https://hyperliquid-json-rpc.stakely.io"
      echo "https://hyperliquid.api.onfinality.io/evm/public"
      ;;
    1313161554)
      echo "https://mainnet.aurora.dev"
      echo "https://aurora.drpc.org"
      ;;
  esac
}

rpc_candidates_for_chain() {
  local chain_id="$1"
  local rpc_var="RPC_${chain_id}"

  {
    if [[ -n "${RPC_ARG_OVERRIDES[${chain_id}]:-}" ]]; then
      echo "${RPC_ARG_OVERRIDES[${chain_id}]}"
    fi

    if [[ -n "${!rpc_var:-}" ]]; then
      echo "${!rpc_var}"
    fi

    preferred_rpcs_for_chain "${chain_id}"
    rpc_for_chain "${chain_id}"
    fallback_rpcs_for_chain "${chain_id}"
  } | awk 'NF && !seen[$0]++'
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
  local rpc_url exit_code attempt
  local rpc_urls=()

  echo "${step_name}: ${source_chain_id} -> ${dst_chain_id}"
  clean_step_route "${step_name}" "${source_chain_id}" "${dst_chain_id}"
  mapfile -t rpc_urls < <(rpc_candidates_for_chain "${source_chain_id}")

  exit_code=1
  attempt=0
  for rpc_url in "${rpc_urls[@]}"; do
    attempt=$((attempt + 1))
    if [[ "${#rpc_urls[@]}" -gt 1 ]]; then
      echo "  RPC attempt ${attempt}/${#rpc_urls[@]}"
    fi

    if SOURCE_CHAIN_ID="${source_chain_id}" \
      DST_CHAIN_ID="${dst_chain_id}" \
      FIX_DVNS_GENERATED_DIR="${GENERATED_DIR}" \
      RUST_LOG=error \
      timeout "${TIMEOUT_SECONDS}" \
        forge script "${script}" \
          --rpc-url "${rpc_url}" \
          --ffi \
          --quiet \
          --disable-labels \
          --contracts scripts/ops/fix/FixDVNs; then
      return 0
    else
      exit_code=$?
    fi

    if [[ "${attempt}" -lt "${#rpc_urls[@]}" ]]; then
      echo "  RPC attempt ${attempt} failed; retrying ${step_name}: ${source_chain_id} -> ${dst_chain_id}" >&2
      clean_step_route "${step_name}" "${source_chain_id}" "${dst_chain_id}"
    fi
  done

  return "${exit_code}"
}

run_evm_route() {
  local source_chain_id="$1"
  local dst_chain_id="$2"

  if [[ "${MODE}" != "set-config-only" ]]; then
    run_route "1a_SetBlockSendLibEVM" "scripts/ops/fix/FixDVNs/1a_SetBlockSendLibEVM.s.sol" "${source_chain_id}" "${dst_chain_id}"
  fi
  run_route "2a_FixDVNsEVM" "scripts/ops/fix/FixDVNs/2a_FixDVNsEVM.s.sol" "${source_chain_id}" "${dst_chain_id}"
  if [[ "${MODE}" != "set-config-only" ]]; then
    run_route "3a_SetSendLibEVM" "scripts/ops/fix/FixDVNs/3a_SetSendLibEVM.s.sol" "${source_chain_id}" "${dst_chain_id}"
  fi
}

run_solana_route() {
  local source_chain_id="$1"
  local dst_chain_id="$2"

  if [[ "${MODE}" != "set-config-only" ]]; then
    run_route "1c_SetBlockSendLibSolana" "scripts/ops/fix/FixDVNs/1c_SetBlockSendLibSolana.s.sol" "${source_chain_id}" "${dst_chain_id}"
  fi
  run_route "2c_FixDVNsSolana" "scripts/ops/fix/FixDVNs/2c_FixDVNsSolana.s.sol" "${source_chain_id}" "${dst_chain_id}"
  if [[ "${MODE}" != "set-config-only" ]]; then
    run_route "3c_SetSendLibSolana" "scripts/ops/fix/FixDVNs/3c_SetSendLibSolana.s.sol" "${source_chain_id}" "${dst_chain_id}"
  fi
}

run_movement_aptos_route() {
  local source_chain_id="$1"
  local dst_chain_id="$2"

  if [[ "${MODE}" != "set-config-only" ]]; then
    run_route "1d_SetBlockSendLibMovementAptos" "scripts/ops/fix/FixDVNs/1d_SetBlockSendLibMovementAptos.s.sol" "${source_chain_id}" "${dst_chain_id}"
  fi
  run_route "2d_FixDVNsMovementAptos" "scripts/ops/fix/FixDVNs/2d_FixDVNsMovementAptos.s.sol" "${source_chain_id}" "${dst_chain_id}"
  if [[ "${MODE}" != "set-config-only" ]]; then
    run_route "3d_SetSendLibMovementAptos" "scripts/ops/fix/FixDVNs/3d_SetSendLibMovementAptos.s.sol" "${source_chain_id}" "${dst_chain_id}"
  fi
}

run_zk_manual_batches() {
  echo "manual ZK batches"
  if [[ "${MODE}" == "set-config-only" ]]; then
    FIX_DVNS_GENERATED_DIR="${GENERATED_DIR}" \
      FIX_DVNS_SET_CONFIG_ONLY=true \
      node scripts/ops/fix/FixDVNs/generate-zk-manual-batches.js
  else
    FIX_DVNS_GENERATED_DIR="${GENERATED_DIR}" node scripts/ops/fix/FixDVNs/generate-zk-manual-batches.js
  fi
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
