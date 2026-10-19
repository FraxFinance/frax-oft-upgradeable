#!/usr/bin/env python3
"""Generate Safe batches for chains DeprecateChain/DeprecateToken.s.sol cannot fork-simulate.

forge --zksync reverts on ZKsync Era (324) and Abstract (2741), and Optimism's configured RPC
was once rate-limited past usability. Those chains still need the same teardown, so this
reproduces the exact decision logic of DeprecateOFTBase._deprecatePairOnToken over plain
eth_calls, for every (source chain, peer, token) triplet selected:

  on-chain peer is neither 0 nor the expected peer -> NEEDS REVIEW, no file
  route wired & send not blocked    -> setSendLibrary(oft, eid, blockedLibrary)
  expected peer matches on-chain    -> setPeer(eid, 0)
  explicit receive library override -> setReceiveLibrary(oft, eid, 0, 0)
  enforced options dirty            -> setEnforcedOptions([...0x0003])
  app ULN config non-zero           -> setConfig(oft, lib, [ULN default])

"Wired" is the expected peer or any non-send wiring evidence (explicit receive library, dirty
enforced options, non-zero app ULN config), exactly as in the Solidity. Every guard is
idempotent the same way: a setting already at its reset value emits no transaction, so these
batches cannot revert with SameValue / OnlyNonDefaultLib. Each emitted call is then eth_call'd
from the Safe that will execute it; the calls of one route touch independent state, so this
is equivalent to simulating the batch.

Chain configs come from scripts/L0Config.json, expected EVM peers from the chain registry in
scripts/L0Constants.sol, and non-EVM peers from scripts/NonEvmPeers.json.

Usage (from anywhere in the repo; dry run unless --write):
  # DeprecateChain shape: every token from one unforkable chain toward every other chain.
  ./generate-unforkable-batches.py --source 2741 --out-dir deprecate-2741 --write
  # DeprecateChain shape, reverse side: an unforkable chain's routes toward the deprecated one.
  ./generate-unforkable-batches.py --source 324 --peer 2741 --out-dir deprecate-2741 --write
  # DeprecateToken shape: FPI toward Fraxtal from the chains forge could not simulate.
  ./generate-unforkable-batches.py --source 10,324,2741 --peer 252 --token FPI --out-dir deprecate-FPI --write

Env: RPC_URL_<chainid> overrides a chain's L0Config RPC.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = subprocess.run(
    ["git", "rev-parse", "--show-toplevel"],
    cwd=os.path.dirname(os.path.abspath(__file__)),
    capture_output=True, text=True, check=True,
).stdout.strip()
L0_CONFIG = os.path.join(ROOT, "scripts/L0Config.json")
L0_CONSTANTS = os.path.join(ROOT, "scripts/L0Constants.sol")
NON_EVM_PEERS = os.path.join(ROOT, "scripts/NonEvmPeers.json")
TXS_DIR = os.path.join(ROOT, "scripts/ops/DeprecateChain/txs")

# `enum Token` order in L0Constants.sol; peer arrays are indexed by it.
TOKENS = ["WFRAX", "SFRXUSD", "SFRXETH", "FRXUSD", "FRXETH", "FPI"]
# BaseL0Script maps NonEvmPeers.json keys onto Token slots.
NON_EVM_KEYS = {"WFRAX": "wfrax", "SFRXUSD": "sfrxUSD", "SFRXETH": "sfrxEth",
                "FRXUSD": "frxUSD", "FRXETH": "frxEth", "FPI": "fpi"}

ZERO32 = "0x" + "00" * 32
ZERO_ADDRESS = "0x" + "00" * 20
CLEARED_OPTIONS = "0x0003"  # OptionsBuilder.newOptions() with no entries
CONFIG_TYPE_ULN = 2

SEL_PEERS = "0xbb0b6a53"                  # peers(uint32)
SEL_OWNER = "0x8da5cb5b"                  # owner()
SEL_BLOCKED_LIBRARY = "0x73318091"        # blockedLibrary()
SEL_IS_DEFAULT_SEND = "0xdc93c8a2"        # isDefaultSendLibrary(address,uint32)
SEL_GET_SEND_LIBRARY = "0xb96a277f"       # getSendLibrary(address,uint32)
SEL_GET_RECEIVE_LIBRARY = "0x402f8468"    # getReceiveLibrary(address,uint32)
SEL_ENFORCED_OPTIONS = "0x5535d461"       # enforcedOptions(uint32,uint16)
SEL_IS_SUPPORTED_EID = "0x6750cd4c"       # isSupportedEid(uint32)
SEL_GET_APP_ULN_CONFIG = "0x39e3f938"     # getAppUlnConfig(address,uint32)


class Reverted(Exception):
    """The node executed the call and it reverted (Solidity's `catch` branch)."""


class Rpc:
    def __init__(self, url):
        self.url = url

    def _post(self, method, params):
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
        last = None
        for attempt in range(8):
            request = urllib.request.Request(
                self.url, data=body,
                headers={"Content-Type": "application/json", "User-Agent": "frax-deprecate/1.0"},
            )
            # Rate limits and transient node errors are not reverts: back off and retry, and never
            # let a transport failure masquerade as "setting is clean" and silently drop a tx.
            backoff = min(2 ** attempt, 60)
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    reply = json.load(response)
            except urllib.error.HTTPError as exc:
                last = exc
                retry_after = exc.headers.get("Retry-After", "") if exc.headers else ""
                time.sleep(int(retry_after) if retry_after.isdigit() else backoff)
                continue
            except (urllib.error.URLError, TimeoutError, ConnectionError, json.JSONDecodeError) as exc:
                last = exc
                time.sleep(backoff)
                continue
            if "error" in reply:
                text = json.dumps(reply["error"]).lower()
                if "revert" in text:
                    raise Reverted(text)
                last = RuntimeError(text)
                time.sleep(backoff)
                continue
            return reply["result"]
        raise RuntimeError(f"{method} on {self.url} failed after retries: {last}")

    def call(self, to, data, sender=None):
        tx = {"to": to, "data": data}
        if sender:
            tx["from"] = sender
        result = self._post("eth_call", [tx, "latest"])
        if not isinstance(result, str) or not result.startswith("0x"):
            raise RuntimeError(f"malformed eth_call result from {self.url}: {result!r}")
        return bytes.fromhex(result[2:])

    def code(self, address):
        return self._post("eth_getCode", [address, "latest"])


def word(value):
    return f"{value:064x}"


def address_word(address):
    return address.lower().removeprefix("0x").rjust(64, "0")


def read_word(raw, index):
    chunk = raw[32 * index: 32 * (index + 1)]
    if len(chunk) != 32:
        raise RuntimeError(f"short return data ({len(raw)} bytes)")
    return int.from_bytes(chunk, "big")


def read_address(raw, index=0):
    return "0x" + f"{read_word(raw, index):040x}"


def read_bytes(raw):
    offset = read_word(raw, 0)
    length = int.from_bytes(raw[offset:offset + 32], "big")
    return "0x" + raw[offset + 32:offset + 32 + length].hex()


def uln_config_is_zero(raw):
    base = read_word(raw, 0)
    head = raw[base:]
    numbers = [read_word(head, i) for i in range(4)]
    lengths = [int.from_bytes(head[read_word(head, i):read_word(head, i) + 32], "big") for i in (4, 5)]
    return all(n == 0 for n in numbers) and all(n == 0 for n in lengths)


def cast(*args):
    result = subprocess.run(["cast", *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"cast {' '.join(args[:2])} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def calldata(signature, *args):
    return cast("calldata", signature, *[str(a) for a in args])


def checksum(address):
    return cast("to-check-sum-address", address)


EMPTY_ULN_CONFIG = "0x" + calldata("x((uint64,uint8,uint8,uint8,address[],address[]))", "(0,0,0,0,[],[])")[10:]


def load_registry():
    """Token-indexed peer arrays per chain id, read from L0Constants.sol (the Solidity registry).

    Mirrors L0Constants: `_registerChain(id, array)` entries, with `expectedProxyOfts` for every
    unregistered chain. Fails loudly rather than guess if the source stops parsing cleanly.
    """
    source = open(L0_CONSTANTS).read()
    constants = {name: value for name, value in
                 re.findall(r"address public (\w+) = (0x[0-9a-fA-F]{40});", source)}
    arrays = {}
    for array, name in re.findall(r"^\s*(\w+)\.push\((\w+)\);", source, re.M):
        if name in constants:
            arrays.setdefault(array, []).append(constants[name])
    # Built by a loop, not pushes: the deterministic set with the FPI slot zeroed (see its NatSpec).
    if "fullDeterministicProxyOftsPostFpi" in source:
        arrays["fullDeterministicProxyOftsPostFpi"] = [
            ZERO_ADDRESS if TOKENS[i] == "FPI" else a for i, a in enumerate(arrays["fullDeterministicProxyOfts"])
        ]
    registry = {}
    for chain_id, array in re.findall(r"_registerChain\((\d+),\s*(\w+)\);", source):
        registry[int(chain_id)] = arrays.get(array, [])
    registry["default"] = arrays.get("expectedProxyOfts", [])
    for key, peers in registry.items():
        if len(peers) != len(TOKENS):
            raise RuntimeError(f"L0Constants registry for {key} resolved {len(peers)} of {len(TOKENS)} slots")
    return registry


def load_chains():
    config = json.load(open(L0_CONFIG))
    non_evm_peers = json.load(open(NON_EVM_PEERS))["Peers"]
    chains = {}
    for entry in config["Proxy"]:
        entry = dict(entry, kind="evm")
        entry["RPC"] = os.environ.get(f"RPC_URL_{entry['chainid']}", entry["RPC"])
        chains[entry["chainid"]] = entry
    for index, entry in enumerate(config["Non-EVM"]):
        peers = non_evm_peers[index] if index < len(non_evm_peers) else {}
        chains[entry["chainid"]] = {"chainid": entry["chainid"], "eid": entry["eid"], "kind": "non-evm",
                                    "peers": {t: peers.get(NON_EVM_KEYS[t], ZERO32) for t in TOKENS}}
    return chains


def expected_peer(registry, peer_chain, token):
    if peer_chain["kind"] == "non-evm":
        return peer_chain["peers"][token].lower()
    peers = registry.get(peer_chain["chainid"], registry["default"])
    address = peers[TOKENS.index(token)]
    return ZERO32 if int(address, 16) == 0 else "0x" + address_word(address)


class RouteTeardown:
    """DeprecateOFTBase._deprecatePairOnToken for one (source, peer, token) over eth_calls."""

    def __init__(self, rpc, source, oft, peer_chain, token, expected):
        self.rpc, self.source, self.oft, self.token = rpc, source, oft, token
        self.eid = peer_chain["eid"]
        self.expected = expected
        self.endpoint = source["endpoint"]
        self.txs, self.owner_txs, self.notes = [], [], []
        self.owner = None

    def _try(self, to, data):
        try:
            return self.rpc.call(to, data)
        except Reverted:
            return None

    def _receive_library(self):
        raw = self._try(self.endpoint, SEL_GET_RECEIVE_LIBRARY + address_word(self.oft) + word(self.eid))
        return None if raw is None else (read_address(raw, 0), read_word(raw, 1) != 0)

    def _enforced_options(self, msg_type):
        raw = self._try(self.oft, SEL_ENFORCED_OPTIONS + word(self.eid) + word(msg_type))
        return "0x" if raw is None else read_bytes(raw).lower()

    def _dirty_options(self):
        return [m for m in (1, 2) if self._enforced_options(m) not in ("0x", CLEARED_OPTIONS)]

    def _app_uln_dirty(self, lib):
        if int(lib, 16) == 0:
            return False
        supported = self._try(lib, SEL_IS_SUPPORTED_EID + word(self.eid))
        if supported is None or read_word(supported, 0) == 0:
            return False
        app = self._try(lib, SEL_GET_APP_ULN_CONFIG + address_word(self.oft) + word(self.eid))
        return app is not None and not uln_config_is_zero(app)

    def _libs(self):
        libs = [self.source["sendLib302"]]
        if self.source["receiveLib302"].lower() != self.source["sendLib302"].lower():
            libs.append(self.source["receiveLib302"])
        return libs

    def _has_non_send_wiring(self):
        receive = self._receive_library()
        if receive is not None and not receive[1]:
            return True
        if self._dirty_options():
            return True
        return any(self._app_uln_dirty(lib) for lib in self._libs())

    def _push(self, name, to, data, owner_scoped=False):
        (self.owner_txs if owner_scoped else self.txs).append({"name": name, "to": to, "data": data})

    def _owner_scoped(self, data, label):
        """Mirrors _simulateOwnerScopedCall: the delegate tries first, then owner()."""
        delegate = self.source["delegate"]
        try:
            self.rpc.call(self.oft, data, sender=delegate)
            return False
        except Reverted:
            pass
        owner = self._try(self.oft, SEL_OWNER)
        if owner is None:
            raise RuntimeError(f"{label}: owner() unavailable")
        owner = read_address(owner)
        if self.owner not in (None, owner):
            raise RuntimeError("mixed owner-scoped tx owners")
        self.owner = owner
        return owner.lower() != delegate.lower()

    def plan(self):
        peer_raw = self._try(self.oft, SEL_PEERS + word(self.eid))
        if peer_raw is None:
            self.notes.append("NEEDS REVIEW: peers() reverted")
            return False
        current = "0x" + peer_raw[:32].hex()
        has_expected_peer = False
        if current != ZERO32:
            if self.expected == ZERO32:
                self.notes.append(f"NEEDS REVIEW: peer set on-chain but no expected peer in config ({current})")
                return False
            if current != self.expected:
                self.notes.append(f"NEEDS REVIEW: on-chain peer {current} != expected {self.expected}")
                return False
            has_expected_peer = True

        route_had_wiring = has_expected_peer or self._has_non_send_wiring()

        # --- send library -> blockedLibrary ---
        is_default = self._try(self.endpoint, SEL_IS_DEFAULT_SEND + address_word(self.oft) + word(self.eid))
        if is_default is not None:
            blocked = read_address(self.rpc.call(self.endpoint, SEL_BLOCKED_LIBRARY))
            current_send = self._try(self.endpoint, SEL_GET_SEND_LIBRARY + address_word(self.oft) + word(self.eid))
            current_send = None if current_send is None else read_address(current_send)
            if read_word(is_default, 0) != 0:
                emit = route_had_wiring and current_send != blocked
            else:
                emit = current_send is not None and current_send != blocked
            if emit:
                self._push("setSendLibrary", self.endpoint,
                           calldata("setSendLibrary(address,uint32,address)", self.oft, self.eid, blocked))

        # --- peer ---
        if has_expected_peer:
            data = calldata("setPeer(uint32,bytes32)", self.eid, ZERO32)
            self._push("setPeer", self.oft, data, self._owner_scoped(data, "setPeer"))

        # --- receive library -> DEFAULT ---
        receive = self._receive_library()
        if receive is not None and not receive[1]:
            self._push("setReceiveLibrary", self.endpoint,
                       calldata("setReceiveLibrary(address,uint32,address,uint256)", self.oft, self.eid, ZERO_ADDRESS, 0))

        # --- enforced options -> 0x0003 ---
        dirty = self._dirty_options()
        if dirty:
            params = "[" + ",".join(f"({self.eid},{m},{CLEARED_OPTIONS})" for m in dirty) + "]"
            data = calldata("setEnforcedOptions((uint32,uint16,bytes)[])", params)
            self._push("setEnforcedOptions", self.oft, data, self._owner_scoped(data, "setEnforcedOptions(clear)"))

        # --- app ULN config -> default, send lib first then receive lib ---
        for lib in self._libs():
            if self._app_uln_dirty(lib):
                params = f"[({self.eid},{CONFIG_TYPE_ULN},{EMPTY_ULN_CONFIG})]"
                self._push("setConfig", self.endpoint,
                           calldata("setConfig(address,address,(uint32,uint32,bytes)[])", self.oft, lib, params))
        return True

    def simulate(self):
        """eth_call every emitted transaction from the Safe that executes it."""
        failures = []
        for sender, txs in ((self.source["delegate"], self.txs), (self.owner, self.owner_txs)):
            for tx in txs:
                try:
                    self.rpc.call(tx["to"], tx["data"], sender=sender)
                except Reverted as exc:
                    failures.append(f"{tx['name']} from {sender} reverted: {exc}")
        return failures


def write_batch(path, chain_id, txs):
    doc = {
        "chainId": chain_id,
        "createdAt": int(time.time() * 1000),
        "meta": {"description": "", "name": "Transactions Batch"},
        "transactions": [{"data": t["data"], "operation": "0", "to": checksum(t["to"]), "value": "0"} for t in txs],
        "version": "1.0",
    }
    with open(path, "w") as handle:
        json.dump(doc, handle, indent=2, sort_keys=True)
        handle.write("\n")


def parse_ids(raw):
    return [int(x) for x in raw.split(",") if x.strip()] if raw else []


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", required=True, help="comma-separated chain ids that execute the batches")
    parser.add_argument("--peer", help="comma-separated peer chain ids (default: every other Proxy + Non-EVM chain)")
    parser.add_argument("--token", help=f"comma-separated subset of {','.join(TOKENS)} (default: all)")
    parser.add_argument("--out-dir", required=True, help="output folder under txs/")
    parser.add_argument("--write", action="store_true", help="persist files (default: dry run)")
    args = parser.parse_args()

    chains, registry = load_chains(), load_registry()
    tokens = [t.strip().upper() for t in args.token.split(",")] if args.token else TOKENS
    unknown = [t for t in tokens if t not in TOKENS]
    if unknown:
        parser.error(f"unknown token(s): {unknown}")
    out_dir = os.path.join(TXS_DIR, args.out_dir)
    review, failures, written = [], [], []

    for source_id in parse_ids(args.source):
        source = chains.get(source_id)
        if source is None or source["kind"] != "evm":
            parser.error(f"source {source_id} is not an EVM chain in L0Config Proxy")
        peer_ids = parse_ids(args.peer) or [c for c in chains if c != source_id]
        rpc = Rpc(source["RPC"])
        own = registry.get(source_id, registry["default"])

        def route(job):
            peer_id, token = job
            oft = own[TOKENS.index(token)]
            if int(oft, 16) == 0 or rpc.code(oft) in ("0x", "0x0"):
                return job, None, ["OFT not deployed"]
            teardown = RouteTeardown(rpc, source, oft, chains[peer_id], token,
                                     expected_peer(registry, chains[peer_id], token))
            if not teardown.plan():
                return job, None, teardown.notes
            return job, teardown, teardown.simulate()

        missing = [p for p in peer_ids if p not in chains]
        if missing:
            parser.error(f"peer chain(s) not in L0Config: {missing}")
        jobs = [(p, t) for p in peer_ids if p != source_id for t in tokens]
        print(f"\n=== source {source_id} (eid {source['eid']}): {len(jobs)} routes ===")
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(route, jobs))

        for (peer_id, token), teardown, notes in results:
            label = f"{token} {source_id} -> {peer_id}"
            if teardown is None:
                if notes and notes[0].startswith("NEEDS REVIEW"):
                    review.append(f"{label}: {notes[0]}")
                    print(f"  SKIP {label}: {notes[0]}")
                continue
            if notes:
                failures.extend(f"{label}: {n}" for n in notes)
            stem = f"Deprecate-{source_id}-{peer_id}-{token}"
            for txs, suffix in ((teardown.txs, ""), (teardown.owner_txs, f"-owner-{teardown.owner}")):
                if not txs:
                    continue
                path = os.path.join(out_dir, f"{stem}{suffix}.json")
                print(f"  {label}: {len(txs)} txs [{', '.join(t['name'] for t in txs)}] -> {os.path.basename(path)}")
                written.append((path, source_id, txs))

    if failures:
        print("\nSIMULATION FAILURES (nothing written):")
        for line in failures:
            print(f"  - {line}")
        return 1
    if args.write:
        os.makedirs(out_dir, exist_ok=True)
        for path, chain_id, txs in written:
            write_batch(path, chain_id, txs)
    print(f"\n{len(written)} batch file(s){'' if args.write else ' (dry run; pass --write to persist)'}")
    if review:
        print("NEEDS REVIEW (no file written for these routes):")
        for line in review:
            print(f"  - {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
