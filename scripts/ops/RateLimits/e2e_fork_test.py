#!/usr/bin/env python3
"""End-to-end test of rate_limits.py against the real v1.2.0 bytecode on anvil forks.

For every selected chain it starts `anvil --fork-url <chain RPC>`, points each active OFT proxy at
the v1.2.0 implementation pinned in scripts/ops/V120/implementations/<chainid>.json (EIP-1967 slot;
the upgrade's initializeV120 only re-inits the EIP-712 domain, which the limiter never reads), and
then drives the CLI the way an operator would:

  1. enable   plan --write, fork-apply every batch as its owner, check == clean, re-plan == empty
  2. modify   tighten, move, clear overrides, flip the global switch, drop a token
  3. reset    inject usage as the owner, reset-usage --write, fork-apply, verify the bucket
  4. remove   empty config -> everything back to the post-upgrade state
  5. fork-sim plan --fork-sim on a pending change (anvil forked from the anvil fork)
  6. gas      lzReceive cost on the Fraxtal frxUSD lockbox: limits off / armed on an unregistered
              eid / armed on a registered eid (why `plan` checkpoints peers before arming them)

Needs network access to the chains' RPCs and Foundry's anvil (and cast for step 6). Nothing is
sent to a real chain: every write goes to the local forks.

    python3 scripts/ops/RateLimits/e2e_fork_test.py
    python3 scripts/ops/RateLimits/e2e_fork_test.py --chains fraxtal,arbitrum --skip-gas
"""

import argparse
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rate_limits as rl  # noqa: E402

DEFAULT_CHAINS = "fraxtal,arbitrum,ethereum,tempo"
DEFAULT_RPCS = {1: "https://ethereum-rpc.publicnode.com"}
TOKENS = "frxUSD,sfrxUSD,frxETH"
E18 = 10 ** 18
DAY = 86400


def lim(amount, window="1d"):
    return {"limit": amount, "window": window}


CONFIG_ENABLE = {"schema": 1, "tokens": {
    "frxUSD": {
        "*": {"default": {"outbound": lim("1_000_000"), "inbound": lim("1_100_000")}},
        "fraxtal": {"peers": {"ethereum": {"outbound": lim("10_000_000"), "inbound": lim("11_000_000")},
                              "solana": {"inbound": "off"}}},
    },
    "sfrxUSD": {"ethereum": {"default": {"outbound": lim("500_000", "12h"), "inbound": lim("550_000", "12h")}}},
    "frxETH": {"arbitrum": {"globallyDisabled": True, "default": {"outbound": lim("100")}}},
}}
CONFIG_MODIFY = {"schema": 1, "tokens": {
    "frxUSD": {
        "*": {"default": {"outbound": lim("800_000"), "inbound": lim("900_000")}},
        "fraxtal": {"peers": {"solana": {"outbound": lim("50_000")}}},
    },
    "frxETH": {"arbitrum": {"globallyDisabled": False, "default": {"outbound": lim("100")}}},
}}
CONFIG_EMPTY = {"schema": 1, "tokens": {}}


class Failure(Exception):
    pass


def check(condition, message):
    if not condition:
        raise Failure(message)
    print(f"    ok  {message}")


def run_cli(argv):
    """Run rate_limits.main(argv), capturing its output; returns (exit code, output)."""
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
        code = rl.main(argv)
    return code, buffer.getvalue()


class Forks:
    def __init__(self, mesh, chain_ids):
        self.anvils = {}
        self.urls = {}
        try:
            for cid in chain_ids:
                chain = mesh.chains[cid]
                print(f"  forking {chain.name} ({cid}) from {chain.rpc}")
                self.anvils[cid] = rl.Anvil(chain.rpc)
                self.urls[cid] = self.anvils[cid].url
        except BaseException:
            self.close()
            raise

    def rpc_args(self):
        args = []
        for cid, url in self.urls.items():
            args += ["--rpc", f"{cid}={url}"]
        return args

    def close(self):
        for anvil in self.anvils.values():
            anvil.close()


def upgrade_on_fork(rpc, chain_id, ofts):
    with open(os.path.join(rl.ROOT, "scripts", "ops", "V120", "implementations", f"{chain_id}.json")) as handle:
        pins = json.load(handle)["implementations"]
    for token, proxy in ofts.items():
        implementation = pins[rl.TOKEN_SLOTS.index(token)]
        rpc.request("anvil_setStorageAt", [proxy, rl.EIP1967_IMPLEMENTATION_SLOT,
                                           "0x" + implementation[2:].lower().rjust(64, "0")])
        version = rl.decode_version(rpc.call(proxy, rl.SEL["version"]))
        if version != "1.2.0":
            raise Failure(f"{proxy} on {chain_id} reports {version} after pointing it at {implementation}")


