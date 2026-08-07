#!/usr/bin/env python3
"""Generate Safe batches for chains DeprecateToken.s.sol cannot fork-simulate.

Optimism's configured RPC is rate-limited past usability, and forge --zksync reverts on
ZKsync Era / Abstract. All three still need the same teardown, so this reproduces the
exact decision logic of DeprecateOFTBase._deprecatePairOnToken over plain eth_calls:

  expected peer matches on-chain    -> setPeer(eid, 0)
  route wired & send not blocked    -> setSendLibrary(oft, eid, blockedLibrary)
  explicit receive library override -> setReceiveLibrary(oft, eid, 0, 0)
  enforced options dirty            -> setEnforcedOptions([...0x0003])
  app ULN config non-zero           -> setConfig(oft, lib, [ULN default])

Every guard is idempotent in the same way the Solidity is: a setting already at its reset
value emits no transaction, so these batches cannot revert with SameValue / OnlyNonDefaultLib.
"""

import json
import subprocess
import sys

ZERO32 = "0x" + "00" * 32
CONFIG_TYPE_ULN = 2
CLEARED_OPTIONS = "0x0003"

# oft, endpoint, libs and the single live peer confirmed by direct peers() reads.
CHAINS = [
    {
        "chainid": 10, "eid": 30111, "name": "Optimism",
        "rpc": "https://mainnet.optimism.io",
        "oft": "0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927",
        "endpoint": "0x1a44076050125825900e736c501f859c50fE728c",
        "sendLib302": "0x1322871e4ab09Bc7f5717189434f97bBD9546e95",
        "receiveLib302": "0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063",
    },
    {
        "chainid": 324, "eid": 30165, "name": "ZKsync Era",
        "rpc": "https://mainnet.era.zksync.io",
        "oft": "0x580f2ee1476edf4b1760bd68f6aabad57dec420e",
        "endpoint": "0xd07C30aF3Ff30D96BDc9c6044958230Eb797DDBF",
        "sendLib302": "0x07fD0e370B49919cA8dA0CE842B8177263c0E12c",
        "receiveLib302": "0x04830f6deCF08Dec9eD6C3fCAD215245B78A59e1",
    },
    {
        "chainid": 2741, "eid": 30324, "name": "Abstract",
        "rpc": "https://api.mainnet.abs.xyz",
        "oft": "0x580f2ee1476edf4b1760bd68f6aabad57dec420e",
        "endpoint": "0x5c6cfF4b7C49805F8295Ff73C204ac83f3bC4AE7",
        "sendLib302": "0x166CAb679EBDB0853055522D3B523621b94029a1",
        "receiveLib302": "0x9d799c1935c51CA399e6465Ed9841DEbCcEc413E",
    },
]

DST_EID = 30255  # Fraxtal
DST_CHAINID = 252
EXPECTED_PEER = "0x" + "00" * 12 + "75c38d46001b0f8108c4136216bd2694982c20fc"


