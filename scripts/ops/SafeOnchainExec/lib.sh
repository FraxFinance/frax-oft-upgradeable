#!/usr/bin/env bash
# Shared helpers for scripts/ops/SafeOnchainExec (bash 3.2 compatible; needs jq + cast).
# Sourced by build-safe-batches.sh, simulate-safe-batches.sh, exec-safe-batch.sh, decode-multisend.sh.

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
require_cmd jq
require_cmd cast

# ---- config loading ---------------------------------------------------------
load_config() {
  CFG="$1"
  [[ -f "$CFG" ]] || { echo "config not found: $CFG" >&2; exit 1; }
  SAFE=$(jq -r .safe "$CFG")
  CHAIN_ID=$(jq -r .chainId "$CFG")
  RPC=${RPC:-$(jq -r .rpc "$CFG")}
  MULTISEND=$(jq -r .multiSendCallOnly "$CFG")
  START_NONCE=$(jq -r .startNonce "$CFG")
  IN_DIR=$(jq -r .inputsDir "$CFG")
  OUT_DIR=$(jq -r .outDir "$CFG")
  EXPLORER=$(jq -r '.explorer // ""' "$CFG")
}

label() { # label <address>  -> "0xabc… (Label)" or just the address
  local a="$1" l
  l=$(jq -r --arg a "$(echo "$1" | tr 'A-F' 'a-f')" '.labels | to_entries[] | select((.key|ascii_downcase)==$a) | .value' "$CFG" 2>/dev/null | head -1)
  if [[ -n "$l" ]]; then echo "$a ($l)"; else echo "$a"; fi
}
eid_name() { # eid_name <eid> -> "Ethereum (30101)" or "eid 30101"
  local n; n=$(jq -r --arg e "$1" '.eids[$e] // ""' "$CFG" 2>/dev/null)
  if [[ -n "$n" ]]; then echo "$n (eid $1)"; else echo "eid $1"; fi
}
role_name() { # role_name <bytes32> -> name if it matches a configured role string
  local r; r=$(echo "$1" | tr 'A-F' 'a-f')
  for name in $(jq -r '.roles | keys[]' "$CFG" 2>/dev/null); do
    if [[ "$(cast keccak "$name" | tr 'A-F' 'a-f')" == "$r" ]]; then echo "$name"; return; fi
  done
  echo "unknown role"
}
short() { echo "${1:0:10}…${1: -8}"; }   # truncate 32-byte hex for display

