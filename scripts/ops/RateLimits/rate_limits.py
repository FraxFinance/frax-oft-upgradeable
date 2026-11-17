#!/usr/bin/env python3
"""Plan, verify and monitor OFT v1.2.0 rate limits from one declarative config.

`rate-limits.json` (next to this file) is the source of truth for every rate-limit setting on every
v1.2.0 OFT and lockbox in the mesh. This tool reads each OFT's live state over plain JSON-RPC
(Multicall3 where deployed), diffs it against the config, and emits one Safe Transaction Builder
batch per (chain, owner Safe) that brings the chain to the config. Every call is simulated with
eth_call from its owner first. Nothing is ever signed or sent.

  status       live limits, usage and headroom per OFT and peer, plus drift against the config
  check        exit 1 when any chain differs from the config (run after execution, or from CI)
  plan         print the changes; --write emits the Safe batches with summary.md and plan.json;
               --fork-sim executes them on an anvil fork and re-reads the result
  reset-usage  emergency: zero a lane's consumed capacity (setRateLimitStates)
  fork-apply   execute a batch file on a local anvil fork as its owner (testing only)

Examples (from the repo root):
  python3 scripts/ops/RateLimits/rate_limits.py status --chains fraxtal --tokens frxUSD
  python3 scripts/ops/RateLimits/rate_limits.py plan
  python3 scripts/ops/RateLimits/rate_limits.py plan --write --label 2026-12-01-enable-frxusd
  python3 scripts/ops/RateLimits/rate_limits.py check
  python3 scripts/ops/RateLimits/rate_limits.py reset-usage --chain fraxtal --token frxUSD \\
      --peer arbitrum --direction outbound --write

RPCs come from scripts/L0Config.json; override one with RPC_URL_<chainid>=<url> or --rpc <chainid>=<url>.
README.md in this folder covers the limiter semantics, the config reference and the runbooks.
Python 3.9+, standard library only; anvil (Foundry) is needed only for --fork-sim and fork-apply.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Dict, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
L0_CONFIG = os.path.join(ROOT, "scripts", "L0Config.json")
L0_CONSTANTS = os.path.join(ROOT, "scripts", "L0Constants.sol")
DEFAULT_CONFIG = os.path.join(HERE, "rate-limits.json")
TXS_DIR = os.path.join(HERE, "txs")

UINT32_MAX = 2**32 - 1
UINT112_MAX = 2**112 - 1
ZERO_ADDRESS = "0x" + "00" * 20
ZERO32 = "0x" + "00" * 32
MULTICALL3 = "0xcA11bde05977b3631167028862bE2a173976CA11"
EIP1967_IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"

# ---------------------------------------------------------------------------------------------
# Chains, endpoint ids and tokens
# ---------------------------------------------------------------------------------------------

# chain id -> (config name, LayerZero v2 endpoint id). Names are what rate-limits.json uses;
# load_mesh() cross-checks every eid against scripts/L0Config.json.
CHAINS: Dict[int, Tuple[str, int]] = {
    1: ("ethereum", 30101),
    10: ("optimism", 30111),
    56: ("bsc", 30102),
    130: ("unichain", 30320),
    137: ("polygon", 30109),
    143: ("monad", 30390),
    146: ("sonic", 30332),
    196: ("xlayer", 30274),
    252: ("fraxtal", 30255),
    324: ("zksync", 30165),
    480: ("worldchain", 30319),
    988: ("stable", 30396),
    999: ("hyperevm", 30367),
    1088: ("metis", 30151),
    1329: ("sei", 30280),
    2741: ("abstract", 30324),
    4217: ("tempo", 30410),
    4663: ("robinhood", 30416),
    5031: ("somnia", 30380),
    8453: ("base", 30184),
    42161: ("arbitrum", 30110),
    42220: ("celo", 30125),
    43114: ("avalanche", 30106),
    57073: ("ink", 30339),
    59144: ("linea", 30183),
    81457: ("blast", 30243),
    98866: ("plume", 30370),
    747474: ("katana", 30375),
    111111111: ("solana", 30168),
    1313161554: ("aurora", 30211),
}
# Retired chains (L0Constants.isDeprecatedChain). They are no longer in L0Config, but a stale
# override could still sit on their eids, so the reader probes them too.
RETIRED_CHAINS: Dict[int, Tuple[str, int]] = {
    1101: ("polygon-zkevm", 30158),
    3637: ("botanix", 30376),
    34443: ("mode", 30260),
    80094: ("berachain", 30362),
    534352: ("scroll", 30214),
    22222222: ("movement", 30325),
    33333333: ("aptos", 30108),
}
ALIASES = {"eth": "ethereum", "mainnet": "ethereum", "arb": "arbitrum", "op": "optimism", "bnb": "bsc",
           "hyperliquid": "hyperevm", "x-layer": "xlayer", "zksync-era": "zksync", "avax": "avalanche"}
# Proxy chains whose OFTs belong to the legacy mesh (UpgradeV120Base._isLegacyOnlyChain).
LEGACY_ONLY_CHAINS = {81457}
FRAXTAL_CHAIN_ID = 252
# anvil cannot fork these: Somnia's RPCs reject the EIP-1898 block-hash reads forge's fork backend
# makes, and the ZK-stack chains run EraVM bytecode.
UNFORKABLE_CHAINS = {5031, 324, 2741}

# `enum Token` order in scripts/L0Constants.sol; registry arrays are indexed by it.
TOKEN_SLOTS = ["WFRAX", "SFRXUSD", "SFRXETH", "FRXUSD", "FRXETH", "FPI"]
TOKEN_DISPLAY = {"WFRAX": "WFRAX", "SFRXUSD": "sfrxUSD", "SFRXETH": "sfrxETH",
                 "FRXUSD": "frxUSD", "FRXETH": "frxETH", "FPI": "FPI"}


def chain_name(chain_id: int) -> str:
    if chain_id in CHAINS:
        return CHAINS[chain_id][0]
    if chain_id in RETIRED_CHAINS:
        return RETIRED_CHAINS[chain_id][0]
    return f"chain-{chain_id}"


EID_NAMES = {eid: name for name, eid in list(CHAINS.values()) + list(RETIRED_CHAINS.values())}


def eid_name(eid: int) -> str:
    return EID_NAMES.get(eid, f"eid-{eid}")


# ---------------------------------------------------------------------------------------------
# Keccak-256 (pure Python; hashlib's sha3_256 uses different padding)
# ---------------------------------------------------------------------------------------------

_KECCAK_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]
_KECCAK_ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61],
               [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
_M64 = (1 << 64) - 1


def _keccak_f(state: List[int]) -> List[int]:
    a = state
    for rc in _KECCAK_RC:
        c = [a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] for x in range(5)]
        d = [c[(x - 1) % 5] ^ (((c[(x + 1) % 5] << 1) | (c[(x + 1) % 5] >> 63)) & _M64) for x in range(5)]
        a = [a[i] ^ d[i % 5] for i in range(25)]
        b = [0] * 25
        for x in range(5):
            for y in range(5):
                r = _KECCAK_ROT[x][y]
                v = a[x + 5 * y]
                b[y + 5 * ((2 * x + 3 * y) % 5)] = (((v << r) | (v >> (64 - r))) & _M64) if r else v
        a = [b[i] ^ ((~b[(i + 1) % 5 + 5 * (i // 5)]) & b[(i + 2) % 5 + 5 * (i // 5)]) for i in range(25)]
        a[0] ^= rc
    return a


def keccak256(data: bytes) -> bytes:
    rate = 136
    padded = bytearray(data)
    padded.append(0x01)
    while len(padded) % rate:
        padded.append(0)
    padded[-1] |= 0x80
    state = [0] * 25
    for offset in range(0, len(padded), rate):
        block = padded[offset:offset + rate]
        for i in range(rate // 8):
            state[i] ^= int.from_bytes(block[8 * i:8 * i + 8], "little")
        state = _keccak_f(state)
    return b"".join(state[i].to_bytes(8, "little") for i in range(4))


def selector(signature: str) -> bytes:
    return keccak256(signature.encode())[:4]


def checksum(address: str) -> str:
    lower = address.lower().removeprefix("0x")
    if not re.fullmatch(r"[0-9a-f]{40}", lower):
        raise ValueError(f"not an address: {address!r}")
    digest = keccak256(lower.encode()).hex()
    return "0x" + "".join(ch.upper() if ch.isalpha() and int(digest[i], 16) >= 8 else ch for i, ch in enumerate(lower))


# ---------------------------------------------------------------------------------------------
# ABI
# ---------------------------------------------------------------------------------------------

RATE_LIMIT_CONFIG = "(bool,bool,bool,uint32,uint32,uint112,uint112)"
SIGNATURES = {
    "owner": "owner()",
    "version": "version()",
    "token": "token()",
    "decimals": "decimals()",
    "sharedDecimals": "sharedDecimals()",
    "decimalConversionRate": "decimalConversionRate()",
    "peers": "peers(uint32)",
    "rateLimitGlobalConfig": "rateLimitGlobalConfig()",
    "defaultRateLimitConfig": "defaultRateLimitConfig()",
    "storedRateLimitConfig": "storedRateLimitConfig(uint32)",
    "storedRateLimitState": "storedRateLimitState(uint32)",
    "rateLimitState": "rateLimitState(uint32)",
    "setRateLimitGlobalConfig": "setRateLimitGlobalConfig((bool))",
    "setDefaultRateLimitConfig": f"setDefaultRateLimitConfig({RATE_LIMIT_CONFIG})",
    "setRateLimitConfigs": f"setRateLimitConfigs((uint32,{RATE_LIMIT_CONFIG})[])",
    "setRateLimitStates": "setRateLimitStates((uint32,(uint112,uint112,uint32))[])",
    "checkpointRateLimits": "checkpointRateLimits(uint32[])",
    "getThreshold": "getThreshold()",
    "getOwners": "getOwners()",
    "delay": "delay()",
    "admin": "admin()",
    "aggregate3": "aggregate3((address,bool,bytes)[])",
    "getBlockNumber": "getBlockNumber()",
    "getCurrentBlockTimestamp": "getCurrentBlockTimestamp()",
}
SEL = {name: selector(sig) for name, sig in SIGNATURES.items()}
ERRORS = {selector(sig): sig for sig in (
    "InvalidRateLimitConfig()", "InvalidRateLimitState()", "RateLimitExceeded(uint32,bool,uint256,uint256)",
    "OwnableUnauthorizedAccount(address)", "Error(string)", "Panic(uint256)",
)}


class DecodeError(Exception):
    pass


def word(value: int) -> bytes:
    if value < 0 or value >= 1 << 256:
        raise ValueError(f"value out of uint256 range: {value}")
    return value.to_bytes(32, "big")


def address_word(address: str) -> bytes:
    return int(address, 16).to_bytes(32, "big")


def read_words(raw: bytes, count: int) -> List[int]:
    if len(raw) < 32 * count:
        raise DecodeError(f"expected {count} words, got {len(raw)} bytes")
    return [int.from_bytes(raw[32 * i:32 * i + 32], "big") for i in range(count)]


def read_bool(raw: bytes) -> bool:
    (value,) = read_words(raw, 1)
    if value > 1:
        raise DecodeError(f"not a bool: {value}")
    return bool(value)


def read_address(raw: bytes) -> str:
    (value,) = read_words(raw, 1)
    if value >> 160:
        raise DecodeError("not an address")
    return checksum(f"{value:040x}")


def read_string(raw: bytes) -> str:
    (offset,) = read_words(raw, 1)
    if offset + 32 > len(raw):
        raise DecodeError("string offset out of range")
    length = int.from_bytes(raw[offset:offset + 32], "big")
    if offset + 32 + length > len(raw):
        raise DecodeError("string length out of range")
    return raw[offset + 32:offset + 32 + length].decode("utf-8", errors="replace")


def read_address_array(raw: bytes) -> List[str]:
    (offset,) = read_words(raw, 1)
    length = int.from_bytes(raw[offset:offset + 32], "big")
    items = read_words(raw[offset + 32:], length)
    return [checksum(f"{item:040x}") for item in items]


def decode_revert(data: Optional[str]) -> str:
    if not data or data in ("0x", ""):
        return "reverted without data"
    raw = bytes.fromhex(data.removeprefix("0x"))
    signature = ERRORS.get(raw[:4])
    if signature == "Error(string)":
        try:
            return f"Error({read_string(raw[4:])!r})"
        except DecodeError:
            pass
    if signature:
        args = raw[4:]
        words = [int.from_bytes(args[i:i + 32], "big") for i in range(0, len(args) - len(args) % 32, 32)]
        return f"{signature.split('(')[0]}({', '.join(str(w) for w in words)})" if words else signature
    return f"reverted with data {data[:74]}"


@dataclass(frozen=True)
class Direction:
    """One direction of a RateLimitConfig in on-chain units (base units of the local token, seconds)."""
    enabled: bool
    limit: int = 0
    window: int = 0


OFF = Direction(False, 0, 0)


@dataclass(frozen=True)
class RLConfig:
    """RateLimiterModule.RateLimitConfig."""
    override: bool
    outbound: Direction
    inbound: Direction

    def words(self) -> List[int]:
        return [int(self.override), int(self.outbound.enabled), int(self.inbound.enabled),
                self.outbound.window, self.inbound.window, self.outbound.limit, self.inbound.limit]

    def is_empty(self) -> bool:
        return self == EMPTY

    def as_override(self) -> "RLConfig":
        return RLConfig(True, self.outbound, self.inbound)


EMPTY = RLConfig(False, OFF, OFF)


def decode_config(raw: bytes) -> RLConfig:
    w = read_words(raw, 7)
    if any(flag > 1 for flag in w[:3]) or w[3] > UINT32_MAX or w[4] > UINT32_MAX \
            or w[5] > UINT112_MAX or w[6] > UINT112_MAX:
        raise DecodeError(f"not a RateLimitConfig: {w}")
    return RLConfig(bool(w[0]), Direction(bool(w[1]), w[5], w[3]), Direction(bool(w[2]), w[6], w[4]))


def encode_config(config: RLConfig) -> bytes:
    return b"".join(word(w) for w in config.words())


def calldata_set_global(disabled: bool) -> bytes:
    return SEL["setRateLimitGlobalConfig"] + word(int(disabled))


def calldata_set_default(config: RLConfig) -> bytes:
    return SEL["setDefaultRateLimitConfig"] + encode_config(config)


def calldata_set_configs(params: List[Tuple[int, RLConfig]]) -> bytes:
    body = b"".join(word(eid) + encode_config(config) for eid, config in params)
    return SEL["setRateLimitConfigs"] + word(0x20) + word(len(params)) + body


def calldata_set_states(params: List[Tuple[int, int, int, int]]) -> bytes:
    """params: (eid, outboundUsage, inboundUsage, lastUpdated)."""
    body = b"".join(word(eid) + word(out) + word(inb) + word(ts) for eid, out, inb, ts in params)
    return SEL["setRateLimitStates"] + word(0x20) + word(len(params)) + body


def calldata_checkpoint(eids: List[int]) -> bytes:
    return SEL["checkpointRateLimits"] + word(0x20) + word(len(eids)) + b"".join(word(e) for e in eids)


def encode_aggregate3(calls: List[Tuple[str, bytes]]) -> bytes:
    """Multicall3.aggregate3 with allowFailure=true on every call."""
    elements = []
    for target, data in calls:
        padding = b"\x00" * ((32 - len(data) % 32) % 32)
        elements.append(address_word(target) + word(1) + word(0x60) + word(len(data)) + data + padding)
    offsets, position = [], 32 * len(elements)
    for element in elements:
        offsets.append(word(position))
        position += len(element)
    return SEL["aggregate3"] + word(0x20) + word(len(elements)) + b"".join(offsets) + b"".join(elements)


def decode_aggregate3(raw: bytes) -> List[Tuple[bool, bytes]]:
    (base,) = read_words(raw, 1)
    count = int.from_bytes(raw[base:base + 32], "big")
    start = base + 32
    results = []
    for i in range(count):
        element = start + int.from_bytes(raw[start + 32 * i:start + 32 * i + 32], "big")
        success = int.from_bytes(raw[element:element + 32], "big") != 0
        data_at = element + int.from_bytes(raw[element + 32:element + 64], "big")
        length = int.from_bytes(raw[data_at:data_at + 32], "big")
        if data_at + 32 + length > len(raw):
            raise DecodeError("aggregate3 result out of range")
        results.append((success, raw[data_at + 32:data_at + 32 + length]))
    return results


# ---------------------------------------------------------------------------------------------
# JSON-RPC
# ---------------------------------------------------------------------------------------------

class Reverted(Exception):
    """The node executed the call and it reverted."""

    def __init__(self, message: str, data: Optional[str] = None):
        super().__init__(message)
        self.data = data

    def reason(self) -> str:
        return decode_revert(self.data) if self.data else str(self)


class RpcError(Exception):
    pass


def _revert_data(error: dict) -> Optional[str]:
    data = error.get("data")
    if isinstance(data, dict):
        data = data.get("data") or data.get("result")
    if isinstance(data, str) and data.startswith("0x"):
        return data
    match = re.search(r"0x[0-9a-fA-F]{8,}", error.get("message", ""))
    return match.group(0) if match else None


TRANSIENT_HINTS = ("rate limit", "rate-limit", "too many", "timeout", "timed out", "busy", "temporar",
                   "unavailable", "overload", "try again", "capacity", "header not found", "upstream",
                   # anvil relaying a failed upstream fetch from the forked chain's RPC
                   "fork error", "transport", "connection", "error sending request")


class Rpc:
    def __init__(self, url: str, label: str = "", attempts: int = 5):
        self.url = url
        self.label = label or url
        self.attempts = attempts
        self.multicall: Optional[bool] = None

    def _post(self, payload):
        """POST with retries on transport failures, 429 and 5xx; other HTTP errors fail at once."""
        body = json.dumps(payload).encode()
        last = None
        for attempt in range(self.attempts):
            request = urllib.request.Request(self.url, data=body, headers={
                "Content-Type": "application/json", "User-Agent": "frax-oft-rate-limits/1.0"})
            backoff = min(2 ** attempt, 16)
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    return json.load(response)
            except urllib.error.HTTPError as exc:
                last = exc
                if exc.code != 429 and exc.code < 500:
                    break
                retry_after = exc.headers.get("Retry-After", "") if exc.headers else ""
                time.sleep(min(int(retry_after), 30) if retry_after.isdigit() else backoff)
            except (urllib.error.URLError, TimeoutError, ConnectionError, json.JSONDecodeError, OSError) as exc:
                last = exc
                time.sleep(backoff)
        raise RpcError(f"{self.label}: request to {self.url} failed: {last}")

    def request(self, method: str, params: list):
        last = None
        for attempt in range(self.attempts):
            reply = self._post({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
            if not isinstance(reply, dict):
                raise RpcError(f"{self.label}: malformed reply to {method}: {reply!r}"[:300])
            if "error" not in reply:
                return reply.get("result")
            error = reply["error"] if isinstance(reply["error"], dict) else {"message": str(reply["error"])}
            text = json.dumps(error).lower()
            if "revert" in text or error.get("code") == 3:
                raise Reverted(error.get("message", "execution reverted"), _revert_data(error))
            last = error
            # Only node-side hiccups are worth retrying; a deterministic error would fail the same way.
            if not any(hint in text for hint in TRANSIENT_HINTS) and error.get("code") not in (-32005, 429):
                break
            time.sleep(min(2 ** attempt, 16))
        raise RpcError(f"{self.label}: {method} failed: {json.dumps(last)[:300]}")

    def call(self, to: str, data: bytes, sender: Optional[str] = None) -> bytes:
        tx = {"to": to, "data": "0x" + data.hex()}
        if sender:
            tx["from"] = sender
        result = self.request("eth_call", [tx, "latest"])
        if not isinstance(result, str) or not result.startswith("0x"):
            raise RpcError(f"{self.label}: malformed eth_call result {result!r}"[:300])
        return bytes.fromhex(result[2:])

    def estimate_gas(self, to: str, data: bytes, sender: str) -> int:
        return int(self.request("eth_estimateGas", [{"from": sender, "to": to, "data": "0x" + data.hex()}]), 16)

    def code(self, address: str) -> bytes:
        result = self.request("eth_getCode", [address, "latest"])
        return bytes.fromhex(result[2:]) if isinstance(result, str) and result.startswith("0x") else b""

    def chain_id(self) -> int:
        return int(self.request("eth_chainId", []), 16)

    def latest_block(self) -> Tuple[int, int]:
        block = self.request("eth_getBlockByNumber", ["latest", False])
        return int(block["number"], 16), int(block["timestamp"], 16)

    def has_multicall(self) -> bool:
        if self.multicall is None:
            self.multicall = len(self.code(MULTICALL3)) > 0
        return self.multicall

    def call_many(self, calls: List[Tuple[str, bytes]], chunk: int = 100) -> List[Tuple[bool, bytes]]:
        """Run static calls, through Multicall3 when deployed; (success, returndata) per call, in order.

        A call that "succeeds" with no return data hit an address without code (or a function-less
        fallback); none of the views read here return nothing, so that counts as a failure.
        """
        results: List[Tuple[bool, bytes]] = []
        for start in range(0, len(calls), chunk):
            part = calls[start:start + chunk]
            results.extend(self._aggregate(part) if self.has_multicall() else self._individually(part))
        return [(ok and len(data) > 0, data) for ok, data in results]

    def _aggregate(self, calls):
        try:
            return decode_aggregate3(self.call(MULTICALL3, encode_aggregate3(calls)))
        except (Reverted, DecodeError, RpcError) as exc:
            # An eth_call gas or size cap: halve until it fits, then fall back to single calls.
            # A dead RPC is not worth splitting for.
            if isinstance(exc, RpcError) and not re.search(r"gas|size|large|exceed|limit", str(exc), re.I):
                raise
            if len(calls) == 1:
                return self._individually(calls)
            middle = len(calls) // 2
            return self._aggregate(calls[:middle]) + self._aggregate(calls[middle:])

    def _one(self, item):
        target, data = item
        try:
            return True, self.call(target, data)
        except Reverted:
            return False, b""

    def _individually(self, calls):
        with ThreadPoolExecutor(max_workers=6) as pool:
            return list(pool.map(self._one, calls))


# ---------------------------------------------------------------------------------------------
# Repo mesh: chains, RPCs, OFT addresses
# ---------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Chain:
    chain_id: int
    name: str
    eid: int
    rpc: str
    delegate: str


@dataclass
class Mesh:
    chains: Dict[int, Chain]               # managed EVM chains (active proxy mesh)
    ofts: Dict[int, Dict[str, str]]        # chain id -> token slot -> OFT address (active tokens only)
    active_tokens: List[str]
    universe_eids: List[int]               # every eid probed for overrides / state
    deprecated: set


def load_registry(source: str) -> Dict[object, List[str]]:
    """Token-indexed OFT arrays per chain id from scripts/L0Constants.sol.

    Mirrors L0Constants: `_registerChain(id, array)` entries, `expectedProxyOfts` for every other
    chain (same parser as scripts/ops/DeprecateChain/generate-unforkable-batches.py).
    """
    constants = dict(re.findall(r"address public (\w+) = (0x[0-9a-fA-F]{40});", source))
    arrays: Dict[str, List[str]] = {}
    for array, name in re.findall(r"^\s*(\w+)\.push\((\w+)\);", source, re.M):
        if name in constants:
            arrays.setdefault(array, []).append(constants[name])
    if "fullDeterministicProxyOftsPostFpi" in source:
        arrays["fullDeterministicProxyOftsPostFpi"] = [
            ZERO_ADDRESS if TOKEN_SLOTS[i] == "FPI" else a for i, a in enumerate(arrays["fullDeterministicProxyOfts"])]
    registry: Dict[object, List[str]] = {}
    for chain_id, array in re.findall(r"_registerChain\((\d+),\s*(\w+)\);", source):
        registry[int(chain_id)] = arrays.get(array, [])
    registry["default"] = arrays.get("expectedProxyOfts", [])
    for key, peers in registry.items():
        if len(peers) != len(TOKEN_SLOTS):
            raise RuntimeError(f"L0Constants registry for {key} resolved {len(peers)} of {len(TOKEN_SLOTS)} slots")
    return registry


def load_active_tokens(source: str) -> List[str]:
    tokens = re.findall(r"^\s*activeTokens\.push\(Token\.(\w+)\);", source, re.M)
    if not tokens or any(t not in TOKEN_SLOTS for t in tokens):
        raise RuntimeError(f"could not parse activeTokens from L0Constants.sol: {tokens}")
    return tokens


def load_deprecated(source: str) -> set:
    body = re.search(r"function isDeprecatedChain\(uint256 _chainid\)[^{]*\{(.*?)\}", source, re.S)
    if not body:
        raise RuntimeError("could not parse isDeprecatedChain from L0Constants.sol")
    return {int(x) for x in re.findall(r"_chainid == (\d+)", body.group(1))}


def load_mesh(rpc_overrides: Optional[Dict[int, str]] = None) -> Mesh:
    rpc_overrides = rpc_overrides or {}
    with open(L0_CONFIG) as handle:
        config = json.load(handle)
    with open(L0_CONSTANTS) as handle:
        source = handle.read()
    registry = load_registry(source)
    active = load_active_tokens(source)
    deprecated = load_deprecated(source)

    universe = set(eid for _, eid in RETIRED_CHAINS.values())
    for section in ("Legacy", "Proxy", "Non-EVM"):
        for entry in config.get(section, []):
            universe.add(int(entry["eid"]))
            known = CHAINS.get(int(entry["chainid"]))
            if known and known[1] != int(entry["eid"]):
                raise RuntimeError(f"eid mismatch for chain {entry['chainid']}: L0Config {entry['eid']} vs table {known[1]}")

    chains: Dict[int, Chain] = {}
    ofts: Dict[int, Dict[str, str]] = {}
    for entry in config["Proxy"]:
        chain_id = int(entry["chainid"])
        if chain_id in deprecated or chain_id in LEGACY_ONLY_CHAINS:
            continue
        rpc = rpc_overrides.get(chain_id) or os.environ.get(f"RPC_URL_{chain_id}") or entry["RPC"]
        chains[chain_id] = Chain(chain_id, chain_name(chain_id), int(entry["eid"]), rpc, entry["delegate"])
        addresses = registry.get(chain_id, registry["default"])
        ofts[chain_id] = {t: checksum(addresses[TOKEN_SLOTS.index(t)]) for t in active
                          if int(addresses[TOKEN_SLOTS.index(t)], 16) != 0}
    return Mesh(chains, ofts, active, sorted(universe), deprecated)


def resolve_chain(key: str, mesh: Mesh, *, peer: bool) -> Tuple[int, int]:
    """Config key (name, alias or numeric chain id) -> (chain id, eid)."""
    raw = str(key).strip().lower()
    raw = ALIASES.get(raw, raw)
    by_name = {name: cid for cid, (name, _) in list(CHAINS.items()) + list(RETIRED_CHAINS.items())}
    if raw.isdigit():
        chain_id = int(raw)
    elif raw in by_name:
        chain_id = by_name[raw]
    else:
        raise ConfigError(f"unknown chain {key!r} (use a name such as 'fraxtal' or a chain id)")
    if peer:
        if chain_id in mesh.chains:
            return chain_id, mesh.chains[chain_id].eid
        known = CHAINS.get(chain_id) or RETIRED_CHAINS.get(chain_id)
        if not known:
            raise ConfigError(f"unknown peer chain {key!r}")
        return chain_id, known[1]
    if chain_id not in mesh.chains:
        raise ConfigError(f"chain {key!r} is not an active EVM chain of the mesh (L0Config Proxy, not deprecated)")
    return chain_id, mesh.chains[chain_id].eid


def resolve_token(key: str) -> str:
    slot = str(key).strip().upper()
    if slot not in TOKEN_SLOTS:
        raise ConfigError(f"unknown token {key!r} (one of {', '.join(TOKEN_DISPLAY[t] for t in TOKEN_SLOTS)})")
    return slot


# ---------------------------------------------------------------------------------------------
# Config: parsing and compilation into the desired on-chain state
# ---------------------------------------------------------------------------------------------

class ConfigError(Exception):
    pass


ENTRY_KEYS = {"globallyDisabled", "default", "peers", "note"}
DURATION_UNITS = {"s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
                  "min": 60, "mins": 60, "minute": 60, "minutes": 60,
                  "h": 3600, "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600,
                  "d": 86400, "day": 86400, "days": 86400, "w": 604800, "week": 604800, "weeks": 604800}


def parse_duration(raw, where: str) -> int:
    if isinstance(raw, bool):
        raise ConfigError(f"{where}: window must be seconds or a duration string, got {raw!r}")
    if isinstance(raw, int):
        seconds = raw
    elif isinstance(raw, str):
        match = re.fullmatch(r"\s*(\d+)\s*([a-zA-Z]*)\s*", raw)
        unit = match.group(2).lower() if match else None
        if not match or (unit and unit not in DURATION_UNITS):
            raise ConfigError(f"{where}: cannot parse window {raw!r} (use e.g. 86400, '3600s', '30min', '12h', '1d'; "
                              f"'m' is ambiguous and not accepted)")
        seconds = int(match.group(1)) * (DURATION_UNITS[unit] if unit else 1)
    else:
        raise ConfigError(f"{where}: window must be seconds or a duration string, got {raw!r}")
    if not 0 < seconds <= UINT32_MAX:
        raise ConfigError(f"{where}: window {raw!r} must be between 1 second and {UINT32_MAX} seconds")
    return seconds


def parse_amount(raw, where: str) -> Decimal:
    """Whole-token amount -> Decimal. Integers or decimal strings; '_' allowed as a separator."""
    if isinstance(raw, bool) or isinstance(raw, float):
        raise ConfigError(f"{where}: write amounts as a string or an integer, not {raw!r} (floats lose precision)")
    text = str(raw).replace("_", "").strip() if isinstance(raw, (int, str)) else None
    if text is None or not re.fullmatch(r"\d+(\.\d+)?", text):
        raise ConfigError(f"{where}: cannot parse amount {raw!r} (whole tokens, e.g. \"1_000_000\" or \"2500.5\")")
    value = Decimal(text)
    if value <= 0:
        raise ConfigError(f"{where}: an enabled limit must be positive (use \"off\" to disable a direction)")
    return value


def to_base_units(amount: Decimal, decimals: int, where: str) -> int:
    scaled = amount.scaleb(decimals)
    if scaled != scaled.to_integral_value():
        raise ConfigError(f"{where}: {amount} has more than {decimals} decimal places for this token")
    return int(scaled)


@dataclass(frozen=True)
class DirectionSpec:
    """A direction as written in the config, before decimals are known."""
    enabled: bool
    amount: Decimal = Decimal(0)
    window: int = 0
    blocked: bool = False


SPEC_OFF = DirectionSpec(False)
# "blocked": the smallest limit the contract accepts (limit == window: one base unit per second),
# i.e. 86,400 base units a day - a lane direction stopped for practical purposes, peers untouched.
SPEC_BLOCKED = DirectionSpec(True, Decimal(0), 86400, True)


def parse_direction(raw, where: str) -> DirectionSpec:
    if raw is None or raw == "off":
        return SPEC_OFF
    if raw == "blocked":
        return SPEC_BLOCKED
    if not isinstance(raw, dict):
        raise ConfigError(f"{where}: a direction is \"off\", \"blocked\" or {{\"limit\": ..., \"window\": ...}}, got {raw!r}")
    unknown = set(raw) - {"limit", "window", "note"}
    if unknown or "limit" not in raw or "window" not in raw:
        raise ConfigError(f"{where}: a direction needs exactly 'limit' and 'window' (optional 'note'), got {sorted(raw)}")
    return DirectionSpec(True, parse_amount(raw["limit"], f"{where}.limit"), parse_duration(raw["window"], f"{where}.window"))


def parse_pair(raw, where: str, allow_partial: bool) -> Dict[str, DirectionSpec]:
    if raw is None:
        raw = {}
    if not isinstance(raw, dict):
        raise ConfigError(f"{where}: expected an object with 'outbound' and/or 'inbound'")
    unknown = set(raw) - {"outbound", "inbound", "note"}
    if unknown:
        raise ConfigError(f"{where}: unknown keys {sorted(unknown)} (expected 'outbound', 'inbound', 'note')")
    pair = {}
    for direction in ("outbound", "inbound"):
        if direction in raw:
            pair[direction] = parse_direction(raw[direction], f"{where}.{direction}")
        elif not allow_partial:
            pair[direction] = SPEC_OFF
    return pair


@dataclass
class EntrySpec:
    globally_disabled: Optional[bool] = None
    default: Optional[Dict[str, DirectionSpec]] = None
    peers: Optional[Dict[int, Dict[str, DirectionSpec]]] = None   # peer eid -> partial pair


@dataclass
class Config:
    path: str
    tokens: Dict[str, Dict[object, EntrySpec]]   # token slot -> chain id or "*" -> entry


def parse_config(raw: dict, mesh: Mesh, path: str = "<config>") -> Config:
    if not isinstance(raw, dict):
        raise ConfigError("config root must be an object")
    unknown = set(raw) - {"schema", "tokens", "note"}
    if unknown:
        raise ConfigError(f"unknown top-level keys {sorted(unknown)}")
    if raw.get("schema") != 1:
        raise ConfigError(f"unsupported schema {raw.get('schema')!r} (expected 1)")
    tokens: Dict[str, Dict[object, EntrySpec]] = {}
    for token_key, chains in (raw.get("tokens") or {}).items():
        token = resolve_token(token_key)
        if token in tokens:
            raise ConfigError(f"token {token_key!r} listed twice")
        if token not in mesh.active_tokens:
            raise ConfigError(f"token {token_key!r} is not an active mesh token")
        if not isinstance(chains, dict):
            raise ConfigError(f"tokens.{token_key}: expected an object keyed by chain")
        entries: Dict[object, EntrySpec] = {}
        for chain_key, entry in chains.items():
            if chain_key == "note":
                continue
            where = f"tokens.{token_key}.{chain_key}"
            key = "*" if chain_key == "*" else resolve_chain(chain_key, mesh, peer=False)[0]
            if key in entries:
                raise ConfigError(f"{where}: chain listed twice in {token_key}")
            if not isinstance(entry, dict):
                raise ConfigError(f"{where}: expected an object")
            bad = set(entry) - ENTRY_KEYS
            if bad:
                raise ConfigError(f"{where}: unknown keys {sorted(bad)} (expected {sorted(ENTRY_KEYS)})")
            spec = EntrySpec()
            if "globallyDisabled" in entry:
                if not isinstance(entry["globallyDisabled"], bool):
                    raise ConfigError(f"{where}.globallyDisabled must be true or false")
                spec.globally_disabled = entry["globallyDisabled"]
            if "default" in entry:
                spec.default = parse_pair(entry["default"], f"{where}.default", allow_partial=False)
            if "peers" in entry:
                if not isinstance(entry["peers"], dict):
                    raise ConfigError(f"{where}.peers: expected an object keyed by peer chain")
                spec.peers = {}
                for peer_key, pair in entry["peers"].items():
                    if peer_key == "note":
                        continue
                    _, eid = resolve_chain(peer_key, mesh, peer=True)
                    if eid in spec.peers:
                        raise ConfigError(f"{where}.peers: peer {peer_key!r} listed twice")
                    if key != "*" and eid == mesh.chains[key].eid:
                        raise ConfigError(f"{where}.peers.{peer_key}: a chain cannot rate-limit itself")
                    spec.peers[eid] = parse_pair(pair, f"{where}.peers.{peer_key}", allow_partial=True)
            entries[key] = spec
        tokens[token] = entries
    return Config(path, tokens)


def load_config(path: str, mesh: Mesh) -> Config:
    try:
        with open(path) as handle:
            raw = json.load(handle)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"{path}: invalid JSON: {exc}")
    return parse_config(raw, mesh, path)


@dataclass
class Desired:
    source: str
    globally_disabled: bool
    default: RLConfig
    overrides: Dict[int, RLConfig]
    inherited: Dict[int, Tuple[bool, bool]] = field(default_factory=dict)
    notes: List[str] = field(default_factory=list)

    def effective(self, eid: int) -> RLConfig:
        return self.overrides.get(eid, self.default)

    def is_off(self) -> bool:
        return not self.globally_disabled and self.default == EMPTY and not self.overrides


def _materialize(spec: DirectionSpec, decimals: int, where: str) -> Direction:
    if not spec.enabled:
        return OFF
    if spec.blocked:
        return Direction(True, spec.window, spec.window)
    limit = to_base_units(spec.amount, decimals, where)
    if limit > UINT112_MAX:
        raise ConfigError(f"{where}: limit {spec.amount} exceeds uint112 in base units")
    if limit < spec.window:
        # RateLimiterLib._validateRateLimitConfig: an enabled direction must refill >= 1 base unit/s.
        raise ConfigError(f"{where}: limit {spec.amount} is below the window length in base units "
                          f"({limit} < {spec.window}); the contract rejects it")
    return Direction(True, limit, spec.window)


def compile_desired(config: Config, token: str, chain: Chain, decimals: int) -> Desired:
    """The exact on-chain state rate-limits.json asks for on one OFT."""
    entries = config.tokens.get(token, {})
    star, own = entries.get("*"), entries.get(chain.chain_id)
    if star is None and own is None:
        return Desired("unlisted (no limits)", False, EMPTY, {})
    label = f"{TOKEN_DISPLAY[token]}.{chain.name if own else '*'}"
    if own and star:
        label = f"{TOKEN_DISPLAY[token]}.{chain.name} over {TOKEN_DISPLAY[token]}.*"

    def pick(attr):
        # A chain entry overrides `*` field by field (no deep merge).
        value = getattr(own, attr) if own else None
        return value if value is not None else (getattr(star, attr) if star else None)

    globally_disabled = bool(pick("globally_disabled"))
    default_spec = pick("default") or {"outbound": SPEC_OFF, "inbound": SPEC_OFF}
    where = f"tokens.{TOKEN_DISPLAY[token]}.{chain.name}"
    out_default = _materialize(default_spec["outbound"], decimals, f"{where}.default.outbound")
    in_default = _materialize(default_spec["inbound"], decimals, f"{where}.default.inbound")
    desired = Desired(label, globally_disabled, RLConfig(False, out_default, in_default), {})

    peers = pick("peers") or {}
    for eid, pair in sorted(peers.items()):
        if eid == chain.eid:
            desired.notes.append(f"skipped the `*` peer entry for {eid_name(eid)}: it is this chain")
            continue
        pwhere = f"{where}.peers.{eid_name(eid)}"
        outbound = _materialize(pair["outbound"], decimals, f"{pwhere}.outbound") if "outbound" in pair else out_default
        inbound = _materialize(pair["inbound"], decimals, f"{pwhere}.inbound") if "inbound" in pair else in_default
        desired.overrides[eid] = RLConfig(True, outbound, inbound)
        desired.inherited[eid] = ("outbound" not in pair, "inbound" not in pair)
    return desired


# ---------------------------------------------------------------------------------------------
# Live state
# ---------------------------------------------------------------------------------------------

@dataclass
class Owner:
    address: str
    kind: str = "unknown"        # safe | timelock | eoa | contract | unknown
    threshold: int = 0
    owners: int = 0

    def describe(self) -> str:
        if self.kind == "safe":
            return f"Safe {self.threshold}/{self.owners}"
        return self.kind


@dataclass
class LiveOft:
    token: str
    address: str
    capable: bool = False
    version: Optional[str] = None
    owner: Optional[str] = None
    decimals: Optional[int] = None
    globally_disabled: bool = False
    default: RLConfig = EMPTY
    stored: Dict[int, RLConfig] = field(default_factory=dict)
    tracked: Dict[int, bool] = field(default_factory=dict)
    usage: Dict[int, Tuple[int, int]] = field(default_factory=dict)     # current (decayed) usage
    peers: Dict[int, str] = field(default_factory=dict)
    errors: List[str] = field(default_factory=list)

    def effective(self, eid: int) -> RLConfig:
        stored = self.stored.get(eid, EMPTY)
        return stored if stored.override else self.default

    def peered(self) -> List[int]:
        return sorted(eid for eid, peer in self.peers.items() if peer != ZERO32)


@dataclass
class ChainLive:
    chain: Chain
    block: int = 0
    timestamp: int = 0
    ofts: Dict[str, LiveOft] = field(default_factory=dict)
    owners: Dict[str, Owner] = field(default_factory=dict)
    error: Optional[str] = None


def _u32(value: int) -> bytes:
    return word(value)


def decode_version(raw: bytes) -> Optional[str]:
    """v1.1.0+ return a string; the oldest lockboxes return (major, minor, patch)."""
    try:
        return read_string(raw)
    except DecodeError:
        if len(raw) == 96:
            return "v" + ".".join(str(w) for w in read_words(raw, 3))
        return None


def read_chain(chain: Chain, mesh: Mesh, tokens: List[str], rpc: Optional[Rpc] = None) -> ChainLive:
    rpc = rpc or Rpc(chain.rpc, chain.name)
    live = ChainLive(chain)
    try:
        actual = rpc.chain_id()
        if actual != chain.chain_id:
            raise RpcError(f"RPC {chain.rpc} serves chain {actual}, expected {chain.chain_id}")
        eids = [e for e in mesh.universe_eids if e != chain.eid]
        ofts = {t: a for t, a in mesh.ofts[chain.chain_id].items() if t in tokens}

        # Phase A: identity, decimals and whether the rate limiter exists (v1.2.0+). With Multicall3 the
        # block number and timestamp come from the same eth_call as these values. Phase B is a second
        # round trip seconds later; batches set absolute values and `check` re-reads after execution,
        # so a change landing in between cannot leave a wrong state behind unnoticed.
        calls, keys = [], []
        if rpc.has_multicall():
            calls += [(MULTICALL3, SEL["getBlockNumber"]), (MULTICALL3, SEL["getCurrentBlockTimestamp"])]
            keys += [("meta", "block"), ("meta", "timestamp")]
        for token, address in ofts.items():
            for name in ("owner", "version", "token", "sharedDecimals", "decimalConversionRate",
                         "rateLimitGlobalConfig", "defaultRateLimitConfig"):
                calls.append((address, SEL[name]))
                keys.append((token, name))
        values = dict(zip(keys, rpc.call_many(calls)))
        if values.get(("meta", "block"), (False, b""))[0] and values[("meta", "timestamp")][0]:
            live.block = read_words(values[("meta", "block")][1], 1)[0]
            live.timestamp = read_words(values[("meta", "timestamp")][1], 1)[0]
        else:
            live.block, live.timestamp = rpc.latest_block()

        token_addresses = {}
        for token, address in ofts.items():
            oft = LiveOft(token, address)
            live.ofts[token] = oft
            ok, raw = values[(token, "owner")]
            if not ok:
                oft.errors.append("owner() failed: no OFT at this address?")
                continue
            oft.owner = read_address(raw)
            ok, raw = values[(token, "version")]
            oft.version = decode_version(raw) if ok else None
            ok_shared, shared = values[(token, "sharedDecimals")]
            ok_rate, rate = values[(token, "decimalConversionRate")]
            if ok_shared and ok_rate:
                shared_decimals, conversion = read_words(shared, 1)[0], read_words(rate, 1)[0]
                if conversion < 1 or 10 ** (len(str(conversion)) - 1) != conversion:
                    oft.errors.append(f"decimalConversionRate {conversion} is not a power of ten")
                else:
                    oft.decimals = shared_decimals + len(str(conversion)) - 1
            ok, raw = values[(token, "token")]
            if ok:
                token_addresses[token] = read_address(raw)
            ok, raw = values[(token, "rateLimitGlobalConfig")]
            ok_default, raw_default = values[(token, "defaultRateLimitConfig")]
            if ok and ok_default:
                oft.capable = True
                oft.globally_disabled = read_bool(raw)
                oft.default = decode_config(raw_default)

        # Phase B: peers everywhere; per-eid limiter state on capable OFTs; token decimals cross-check.
        calls, keys = [], []
        for token, oft in live.ofts.items():
            if oft.owner is None:
                continue
            for eid in eids:
                calls.append((oft.address, SEL["peers"] + _u32(eid)))
                keys.append((token, "peers", eid))
                if oft.capable:
                    for name in ("storedRateLimitConfig", "storedRateLimitState", "rateLimitState"):
                        calls.append((oft.address, SEL[name] + _u32(eid)))
                        keys.append((token, name, eid))
            if token in token_addresses:
                calls.append((token_addresses[token], SEL["decimals"]))
                keys.append((token, "tokenDecimals", 0))
        owners = sorted({o.owner for o in live.ofts.values() if o.owner})
        for owner in owners:
            for name in ("getThreshold", "getOwners", "delay", "admin"):
                calls.append((owner, SEL[name]))
                keys.append((owner, name, 0))
        values = dict(zip(keys, rpc.call_many(calls)))

        for token, oft in live.ofts.items():
            if oft.owner is None:
                continue
            for eid in eids:
                ok, raw = values[(token, "peers", eid)]
                oft.peers[eid] = "0x" + raw[:32].hex() if ok and len(raw) >= 32 else ZERO32
                if not oft.capable:
                    continue
                ok_c, raw_c = values[(token, "storedRateLimitConfig", eid)]
                ok_s, raw_s = values[(token, "storedRateLimitState", eid)]
                ok_u, raw_u = values[(token, "rateLimitState", eid)]
                if not (ok_c and ok_s and ok_u):
                    oft.errors.append(f"rate-limit reads reverted for eid {eid}")
                    continue
                oft.stored[eid] = decode_config(raw_c)
                oft.tracked[eid] = read_words(raw_s, 3)[2] != 0
                out_usage, in_usage, _ = read_words(raw_u, 3)
                oft.usage[eid] = (out_usage, in_usage)
            if (token, "tokenDecimals", 0) in values:
                ok, raw = values[(token, "tokenDecimals", 0)]
                if ok and oft.decimals is not None and read_words(raw, 1)[0] != oft.decimals:
                    oft.errors.append(f"token decimals {read_words(raw, 1)[0]} != OFT local decimals {oft.decimals}")
        for owner in owners:
            info = Owner(owner)
            ok_t, raw_t = values[(owner, "getThreshold", 0)]
            ok_o, raw_o = values[(owner, "getOwners", 0)]
            ok_d, _ = values[(owner, "delay", 0)]
            ok_a, _ = values[(owner, "admin", 0)]
            if ok_t and ok_o:
                info.kind, info.threshold, info.owners = "safe", read_words(raw_t, 1)[0], len(read_address_array(raw_o))
            elif ok_d and ok_a:
                info.kind = "timelock"
            else:
                info.kind = "contract" if rpc.code(owner) else "eoa"
            live.owners[owner] = info
    except (RpcError, Reverted, DecodeError, OSError, KeyError, ValueError) as exc:
        live.error = f"{type(exc).__name__}: {exc}"
    return live


def read_chains(mesh: Mesh, chain_ids: List[int], tokens: List[str], workers: int = 8) -> Dict[int, ChainLive]:
    with ThreadPoolExecutor(max_workers=max(1, min(workers, len(chain_ids)))) as pool:
        futures = {cid: pool.submit(read_chain, mesh.chains[cid], mesh, tokens) for cid in chain_ids}
    return {cid: futures[cid].result() for cid in chain_ids}


# ---------------------------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------------------------

def fmt_amount(base_units: int, decimals: Optional[int]) -> str:
    if decimals is None:
        return f"{base_units} (base units)"
    value = Decimal(base_units).scaleb(-decimals)
    text = f"{value:,.{min(decimals, 6)}f}"
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    if value != 0 and text in ("0", "0.0"):
        return f"<{Decimal(1).scaleb(-min(decimals, 6))}"
    return text


def fmt_window(seconds: int) -> str:
    for size, unit in ((604800, "w"), (86400, "d"), (3600, "h"), (60, "min")):
        if seconds % size == 0:
            return f"{seconds // size}{unit}"
    return f"{seconds}s"


def fmt_direction(direction: Direction, decimals: Optional[int], symbol: str = "") -> str:
    if not direction.enabled:
        stray = f" (stored limit {direction.limit}, window {direction.window})" if direction.limit or direction.window else ""
        return "off" + stray
    unit = f" {symbol}" if symbol else ""
    if direction.limit == direction.window:
        return f"blocked ({direction.limit} base units / {fmt_window(direction.window)}, the contract minimum)"
    return f"{fmt_amount(direction.limit, decimals)}{unit} / {fmt_window(direction.window)}"


def fmt_config(config: RLConfig, decimals: Optional[int], symbol: str = "") -> str:
    if config.is_empty():
        return "none"
    prefix = "override " if config.override else ""
    return f"{prefix}out {fmt_direction(config.outbound, decimals, symbol)}, in {fmt_direction(config.inbound, decimals, symbol)}"


def display_path(path: str) -> str:
    path = os.path.abspath(path)
    return os.path.relpath(path, ROOT) if path.startswith(ROOT + os.sep) else path


def short(address: str) -> str:
    return f"{address[:6]}…{address[-4:]}"


def utc(timestamp: int) -> str:
    return datetime.datetime.fromtimestamp(timestamp, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")


# ---------------------------------------------------------------------------------------------
# Planning
# ---------------------------------------------------------------------------------------------

@dataclass
class Call:
    name: str
    to: str
    data: bytes
    lines: List[str]


@dataclass
class OftPlan:
    chain: Chain
    token: str
    oft: LiveOft
    desired: Optional[Desired]
    calls: List[Call] = field(default_factory=list)
    status: str = "ok"            # ok | pending-upgrade | error
    messages: List[str] = field(default_factory=list)


def _direction_change(label: str, old: Direction, new: Direction, decimals: int, symbol: str) -> Optional[str]:
    if old == new:
        return None
    return f"{label} {fmt_direction(old, decimals, symbol)} -> {fmt_direction(new, decimals, symbol)}"


def plan_oft(chain: Chain, oft: LiveOft, desired: Desired) -> List[Call]:
    """Calls (in execution order) that turn the live OFT into `desired`. Empty when they already match.

    Order follows scripts/DeployFraxOFTProtocol/inherited/SetRateLimits.s.sol: global switch, checkpoint
    of untracked peered eids, default, per-eid configs. A Safe batch is atomic, so the order only
    affects how usage is settled across the change (always clamped, never inflated).
    """
    symbol, decimals = TOKEN_DISPLAY[oft.token], oft.decimals
    calls: List[Call] = []

    if oft.globally_disabled != desired.globally_disabled:
        state = "DISABLED (limits bypassed)" if desired.globally_disabled else "enforced"
        calls.append(Call("setRateLimitGlobalConfig", oft.address, calldata_set_global(desired.globally_disabled),
                          [f"global switch -> {state}"]))

    params: List[Tuple[int, RLConfig]] = []
    lines: List[str] = []
    candidates = set(desired.overrides) | {eid for eid, cfg in oft.stored.items() if not cfg.is_empty()}
    for eid in sorted(candidates):
        want = desired.overrides.get(eid, EMPTY)
        have = oft.stored.get(eid, EMPTY)
        if want == have:
            continue
        params.append((eid, want))
        peered = "" if oft.peers.get(eid, ZERO32) != ZERO32 else " [no peer set: inert until wired]"
        if want.is_empty():
            lines.append(f"{eid} {eid_name(eid)}: clear override ({fmt_config(have, decimals, symbol)}) -> follows default{peered}")
        else:
            inherited = desired.inherited.get(eid, (False, False))
            tags = [d for d, inh in zip(("outbound", "inbound"), inherited) if inh]
            note = f" ({' and '.join(tags)} from default)" if tags else ""
            lines.append(f"{eid} {eid_name(eid)}: {fmt_config(have, decimals, symbol)} -> {fmt_config(want, decimals, symbol)}{note}{peered}")
    written = {eid for eid, _ in params}

    # Register peered eids that will be armed but have never been written: their first armed delivery
    # would otherwise pay the trackedEids push inside lzReceive (see SetRateLimits._registerRateLimitEids).
    untracked = [eid for eid in oft.peered()
                 if not oft.tracked.get(eid, False) and eid not in written
                 and (desired.effective(eid).outbound.enabled or desired.effective(eid).inbound.enabled)]
    if untracked:
        calls.append(Call("checkpointRateLimits", oft.address, calldata_checkpoint(untracked), [
            f"register {len(untracked)} untracked peered eid(s): " + ", ".join(f"{e} {eid_name(e)}" for e in untracked)]))

    if oft.default != desired.default:
        changes = [c for c in (
            _direction_change("outbound", oft.default.outbound, desired.default.outbound, decimals, symbol),
            _direction_change("inbound", oft.default.inbound, desired.default.inbound, decimals, symbol)) if c]
        if oft.default.override != desired.default.override:
            changes.append("clear the override flag stored on the default")
        calls.append(Call("setDefaultRateLimitConfig", oft.address, calldata_set_default(desired.default),
                          ["default: " + "; ".join(changes)]))

    if params:
        calls.append(Call("setRateLimitConfigs", oft.address, calldata_set_configs(params), lines))
    return calls


def impact_lines(oft: LiveOft, desired: Desired) -> List[str]:
    """Lanes whose current usage the change clamps (tightened or disabled while in use)."""
    out = []
    for eid in sorted(oft.usage):
        used_out, used_in = oft.usage[eid]
        old, new = oft.effective(eid), desired.effective(eid)
        for label, used, before, after in (("outbound", used_out, old.outbound, new.outbound),
                                           ("inbound", used_in, old.inbound, new.inbound)):
            if used == 0 or before == after:
                continue
            if not after.enabled:
                out.append(f"{eid_name(eid)} lane {label}: usage {fmt_amount(used, oft.decimals)} dropped (direction disabled)")
            elif used > after.limit:
                out.append(f"{eid_name(eid)} lane {label}: usage {fmt_amount(used, oft.decimals)} clamped to the new limit; "
                           f"lane exhausted until it refills ({fmt_window(after.window)} for a full refill)")
            else:
                out.append(f"{eid_name(eid)} lane {label}: usage {fmt_amount(used, oft.decimals)} kept, "
                           f"{fmt_amount(after.limit - used, oft.decimals)} available after the change")
    return out


def build_plans(config: Config, mesh: Mesh, lives: Dict[int, ChainLive], tokens: List[str]) -> List[OftPlan]:
    plans = []
    for cid, live in lives.items():
        chain = mesh.chains[cid]
        if live.error:
            continue
        for token in tokens:
            oft = live.ofts.get(token)
            if oft is None:
                continue
            plan = OftPlan(chain, token, oft, None)
            plans.append(plan)
            if oft.errors and oft.owner is None:
                plan.status, plan.messages = "error", list(oft.errors)
                continue
            if oft.decimals is None:
                plan.status, plan.messages = "error", ["could not determine local decimals"] + oft.errors
                continue
            try:
                plan.desired = compile_desired(config, token, chain, oft.decimals)
            except ConfigError as exc:
                plan.status, plan.messages = "error", [str(exc)]
                continue
            plan.messages.extend(plan.desired.notes)
            if not oft.capable:
                if plan.desired.is_off():
                    continue
                if not oft.peered():
                    # Disconnected and never upgraded (a chain being retired): nothing can flow, nothing to apply.
                    plan.messages.append(f"OFT is {oft.version or 'pre-v1.2.0'} with no peers: disconnected, ignored")
                    continue
                plan.status = "pending-upgrade"
                plan.messages.append(f"OFT is {oft.version or 'pre-v1.2.0'} without the rate limiter; "
                                     f"the configured limits apply once it is upgraded")
                continue
            if oft.errors:
                plan.status, plan.messages = "error", plan.messages + oft.errors
                continue
            for eid in plan.desired.overrides:
                if oft.peers.get(eid, ZERO32) == ZERO32:
                    plan.messages.append(f"override for {eid_name(eid)} ({eid}) but the OFT has no peer there: inert")
            plan.calls = plan_oft(chain, oft, plan.desired)
    return plans


# ---------------------------------------------------------------------------------------------
# Lane lint (hub-and-spoke: every lane is Fraxtal <-> spoke)
# ---------------------------------------------------------------------------------------------

def lint_lanes(plans: List[OftPlan], mesh: Mesh, headroom: Decimal) -> List[str]:
    """Compare each lane's outbound limit at the source with the inbound limit at the destination.

    An inbound limit below what the source lets out means transfers that cleared the source revert
    in lzReceive and sit at the destination endpoint until someone retries them. Delivery delays can
    bunch messages up, so the destination wants headroom on top of the source's limit.
    """
    by_key = {(p.chain.chain_id, p.token): p for p in plans if p.desired is not None and p.oft.decimals is not None}
    eid_to_chain = {c.eid: cid for cid, c in mesh.chains.items()}
    warnings = []
    for (cid, token), source in sorted(by_key.items(), key=lambda kv: (kv[0][1], kv[1].chain.name)):
        for eid in source.oft.peered():
            dst_cid = eid_to_chain.get(eid)
            dest = by_key.get((dst_cid, token)) if dst_cid else None
            if dest is None:
                continue
            out = source.desired.effective(eid).outbound
            inb = dest.desired.effective(source.chain.eid).inbound
            if source.desired.globally_disabled:
                out = OFF
            if dest.desired.globally_disabled:
                inb = OFF
            lane = f"{TOKEN_DISPLAY[token]} {source.chain.name} -> {dest.chain.name}"
            if not inb.enabled:
                continue
            if not out.enabled:
                warnings.append(f"{lane}: inbound limit at {dest.chain.name} ({fmt_direction(inb, dest.oft.decimals)}) "
                                f"with no outbound limit at {source.chain.name}: oversized transfers clear the source and "
                                f"get stuck (retryable) at the destination instead of reverting at send")
                continue
            out_tokens = Decimal(out.limit).scaleb(-source.oft.decimals)
            in_tokens = Decimal(inb.limit).scaleb(-dest.oft.decimals)
            if in_tokens < out_tokens * (1 + headroom):
                warnings.append(f"{lane}: inbound {fmt_direction(inb, dest.oft.decimals)} at {dest.chain.name} is below "
                                f"outbound {fmt_direction(out, source.oft.decimals)} at {source.chain.name} + "
                                f"{headroom * 100:.0f}% headroom; delayed deliveries that bunch up would revert in lzReceive")
            elif in_tokens / inb.window < out_tokens / out.window:
                warnings.append(f"{lane}: inbound refills slower at {dest.chain.name} ({fmt_direction(inb, dest.oft.decimals)}) "
                                f"than outbound at {source.chain.name} ({fmt_direction(out, source.oft.decimals)})")
    return warnings


# ---------------------------------------------------------------------------------------------
# Batches, simulation, output
# ---------------------------------------------------------------------------------------------

@dataclass
class Batch:
    chain: Chain
    owner: Owner
    plans: List[OftPlan]
    calls: List[Call]
    timestamp: int
    simulation: List[str] = field(default_factory=list)
    failures: List[str] = field(default_factory=list)
    gas: Optional[int] = None
    call_gas: List[Optional[int]] = field(default_factory=list)


def group_batches(plans: List[OftPlan], lives: Dict[int, ChainLive]) -> List[Batch]:
    groups: Dict[Tuple[int, str], Batch] = {}
    for plan in plans:
        if not plan.calls:
            continue
        live = lives[plan.chain.chain_id]
        owner = live.owners.get(plan.oft.owner) or Owner(plan.oft.owner)
        key = (plan.chain.chain_id, plan.oft.owner.lower())
        batch = groups.setdefault(key, Batch(plan.chain, owner, [], [], live.timestamp))
        batch.plans.append(plan)
        batch.calls.extend(plan.calls)
    return [groups[k] for k in sorted(groups, key=lambda k: chain_sort_key(k[0]) + (k[1],))]


def chain_sort_key(chain_id: int) -> tuple:
    hubs = {FRAXTAL_CHAIN_ID: 0, 1: 1}
    return (hubs.get(chain_id, 2), chain_name(chain_id))


def simulate(batch: Batch) -> None:
    """eth_call every call from the owner. The setters only revert on input or ownership, never on state
    an earlier call in the batch changed, so per-call simulation covers the batch."""
    rpc = Rpc(batch.chain.rpc, batch.chain.name)
    if batch.owner.kind != "safe":
        batch.failures.append(f"owner {batch.owner.address} is a {batch.owner.kind}, not a Safe; "
                              f"a Transaction Builder batch cannot be executed by it")
    total, gas_ok = 0, True
    batch.call_gas = []
    for index, call in enumerate(batch.calls, 1):
        try:
            rpc.call(call.to, call.data, sender=batch.owner.address)
        except Reverted as exc:
            batch.failures.append(f"tx {index} {call.name} reverts as {short(batch.owner.address)}: {exc.reason()}")
            batch.call_gas.append(None)
            continue
        except RpcError as exc:
            batch.failures.append(f"tx {index} {call.name}: simulation RPC error: {exc}")
            batch.call_gas.append(None)
            continue
        try:
            gas = rpc.estimate_gas(call.to, call.data, batch.owner.address)
            batch.call_gas.append(gas)
            total += gas
        except (Reverted, RpcError):
            batch.call_gas.append(None)
            gas_ok = False
    batch.gas = total if gas_ok else None
    ok = len(batch.calls) - len([f for f in batch.failures if f.startswith("tx ")])
    batch.simulation.append(f"eth_call as owner: {ok}/{len(batch.calls)} OK"
                            + (f"; est. gas {total:,}" if gas_ok else "; gas estimate unavailable"))


def batch_document(batch: Batch) -> dict:
    return {
        "chainId": batch.chain.chain_id,
        "createdAt": batch.timestamp * 1000,
        "meta": {"description": "", "name": "Transactions Batch"},
        "transactions": [{"data": "0x" + c.data.hex(), "operation": "0", "to": checksum(c.to), "value": "0"}
                         for c in batch.calls],
        "version": "1.0",
    }


def batch_filename(prefix: str, batch: Batch) -> str:
    return f"{prefix}-{batch.chain.chain_id}-{batch.owner.address.lower()}.json"


def describe_batch(batch: Batch) -> List[str]:
    lines = [f"{batch.chain.name} ({batch.chain.chain_id}) - owner {batch.owner.address} "
             f"({batch.owner.describe()}) - {len(batch.calls)} tx(s)"]
    index = 0
    for plan in batch.plans:
        lines.append(f"  {TOKEN_DISPLAY[plan.token]} {plan.oft.address}  [{plan.desired.source}]")
        for call in plan.calls:
            index += 1
            gas = batch.call_gas[index - 1] if index - 1 < len(batch.call_gas) else None
            lines.append(f"    {index}. {call.name}" + (f"  (~{gas:,} gas)" if gas else ""))
            for line in call.lines:
                lines.append(f"         {line}")
        for line in impact_lines(plan.oft, plan.desired):
            lines.append(f"       impact: {line}")
        for message in plan.messages:
            lines.append(f"       note: {message}")
    for line in batch.simulation:
        lines.append(f"  simulation: {line}")
    for failure in batch.failures:
        lines.append(f"  FAILED: {failure}")
    return lines


def write_outputs(out_dir: str, prefix: str, batches: List[Batch], report: List[str], plan_json: dict) -> List[str]:
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for batch in batches:
        path = os.path.join(out_dir, batch_filename(prefix, batch))
        with open(path, "w") as handle:
            json.dump(batch_document(batch), handle, indent=2, sort_keys=True)
            handle.write("\n")
        written.append(path)
    with open(os.path.join(out_dir, "summary.md"), "w") as handle:
        handle.write("\n".join(report) + "\n")
    with open(os.path.join(out_dir, "plan.json"), "w") as handle:
        json.dump(plan_json, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return written + [os.path.join(out_dir, "summary.md"), os.path.join(out_dir, "plan.json")]


def config_json(config: RLConfig) -> dict:
    return {"overrideDefaultConfig": config.override,
            "outboundEnabled": config.outbound.enabled, "outboundLimit": str(config.outbound.limit),
            "outboundWindow": config.outbound.window,
            "inboundEnabled": config.inbound.enabled, "inboundLimit": str(config.inbound.limit),
            "inboundWindow": config.inbound.window}


def plan_document(batches: List[Batch], config_path: str, lives: Dict[int, ChainLive]) -> dict:
    return {
        "config": display_path(config_path),
        "batches": [{
            "chainId": b.chain.chain_id, "chain": b.chain.name, "owner": b.owner.address,
            "readAtBlock": lives[b.chain.chain_id].block, "readAtTimestamp": lives[b.chain.chain_id].timestamp,
            "simulation": b.simulation, "failures": b.failures, "estimatedGas": b.gas,
            "ofts": [{
                "token": TOKEN_DISPLAY[p.token], "address": p.oft.address, "decimals": p.oft.decimals,
                "desired": {"globallyDisabled": p.desired.globally_disabled,
                            "default": config_json(p.desired.default),
                            "overrides": {str(e): config_json(c) for e, c in sorted(p.desired.overrides.items())}},
                "calls": [{"name": c.name, "to": c.to, "data": "0x" + c.data.hex(), "description": c.lines}
                          for c in p.calls],
                "impact": impact_lines(p.oft, p.desired),
            } for p in b.plans],
        } for b in batches],
    }


# ---------------------------------------------------------------------------------------------
# anvil
# ---------------------------------------------------------------------------------------------

def anvil_binary() -> str:
    found = shutil.which("anvil") or os.path.expanduser("~/.foundry/bin/anvil")
    if not os.path.exists(found):
        raise RuntimeError("anvil not found (install Foundry or put anvil on PATH)")
    return found


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Anvil:
    def __init__(self, fork_url: str, extra: Tuple[str, ...] = ()):
        self.port = free_port()
        self.url = f"http://127.0.0.1:{self.port}"
        # A zero base fee lets impersonated owners send at gas price 0, so no chain needs them funded
        # (Tempo forks charge fees in a TIP-20 fee token that anvil_setBalance does not touch).
        self.process = subprocess.Popen(
            [anvil_binary(), "--fork-url", fork_url, "--port", str(self.port), "--silent",
             "--block-base-fee-per-gas", "0", *extra],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        rpc = Rpc(self.url, "anvil", attempts=1)
        deadline = time.time() + 120
        while True:
            if self.process.poll() is not None:
                raise RuntimeError(f"anvil exited: {self.process.stderr.read().decode()[-500:]}")
            try:
                rpc.chain_id()
                break
            except (RpcError, OSError):
                if time.time() > deadline:
                    self.close()
                    detail = self.process.stderr.read().decode()[-500:] if self.process.stderr else ""
                    raise RuntimeError(f"anvil forking {fork_url} did not come up within 120s {detail}".strip())
                time.sleep(0.5)

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(10)
            except subprocess.TimeoutExpired:
                self.process.kill()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def require_anvil(rpc: Rpc) -> None:
    version = str(rpc.request("web3_clientVersion", [])).lower()
    if "anvil" not in version:
        raise RuntimeError(f"{rpc.url} is not anvil ({version}); fork-apply only runs against a local fork")


# Tempo charges gas in a TIP-20 fee token, and an account with no preference pays in pathUSD. Its
# balances mapping is slot 9 of the precompile's storage (the same layout as frxUSD's TIP-20).
FORK_FEE_TOKENS = {4217: ("0x20C0000000000000000000000000000000000000", 9)}


def fund_on_fork(rpc: Rpc, sender: str) -> None:
    rpc.request("anvil_setBalance", [sender, hex(10 ** 21)])
    fee_token = FORK_FEE_TOKENS.get(rpc.chain_id())
    if fee_token:
        token, slot = fee_token
        key = "0x" + keccak256(address_word(sender) + word(slot)).hex()
        rpc.request("anvil_setStorageAt", [token, key, "0x" + word(10 ** 15).hex()])


def apply_on_fork(rpc: Rpc, sender: str, transactions: List[dict]) -> None:
    """Send each batch transaction from `sender` (impersonated) and require success."""
    require_anvil(rpc)
    rpc.request("anvil_impersonateAccount", [sender])
    fund_on_fork(rpc, sender)
    base_fee = int(rpc.request("eth_getBlockByNumber", ["latest", False]).get("baseFeePerGas") or "0x0", 16)
    try:
        for index, tx in enumerate(transactions, 1):
            if tx.get("operation", "0") not in ("0", 0) or int(str(tx.get("value", "0"))) != 0:
                raise RuntimeError(f"tx {index}: only plain calls with zero value are supported")
            params = {"from": sender, "to": tx["to"], "data": tx["data"], "value": "0x0", "gas": hex(5_000_000)}
            if base_fee == 0:
                params["gasPrice"] = "0x0"
            tx_hash = rpc.request("eth_sendTransaction", [params])
            receipt = None
            for _ in range(100):
                receipt = rpc.request("eth_getTransactionReceipt", [tx_hash])
                if receipt:
                    break
                time.sleep(0.1)
            if not receipt or int(receipt["status"], 16) != 1:
                try:
                    rpc.call(tx["to"], bytes.fromhex(tx["data"][2:]), sender=sender)
                    reason = "reverted"
                except Reverted as exc:
                    reason = exc.reason()
                raise RuntimeError(f"tx {index} to {tx['to']} failed on the fork: {reason}")
    finally:
        rpc.request("anvil_stopImpersonatingAccount", [sender])


def fork_simulate(batches: List[Batch], config: Config, mesh: Mesh, tokens: List[str]) -> None:
    """Execute every batch of a chain on an anvil fork, re-read the chain and require an empty re-plan."""
    by_chain: Dict[int, List[Batch]] = {}
    for batch in batches:
        by_chain.setdefault(batch.chain.chain_id, []).append(batch)
    for cid, group in by_chain.items():
        chain = mesh.chains[cid]
        if cid in UNFORKABLE_CHAINS:
            for batch in group:
                batch.simulation.append("fork-sim: skipped (anvil cannot fork this chain)")
            continue
        try:
            with Anvil(chain.rpc) as anvil:
                rpc = Rpc(anvil.url, f"anvil:{chain.name}")
                for batch in group:
                    apply_on_fork(rpc, batch.owner.address, batch_document(batch)["transactions"])
                fork_chain = Chain(cid, chain.name, chain.eid, anvil.url, chain.delegate)
                after = read_chain(fork_chain, mesh, tokens, rpc)
                if after.error:
                    raise RuntimeError(after.error)
                residual = [p for p in build_plans(config, mesh, {cid: after}, tokens) if p.calls or p.status == "error"]
            message = "fork-sim: executed on an anvil fork; re-read state matches the config" if not residual else \
                "fork-sim: state still differs after execution: " + "; ".join(
                    f"{TOKEN_DISPLAY[p.token]} {[c.name for c in p.calls]} {p.messages}" for p in residual)
            for batch in group:
                (batch.simulation if not residual else batch.failures).append(message)
        except (RuntimeError, RpcError, Reverted, OSError) as exc:
            for batch in group:
                batch.failures.append(f"fork-sim: {exc}")


# ---------------------------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------------------------

def parse_rpc_overrides(values: List[str]) -> Dict[int, str]:
    overrides = {}
    for item in values or []:
        chain_id, _, url = item.partition("=")
        if not chain_id.strip().isdigit() or not url:
            raise SystemExit(f"--rpc expects <chainid>=<url>, got {item!r}")
        overrides[int(chain_id)] = url
    return overrides


def select(args, mesh: Mesh) -> Tuple[List[int], List[str]]:
    chain_ids = sorted(mesh.chains, key=chain_sort_key)
    if args.chains:
        chain_ids = []
        for key in args.chains.split(","):
            cid, _ = resolve_chain(key, mesh, peer=False)
            if cid not in chain_ids:
                chain_ids.append(cid)
    tokens = list(mesh.active_tokens)
    if args.tokens:
        tokens = [resolve_token(t) for t in args.tokens.split(",")]
        unknown = [t for t in tokens if t not in mesh.active_tokens]
        if unknown:
            raise ConfigError(f"not active mesh tokens: {unknown}")
    return chain_ids, tokens


def context(args):
    mesh = load_mesh(parse_rpc_overrides(args.rpc))
    config = load_config(args.config, mesh)
    chain_ids, tokens = select(args, mesh)
    return mesh, config, chain_ids, tokens


def report_unreachable(lives: Dict[int, ChainLive]) -> List[str]:
    return [f"UNREACHABLE {live.chain.name} ({cid}): {live.error}" for cid, live in lives.items() if live.error]


def cmd_status(args) -> int:
    mesh, config, chain_ids, tokens = context(args)
    lives = read_chains(mesh, chain_ids, tokens)
    plans = {(p.chain.chain_id, p.token): p for p in build_plans(config, mesh, lives, tokens)}
    document = []
    for cid in chain_ids:
        live = lives[cid]
        chain = live.chain
        if live.error:
            print(f"\n{chain.name} ({cid}): UNREACHABLE - {live.error}")
            continue
        print(f"\n{chain.name} (chain {cid}, eid {chain.eid}) - block {live.block} at {utc(live.timestamp)}")
        for token in tokens:
            oft = live.ofts.get(token)
            if oft is None:
                continue
            plan = plans.get((cid, token))
            owner = live.owners.get(oft.owner) if oft.owner else None
            symbol = TOKEN_DISPLAY[token]
            head = (f"  {symbol:8s} {oft.address}  {oft.version or '?'}  dec {oft.decimals}  owner "
                    f"{oft.owner or '?'}" + (f" ({owner.describe()})" if owner else ""))
            print(head)
            entry = {"chainId": cid, "chain": chain.name, "token": symbol, "address": oft.address,
                     "version": oft.version, "owner": oft.owner, "capable": oft.capable, "decimals": oft.decimals,
                     "block": live.block, "timestamp": live.timestamp, "drift": [], "peers": []}
            document.append(entry)
            if not oft.capable:
                pending = plan and plan.status == "pending-upgrade"
                print(f"    no rate limiter (pre-v1.2.0)" + ("; config has limits: PENDING UPGRADE" if pending else ""))
                for message in (plan.messages if plan else []):
                    if "PENDING" not in message and "without the rate limiter" not in message:
                        print(f"    note: {message}")
                continue
            print(f"    enforcement: {'BYPASSED (globally disabled)' if oft.globally_disabled else 'on'}   "
                  f"default: {fmt_config(oft.default, oft.decimals)}")
            entry["globallyDisabled"] = oft.globally_disabled
            entry["default"] = config_json(oft.default)
            shown = [eid for eid in sorted(oft.stored) if args.all_eids or oft.peers.get(eid, ZERO32) != ZERO32
                     or not oft.stored[eid].is_empty() or any(oft.usage.get(eid, (0, 0)))]
            if shown:
                print(f"    {'peer':14s} {'eid':>6s} {'cfg':4s} {'outbound used / limit':38s} {'inbound used / limit':38s} reg")
            for eid in shown:
                eff = oft.effective(eid)
                used_out, used_in = oft.usage.get(eid, (0, 0))

                def cell(direction: Direction, used: int) -> str:
                    if oft.globally_disabled:
                        return "bypassed"
                    if not direction.enabled:
                        return "off"
                    return f"{fmt_amount(used, oft.decimals)} / {fmt_amount(direction.limit, oft.decimals)} per {fmt_window(direction.window)}"

                peered = oft.peers.get(eid, ZERO32) != ZERO32
                cfg = "ovr" if oft.stored[eid].override else "def"
                reg = "yes" if oft.tracked.get(eid) else ("NO" if peered and (eff.outbound.enabled or eff.inbound.enabled) else "-")
                name = eid_name(eid) + ("" if peered else " (no peer)")
                print(f"    {name:14s} {eid:>6d} {cfg:4s} {cell(eff.outbound, used_out):38s} {cell(eff.inbound, used_in):38s} {reg}")
                entry["peers"].append({"eid": eid, "name": eid_name(eid), "peered": peered,
                                       "effective": config_json(eff), "stored": config_json(oft.stored[eid]),
                                       "outboundUsage": str(used_out), "inboundUsage": str(used_in),
                                       "registered": bool(oft.tracked.get(eid))})
            if plan and plan.calls:
                print("    DRIFT vs config:")
                for call in plan.calls:
                    for line in call.lines:
                        print(f"      {call.name}: {line}")
                        entry["drift"].append(f"{call.name}: {line}")
            for message in (plan.messages if plan else []):
                print(f"    note: {message}")
            for error in oft.errors:
                print(f"    error: {error}")
    if args.json:
        with open(args.json, "w") as handle:
            json.dump(document, handle, indent=2)
        print(f"\nwrote {args.json}")
    return 2 if any(live.error for live in lives.values()) else 0


def cmd_check(args) -> int:
    mesh, config, chain_ids, tokens = context(args)
    lives = read_chains(mesh, chain_ids, tokens)
    plans = build_plans(config, mesh, lives, tokens)
    drift = [p for p in plans if p.calls or p.status in ("pending-upgrade", "error")]
    for plan in drift:
        print(f"DRIFT {plan.chain.name} {TOKEN_DISPLAY[plan.token]} {plan.oft.address} [{plan.status}]")
        for call in plan.calls:
            for line in call.lines:
                print(f"    {call.name}: {line}")
        for message in plan.messages:
            print(f"    {message}")
    unreachable = report_unreachable(lives)
    for line in unreachable:
        print(line)
    warnings = lint_lanes(plans, mesh, Decimal(str(args.inbound_headroom)))
    for warning in warnings:
        print(f"WARN {warning}")
    capable = sum(1 for p in plans if p.oft.capable)
    print(f"\nchecked {len(plans)} OFTs on {len(chain_ids) - len(unreachable)} chains ({capable} with the rate limiter): "
          f"{len(drift)} differ from {display_path(args.config)}, {len(warnings)} lint warning(s)")
    if unreachable:
        return 2
    return 1 if drift or (args.strict and warnings) else 0


def cmd_plan(args) -> int:
    mesh, config, chain_ids, tokens = context(args)
    lives = read_chains(mesh, chain_ids, tokens)
    unreachable = report_unreachable(lives)
    plans = build_plans(config, mesh, lives, tokens)
    batches = group_batches(plans, lives)
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(simulate, batches))
    if args.fork_sim and batches:
        fork_simulate(batches, config, mesh, tokens)
    warnings = lint_lanes(plans, mesh, Decimal(str(args.inbound_headroom)))

    report = [f"# Rate-limit plan", "",
              f"- config: `{display_path(args.config)}`",
              f"- chains read: {len(chain_ids) - len(unreachable)} of {len(chain_ids)}; tokens: "
              f"{', '.join(TOKEN_DISPLAY[t] for t in tokens)}",
              f"- generated: {utc(int(time.time()))}", ""]
    if not batches:
        report.append("No changes: every reachable chain already matches the config.")
    for batch in batches:
        report.append("```")
        report.extend(describe_batch(batch))
        report.append("```")
    pending = [p for p in plans if p.status == "pending-upgrade"]
    errors = [p for p in plans if p.status == "error"]
    if pending:
        report += ["", "Pending (OFT not on v1.2.0 yet):"] + [f"- {p.chain.name} {TOKEN_DISPLAY[p.token]}" for p in pending]
    if errors:
        report += ["", "Errors:"] + [f"- {p.chain.name} {TOKEN_DISPLAY[p.token]}: {'; '.join(p.messages)}" for p in errors]
    if warnings:
        report += ["", "Lane lint:"] + [f"- {w}" for w in warnings]
    if unreachable:
        report += ["", "Unreachable:"] + [f"- {u}" for u in unreachable]
    unchanged = sorted({p.chain.name for p in plans if p.oft.capable and not p.calls and p.status == "ok"}
                       - {b.chain.name for b in batches})
    if unchanged:
        report += ["", f"Unchanged: {', '.join(unchanged)}"]
    print("\n".join(report))

    failed = [b for b in batches if b.failures]
    if args.write:
        if failed or errors:
            print("\nNOT WRITTEN: fix the simulation failures / errors above first.")
            return 1
        if unreachable and not args.skip_unreachable:
            print("\nNOT WRITTEN: some chains were unreachable; fix their RPC (--rpc / RPC_URL_<id>) "
                  "or pass --skip-unreachable to write the rest.")
            return 2
        if not batches:
            return 0
        label = args.label or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
        out_dir = args.out or os.path.join(TXS_DIR, label)
        if os.path.isdir(out_dir) and os.listdir(out_dir) and not args.overwrite:
            print(f"\nNOT WRITTEN: {out_dir} already has files; pass another --label or --overwrite.")
            return 2
        for path in write_outputs(out_dir, "RateLimits", batches, report, plan_document(batches, args.config, lives)):
            print(f"wrote {display_path(path)}")
    if failed or errors:
        return 1
    return 2 if unreachable else 0


def cmd_reset_usage(args) -> int:
    mesh = load_mesh(parse_rpc_overrides(args.rpc))
    cid, _ = resolve_chain(args.chain, mesh, peer=False)
    token = resolve_token(args.token)
    live = read_chain(mesh.chains[cid], mesh, [token])
    if live.error:
        print(f"{live.chain.name}: {live.error}")
        return 2
    oft = live.ofts.get(token)
    if oft is None or not oft.capable:
        print(f"{TOKEN_DISPLAY[token]} on {live.chain.name} has no rate limiter (not v1.2.0)")
        return 2
    if args.peer == "all":
        eids = [eid for eid, usage in sorted(oft.usage.items()) if any(usage)]
    else:
        eids = [resolve_chain(p, mesh, peer=True)[1] for p in args.peer.split(",")]
    reset_out = args.direction in ("outbound", "both")
    reset_in = args.direction in ("inbound", "both")
    params, lines = [], []
    for eid in eids:
        used_out, used_in = oft.usage.get(eid, (0, 0))
        new_out = 0 if reset_out else used_out
        new_in = 0 if reset_in else used_in
        if (new_out, new_in) == (used_out, used_in):
            lines.append(f"{eid} {eid_name(eid)}: nothing to reset (usage out {fmt_amount(used_out, oft.decimals)}, "
                         f"in {fmt_amount(used_in, oft.decimals)})")
            continue
        params.append((eid, new_out, new_in, live.timestamp))
        lines.append(f"{eid} {eid_name(eid)}: outbound {fmt_amount(used_out, oft.decimals)} -> {fmt_amount(new_out, oft.decimals)}, "
                     f"inbound {fmt_amount(used_in, oft.decimals)} -> {fmt_amount(new_in, oft.decimals)} "
                     f"(state stamped {utc(live.timestamp)})")
    print(f"{live.chain.name} {TOKEN_DISPLAY[token]} {oft.address} - read at block {live.block}")
    for line in lines:
        print(f"  {line}")
    if not params:
        print("Nothing to do.")
        return 0
    call = Call("setRateLimitStates", oft.address, calldata_set_states(params), lines)
    owner = live.owners.get(oft.owner) or Owner(oft.owner)
    plan = OftPlan(live.chain, token, oft, Desired("reset-usage", oft.globally_disabled, oft.default, {}), [call])
    batch = Batch(live.chain, owner, [plan], [call], live.timestamp)
    simulate(batch)
    kept = [d for d, reset in (("outbound", reset_out), ("inbound", reset_in)) if not reset]
    report = ["# Rate-limit usage reset", ""] + ["```"] + describe_batch(batch) + ["```", "",
              "The reset direction(s) restart from an empty bucket when this executes."]
    if kept:
        report.append(f"The {kept[0]} usage is rewritten with its value at the read block and keeps decaying from "
                      f"there; consumption between now and execution is dropped (it only loosens the limit).")
    print("\n".join(report))
    if batch.failures:
        return 1
    if args.write:
        label = args.label or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d") + "-reset-usage"
        out_dir = args.out or os.path.join(TXS_DIR, label)
        if os.path.isdir(out_dir) and os.listdir(out_dir) and not args.overwrite:
            print(f"\nNOT WRITTEN: {out_dir} already has files; pass another --label or --overwrite.")
            return 2
        for path in write_outputs(out_dir, "ResetUsage", [batch], report, plan_document([batch], DEFAULT_CONFIG, {cid: live})):
            print(f"wrote {display_path(path)}")
    return 0


def cmd_fork_apply(args) -> int:
    rpc = Rpc(args.rpc_url, "fork", attempts=2)
    with open(args.batch) as handle:
        document = json.load(handle)
    sender = args.sender
    if not sender:
        match = re.search(r"-(0x[0-9a-fA-F]{40})\.json$", args.batch)
        if not match:
            raise SystemExit("cannot infer the owner from the file name; pass --as <address>")
        sender = match.group(1)
    if int(document["chainId"]) != rpc.chain_id():
        raise SystemExit(f"batch is for chain {document['chainId']}, fork serves {rpc.chain_id()}")
    apply_on_fork(rpc, checksum(sender), document["transactions"])
    print(f"applied {len(document['transactions'])} tx(s) from {args.batch} as {checksum(sender)}")
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p, filters=True):
        p.add_argument("--config", default=DEFAULT_CONFIG, help="desired-state file (default: rate-limits.json here)")
        p.add_argument("--rpc", action="append", metavar="CHAINID=URL", help="override a chain's RPC (repeatable)")
        if filters:
            p.add_argument("--chains", help="comma-separated chain names or ids (default: every active chain)")
            p.add_argument("--tokens", help="comma-separated tokens (default: every active token)")

    p = sub.add_parser("status", help="live limits, usage and drift")
    common(p)
    p.add_argument("--all-eids", action="store_true", help="also list eids with no peer, config or usage")
    p.add_argument("--json", help="also write the status as JSON to this path")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("check", help="exit 1 if any chain differs from the config")
    common(p)
    p.add_argument("--inbound-headroom", type=float, default=0.10, help="lane lint headroom (default 0.10)")
    p.add_argument("--strict", action="store_true", help="also fail on lane lint warnings")
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("plan", help="diff config vs chain; --write emits Safe batches")
    common(p)
    p.add_argument("--write", action="store_true", help="write the batches, summary.md and plan.json")
    p.add_argument("--label", help="output folder name under txs/ (default: today's UTC date)")
    p.add_argument("--out", help="explicit output folder (overrides --label)")
    p.add_argument("--overwrite", action="store_true", help="allow writing into a non-empty output folder")
    p.add_argument("--skip-unreachable", action="store_true", help="write batches even if some chains failed to read")
    p.add_argument("--fork-sim", action="store_true", help="also execute the batches on anvil forks and re-read")
    p.add_argument("--inbound-headroom", type=float, default=0.10, help="lane lint headroom (default 0.10)")
    p.set_defaults(func=cmd_plan)

    p = sub.add_parser("reset-usage", help="emergency: zero a lane's consumed capacity")
    common(p, filters=False)
    p.add_argument("--chain", required=True)
    p.add_argument("--token", required=True)
    p.add_argument("--peer", required=True, help="peer chain name(s), comma-separated, or 'all' (every lane in use)")
    p.add_argument("--direction", choices=("outbound", "inbound", "both"), default="both")
    p.add_argument("--write", action="store_true")
    p.add_argument("--label")
    p.add_argument("--out")
    p.add_argument("--overwrite", action="store_true")
    p.set_defaults(func=cmd_reset_usage)

    p = sub.add_parser("fork-apply", help="execute a batch on a local anvil fork (testing only)")
    p.add_argument("--rpc-url", required=True, help="anvil RPC, e.g. http://127.0.0.1:8545")
    p.add_argument("--batch", required=True)
    p.add_argument("--as", dest="sender", help="owner to impersonate (default: from the file name)")
    p.set_defaults(func=cmd_fork_apply)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ConfigError as exc:
        print(f"config error: {exc}", file=sys.stderr)
        return 2
    except (RpcError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