def cast(args, rpc):
    r = subprocess.run(["cast", *args, "--rpc-url", rpc], capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        return None
    return r.stdout.strip()


def calldata(sig, *args, rpc=None):
    r = subprocess.run(["cast", "calldata", sig, *[str(a) for a in args]], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"cast calldata failed for {sig}: {r.stderr}")
    return r.stdout.strip()


def tx(to, data):
    return {"to": to, "value": "0", "operation": "0", "data": data}


def build(chain):
    rpc, oft, ep = chain["rpc"], chain["oft"], chain["endpoint"]
    out, notes = [], []

    peer = cast(["call", oft, "peers(uint32)(bytes32)", str(DST_EID)], rpc)
    if peer is None:
        return None, ["peers() read failed"]
    peer = peer.split()[0].lower()
    if peer == ZERO32:
        return [], ["peer already zero - route clean"]
    if peer != EXPECTED_PEER:
        return None, [f"UNEXPECTED PEER {peer} (expected {EXPECTED_PEER}) - refusing, needs review"]

    blocked = cast(["call", ep, "blockedLibrary()(address)", ], rpc)
    blocked = blocked.split()[0] if blocked else None

    # --- send library ---
    cur_send = cast(["call", ep, "getSendLibrary(address,uint32)(address)", oft, str(DST_EID)], rpc)
    cur_send = cur_send.split()[0] if cur_send else None
    if blocked and cur_send and cur_send.lower() != blocked.lower():
        out.append(tx(ep, calldata("setSendLibrary(address,uint32,address)", oft, DST_EID, blocked)))
        notes.append(f"setSendLibrary {cur_send} -> blocked {blocked}")
    else:
        notes.append("send library already blocked - skipped")

    # --- peer ---
    out.append(tx(oft, calldata("setPeer(uint32,bytes32)", DST_EID, ZERO32)))
    notes.append("setPeer -> 0")

    # --- receive library (only when an explicit override exists) ---
    recv = cast(["call", ep, "getReceiveLibrary(address,uint32)(address,bool)", oft, str(DST_EID)], rpc)
    if recv:
        parts = recv.split()
        is_default = parts[-1].lower() == "true"
        if not is_default:
            out.append(tx(ep, calldata("setReceiveLibrary(address,uint32,address,uint256)", oft, DST_EID, "0x" + "0" * 40, 0)))
            notes.append(f"setReceiveLibrary {parts[0]} -> DEFAULT")
        else:
            notes.append("receive library already default - skipped")

    # --- enforced options ---
    dirty = []
    for msg_type in (1, 2):
        v = cast(["call", oft, "enforcedOptions(uint32,uint16)(bytes)", str(DST_EID), str(msg_type)], rpc)
        v = v.split()[0].lower() if v else "0x"
        if v not in ("0x", CLEARED_OPTIONS, ""):
            dirty.append(msg_type)
    if dirty:
        tuples = "[" + ",".join(f"({DST_EID},{m},{CLEARED_OPTIONS})" for m in dirty) + "]"
        out.append(tx(oft, calldata("setEnforcedOptions((uint32,uint16,bytes)[])", tuples)))
        notes.append(f"setEnforcedOptions msgTypes={dirty} -> 0x0003")
    else:
        notes.append("enforced options already clear - skipped")

    # --- app ULN config on each distinct lib ---
    empty_uln = calldata(
        "x((uint64,uint8,uint8,uint8,address[],address[]))", f"(0,0,0,0,[],[])"
    )[10:]  # strip selector, keep encoded struct
    for lib in {chain["sendLib302"].lower(), chain["receiveLib302"].lower()}:
        supported = cast(["call", lib, "isSupportedEid(uint32)(bool)", str(DST_EID)], rpc)
        if not supported or supported.split()[0].lower() != "true":
            notes.append(f"lib {lib[:10]}.. does not support eid - skipped")
            continue
        app = cast(["call", lib, "getAppUlnConfig(address,uint32)((uint64,uint8,uint8,uint8,address[],address[]))", oft, str(DST_EID)], rpc)
        if app is None:
            notes.append(f"lib {lib[:10]}.. getAppUlnConfig unavailable - skipped")
            continue
        nums = app.replace("(", " ").replace(")", " ").replace(",", " ").split()
        is_zero = all(n in ("0", "[]") for n in nums if not n.startswith("0x"))
        if is_zero and "0x" not in app:
            notes.append(f"lib {lib[:10]}.. app ULN already default - skipped")
            continue
        params = f"[({DST_EID},{CONFIG_TYPE_ULN},0x{empty_uln})]"
        out.append(tx(chain["endpoint"], calldata("setConfig(address,address,(uint32,uint32,bytes)[])", oft, lib, params)))
        notes.append(f"setConfig ULN -> default on {lib[:10]}..")

    return out, notes


def main():
    dry = "--write" not in sys.argv
    outdir = "scripts/ops/DeprecateChain/txs/deprecate-FPI"

    for chain in CHAINS:
        print(f"\n=== {chain['name']} ({chain['chainid']}) -> Fraxtal ({DST_CHAINID}) ===")
        try:
            txs, notes = build(chain)
        except Exception as exc:
            print(f"  ERROR: {exc}")
            continue
        for n in notes:
            print(f"  - {n}")
        if txs is None:
            print("  => NO FILE (needs manual review)")
            continue
        if not txs:
            print("  => NO FILE (nothing to do)")
            continue

        doc = {
            "version": "1.0",
            "chainId": chain["chainid"],
            "createdAt": 0,
            "meta": {"name": "Transactions Batch", "description": ""},
            "transactions": txs,
        }
        path = f"{outdir}/Deprecate-{chain['chainid']}-{DST_CHAINID}-FPI.json"
        print(f"  => {len(txs)} txs -> {path}")
        if dry:
            print("     (dry run; pass --write to persist)")
        else:
            with open(path, "w") as fh:
                json.dump(doc, fh, indent=4)
                fh.write("\n")


if __name__ == "__main__":
    main()