# ---- calldata decoding -------------------------------------------------------
# decode_call <to> <data>  -> one line "function | human readable args"
decode_call() {
  local to="$1" data="$2" sel="${2:0:10}" out
  case "$sel" in
    0x6a14d715) # setReceiveLibrary(address oapp,uint32 eid,address lib,uint256 grace)
      set -- $(cast calldata-decode 'setReceiveLibrary(address,uint32,address,uint256)' "$data" | sed 's/ \[.*\]//')
      out="setReceiveLibrary | oapp=$(label "$1") remote=$(eid_name "$2") lib=$(if [[ "$3" == 0x0000000000000000000000000000000000000000 ]]; then echo 'address(0) => use endpoint DEFAULT receive lib'; else label "$3"; fi) gracePeriod=$4";;
    0x9535ff30) # setSendLibrary(address oapp,uint32 eid,address lib)
      set -- $(cast calldata-decode 'setSendLibrary(address,uint32,address)' "$data" | sed 's/ \[.*\]//')
      out="setSendLibrary | oapp=$(label "$1") remote=$(eid_name "$2") lib=$(if [[ "$3" == 0x0000000000000000000000000000000000000000 ]]; then echo 'address(0) => use endpoint DEFAULT send lib'; else label "$3"; fi)";;
    0xb98bd070) # setEnforcedOptions((uint32,uint16,bytes)[])
      out="setEnforcedOptions | oapp=$(label "$to") params=$(cast calldata-decode 'setEnforcedOptions((uint32,uint16,bytes)[])' "$data" | sed 's/ \[[^]]*\]//g' | tr -d '\n')";;
    0x6dbd9f90) # setConfig(address oapp,address lib,(uint32 eid,uint32 configType,bytes config)[])
      local dec oapp lib params
      dec=$(cast calldata-decode 'setConfig(address,address,(uint32,uint32,bytes)[])' "$data")
      oapp=$(echo "$dec" | sed -n 1p); lib=$(echo "$dec" | sed -n 2p); params=$(echo "$dec" | sed -n 3p)
      # params like [(30101 [3.01e4], 2, 0x...)] — walk each tuple
      local rendered="" eid ctype cfg
      while read -r eid ctype cfg; do
        [[ -z "$eid" ]] && continue
        if [[ "$ctype" == "2" ]]; then
          local uln; uln=$(cast abi-decode 'f()((uint64,uint8,uint8,uint8,address[],address[]))' "$cfg" 2>/dev/null | tr -d '\n' || echo "$cfg")
          local note=""; [[ "$uln" == "(0, 0, 0, 0, [], [])" ]] && note=" => RESET to lib DEFAULT ULN config"
          rendered="$rendered{remote=$(eid_name "$eid") configType=2(ULN) confirmations/required/optional/threshold/requiredDVNs/optionalDVNs=$uln$note} "
        elif [[ "$ctype" == "1" ]]; then
          local ex; ex=$(cast abi-decode 'f()((uint32,address))' "$cfg" 2>/dev/null | tr -d '\n' || echo "$cfg")
          rendered="$rendered{remote=$(eid_name "$eid") configType=1(Executor) (maxMessageSize,executor)=$ex} "
        else
          rendered="$rendered{remote=$(eid_name "$eid") configType=$ctype config=$cfg} "
        fi
      done < <(echo "$params" | sed 's/ \[[^]]*\]//g' | sed 's/^\[//; s/\]$//' | sed 's/), (/)\
(/g' | tr -d '()' | awk -F', *' '{print $1, $2, $3}')
      out="setConfig | oapp=$(label "$oapp") lib=$(label "$lib") $rendered";;
    0x3400288b) # setPeer(uint32,bytes32)
      set -- $(cast calldata-decode 'setPeer(uint32,bytes32)' "$data" | sed 's/ \[.*\]//')
      local p="$2"; [[ "$p" =~ ^0x0+$ ]] && p="bytes32(0) => peer REMOVED"
      out="setPeer | oapp=$(label "$to") remote=$(eid_name "$1") peer=$p";;
    0x9623609d) # upgradeAndCall(address proxy,address impl,bytes data)  (OZ v5 ProxyAdmin)
      local d; d=$(cast calldata-decode 'upgradeAndCall(address,address,bytes)' "$data")
      out="upgradeAndCall | proxyAdmin=$(label "$to") proxy=$(label "$(echo "$d" | sed -n 1p)") newImplementation=$(label "$(echo "$d" | sed -n 2p)") initData=$(echo "$d" | sed -n 3p)";;
    0x2f2ff15d) # grantRole(bytes32,address)
      local d; d=$(cast calldata-decode 'grantRole(bytes32,address)' "$data")
      out="grantRole | contract=$(label "$to") role=$(short "$(echo "$d" | sed -n 1p)") [$(role_name "$(echo "$d" | sed -n 1p)")] account=$(label "$(echo "$d" | sed -n 2p)")";;
    0xca5eb5e1) out="setDelegate | oapp=$(label "$to") delegate=$(cast calldata-decode 'setDelegate(address)' "$data")";;
    *) out="UNKNOWN selector $sel | to=$(label "$to") data=$data";;
  esac
  echo "$out"
}

