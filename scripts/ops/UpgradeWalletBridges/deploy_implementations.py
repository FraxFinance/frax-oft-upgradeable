#!/usr/bin/env python3
"""Deploy and verify the FraxOFTWallet implementation on every active chain from a hot EOA.

The proxy upgrade itself is signed by the admin (hardware wallet) in the separate MetaMask upgrade console, which reads
the implementations.json written here. Implementation deployment needs no privileges, so any funded EOA works.

  # dry run: simulates every chain, deploys nothing
  python3 scripts/ops/UpgradeWalletBridges/deploy_implementations.py

  # deploy + verify, then record addresses in scripts/ops/UpgradeWalletBridges/implementations.json
  PK_IMPL_DEPLOYER=<hot key> ETHERSCAN_API_KEY=<etherscan v2 key> \
  python3 scripts/ops/UpgradeWalletBridges/deploy_implementations.py --broadcast [--chain 42161 --chain 8453]

Options: --no-verify, --force (redeploy even if a matching implementation is recorded).
Chains come from UpgradeWalletBridges.s.sol `upgradeTargets()`, so retired chains are never included.
zkSync is deferred: it needs a zksolc build (foundry-zksync). Somnia uses `forge create` (forge >= 1.9 cannot fork it).
Per-chain overrides: WALLET_UPGRADE_RPC_<chainid>=<url>, VERIFY_ARGS_<chainid>="--verify --verifier ... ".
Run from the repo root or anywhere; paths resolve relative to this file.
"""

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SCRIPT = "scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol"
RECORD = HERE / "implementations.json"

BUILD_IDS = {0: "default", 1: "paris", 2: "tempo", 3: "zksync"}
CONTRACT = {
    "default": "contracts/FraxOFTWalletUpgradeable.sol:FraxOFTWalletUpgradeable",
    "paris": "contracts/FraxOFTWalletUpgradeable.sol:FraxOFTWalletUpgradeable",
    "tempo": "contracts/FraxOFTWalletUpgradeableTempo.sol:FraxOFTWalletUpgradeableTempo",
}
DEFERRED_BUILDS = {"zksync"}

# Flaky L0Config RPCs (World Chain drpc, Avalanche zan.top). Env WALLET_UPGRADE_RPC_<chainid> wins.
DEFAULT_RPC_OVERRIDES = {
    480: "https://worldchain-mainnet.g.alchemy.com/public",
    43114: "https://api.avax.network/ext/bc/C/rpc",
}
FORGE_CREATE_CHAINS = {5031}  # Somnia: RPCs reject forge's EIP-1898 fork queries; forge create does not fork

# Explorers that are not reachable through Etherscan v2 (forge has no URL, or the URL serves Blockscout).
BLOCKSCOUT = {
    4663: "https://robinhoodchain.blockscout.com/api/",
    5031: "https://explorer.somnia.network/api/",
    57073: "https://explorer.inkonchain.com/api/",
    98866: "https://explorer.plume.org/api/",
    747474: "https://explorer.katanarpc.com/api/",
}
SOURCIFY = {196, 4217}  # X Layer, Tempo: no Etherscan v2 support in forge; previous Tempo impl is on Sourcify


def die(message):
    sys.exit(f"error: {message}")


def tool(name):
    found = shutil.which(name) or str(Path.home() / ".foundry/bin" / name)
    if not Path(found).exists():
        die(f"{name} not found: install Foundry (foundryup) or add it to PATH")
    return found


FORGE, CAST = tool("forge"), tool("cast")


def run(cmd, env=None, timeout=1800):
    return subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, env=env, timeout=timeout)


def run_ok(cmd, env=None):
    proc = run(cmd, env)
    if proc.returncode != 0:
        die(f"{' '.join(cmd[:4])} failed:\n{proc.stdout[-1500:]}\n{proc.stderr[-1500:]}")
    return proc.stdout


def rpc(url, method, params, attempts=3):
    for attempt in range(1, attempts + 1):
        try:
            req = urllib.request.Request(
                url,
                data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
                headers={"Content-Type": "application/json", "User-Agent": "frax-wallet-impl-deployer"},
            )
            body = json.load(urllib.request.urlopen(req, timeout=25))
            if "error" in body:
                raise RuntimeError(body["error"].get("message", body["error"]))
            return body["result"]
        except Exception:  # noqa: BLE001 - public RPCs flake; retry then surface
            if attempt == attempts:
                raise
            time.sleep(2 * attempt)


def parse_list(value):
    inner = value.strip()[1:-1].strip()
    return [item.strip() for item in inner.split(", ")] if inner else []


