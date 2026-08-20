# Mode ops Safe — on-chain execution guide (no Safe UI)

**Safe:** `0x6336CFA6eDBeC2A459d869031DB77fC2770Eaa66` on **Mode (chainId 34443)** — Safe v1.3.0 (L2 singleton), 6 owners, threshold **3**, nonce **56** at time of writing.
**Scope:** 86 Transaction-Builder JSON batches (OFT lane deprecations for frxUSD / sfrxUSD / frxETH / sfrxETH / WFRAX / FPI from Mode to 14–15 remotes, plus the hop-v2 `RemoteHopV2 → RemoteHopV201` upgrade), packed into **2 Safe transactions** (nonces 56–57) — the minimum possible while keeping every upstream JSON payload byte-identical (the full set is ~180 KB of calldata; op-geth's txpool rejects any tx over 128 KB, so one tx is impossible without re-encoding the calls).
**Tooling:** `scripts/ops/SafeOnchainExec/` (bash + `jq` + Foundry `cast`/`anvil`; nothing else).

> Generated 2026-08-20. Every hash below is truncated (`0xprefix…suffix`); the full values are in `scripts/ops/SafeOnchainExec/out/34443-0x6336…/SUMMARY.md`, which you must regenerate yourself in Step 1 — never trust a hash you didn't rebuild.

---

## 0. Why this flow

No hosted Safe front-end currently serves Mode (checked 2026-08-20):

| Provider | Mode 34443 |
|---|---|
| `app.safe.global` | not supported (gateway 404) |
| Superchain Safe `safe.optimism.io` (what Mode docs link) | redirects to Protofire `app.safe.protofire.io`; Mode is not in its chain list |
| Den, Brahma | not supported |
| Eternal Safe (`eternalsafe.vercel.app`) | works, but has no Transaction Builder / JSON import; only a 1-call "Custom transaction" + a fragile "Add to batch" sidebar, and coordination is by sharing URLs |

So we skip UIs entirely and use the Safe contract's own **approved-hash** flow, which only needs an RPC:

1. Pack each group of JSON files into **one `MultiSendCallOnly.multiSend(bytes)`** call (Safe executes it via `DELEGATECALL`, exactly what the Safe UI / Transaction Builder would have produced).
2. Compute the Safe's EIP-712 **`safeTxHash`** for `(to=MultiSendCallOnly, value=0, data, operation=1, safeTxGas=0, baseGas=0, gasPrice=0, gasToken=0, refundReceiver=0, nonce)`.
3. Owners call **`Safe.approveHash(safeTxHash)`** from their own wallet (one cheap on-chain tx per batch).
4. Once enough approvals exist, an owner calls **`Safe.execTransaction(...)`** with "signatures" that are just `(r=owner, s=0, v=1)` for each approver. The Safe checks `approvedHashes[owner][hash]` — **except for `msg.sender`, who counts automatically if they are an owner**. So per batch: **2 owners `approveHash` + a 3rd owner executes = 3 on-chain txs**, **6 txs total** for both batches (vs. 3×n+n with naive approvals).

Atomicity: `safeTxGas=0 && gasPrice=0` makes the Safe **revert the whole tx (GS013)** if the inner batch fails, and `MultiSendCallOnly` reverts if any inner call fails — so a batch either fully applies or does nothing (nonce untouched, approvals still valid).

---

## 1. The 4 batches

| # | nonce | batch | inner calls | source files | multiSend calldata | fork gas | safeTxHash (truncated) |
|---|---|---|---|---|---|---|---|
| 01 | 56 | `01-frxusd-sfrxusd-frxeth` — frxUSD, sfrxUSD, frxETH lanes to 14 remotes each | 174 | 42 | 88,612 B | ≈5.3 M | `0xfcfe3865…1dcb8003` |
| 02 | 57 | `02-sfrxeth-wfrax-fpi-hopv2` — sfrxETH, WFRAX (14 remotes each), FPI (15 remotes incl. Polygon zkEVM), then hop-v2: upgrade RemoteHopV2 proxy → RemoteHopV201 impl `0x0000000f9a66…ecCCd` and grant `RECOVER_ETH_ROLE` to this Safe | 180 | 44 | 91,076 B | ≈5.5 M | `0x59492f4e…817227a8` |

Why 2 and not 1: gas is fine (all 354 calls ≈ 11 M on a 30 M block; the fork showed ~30 k gas per inner call) but the packed calldata is ~180 KB total and op-geth rejects txs > 128 KB. Getting to a single batch would require re-encoding the calls (e.g. one `setConfig` per OFT+lib carrying all 14 eids, one `setEnforcedOptions` per OFT) — semantically identical but no longer byte-identical to the reviewed upstream JSONs, so it was not done; say so if you want it.

**Per-lane template (every `Deprecate-34443-<remoteChainId>-<TOKEN>.json`):**
1. `EndpointV2.setReceiveLibrary(oft, remoteEid, address(0), 0)` → back to the endpoint **default** receive lib
2. `OFT.setEnforcedOptions([(remoteEid,1,0x0003),(remoteEid,2,0x0003)])` → enforced options **cleared** (empty type-3 options)
3. `EndpointV2.setConfig(oft, SendUln302, [(remoteEid, 2, emptyUlnConfig)])` → send-side DVN/ULN config **reset to default**
4. `EndpointV2.setConfig(oft, ReceiveUln302, [(remoteEid, 2, emptyUlnConfig)])` → receive-side DVN/ULN config **reset to default**

The **Fraxtal (eid 30255) files have 6 calls** — the above plus `setSendLibrary(oft, 30255, BlockedMessageLib 0x1ccB…D862)` (lane hard-blocked for sending) and `setPeer(30255, bytes32(0))` (peer removed).

Inputs are vendored at `scripts/ops/SafeOnchainExec/inputs/34443-0x6336…/` with `MANIFEST.tsv` recording the upstream source of every file:

| Upstream | Commit | Path | Files |
|---|---|---|---|
| `dhruvinparikh/frax-oft-upgradeable` | `edc0e95f` | `scripts/ops/DeprecateChain/txs/deprecate-34443/` | 84 (`Deprecate-34443-*-{FPI,FRXETH,FRXUSD,SFRXETH,SFRXUSD,WFRAX}.json`) |
| `dhruvinparikh/frax-oft-upgradeable` | `28a6a221` | `scripts/ops/DeprecateChain/txs/deprecate-FPI/` | 1 (`Deprecate-34443-1101-FPI.json`; the other 14 FPI files there are byte-identical to the `deprecate-34443` ones) |
| `dhruvinparikh/frax-oft-upgradeable` | `b6330ad7` | `scripts/ops/DeprecateChain/txs/deprecate-111111111/` | 0 vendored — the 6 `Deprecate-34443-30168-*.json` are byte-identical to `Deprecate-34443-111111111-*.json` (Solana, eid 30168) already included; recorded in the manifest as duplicates |
| `dhruvinparikh/hop-v2` | `4cf8976f` | `src/script/hop/upgrade/txs/34443-0x6336…eaa66.json` | 1 (`HopV2-Upgrade-34443-0x6336.json`) |

> Not included: the Fraxtal-side / other-chain halves of these campaigns (see `MSIG-TXN-DECODE.md`). This guide is only the Mode Safe.

---

## 2. Prerequisites (every signer)

```bash
# Foundry (cast + anvil) and jq
curl -L https://foundry.paradigm.xyz | bash && foundryup
brew install jq          # or your package manager
git clone <this repo> && cd frax-oft-upgradeable && git checkout <this commit>
```
RPC used by default: `https://mainnet.mode.network/` (override with `RPC=...`).

---

## 3. Step-by-step

### Step 1 — Rebuild the batches yourself and confirm the hashes
```bash
scripts/ops/SafeOnchainExec/build-safe-batches.sh scripts/ops/SafeOnchainExec/config/34443-0x6336.json
```
Expected output, per batch: `safeTxHash (offline == on-chain getTransactionHash): 0x…` — the script computes the EIP-712 hash locally **and** asks the Safe contract (`getTransactionHash`) and aborts on mismatch. It also verifies every input file's sha256 against `MANIFEST.tsv`, checks `MultiSendCallOnly` has code on Mode, and warns if the Safe nonce ≠ 56.

Then confirm the build is reproducible: `git status scripts/ops/SafeOnchainExec/out/` must show **no changes** (outputs are deterministic). The 4 truncated hashes in §1 must match `out/…/SUMMARY.md`.

Optional — verify inputs against upstream instead of trusting the manifest:
```bash
IN=scripts/ops/SafeOnchainExec/inputs/34443-0x6336cfa6edbec2a459d869031db77fc2770eaa66
tail -n +2 $IN/MANIFEST.tsv | grep -v DUPLICATE | while IFS=$'\t' read f repo commit path sha; do
  up=$(curl -s https://raw.githubusercontent.com/$repo/$commit/$path | shasum -a 256 | cut -d' ' -f1)
  [ "$up" = "$sha" ] && echo "OK   $f" || echo "DIFF $f (upstream $up)"
done
```

### Step 2 — Review what you are approving
Read `out/…/batch-NN-<name>.decoded.md` (one row per inner call: source file, target, function, decoded args with labels). Things to check:

- Targets are **only**: LayerZero `EndpointV2 0x1a44…728c`, the six OFTs (`frxUSD 0x80Ee…00df`, `sfrxUSD 0x5Bff…70c0`, `frxETH 0x43eD…9050`, `sfrxETH 0x3Ec3…De45`, `WFRAX 0x6444…561a`, `FPI 0x9058…7927`), and for batch 04 `ProxyAdmin 0x223a…405c` + `RemoteHopV2 proxy 0x0000006D…e659`.
- Every `setConfig` row says **`=> RESET to lib DEFAULT ULN config`**, every `setReceiveLibrary` says **`=> use endpoint DEFAULT receive lib`**, enforced options are `0x0003`.
- Only Fraxtal rows (`eid 30255`) contain `setSendLibrary → BlockedMessageLib` and `setPeer → peer REMOVED`.
- Batch 04: new implementation `0x0000000f9a66622C8885E1071B78E37b2b3ecCCd`, `initData=0x`, role decodes as `RECOVER_ETH_ROLE`, account = this Safe.
- No row says `UNKNOWN selector`; `value` is 0 everywhere; all inner operations are CALL (the builder rejects anything else).

To decode independently of the build outputs (e.g. the hex your hardware wallet / explorer shows):
```bash
scripts/ops/SafeOnchainExec/decode-multisend.sh scripts/ops/SafeOnchainExec/config/34443-0x6336.json <0x8d80ff0a…hex or batch-NN.json> --nonce 56
```

### Step 3 — Simulate on a fork (recommended before anyone approves)
```bash
scripts/ops/SafeOnchainExec/simulate-safe-batches.sh scripts/ops/SafeOnchainExec/config/34443-0x6336.json
```
Spins up `anvil --fork-url <Mode RPC>`, impersonates 3 owners → `approveHash`, executes each batch from a **non-owner** EOA, asserts `ExecutionSuccess` + nonce advance, then re-reads state for **every** inner call (receive lib is default, `getAppUlnConfig` is all-zero, enforced options == `0x0003`, peers zero, proxy implementation updated, `hasRole` true). Ends with `ALL POST-CONDITIONS PASSED` and writes `out/…/SIMULATION.md` (incl. gas used per batch).

### Step 4 — Approve (2 owners per batch, any order, any time)
Full hashes: `out/…/SUMMARY.md` / `COMMANDS.md` (from **your** rebuild).
```bash
SAFE=0x6336CFA6eDBeC2A459d869031DB77fC2770Eaa66; RPC=https://mainnet.mode.network/
cast send $SAFE 'approveHash(bytes32)' <SAFE_TX_HASH_01> --rpc-url $RPC --ledger     # or --trezor / --account <name> / --interactive
cast send $SAFE 'approveHash(bytes32)' <SAFE_TX_HASH_02> --rpc-url $RPC --ledger
```
Minimum plan for threshold 3: owners A and B each approve both hashes (4 txs), owner C executes both batches (2 txs) — C never calls `approveHash`. A third approval is harmless and lets a non-owner execute instead.
- On the hardware wallet you will see a plain contract call to the Safe with one `bytes32` — compare **prefix and suffix** with your rebuilt hash.
- You need a little ETH on Mode in your owner EOA (≈ 30–50k gas per approval). The Safe itself needs none.
- Check it landed: `cast call $SAFE 'approvedHashes(address,bytes32)(uint256)' <YOUR_ADDRESS> <HASH> --rpc-url $RPC` → `1`.
- Explorer alternative (no CLI): Mode Blockscout → the Safe address → *Write proxy* → `approveHash(bytes32)` with your wallet (works only if Blockscout has the `GnosisSafeL2 1.3.0` implementation verified).
- Approving is **independent of order** and does not execute anything. But both hashes embed nonces 56/57: if **any other** transaction executes through this Safe before batch 01 (e.g. someone signs something in Eternal Safe), both hashes become stale — edit `startNonce` in the config, rebuild, re-approve.

### Step 5 — Execute (an owner, or anyone if 3 approvals exist; strictly 01 then 02)
```bash
scripts/ops/SafeOnchainExec/exec-safe-batch.sh scripts/ops/SafeOnchainExec/config/34443-0x6336.json 01 \
  --approvers 0xOWNER_A,0xOWNER_B --sender 0xOWNER_C            # dry run: checks + eth_call + calldata
scripts/ops/SafeOnchainExec/exec-safe-batch.sh scripts/ops/SafeOnchainExec/config/34443-0x6336.json 01 \
  --approvers 0xOWNER_A,0xOWNER_B --sender 0xOWNER_C --send --ledger   # broadcast (C's ledger = the --sender owner)
```
The script refuses to run unless: the Safe nonce equals the batch nonce, `getTransactionHash` still matches, every listed approver is an owner with `approvedHashes == 1`, ≥ 3 approvals counting the sender if it is an owner, and an `eth_call` of the exact `execTransaction` returns `true`. It then estimates gas (+30 %) and broadcasts. Repeat for 02. Expected gas ≈ 5.3 M and 5.5 M (fork numbers in `SIMULATION.md`) — a few cents on Mode. `--sender` must be the address that actually signs the broadcast (your ledger account).

### Step 6 — Verify on-chain afterwards
```bash
cast call $SAFE 'nonce()(uint256)' --rpc-url $RPC                                   # 58 after both
cast receipt <EXEC_TX_HASH> --rpc-url $RPC | grep -A1 -i status                     # 1
# spot-check a lane (frxUSD → Ethereum):
EP=0x1a44076050125825900e736c501f859c50fE728c; OFT=0x80Eede496655FB9047dd39d9f418d5483ED600df
cast call $EP 'getReceiveLibrary(address,uint32)(address,bool)' $OFT 30101 --rpc-url $RPC      # (…, true) = default
cast call 0x2367325334447C5E1E0f1b3a6fB947b262F58312 'getAppUlnConfig(address,uint32)((uint64,uint8,uint8,uint8,address[],address[]))' $OFT 30101 --rpc-url $RPC   # (0, 0, 0, 0, [], [])
cast call $OFT 'enforcedOptions(uint32,uint16)(bytes)' 30101 1 --rpc-url $RPC                  # 0x0003
# hop:
cast implementation 0x0000006D38568b00B457580b734e0076C62de659 --rpc-url $RPC                    # 0x0000000f9a66…ecCCd
```
The same post-condition reads the simulator performs (`simulate-safe-batches.sh`, section "post-conditions") work against the live RPC.

---

## 4. Troubleshooting

| Symptom | Meaning / fix |
|---|---|
| `ERROR: Safe nonce is N but this batch is for nonce M` | Something else executed, or earlier batch not executed yet. Execute in order, or set `startNonce` in the config, rebuild, re-approve. |
| `GS025` revert on execute | An address in `--approvers` has not actually approved this hash (or approved a stale hash). Check `approvedHashes`. |
| `GS026` | Signatures not sorted / non-owner included. Always use `exec-safe-batch.sh` (it sorts). |
| `GS013` | Inner batch reverted (some config call failed on mainnet state, e.g. already changed). Nonce unchanged. Re-run the fork simulation to see which call; regenerate inputs upstream if state drifted. |
| Build says offline hash ≠ on-chain hash | Wrong `chainId`/`safe` in config or a non-1.3.0 Safe. Stop. |
| Want different grouping (e.g. one batch per token, or hop separate) | Edit `groups` in `config/34443-0x6336.json`, rebuild; hashes change, re-approve. Keep each batch < ~120 KB multiSend calldata (op-geth 128 KB tx cap) and well under the 30 M block gas limit. |
| Signer can't do on-chain `approveHash` | Alternative: sign the EIP-712 digest off-chain (`cast wallet sign --no-hash <SAFE_TX_HASH>` — this signs the 32-byte digest directly, the same thing the Safe verifies; Ledger needs blind signing for this) and build the `signatures` blob as `r‖s‖v` sorted by owner instead of the `v=1` approved-hash entries. Mixed blobs (some approved-hash, some ECDSA) are fine. |

## 5. Files

```
MODE-SAFE-ONCHAIN-EXEC.md                     this guide
scripts/ops/SafeOnchainExec/
  config/34443-0x6336.json                    Safe, RPC, MultiSendCallOnly, pinned startNonce, labels, batch groups
  inputs/34443-0x6336…/*.json + MANIFEST.tsv  vendored Transaction-Builder JSONs + upstream provenance/sha256
  lib.sh                                      MultiSend packing/parsing, EIP-712 hashing, decoders, sig packing
  build-safe-batches.sh                       inputs → out/batch-NN.json, .decoded.md, SUMMARY.md, COMMANDS.md
  simulate-safe-batches.sh                    anvil fork: approve → execute → post-condition checks → SIMULATION.md
  exec-safe-batch.sh                          verify approvals + simulate + (optionally) broadcast execTransaction
  decode-multisend.sh                         decode any multiSend hex / batch json, recompute safeTxHash
  out/34443-0x6336…/                          generated; deterministic — rebuild and diff, don't trust
```