def write_config(tmp, name, document):
    path = os.path.join(tmp, f"{name}.json")
    with open(path, "w") as handle:
        json.dump(document, handle, indent=2)
    return path


def apply_dir(rpc_args, out_dir):
    """fork-apply every batch file in out_dir against the fork of its chain."""
    urls = {int(rpc_args[i + 1].split("=")[0]): rpc_args[i + 1].split("=", 1)[1] for i in range(0, len(rpc_args), 2)}
    files = sorted(f for f in os.listdir(out_dir) if f.endswith(".json") and f != "plan.json")
    for name in files:
        chain_id = json.load(open(os.path.join(out_dir, name)))["chainId"]
        code, output = run_cli(["fork-apply", "--rpc-url", urls[chain_id], "--batch", os.path.join(out_dir, name)])
        if code != 0:
            raise Failure(f"fork-apply {name}: {output}")
    return files


def plan_and_apply(step, config_path, rpc_args, chain_names, tmp):
    out_dir = os.path.join(tmp, step)
    code, output = run_cli(["plan", "--config", config_path, "--chains", chain_names, "--tokens", TOKENS,
                            "--write", "--out", out_dir, *rpc_args])
    print("\n".join("      | " + line for line in output.splitlines() if line.strip()))
    check(code == 0, f"{step}: plan --write exits 0")
    files = apply_dir(rpc_args, out_dir) if os.path.isdir(out_dir) else []
    code, output = run_cli(["check", "--config", config_path, "--chains", chain_names, "--tokens", TOKENS, *rpc_args])
    check(code == 0, f"{step}: check is clean after executing {len(files)} batch(es)")
    code, output = run_cli(["plan", "--config", config_path, "--chains", chain_names, "--tokens", TOKENS, *rpc_args])
    check(code == 0 and "No changes" in output, f"{step}: re-plan is empty (idempotent)")
    return out_dir, files


def calls_in(out_dir):
    with open(os.path.join(out_dir, "plan.json")) as handle:
        plan = json.load(handle)
    return {(b["chain"], o["token"]): [c["name"] for c in o["calls"]] for b in plan["batches"] for o in b["ofts"]}


def read(mesh, cid, url, tokens=("FRXUSD", "SFRXUSD", "FRXETH")):
    chain = mesh.chains[cid]
    live = rl.read_chain(rl.Chain(cid, chain.name, chain.eid, url, chain.delegate), mesh, list(tokens),
                         rl.Rpc(url, f"anvil:{chain.name}"))
    if live.error:
        raise Failure(f"read {chain.name}: {live.error}")
    return live


def as_owner(rpc, owner, to, data):
    rl.apply_on_fork(rpc, owner, [{"to": to, "data": "0x" + data.hex(), "value": "0", "operation": "0"}])