def upgrade_targets(env):
    out = run_ok([FORGE, "script", SCRIPT, "--sig", "upgradeTargets()", "--json"], env)
    line = next((ln for ln in out.splitlines() if '"returns"' in ln), None)
    if not line:
        die("upgradeTargets() returned nothing")
    r = json.loads(line)["returns"]
    rows = zip(
        (int(x) for x in parse_list(r["chainids"]["value"])),
        parse_list(r["rpcs"]["value"]),
        parse_list(r["proxies"]["value"]),
        (BUILD_IDS[int(x)] for x in parse_list(r["builds"]["value"])),
    )
    return [{"chainId": c, "rpc": u, "proxy": p, "build": b} for c, u, p, b in rows]


_code_cache = {}


def compiled(build, field):
    """creation ('bytecode') or runtime ('deployedBytecode') code exactly as forge builds it for this chain."""
    key = (build, field)
    if key not in _code_cache:
        cmd = [FORGE, "inspect", CONTRACT[build], field] + (["--evm-version", "paris"] if build == "paris" else [])
        out = run_ok(cmd)
        code = next((ln.strip() for ln in out.splitlines() if ln.strip().startswith("0x")), None)
        if not code:
            die(f"forge inspect {CONTRACT[build]} {field} returned no bytecode")
        _code_cache[key] = code.lower()
    return _code_cache[key]


def code_at(url, address):
    try:
        return rpc(url, "eth_getCode", [address, "latest"]).lower()
    except Exception:  # noqa: BLE001
        return None


def load_record():
    return json.loads(RECORD.read_text()) if RECORD.exists() else {}


def save_record(record):
    RECORD.write_text(json.dumps(dict(sorted(record.items(), key=lambda kv: int(kv[0]))), indent=2) + "\n")


def verify_args(chain_id, etherscan_key):
    override = os.environ.get(f"VERIFY_ARGS_{chain_id}")
    if override is not None:
        return shlex.split(override), "custom"
    if chain_id in BLOCKSCOUT:
        return ["--verify", "--verifier", "blockscout", "--verifier-url", BLOCKSCOUT[chain_id]], "blockscout"
    if chain_id in SOURCIFY:
        return ["--verify", "--verifier", "sourcify"], "sourcify"
    if etherscan_key:
        return ["--verify", "--etherscan-api-key", etherscan_key], "etherscan"
    return [], "skipped (no ETHERSCAN_API_KEY)"


def git(*args):
    return run(["git", *args]).stdout.strip()


def deploy(target, args, pk, verify):
    """Returns (address or None, ok, log tail)."""
    chain_id, build = target["chainId"], target["build"]
    paris = ["--evm-version", "paris"] if build == "paris" else []
    if chain_id in FORGE_CREATE_CHAINS:
        if not pk:
            return None, False, "needs PK_IMPL_DEPLOYER (forge create signs directly, even for a dry run)"
        cmd = [FORGE, "create", CONTRACT[build], "--rpc-url", target["rpc"], "--private-key", pk, *paris]
        cmd += ["--broadcast", "--json", *verify] if args.broadcast else []
        proc = run(cmd)
        if not args.broadcast:
            return None, proc.returncode == 0, "dry run (forge create builds the transaction without sending)"
        line = next((ln for ln in proc.stdout.splitlines() if '"deployedTo"' in ln), None)
        address = json.loads(line)["deployedTo"] if line else None
        return address, proc.returncode == 0, (proc.stdout + proc.stderr)[-1200:]

    cmd = [FORGE, "script", SCRIPT, "--sig", "deployImplementation()", "--rpc-url", target["rpc"], "--json", *paris]
    cmd += ["--broadcast", *verify] if args.broadcast else []
    proc = run(cmd, env=args.env)
    line = next((ln for ln in proc.stdout.splitlines() if '"returns"' in ln), None)
    address = json.loads(line)["returns"]["implementation"]["value"] if line else None
    return address, proc.returncode == 0, (proc.stdout + proc.stderr)[-1200:]