# ---- MultiSend packing / parsing --------------------------------------------
# pack_call <operation(0|1)> <to> <value(dec)> <data(0x..)>  -> hex (no 0x) of the packed tuple
pack_call() {
  local op="$1" to="$2" value="$3" data="$4"
  local opx; opx=$(printf '%02x' "$op")
  local tox; tox=$(echo "${to#0x}" | tr 'A-F' 'a-f')
  local valx; valx=$(cast to-uint256 "$value"); valx=${valx#0x}
  local len=$(( (${#data} - 2) / 2 ))
  local lenx; lenx=$(cast to-uint256 "$len"); lenx=${lenx#0x}
  echo "${opx}${tox}${valx}${lenx}${data#0x}"
}
# multisend_calldata <packedhex(no 0x)> -> 0x8d80ff0a... calldata for multiSend(bytes)
multisend_calldata() { cast calldata 'multiSend(bytes)' "0x$1"; }

# parse_multisend <multiSend calldata 0x8d80ff0a...> -> TSV lines: op<TAB>to<TAB>value<TAB>data
parse_multisend() {
  local cd="$1" packed
  [[ "${cd:0:10}" == "0x8d80ff0a" ]] || { echo "not a multiSend(bytes) calldata (selector ${cd:0:10})" >&2; return 1; }
  packed=$(cast calldata-decode 'multiSend(bytes)' "$cd" | head -1); packed=${packed#0x}
  local i=0 n=${#packed}
  while (( i < n )); do
    local op=$((16#${packed:$i:2})); local to="0x${packed:$((i+2)):40}"
    local value=$(cast to-dec "0x${packed:$((i+42)):64}"); local len=$(cast to-dec "0x${packed:$((i+106)):64}")
    local data="0x${packed:$((i+170)):$((len*2))}"
    printf '%s\t%s\t%s\t%s\n' "$op" "$to" "$value" "$data"
    i=$((i + 170 + len*2))
  done
}

# ---- Safe EIP-712 hashing (offline) -----------------------------------------
# safe_tx_hash_offline <to> <value> <data> <operation> <safeTxGas> <baseGas> <gasPrice> <gasToken> <refundReceiver> <nonce>
# Uses the Safe v1.3.0 typehashes, computed at runtime from their type strings.
safe_tx_hash_offline() {
  local DOMAIN_TYPEHASH SAFE_TX_TYPEHASH ds st
  DOMAIN_TYPEHASH=$(cast keccak 'EIP712Domain(uint256 chainId,address verifyingContract)')
  SAFE_TX_TYPEHASH=$(cast keccak 'SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)')
  ds=$(cast keccak "$(cast abi-encode 'f(bytes32,uint256,address)' "$DOMAIN_TYPEHASH" "$CHAIN_ID" "$SAFE")")
  st=$(cast keccak "$(cast abi-encode 'f(bytes32,address,uint256,bytes32,uint8,uint256,uint256,uint256,address,address,uint256)' \
        "$SAFE_TX_TYPEHASH" "$1" "$2" "$(cast keccak "$3")" "$4" "$5" "$6" "$7" "$8" "$9" "${10}")")
  cast keccak "$(cast concat-hex 0x1901 "$ds" "$st")"
}
safe_domain_separator_offline() {
  local DOMAIN_TYPEHASH; DOMAIN_TYPEHASH=$(cast keccak 'EIP712Domain(uint256 chainId,address verifyingContract)')
  cast keccak "$(cast abi-encode 'f(bytes32,uint256,address)' "$DOMAIN_TYPEHASH" "$CHAIN_ID" "$SAFE")"
}
# safe_tx_hash_onchain <same args> — asks the Safe contract itself (needs RPC)
safe_tx_hash_onchain() {
  cast call "$SAFE" 'getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)(bytes32)' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" --rpc-url "$RPC"
}

# ---- approved-hash signature packing ----------------------------------------
# pack_approved_sigs <owner1> <owner2> ... -> 0x-prefixed signatures blob for execTransaction
# Each "signature" is r=owner (left-padded), s=0, v=1 (approved-hash / msg.sender-is-owner scheme); sorted ascending by owner.
pack_approved_sigs() {
  local sigs="0x" o
  for o in $(printf '%s\n' "$@" | tr 'A-F' 'a-f' | sort -u); do
    sigs="${sigs}$(cast to-uint256 "$o" | sed 's/^0x//')$(printf '%064d' 0)01"
  done
  echo "$sigs"
}