def gas_experiment(mesh, url):
    """lzReceive on the Fraxtal frxUSD lockbox, called as the endpoint, at three limiter states."""
    cast = shutil.which("cast") or os.path.expanduser("~/.foundry/bin/cast")
    rpc = rl.Rpc(url, "anvil:fraxtal")
    oft = mesh.ofts[252]["FRXUSD"]
    endpoint = rl.read_address(rpc.call(oft, rl.selector("endpoint()")))
    owner = rl.read_address(rpc.call(oft, rl.SEL["owner"]))
    src_eid = 30110  # arbitrum
    peer = "0x" + rpc.call(oft, rl.SEL["peers"] + rl.word(src_eid))[:32].hex()
    message = "0x" + "00" * 12 + "000000000000000000000000000000000000dEaD".lower() + (10 ** 6).to_bytes(8, "big").hex()
    data = subprocess.run(
        [cast, "calldata", "lzReceive((uint32,bytes32,uint64),bytes32,bytes,address,bytes)",
         f"({src_eid},{peer},1)", "0x" + "ab" * 32, message, rl.ZERO_ADDRESS, "0x"],
        capture_output=True, text=True, check=True, cwd=tempfile.gettempdir()).stdout.strip()

    def estimate():
        return int(rpc.request("eth_estimateGas", [{"from": endpoint, "to": oft, "data": data}]), 16)

    live = read(mesh, 252, url, ("FRXUSD",))
    if any(not c.is_empty() for c in live.ofts["FRXUSD"].stored.values()) or live.ofts["FRXUSD"].default != rl.EMPTY:
        raise Failure("gas experiment needs a fresh fork with limits off")
    off = estimate()
    armed = rl.RLConfig(False, rl.Direction(True, 1_000_000 * E18, DAY), rl.Direction(True, 1_000_000 * E18, DAY))
    as_owner(rpc, owner, oft, rl.calldata_set_default(armed))
    unregistered = estimate()
    as_owner(rpc, owner, oft, rl.calldata_checkpoint([src_eid]))
    registered = estimate()
    print(f"    lzReceive gas (eth_estimateGas, 1 frxUSD from arbitrum): limits off {off:,} | armed, eid unregistered "
          f"{unregistered:,} (+{unregistered - off:,}) | armed, eid registered {registered:,} (+{registered - off:,})")
    check(unregistered > registered > off, "registering the eid moves the one-time tracking write out of lzReceive")
    return off, unregistered, registered


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--chains", default=DEFAULT_CHAINS)
    parser.add_argument("--skip-gas", action="store_true")
    parser.add_argument("--keep", action="store_true", help="keep the temp folder with the generated batches")
    args = parser.parse_args()

    overrides = {cid: url for cid, url in DEFAULT_RPCS.items() if not os.environ.get(f"RPC_URL_{cid}")}
    mesh = rl.load_mesh(overrides)
    chain_ids = [rl.resolve_chain(c, mesh, peer=False)[0] for c in args.chains.split(",")]
    names = ",".join(mesh.chains[c].name for c in chain_ids)
    tmp = tempfile.mkdtemp(prefix="rate-limits-e2e-")
    started = time.time()
    forks = None
    try:
        forks = Forks(mesh, chain_ids)
        print("setup: point every OFT proxy at its pinned v1.2.0 implementation")
        for cid in chain_ids:
            upgrade_on_fork(rl.Rpc(forks.urls[cid], "anvil"), cid, mesh.ofts[cid])
        rpc_args = forks.rpc_args()

        print("\n1. enable")
        out_dir, files = plan_and_apply("enable", write_config(tmp, "enable", CONFIG_ENABLE), rpc_args, names, tmp)
        calls = calls_in(out_dir)
        if 252 in chain_ids:
            check(calls[("fraxtal", "frxUSD")] == ["checkpointRateLimits", "setDefaultRateLimitConfig", "setRateLimitConfigs"],
                  "fraxtal frxUSD: checkpoint unregistered peers, then default, then overrides")
            live = read(mesh, 252, forks.urls[252])
            frx = live.ofts["FRXUSD"]
            check(all(frx.tracked[e] for e in frx.peered()), f"fraxtal frxUSD: all {len(frx.peered())} peered eids registered")
            check(frx.stored[30101] == rl.RLConfig(True, rl.Direction(True, 10_000_000 * E18, DAY),
                                                   rl.Direction(True, 11_000_000 * E18, DAY)), "fraxtal frxUSD: ethereum override")
            check(frx.stored[30168].inbound == rl.OFF and frx.stored[30168].outbound.limit == 1_000_000 * E18,
                  "fraxtal frxUSD: solana override inherits outbound, inbound off")
        if 1 in chain_ids:
            eth_files = [f for f in files if f.startswith("RateLimits-1-")]
            check(len(eth_files) == 2, f"ethereum: one batch per owner Safe ({', '.join(eth_files)})")
        if 4217 in chain_ids:
            live = read(mesh, 4217, forks.urls[4217], ("FRXUSD",))
            check(live.ofts["FRXUSD"].default.outbound.limit == 1_000_000 * 10 ** 6,
                  "tempo frxUSD: 1,000,000 written in 6-decimal base units")
        if 42161 in chain_ids:
            live = read(mesh, 42161, forks.urls[42161])
            check(live.ofts["FRXETH"].globally_disabled and live.ofts["FRXETH"].default.outbound.enabled,
                  "arbitrum frxETH: limits configured but globally bypassed")

        print("\n2. modify")
        out_dir, _ = plan_and_apply("modify", write_config(tmp, "modify", CONFIG_MODIFY), rpc_args, names, tmp)
        calls = calls_in(out_dir)
        if 252 in chain_ids:
            check(calls[("fraxtal", "frxUSD")] == ["setDefaultRateLimitConfig", "setRateLimitConfigs"],
                  "fraxtal frxUSD: no checkpoint once every peer is registered")
            frx = read(mesh, 252, forks.urls[252]).ofts["FRXUSD"]
            check(frx.stored[30101].is_empty(), "fraxtal frxUSD: ethereum override cleared")
            check(frx.effective(30101).outbound.limit == 800_000 * E18, "fraxtal frxUSD: ethereum now follows the default")
        if 1 in chain_ids:
            check(calls[("ethereum", "sfrxUSD")] == ["setDefaultRateLimitConfig"], "ethereum sfrxUSD: dropped token disabled")
        if 42161 in chain_ids:
            check(calls[("arbitrum", "frxETH")] == ["setRateLimitGlobalConfig"], "arbitrum frxETH: bypass lifted")

        if 252 in chain_ids:
            print("\n3. reset usage (fraxtal frxUSD -> arbitrum)")
            rpc = rl.Rpc(forks.urls[252], "anvil:fraxtal")
            live = read(mesh, 252, forks.urls[252], ("FRXUSD",))
            frx = live.ofts["FRXUSD"]
            as_owner(rpc, frx.owner, frx.address,
                     rl.calldata_set_states([(30110, 400_000 * E18, 300_000 * E18, live.timestamp)]))
            frx = read(mesh, 252, forks.urls[252], ("FRXUSD",)).ofts["FRXUSD"]
            check(frx.usage[30110][0] > 399_000 * E18, "usage injected as the owner")
            out_dir = os.path.join(tmp, "reset")
            code, output = run_cli(["reset-usage", "--chain", "fraxtal", "--token", "frxUSD", "--peer", "arbitrum",
                                    "--direction", "outbound", "--write", "--out", out_dir, *rpc_args])
            print("\n".join("      | " + line for line in output.splitlines() if line.strip()))
            check(code == 0, "reset-usage --write exits 0")
            apply_dir(rpc_args, out_dir)
            frx = read(mesh, 252, forks.urls[252], ("FRXUSD",)).ofts["FRXUSD"]
            check(frx.usage[30110][0] == 0, "outbound bucket empty after the reset")
            check(250_000 * E18 < frx.usage[30110][1] < 300_000 * E18, "inbound usage kept (still decaying)")

        print("\n4. remove everything")
        plan_and_apply("remove", write_config(tmp, "remove", CONFIG_EMPTY), rpc_args, names, tmp)
        for cid in chain_ids:
            for token, oft in read(mesh, cid, forks.urls[cid]).ofts.items():
                if oft.default != rl.EMPTY or oft.globally_disabled or any(not c.is_empty() for c in oft.stored.values()):
                    raise Failure(f"{mesh.chains[cid].name} {token} not back to the post-upgrade state")
        check(True, "every OFT back to the post-upgrade state (no default, no overrides, enforcement on)")

        print("\n5. plan --fork-sim")
        first = chain_ids[0]
        code, output = run_cli(["plan", "--config", write_config(tmp, "sim", CONFIG_ENABLE), "--chains",
                                mesh.chains[first].name, "--tokens", TOKENS, "--fork-sim", *rpc_args])
        print("\n".join("      | " + line for line in output.splitlines() if "simulation" in line or "FAILED" in line))
        check(code == 0 and "re-read state matches the config" in output, "fork-sim executes and verifies the batch")

        if 252 in chain_ids and not args.skip_gas:
            print("\n6. lzReceive gas on the Fraxtal frxUSD lockbox (fresh fork)")
            with rl.Anvil(mesh.chains[252].rpc) as anvil:
                upgrade_on_fork(rl.Rpc(anvil.url, "anvil"), 252, {"FRXUSD": mesh.ofts[252]["FRXUSD"]})
                gas_experiment(mesh, anvil.url)

        print(f"\nPASS in {time.time() - started:.0f}s (batches in {tmp})" if args.keep else
              f"\nPASS in {time.time() - started:.0f}s")
        return 0
    except (Failure, rl.RpcError, rl.Reverted, RuntimeError) as exc:
        print(f"\nFAIL: {type(exc).__name__}: {exc}\n(batches kept in {tmp})")
        args.keep = True
        return 1
    finally:
        if forks:
            forks.close()
        if not args.keep:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