def preflight(targets, deployer):
    print(f"\nDeployer {deployer}: gas check (deployment estimate x gas price x 1.3)")
    low = []
    for t in targets:
        if t["chainId"] == 4217:
            print(f"  {t['chainId']:>7}  fee paid in the deployer's TIP-20 fee token (not checked)")
            continue
        try:
            build = "default" if t["build"] == "paris" else t["build"]  # paris differs by bytes; close enough here
            estimate = int(rpc(t["rpc"], "eth_estimateGas", [{"from": deployer, "data": compiled(build, "bytecode")}]), 16)
            cost = estimate * int(rpc(t["rpc"], "eth_gasPrice", []), 16) * 13 // 10
            balance = int(rpc(t["rpc"], "eth_getBalance", [deployer, "latest"]), 16)
            flag = "ok" if balance >= cost else "LOW"
            if flag == "LOW":
                low.append(t["chainId"])
            print(f"  {t['chainId']:>7}  balance {balance / 1e18:.6f}  needs ~{cost / 1e18:.6f}  {flag}")
        except Exception as err:  # noqa: BLE001
            print(f"  {t['chainId']:>7}  could not check ({err})")
    return low


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--broadcast", action="store_true", help="send transactions (default: dry run)")
    parser.add_argument("--chain", type=int, action="append", help="limit to these chain ids (repeatable)")
    parser.add_argument("--no-verify", action="store_true", help="skip explorer verification")
    parser.add_argument("--force", action="store_true", help="redeploy even if a matching implementation is recorded")
    args = parser.parse_args()

    env = dict(os.environ)
    for chain_id, url in DEFAULT_RPC_OVERRIDES.items():
        env.setdefault(f"WALLET_UPGRADE_RPC_{chain_id}", url)
    args.env = env
    pk = env.get("PK_IMPL_DEPLOYER")
    if args.broadcast and not pk:
        die("set PK_IMPL_DEPLOYER to the deployer's private key for --broadcast")
    etherscan_key = env.get("ETHERSCAN_API_KEY")

    targets = upgrade_targets(env)
    deferred = [t for t in targets if t["build"] in DEFERRED_BUILDS]
    targets = [t for t in targets if t["build"] not in DEFERRED_BUILDS]
    if args.chain:
        unknown = set(args.chain) - {t["chainId"] for t in targets}
        if unknown:
            die(f"not an active, non-deferred chain: {sorted(unknown)}")
        targets = [t for t in targets if t["chainId"] in args.chain]
    order = {"default": 0, "tempo": 1, "paris": 2}  # Linea (paris) last: it recompiles the whole project
    targets.sort(key=lambda t: order[t["build"]])

    mode = "BROADCAST" if args.broadcast else "dry run"
    print(f"{mode}: {len(targets)} chains; deferred: {[t['chainId'] for t in deferred] or 'none'}")
    commit = git("rev-parse", "HEAD")
    contracts_dirty = bool(git("status", "--porcelain", "--", "contracts"))
    if contracts_dirty:
        print("WARNING: contracts/ has uncommitted changes; deployments will not match the recorded commit.")

    deployer = None
    if pk:
        deployer = run_ok([CAST, "wallet", "address", "--private-key", pk]).strip()
        low = preflight(targets, deployer)
        if low and args.broadcast:
            print(f"Skipping chains with low deployer balance: {low} (fund them and rerun with --chain)")
            targets = [t for t in targets if t["chainId"] not in low]

    record = load_record()
    summary = []
    for t in targets:
        chain_id, build = t["chainId"], t["build"]
        key = str(chain_id)
        runtime = compiled(build, "deployedBytecode")
        existing = record.get(key, {}).get("implementation")
        if existing and not args.force:
            current = code_at(t["rpc"], existing)
            if current is None:  # never redeploy just because a public RPC hiccuped
                summary.append((chain_id, "SKIPPED", existing, "could not read the recorded implementation; rerun"))
                continue
            if current == runtime:
                summary.append((chain_id, "already deployed", existing, record[key].get("verification", "")))
                continue

        flags, verifier = ([], "skipped (--no-verify)") if args.no_verify else verify_args(chain_id, etherscan_key)
        print(f"\n[{chain_id}] {'deploying' if args.broadcast else 'simulating'} {build} build ...")
        address, ok, tail = deploy(t, args, pk, flags)

        if not args.broadcast:
            summary.append((chain_id, "simulated" if ok else "SIMULATION FAILED", address or "-", tail if not ok else ""))
            continue
        if not address:
            summary.append((chain_id, "FAILED", "-", tail))
            continue

        code = None
        for _ in range(10):  # public RPCs can lag the node that accepted the transaction
            code = code_at(t["rpc"], address)
            if code and code != "0x":
                break
            time.sleep(3)
        if code != runtime:
            status = "NOT CONFIRMED" if ok else "FAILED"
            summary.append((chain_id, status, address, "no matching code at the address yet; check the tx before rerunning\n" + tail))
            continue

        verification = verifier if not flags else (f"{verifier}: ok" if ok else f"{verifier}: FAILED, rerun forge verify-contract")
        record[key] = {
            "implementation": address,
            "build": build,
            "deployer": deployer,
            "commit": commit,
            "contractsDirty": contracts_dirty,
            "verification": verification,
            "recordedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        save_record(record)
        summary.append((chain_id, "deployed", address, verification))

    print("\nSummary")
    for chain_id, status, address, detail in summary:
        print(f"  {chain_id:>7}  {status:<18} {address}  {detail.splitlines()[-1] if detail else ''}"[:220])
    for t in deferred:
        print(f"  {t['chainId']:>7}  deferred            zksolc build: deploy with foundry-zksync, then add it to {RECORD.name}")
    if args.broadcast:
        print(f"\nRecorded in {RECORD.relative_to(REPO)}. Next: rebuild the upgrade console manifest and sign the upgrades.")


if __name__ == "__main__":
    main()
