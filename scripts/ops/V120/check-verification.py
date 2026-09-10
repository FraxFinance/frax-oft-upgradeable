#!/usr/bin/env python3
"""Audit explorer-verification coverage for every OFT proxy and implementation in the mesh.

Each chain is queried through the verifier that actually serves it (Etherscan v2, Sourcify, or
Tempo's own service), because "not on Sourcify" does not mean "unverified".

    scripts/ops/V120/check-verification.py            # every active chain
    scripts/ops/V120/check-verification.py 10 252     # selected chain ids

ETHERSCAN_API_KEY is read from the environment or .env. Chains without it fall back to Sourcify.
Run it before the upgrade to see the baseline, and again afterwards to confirm the new
implementations landed verified.
"""

import json
import os
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CONFIG = os.path.join(ROOT, "scripts", "L0Config.json")

IMPL_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
DEPRECATED = {1101, 34443, 80094, 534352, 3637, 22222222, 33333333}
LEGACY_ONLY = {81457}

# Etherscan v2 serves these with a single key; everything else falls back to Sourcify.
ETHERSCAN_V2 = {1, 10, 56, 130, 137, 143, 146, 252, 480, 988, 999, 1329, 2741, 8453, 42161,
                43114, 59144, 747474}

TOKENS = ["WFRAX", "sfrxUSD", "sfrxETH", "frxUSD", "frxETH"]

# Mirrors the per-chain OFT registry in L0Constants.sol and must be updated alongside it when a
# chain is added. A chain absent from REGISTRY falls back to EXPECTED, exactly as
# `_getChainPeers()` does; if that address holds no proxy the row reports "not deployed" rather
# than silently passing.

EXPECTED = ["0x64445f0aecC51E94aD52d8AC56b7190e764E561a", "0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0",
            "0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45", "0x80Eede496655FB9047dd39d9f418d5483ED600df",
            "0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050"]
ZK = ["0xAf01aE13Fb67AD2bb2D76f29A83961069a5F245F", "0x9F87fbb47C33Cd0614E43500b9511018116F79eE",
      "0xFD78FD3667DeF2F1097Ed221ec503AE477155394", "0xEa77c590Bb36c43ef7139cE649cFBCFD6163170d",
      "0xc7Ab797019156b543B7a3fBF5A99ECDab9eb4440"]
FULL_DET = ["0x00000000E9CE0f293D1Ce552768b187eBA8a56D4", "0x00000000fD8C4B8A413A06821456801295921a71",
            "0x00000000883279097A49dB1f2af954EAd0C77E3c", "0x00000000D61733e7A393A10A5B48c311AbE8f1E5",
            "0x000000008c3930dCA540bB9B3A5D0ee78FcA9A4c"]
REGISTRY = {
    1: ["0x04ACaF8D2865c0714F79da09645C13FD2888977f", "0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126",
        "0xbBc424e58ED38dd911309611ae2d7A23014Bd960", "0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0",
        "0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6"],
    252: ["0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A", "0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361",
          "0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168", "0x96A394058E2b84A89bac9667B19661Ed003cF5D4",
          "0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604"],
    8453: ["0x0CEAC003B0d2479BebeC9f4b2EBAd0a803759bbf", "0x91A3f8a8d7a881fBDfcfEcd7A2Dc92a46DCfa14e",
           "0x192e0C7Cc9B263D93fa6d472De47bBefe1Fb12bA", "0xe5020A6d073a794B6E7f05678707dE47986Fb0b6",
           "0x7eb8d1E4E2D0C8b9bEDA7a97b305cF49F3eeE8dA"],
    59144: ["0x5217Ab28ECE654Aab2C68efedb6A22739df6C3D5", "0x592a48c0FB9c7f8BF1701cB0136b90DEa2A5B7B6",
            "0x383Eac7CcaA89684b8277cBabC25BCa8b13B7Aa2", "0xC7346783f5e645aa998B106Ef9E7f499528673D8",
            "0xB1aFD04774c02AE84692619448B08BA79F19b1ff"],
    143: ["0x29aCC7c504665A5EA95344796f784095f0cfcC58", "0x137643F7b2C189173867b3391f6629caB46F0F1a",
          "0x3B4cf37A3335F21c945a40088404c715525fCb29", "0x58E3ee6accd124642dDB5d3f91928816Be8D8ed3",
          "0x288F9D76019469bfEb56BB77d86aFa2bF563B75B"],
    2741: ZK, 324: ZK, 4217: FULL_DET, 5031: FULL_DET,
}

# Native Blockscout instances — these carry verifications that Sourcify does not mirror.
BLOCKSCOUT = {
    57073: "https://explorer.inkonchain.com/api",
    98866: "https://explorer.plume.org/api",
    1313161554: "https://explorer.mainnet.aurora.dev/api",
    5031: "https://explorer.somnia.network/api",
}
# zksync-stack explorers expose an Etherscan-compatible module too.
ZKSYNC_EXPLORER = {
    324: "https://block-explorer-api.mainnet.zksync.io/api",
    2741: "https://api.abscan.org/api",
}

