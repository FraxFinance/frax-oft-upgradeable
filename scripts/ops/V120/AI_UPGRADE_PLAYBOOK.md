# V120 OFT Upgrade — AI Operator Prompt & In‑Depth Playbook

This document is the control sheet for driving the **Frax OFT v1.1.0 → v1.2.0** upgrade with an
AI coding agent (Codex CLI). It contains:

1. [Recommended Codex configuration](#1-recommended-codex-configuration) (model / reasoning effort / sandbox).
2. [The copy‑paste AI prompt](#2-copy-paste-ai-prompt) — feed this to the agent.
3. [The in‑depth playbook](#3-in-depth-playbook) the prompt references (also a human checklist).
4. [Grounding facts & preliminary findings](#4-grounding-facts--preliminary-findings) — the invariants the agent must respect.

> ⚠️ **Headline finding (read first).** The v1.2.0 mintable adapters add a `SupplyTrackingModule`
> guard that **reverts inbound bridges** (`TotalTransferFromExceedsInitialTotalSupply`) until
> `setInitialTotalSupply(eid, amount)` is seeded per destination. Post‑upgrade the module storage
> starts at zero, so the **first** inbound `frxUSD`/`sfrxUSD` transfer from every chain reverts
> unless initial supply is set **or** `setAllowNegativeSupply(eid, true)` is enabled. The V120
> scripts now append those txs atomically: a reviewed `scripts/ops/V120/supply/<chainid>.json`
> takes precedence, otherwise EVM-readable seeds are generated from fresh peer-chain forks and
> written to `scripts/ops/V120/supply/generated/<chainid>.json`.

---

## 1. Recommended Codex configuration

This is a safety‑critical, money‑moving smart‑contract upgrade with cross‑chain supply accounting.
**Optimize for correctness, not speed.** Use a strong reasoning model at **high** effort for the
analysis/accounting/Safe‑batch work; only drop to lower effort for mechanical formatting.

| Setting | Recommended value | Why |
|---|---|---|
| `model` | strongest reasoning‑capable model available (e.g. `gpt-5-codex` / `gpt-5.1-codex`) | Accounting + storage‑layout + calldata reasoning |
| `model_reasoning_effort` | **`high`** (i.e. "slow / thorough") for Phases 0–3, 5–8; `medium` OK for report formatting only | Never use `minimal`/`low` on supply accounting or upgrade calldata |
| `model_reasoning_summary` | `detailed` | You want to see the accounting reasoning to sanity‑check it |
| `sandbox_mode` | `workspace-write` **with** `network_access = true` | `forge` fork simulations read RPCs and write Safe JSON under `txs/` |
| `approval_policy` | `on-request` (or `untrusted`) | Never let it broadcast, push, or execute a Safe tx unattended |
| Broadcast/keys | **Manual only** | The agent must never touch `PK_CONFIG_DEPLOYER` or `--broadcast` without your explicit go |

**Effort by phase (fast vs. slow):**

- **Slow / `high`:** §3 Phase 0 (recon), Phase 1 (simulate), Phase 2 (storage & safety), Phase 5
  (initial‑supply accounting), Phase 6 (allowNegative decision), Phase 8 (post‑upgrade proofs).
- **Medium:** Phase 4 (deploy/verify orchestration), Phase 7 (auditor report formatting).
- **Fast / `low`:** only trivial reformatting or link‑fixing. Do **not** use fast mode to compute
  `initialTotalSupply` values or to assemble upgrade calldata.

### `~/.codex/config.toml` profile

```toml
[profiles.frax-v120-audit]
model = "gpt-5-codex"                 # swap for the strongest model you have access to
model_reasoning_effort = "high"       # thorough; correctness > latency
model_reasoning_summary = "detailed"
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[profiles.frax-v120-audit.sandbox_workspace_write]
network_access = true                 # forge fork sims + RPC reads
```

### Invocation

```bash
# From the repo root of frax-oft-upgradeable
codex --profile frax-v120-audit
# then paste the prompt in §2, OR pipe it:
#   codex --profile frax-v120-audit "$(sed -n '/^BEGIN-PROMPT/,/^END-PROMPT/p' scripts/ops/V120/AI_UPGRADE_PLAYBOOK.md)"
```

Keep `--sandbox read-only` if you only want the **findings report** (Phases 0–2, 5) with no file
writes; switch to `workspace-write` when you want it to generate the Safe batches and reports.

---

## 2. Copy‑paste AI prompt

Everything between the `BEGIN-PROMPT` / `END-PROMPT` markers is the prompt. Paste it into Codex.

```text
BEGIN-PROMPT
ROLE
You are a senior protocol/release engineer auditing and driving the Frax OFT v1.1.0 -> v1.2.0
upgrade in this repository (frax-oft-upgradeable, Foundry + LayerZero v2). You are meticulous,
security-first, and you prefer to be provably correct over fast. You never broadcast transactions,
never push git, never execute Safe transactions, and never read or use private keys. You only
produce artifacts (reports + Safe Transaction Builder JSON) and run read-only / fork simulations.

CONTEXT YOU MUST LOAD FIRST (read these before acting)
- scripts/ops/V120/UpgradeV120Base.s.sol  (deploy + simulate + validate + serialize)
- scripts/ops/V120/destinations/{UpgradeV120Destinations,UpgradeV120Destination,
  UpgradeV120DestinationsEVM,UpgradeV120DestinationsZK}.s.sol and destinations/README.md
- scripts/ops/V120/ethereum/UpgradeV120Ethereum.s.sol
- scripts/ops/V120/fraxtal/UpgradeV120Fraxtal.s.sol
- contracts/FraxOFTMintableAdapterUpgradeable.sol
- contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol
- contracts/modules/SupplyTrackingModule.sol
- contracts/modules/RateLimiterModule.sol
- contracts/FraxOFTUpgradeable.sol            (initializeV120 / version)
- scripts/L0Constants.sol                     (L0Config, `enum Token`, NUM_OFTS)
- config/ (per-chain L0Config: delegate = Safe, proxyAdmin, eid, RPC, endpoint)
Resolve ALL live addresses (proxies, proxyAdmin, Safe/delegate, endpoint, connectedOfts) from
config + on-chain reads at runtime. Do NOT hardcode addresses from memory or from older scripts.

PRIMARY QUESTION TO RESOLVE (do this explicitly and first)
We upgraded (or are about to upgrade) to v1.2.0 but we believe we NEVER executed the
`setInitialTotalSupply` batch (historically produced by an external script
`script/lzpeers/set-Initial-supply-msig.ts`). Determine, with on-chain and code evidence:
  (a) For which contracts does the v1.2.0 SupplyTrackingModule guard actually apply? (Which
      tokens/chains use FraxOFTMintableAdapterUpgradeable / ...TIP20 vs. escrow adapters vs. plain
      OFTs? Only the mintable adapters track supply.)
  (b) Is `initialTotalSupply[eid]` currently 0 on the live mintable adapters (frxUSD + sfrxUSD on
      Fraxtal and Ethereum, frxUSD TIP20 on Tempo 4217)? Read it on-chain for every active
      destination eid.
  (c) Given the guard `totalTransferFrom[eid] > initialTotalSupply[eid] + totalTransferTo[eid]`
      (skipped only if allowNegativeSupply[eid]), does an inbound transfer from a chain with
      pre-existing circulating supply revert when initialTotalSupply is unset? PROVE it on a fork
      (simulate a credit / lzReceive both WITHOUT and WITH initial supply set).
  (d) Is this a release blocker? State clearly whether inbound frxUSD/sfrxUSD bridging is (or would
      be) frozen and for which chains.
  (e) What is the safe remediation and ordering? Compare: (i) append setInitialTotalSupply to the
      SAME upgrade Safe batch, (ii) set allowNegativeSupply=true in the upgrade batch then reconcile
      later, (iii) execute a separate setInitialTotalSupply batch immediately after — quantify the
      freeze-window risk of each.
Note: the old TS script also handled FPI and used a stale snapshot. FPI is removed from V120
(NUM_OFTS = 5). Any regenerated batch must cover ONLY frxUSD + sfrxUSD mintable adapters (Fraxtal +
Ethereum) and frxUSD TIP20 (Tempo), at a FRESH snapshot block taken close to execution.

DELIVERABLE 1 — FINDINGS REPORT (write to scripts/ops/V120/reports/V120-findings.md)
Concise, evidence-backed. Include:
- Exact chain x token -> implementation-kind matrix (StandardOFT / TempoOFT / EscrowAdapter /
  MintableAdapter / Tip20Adapter) and which ones carry the supply guard and the rate limiter.
- Live on-chain state table: for each mintable adapter and each active destination eid ->
  initialTotalSupply, totalTransferTo, totalTransferFrom, allowNegativeSupply, version, owner (Safe),
  proxyAdmin, current implementation.
- The initial-supply verdict (a–e above) with the fork-simulation transcript proving revert-without /
  success-with.
- Any other gaps found (e.g. missing RATE_LIMIT_RUNBOOK.md, rate limits disabled by design,
  reinitializer(4) only wired for StandardOFT/TempoOFT, storage-layout/ERC-7201 namespacing check).
- A prioritized action list (blockers vs. nice-to-have) with the exact commands / Safe batches to run.

DELIVERABLE 2 — EXECUTE THE PLAYBOOK in scripts/ops/V120/AI_UPGRADE_PLAYBOOK.md §3
Follow every phase in order. For each phase produce the specified artifact. Stop and ask before any
step that would broadcast, verify on-chain, push, or execute a Safe transaction. Specifically you MUST
produce:
- Phase 1: a fork simulation log per chain (upgrade simulated as the Safe/delegate) with the
  UpgradeV120Base validation invariants all passing.
- Phase 2: a storage-layout compatibility check (confirm the new modules use ERC-7201 namespaced
  slots and do not collide with pre-1.2.0 layout) + reinitializer(4) analysis.
- Phase 4: exact, ready-to-run deploy + explorer-verify commands per chain (NOT executed).
- Phase 5: a regenerated setInitialTotalSupply Safe batch per hub adapter, plus the snapshot method,
  block numbers, and the arithmetic for each eid amount. Save JSON under
  scripts/ops/V120/reports/txs/ and show a decoded, human-readable preview.
- Phase 6: an explicit allowNegativeSupply recommendation (on/off, which eids, when to flip back).
- Phase 7: the AUDITOR REPORT (scripts/ops/V120/reports/V120-auditor-report.md) — per chain per token:
  proxy address, current impl (pre), new impl (post/target), proxyAdmin, Safe (delegate) address,
  the raw upgrade calldata, and the decoded action, plus the module/version diff summary. This is
  meant to be shared with auditors BEFORE the Safe executes the upgrade.
- Phase 8: the post-upgrade on-chain verification checklist as an executable script/checklist
  (version==1.2.0, owner/endpoint/token/symbol/approvalRequired unchanged, rateLimitGlobalConfig()
  present + disabled, initialTotalSupply seeded, a live inbound + outbound smoke test plan).

HARD RULES
- No broadcasting, no `--verify` against live explorers, no git push, no Safe execution without an
  explicit human "go". Simulations and JSON/report generation only.
- Never invent addresses/values — read them from config + chain. If an RPC is missing, list what you
  need and stop.
- Skip deprecated chains (use isDeprecatedChain) and skip FPI everywhere.
- Treat Tempo (4217) specially: EndpointV2Alt + FraxOFTUpgradeableTempo + frxUSD TIP20 adapter.
- If anything is ambiguous or a value looks unsafe, stop and ask rather than guess.

OUTPUT
Finish with a short executive summary: is the upgrade safe to hand to the Safe signers yet? List the
remaining blockers (initial supply being the prime suspect) and the exact next action for each.
END-PROMPT
```

---

## 3. In‑depth playbook

Phase‑by‑phase. Each phase names its **artifact**. This doubles as a human runbook.

### Phase 0 — Recon & scope freeze
- Enumerate active chains from `config/` (skip `isDeprecatedChain`, skip zkEVM/Mode/Berachain/Scroll,
  skip FPI). Confirm `NUM_OFTS == 5` and the `Token` order `WFRAX, SFRXUSD, SFRXETH, FRXUSD, FRXETH`.
- Build the **chain × token → implementation‑kind** matrix (StandardOFT / TempoOFT / EscrowAdapter /
  MintableAdapter / Tip20Adapter) directly from the `_deploy*Implementations()` logic in
  [UpgradeV120Base.s.sol](UpgradeV120Base.s.sol).
- **Artifact:** the matrix + the definitive list of contracts that carry (a) the supply‑tracking
  guard and (b) the rate limiter.

### Phase 1 — Simulate the upgrade (no broadcast)
- For each profile run the matching script as a **fork simulation** (no `--broadcast`):
  ```bash
  forge script scripts/ops/V120/destinations/UpgradeV120Destination.s.sol   --rpc-url "$RPC_URL"      # one standard destination
  forge script scripts/ops/V120/ethereum/UpgradeV120Ethereum.s.sol          --rpc-url "$ETH_RPC_URL"
  forge script scripts/ops/V120/fraxtal/UpgradeV120Fraxtal.s.sol            --rpc-url "$FRAXTAL_RPC_URL"
  ```
- The script deploys new impls, **pranks the Safe/delegate**, calls `ProxyAdmin.upgrade(AndCall)`,
  and runs `_validateUpgrade`. Confirm every invariant passes (token/symbol/endpoint/owner/
  approvalRequired unchanged, `version()=="1.2.0"`, `rateLimitGlobalConfig()` present, Tempo native
  token unchanged) and that a Safe JSON is written to the corresponding `txs/UpgradeV120-<chainid>.json`.
- **Artifact:** per‑chain simulation log + the generated Safe batch files.

### Phase 2 — "Nothing goes wrong" safety gate
- **Storage layout:** confirm the new state lives in **ERC‑7201 namespaced storage**
  (`frax.storage.SupplyTrackingModule`, `frax.storage.RateLimiterModule`) so it cannot collide with
  the pre‑1.2.0 layout. Optionally diff `forge inspect <impl> storageLayout` old vs. new.
- **Reinitializer:** verify `initializeV120()` is `reinitializer(4)` and is only invoked (via
  `upgradeAndCall`) for `StandardOFT`/`TempoOFT`; adapters use plain `upgrade`. Confirm no
  double‑init / already‑initialized reverts on the live proxies.
- **Immutables:** each adapter binds `token`/`nativeToken` as immutables — confirm the new impl's
  immutables match the live underlying token per chain.
- **Artifact:** storage/reinit/immutable compatibility note (pass/fail per chain).

### Phase 3 — Peers / config unchanged
- Confirm the upgrade does **not** alter peers, DVNs, or LayerZero libraries. Spot‑check `peers`,
  `owner`, `delegate`, and `endpoint` before/after in the fork.
- **Artifact:** a short "no config drift" confirmation.

### Phase 4 — Deploy & verify implementations
- Deploy **only** the new implementations (broadcast) with either a funded `PK_CONFIG_DEPLOYER` or the Google Cloud signer:
  ```bash
  forge script scripts/ops/V120/<profile>.s.sol --rpc-url "$RPC" --broadcast   # + --verify where supported
  forge script scripts/ops/V120/<profile>.s.sol --rpc-url "$RPC" --gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc --broadcast
  ```
- Explorer verify: standard EVM via `--verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY`;
  **Tempo** via `scripts/verify-tempo-contracts.ts`. Record each new implementation address.
- The proxy upgrade itself is **not** broadcast here — it's the Safe batch from Phase 1.
- **Artifact:** table of new implementation addresses + verification status per chain/token.

### Phase 5 — Initial supply (the pending step) ⛔ blocker
- **Applies only to** the mintable adapters: `frxUSD` + `sfrxUSD` on **Fraxtal** and **Ethereum**,
  and `frxUSD` (TIP20) on **Tempo**. Escrow adapters and destination OFTs need nothing.
- **Topology precondition (the reason per‑eid seeding is valid).** The guard assumes a strict
  **hub‑and‑spoke star with Fraxtal (252) as hub** — spokes bridge only to/from Fraxtal. This is
  enforced on‑chain by `scripts/ops/RemovePeers/RemovePeers.s.sol` ("if the peer is not fraxtal,
  remove it"), and the module's own dev note says the accounting is only trustworthy for
  hub‑connected chains. **Verify the star is actually live before seeding:** for every spoke,
  `peers(eid) == 0` for all non‑Fraxtal eids. If any spoke↔spoke or spoke↔Ethereum peer remains,
  direct flows can make the per‑eid guard false‑revert — seed conservatively or use `allowNegative`
  for those eids.
- Take a **fresh** circulating‑supply snapshot per destination eid (do not reuse the stale TS output;
  and exclude FPI). For each hub adapter and each active destination `eid` compute the baseline
  `initialTotalSupply[eid]` = that destination's circulating supply at the snapshot block, i.e. read
  the spoke's `totalSupply()` (under the star this equals Fraxtal's net outflow to that spoke — use
  it as a cross‑check). You cannot derive it from Fraxtal's new ledger (it starts at zero on upgrade).
- **Seed every one of Fraxtal's peers**, including the **Ethereum eid and Tempo eid** (they hold
  frxUSD/sfrxUSD too), not just the small spokes.
- **Hub‑facing direction (Ethereum/Tempo adapters):** their guard faces Fraxtal, so a numeric seed
  would be ≈ the entire rest‑of‑mesh supply (large + drifting). Prefer
  `setAllowNegativeSupply(fraxtalEid, true)` there instead of a numeric `setInitialTotalSupply`. This
  is likely why the historical script only generated `setInitialTotalSupply` for Fraxtal.
- The V120 hub upgrade scripts seed **atomically in the same Safe batch**. A reviewed snapshot file at
  `scripts/ops/V120/supply/<chainid>.json` (schema in `supply/example.json`) is treated as the source
  of truth and appended after the upgrade txs. If no reviewed file exists, the script auto-generates
  EVM-readable seeds from fresh peer-chain forks, writes an audit artifact to
  `scripts/ops/V120/supply/generated/<chainid>.json`, and appends those calls in-memory. Fraxtal gets
  numeric `setInitialTotalSupply` values from peer `totalSupply()` reads; Ethereum and Tempo get
  hub-facing `setAllowNegativeSupply(fraxtalEid, true)` txs. Non-EVM supply that cannot be read by
  Foundry still requires a reviewed manual JSON.
- **Batching model (how it must be executed):**
  - **Across chains:** there is **no single cross‑chain batch** — Safe batches are per‑`chainId`,
    each executed by that chain's Safe. No cross‑chain ordering is required either: the guard is
    hub‑side and keyed by destination `eid`, so it depends only on the hub's own seeded values, not
    on whether the destination chain has been upgraded. Roll out chain‑by‑chain.
  - **Within each supply‑tracked chain (Fraxtal, Ethereum, Tempo): make the upgrade + seeding ONE
    atomic Safe MultiSend batch,** ordered: `ProxyAdmin.upgrade(proxy→v1.2.0)` → then
    `setInitialTotalSupply(eid, amount)` for every active destination `eid` (repeat per mintable
    token). The setters resolve against the new impl because MultiSend runs calls sequentially in a
    single tx; batching removes the freeze window where the guard is live but storage is zero.
    Confirm the ProxyAdmin and the adapter share the same Safe owner so both fit in one batch.
  - **Destination chains: upgrade only — no `setInitialTotalSupply`** (no guard).
  - If snapshot↔execution drift is a concern, batch `upgrade + setAllowNegativeSupply(eid,true)` as a
    transition instead, then seed exact values and flip `allowNegative` back to `false` (Phase 6).
- **Artifact:** `reports/txs/V120-setInitialTotalSupply-<chain>-<token>.json` + the per‑eid arithmetic,
  snapshot block, and a decoded preview.

### Phase 6 — allowNegativeSupply decision
- `setAllowNegativeSupply(eid, true)` is the transitional safety valve that bypasses the guard.
  Decide explicitly: enable it (which eids, set in the upgrade batch) to eliminate the freeze window,
  then flip back to `false` after initial supply is reconciled — **or** rely solely on seeding.
- **Artifact:** a written recommendation (on/off, scope, and the flip‑back plan/batch if used).

### Phase 7 — Auditor report (share BEFORE Safe execution)
- Produce `reports/V120-auditor-report.md`. For **each chain × token**:
  proxy address · current (pre) implementation · new (target) implementation · proxyAdmin · Safe
  (delegate) address · raw upgrade calldata · decoded action · reinitializer/version bump.
- Add a summary of what v1.2.0 changes: new `RateLimiterModule` + `SupplyTrackingModule` (ERC‑7201),
  EIP‑712 domain bump to `1.2.0`, rate limits shipped **disabled**, and the initial‑supply
  prerequisite. Link the Phase 1 Safe JSON and Phase 4 impl addresses.
- **Artifact:** the auditor report (source these values from `broadcast/**/run-latest.json` and the
  `txs/UpgradeV120-<chainid>.json` files, cross‑checked against on‑chain reads).

### Phase 8 — Post‑upgrade on‑chain checks
After the Safe executes the upgrade:
- `version() == "1.2.0"` on every proxy; `owner`, `endpoint`, `token`, `symbol`, `approvalRequired`
  unchanged; `proxyAdmin` unchanged.
- `rateLimitGlobalConfig()` responds and rate limiting is **disabled** as intended.
- On each mintable adapter: `initialTotalSupply[eid]` matches the seeded values for every active eid;
  `allowNegativeSupply[eid]` is in the intended state.
- **Live smoke test:** a small outbound and a small inbound `frxUSD`/`sfrxUSD` transfer to/from a hub,
  confirming the guard passes with supply seeded (and reproducing the revert on a fork if unseeded).
- **Artifact:** a pass/fail post‑upgrade checklist + the smoke‑test tx hashes.

### Phase 9 — Rate limits (later, separate op)
- Rate limits remain disabled by design. Enabling them is a distinct change gated by the
  (currently missing) `RATE_LIMIT_RUNBOOK.md`. Track as follow‑up, not part of this upgrade.

---

## 4. Grounding facts & preliminary findings

These are established from the current code on branch `feature/oft-rate-limits`. The agent must
re‑verify against live chains, but should treat these as the expected shape.

**Where supply tracking actually lives (scope):**

| Chain | WFRAX | sfrxUSD | sfrxETH | frxUSD | frxETH |
|---|---|---|---|---|---|
| Fraxtal (252) | Escrow adapter | **Mintable (guard)** | Escrow adapter | **Mintable (guard)** | Escrow adapter |
| Ethereum (1) | Standard OFT | **Mintable (guard)** | Escrow adapter | **Mintable (guard)** | Escrow adapter |
| Tempo (4217) | Tempo OFT | Tempo OFT | Tempo OFT | **TIP20 mintable (guard)** | Tempo OFT |
| Other EVM destinations | Standard OFT | Standard OFT | Standard OFT | Standard OFT | Standard OFT |

Only the **bold** cells inherit `SupplyTrackingModule` and enforce the initial‑supply guard. Every
contract inherits `RateLimiterModule` (shipped disabled).

**The guard (from `contracts/modules/SupplyTrackingModule.sol`):**
```
_addToTotalTransferFrom(eid, amount):   // called in _credit (inbound / lzReceive)
  if (!allowNegativeSupply[eid] &&
      totalTransferFrom[eid] > initialTotalSupply[eid] + totalTransferTo[eid])
      revert TotalTransferFromExceedsInitialTotalSupply(...)
```
Post‑upgrade the namespaced storage is fresh → `initialTotalSupply`, `totalTransferTo`,
`totalTransferFrom` all start at **0**. So the first inbound from any chain with pre‑existing
circulating supply reverts unless `setInitialTotalSupply(eid, …)` was seeded or
`setAllowNegativeSupply(eid, true)` is set. **This is the pending step and the prime release blocker.**

**Admin entry points (owner = the chain's Safe/delegate):**
- `setInitialTotalSupply(uint32 eid, uint256 amount)` — seed baseline (added v1.1.0).
- `setAllowNegativeSupply(uint32 eid, bool allow)` — transitional bypass (added v1.2.0).
- `setRateLimit*` / `checkpointRateLimits` — rate limiter (kept disabled).

**What the V120 scripts do / don't do:**
- ✅ Deploy new impls (broadcast), simulate the proxy upgrade as the Safe/delegate, validate, and
  emit Safe Tx Builder JSON to `txs/UpgradeV120-<chainid>.json`.
- ✅ Append `setInitialTotalSupply` / `setAllowNegativeSupply` txs atomically when supply seeds are
  needed. A reviewed `scripts/ops/V120/supply/<chainid>.json` file takes precedence; otherwise the
  script auto-generates EVM-readable seeds from fresh peer-chain forks and writes
  `scripts/ops/V120/supply/generated/<chainid>.json` as the audit artifact.
- ❌ Do **not** generate rate-limit txs. Those are separate artifacts (Phase 9).
- The old `set-Initial-supply-msig.ts` reference is **stale**: it includes FPI (removed in V120) and
  a snapshot from an earlier time. Regenerate for the 5‑token mesh's mintable adapters only, at a
  fresh block.

**Known gaps:** `destinations/README.md` links `../RATE_LIMIT_RUNBOOK.md`, which does not exist yet.

**Key source references:**
- [UpgradeV120Base.s.sol](UpgradeV120Base.s.sol) · [destinations/README.md](destinations/README.md)
- [contracts/modules/SupplyTrackingModule.sol](../../../contracts/modules/SupplyTrackingModule.sol)
- [contracts/FraxOFTMintableAdapterUpgradeable.sol](../../../contracts/FraxOFTMintableAdapterUpgradeable.sol)
- [contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol](../../../contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol)
- [contracts/modules/RateLimiterModule.sol](../../../contracts/modules/RateLimiterModule.sol)
- [scripts/L0Constants.sol](../../L0Constants.sol)