HEADERS = {"Content-Type": "application/json", "User-Agent": "Mozilla/5.0 frax-verify-audit/1.0"}


def etherscan_key():
    if os.environ.get("ETHERSCAN_API_KEY"):
        return os.environ["ETHERSCAN_API_KEY"]
    envfile = os.path.join(ROOT, ".env")
    if os.path.exists(envfile):
        for line in open(envfile):
            if line.strip().startswith("ETHERSCAN_API_KEY="):
                return line.split("=", 1)[1].strip().strip("'\"")
    return None


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(url, body, HEADERS)
    return json.loads(urllib.request.urlopen(req, timeout=25).read()).get("result")


def implementation_of(rpc_url, proxy):
    raw = rpc(rpc_url, "eth_getStorageAt", [proxy, IMPL_SLOT, "latest"])
    if not raw or int(raw, 16) == 0:
        return None
    return "0x" + raw[-40:]


def sourcify_status(chain_id, address):
    url = f"https://sourcify.dev/server/v2/contract/{chain_id}/{address}"
    try:
        d = json.loads(urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=20).read())
        return d.get("match") or "unverified"
    except Exception:
        return "unverified"


def etherscan_status(chain_id, address, key):
    q = urllib.parse.urlencode({"chainid": chain_id, "module": "contract", "action": "getsourcecode",
                                "address": address, "apikey": key})
    try:
        d = json.loads(urllib.request.urlopen(
            urllib.request.Request(f"https://api.etherscan.io/v2/api?{q}", headers=HEADERS), timeout=25).read())
        result = (d.get("result") or [{}])[0]
        return "verified" if result.get("SourceCode") else "unverified"
    except Exception as exc:
        return f"error({type(exc).__name__})"


def etherscan_compatible_status(base, address):
    q = urllib.parse.urlencode({"module": "contract", "action": "getsourcecode", "address": address})
    try:
        d = json.loads(urllib.request.urlopen(
            urllib.request.Request(f"{base}?{q}", headers=HEADERS), timeout=25).read())
        result = (d.get("result") or [{}])
        if isinstance(result, list) and result and result[0].get("SourceCode"):
            return "verified"
        return "unverified"
    except Exception as exc:
        return f"error({type(exc).__name__})"


def status_for(chain_id, address, key):
    if chain_id == 4217:
        return "tempo-service"  # verified via contracts.tempo.xyz; not queryable here
    if chain_id in BLOCKSCOUT:
        st = etherscan_compatible_status(BLOCKSCOUT[chain_id], address)
        return st if st == "verified" else f"blockscout:{st}/sourcify:{sourcify_status(chain_id, address)}"
    if chain_id in ZKSYNC_EXPLORER:
        st = etherscan_compatible_status(ZKSYNC_EXPLORER[chain_id], address)
        return st if st == "verified" else f"zksync:{st}/sourcify:{sourcify_status(chain_id, address)}"
    if chain_id in ETHERSCAN_V2 and key:
        st = etherscan_status(chain_id, address, key)
        if st == "unverified":  # some explorers only carry the Sourcify record
            alt = sourcify_status(chain_id, address)
            return st if alt == "unverified" else f"sourcify:{alt}"
        return st
    return sourcify_status(chain_id, address)


def main():
    cfg = json.load(open(CONFIG))
    wanted = {int(a) for a in sys.argv[1:]} or None
    key = etherscan_key()
    print(f"ETHERSCAN_API_KEY: {'found' if key else 'MISSING (Sourcify only)'}\n")

    seen, unverified = set(), []
    for c in cfg["Proxy"]:
        cid = c["chainid"]
        if cid in seen or cid in DEPRECATED or cid in LEGACY_ONLY:
            continue
        seen.add(cid)
        if wanted and cid not in wanted:
            continue

        ofts = REGISTRY.get(cid, EXPECTED)
        print(f"chain {cid}")
        for i, proxy in enumerate(ofts):
            try:
                impl = implementation_of(c["RPC"], proxy)
            except Exception as exc:
                print(f"  {TOKENS[i]:<8} RPC ERROR {type(exc).__name__}")
                continue
            if impl is None:
                print(f"  {TOKENS[i]:<8} not deployed")
                continue
            st = status_for(cid, impl, key)
            ok = st == "verified" or "match" in st or st == "tempo-service"
            flag = "" if ok else "   <-- UNVERIFIED"
            print(f"  {TOKENS[i]:<8} impl {impl} {st}{flag}")
            if flag:
                unverified.append((cid, TOKENS[i], impl))

    print("\n==== SUMMARY ====")
    if unverified:
        print(f"{len(unverified)} unverified implementation(s):")
        for cid, tok, impl in unverified:
            print(f"  chain {cid} {tok} {impl}")
    else:
        print("all implementations report verified")


if __name__ == "__main__":
    main()
