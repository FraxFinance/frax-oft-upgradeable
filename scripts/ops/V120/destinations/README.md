# v1.2.0 upgrade scripts

The V120 scripts deploy rate-limited implementations, simulate each proxy upgrade as the actual ProxyAdmin owner, validate the upgraded state, and write Safe Transaction Builder JSON.

## Chain profiles

- Standard destinations use the WFRAX, sfrxUSD, generic OFT, frxUSD, and generic OFT implementations in the five-token active order.
- Tempo (`4217`) retains `FraxOFTUpgradeableTempo` for all four native OFTs and `FraxOFTMintableAdapterUpgradeableTIP20` for frxUSD.
- Ethereum (`1`) and Fraxtal (`252`) have dedicated scripts because their adapter implementations bind the underlying token as an immutable constructor argument.
- Retired and always skipped: Polygon zkEVM (`1101`), Mode (`34443`), Berachain (`80094`), Scroll (`534352`), Botanix (`3637`), and the non-EVM pair Movement / Aptos. Solana is the only active non-EVM chain.
- Blast (`81457`) is skipped as legacy-mesh only: it appears in both the Legacy and Proxy sections of `L0Config`, but its proxy OFTs peer outward to active chains without any of them peering back, so the wiring is one-way and stale. The legacy mesh is not in scope for v1.2.0.
- FPI is not part of V120. The scripts upgrade exactly the `activeTokens` registry in `L0Constants`; peer arrays stay `NUM_OFTS` wide and `Token`-indexed, so chains that still hold an FPI proxy keep it untouched and post-retirement chains (Robinhood onward), whose FPI slot is `address(0)`, upgrade cleanly.

## Commands

All runs need `--ffi` (the Safe batch writer shells out to post-process its JSON). Broadcast **one chain per run** with `--rpc-url` set to that chain, and always pass `--sender` as the broadcasting address (the GCS signer's `0x54f9…`, or the address behind `PK_CONFIG_DEPLOYER`): forge pre-deploys the linked libraries from `--sender` on the `--rpc-url` fork, and the implementation addresses are computed from the nonces that leaves behind. `--slow` is cheap insurance on public RPCs.

```bash
SIGN="--gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc --broadcast --slow --ffi"

# One non-Tempo destination selected by the RPC chain ID
forge script scripts/ops/V120/destinations/UpgradeV120Destination.s.sol --rpc-url "$RPC_URL" $SIGN

# Tempo destination only
forge script scripts/ops/V120/destinations/UpgradeV120DestinationsTempo.s.sol --rpc-url "$TEMPO_RPC_URL" $SIGN

# ZK-stack destination (requires foundryup-zksync; the batch prints to console)
forge script scripts/ops/V120/destinations/UpgradeV120DestinationsZK.s.sol --rpc-url "$RPC_URL" $SIGN --zksync

# Ethereum lockboxes/OFT — needs a modern EVM spec; the live sfrxUSD token and the
# ProxyAdmin's timelock use opcodes newer than forge's default simulation spec.
forge script scripts/ops/V120/ethereum/UpgradeV120Ethereum.s.sol --rpc-url "$ETH_RPC_URL" $SIGN --evm-version osaka

# Fraxtal lockboxes — do NOT pass --evm-version osaka here; op-revm then expects Isthmus
# L1Block fields Fraxtal does not have and forge panics.
forge script scripts/ops/V120/fraxtal/UpgradeV120Fraxtal.s.sol --rpc-url "$FRAXTAL_RPC_URL" $SIGN
```

`UpgradeV120DestinationsEVM.s.sol` sweeps every active non-ZK destination in one process and is for **simulation only** (`--rpc-url` any chain, no `--broadcast`): the library pre-deploy exists on the `--rpc-url` fork alone, so a broadcast from the sweep would mis-nonce every other chain. Somnia and HyperEVM are skipped in the sweep with a log line because they cannot be fork-simulated.

Broadcasting deploys only the libraries and implementations. Proxy upgrades and ledger writes are simulated and emitted under the corresponding `txs/` directory for Safe review and signing.

## Deploy now, sign later

Implementations are deployed and verified first, go to audit, and are upgraded to only once the audit clears — so the batches must be regenerable weeks after the deployment against exactly the addresses that were audited. The broadcast that deploys a chain's implementations writes `scripts/ops/V120/implementations/<chainid>.json` (commit it). From then on:

- A run **without** `--broadcast` binds its batches to the pinned addresses instead of the addresses it just simulated, after checking each pinned implementation carries exactly the runtime code the current build produces (immutables, linked libraries and metadata included). A pin that does not match this commit — or has no code — refuses. Regenerate the batches on signing day this way: Ethereum gets a fresh timelock `eta`, the hubs get fresh ledger reads and `V120 WINDOW:` lines.
- A run **with** `--broadcast` refuses while the pin exists. To redeploy after an audit finding: fix, delete the pin, broadcast, verify, commit the new pin. Libraries already on-chain are detected by forge and not redeployed.
- If a broadcast fails part-way, `forge script … --resume` finishes sending the recorded transactions; the pin written by that run is still correct because the nonces have not changed. Delete the pin only if you abandon the run.

## Externally linked libraries

The v1.2.0 implementations link `contracts/libraries/*.sol` (rate limiter, EIP-3009, permit, EIP-712, freeze/thaw, pause, Tempo fee routing) to stay under the EIP-170 code size limit. `forge script --broadcast` deploys them via CREATE2 (salt 0 through the canonical `0x4e59…` factory, so the addresses are the same on every chain) in the same run and links automatically, so no extra step is needed — but **explorer verification requires the `--libraries` mapping**. Use `scripts/ops/V120/verify-v120-implementations.sh <broadcast run-latest.json>` (or `--all`), which reads the linked library addresses out of the broadcast file's `libraries` list (present even when forge found them already deployed) and routes each chain to the right verifier.

`FrxUSDOFTUpgradeable` sits ~227 bytes under the limit — re-check its size on any change to it or its modules.

## Batch ordering and executors

Supply-tracked chains emit **ordered step files** rather than one batch, because the ProxyAdmin owner is not the config `delegate` on the hubs:

1. `upgrade` — direct `ProxyAdmin.upgrade*` by its owner Safe; on Ethereum the owner is a Compound-style timelock, so this becomes a `queue` step and, after the delay, an `execute` step signed by the timelock's admin Safe (`eta` defaults to now + delay + 3 days, override with `V120_TIMELOCK_ETA`). `queueTransaction` requires `eta >= block.timestamp + delay` **at queue time**, so the queue step must execute within ~3 days of generating the batch — regenerate if signing slips.
2. `supply-ledger` — `setInitialTotalSupply` and `setAllowNegativeSupply`, executed by the OFT owner **after** the upgrade; folded into the execute step when the same Safe owns both.

**The ledger writes must follow the upgrade.** v1.1.0's `setInitialTotalSupply` also zeroes `totalTransferFrom` and `totalTransferTo`; v1.2.0's writes only the baseline. The seed values are computed assuming the counters persist (`transferFrom - transferTo + peerSupply`, so headroom equals the peer's circulating supply), and applying them to v1.1.0 would wipe the ledger and leave the guard looser by the whole accumulated deficit. Where the OFT owner is also the upgrade executor (all destinations, Tempo) the writes sit in the same Safe batch directly after the upgrade, so there is no window. Where the two Safes differ, any eid already in deficit rejects inbound messages between the upgrade step and the ledger step; those messages stay retryable at the endpoint and clear once the ledger step lands. Execute the steps back to back. Today that is Fraxtal (Base 30184 and Katana 30375 on frxUSD, executed by the delegate after the ProxyAdmin Safe's upgrade step) and Ethereum (sfrxUSD eid 30255, executed by the delegate after the timelock's execute step; frxUSD is owned by the timelock's admin Safe so its writes fold into the execute step with no window). The scripts recompute this from the live ledger on every run and print a `V120 WINDOW:` line per affected eid — treat that output as the authoritative list.

Steps must execute in ascending order; the script prints the file → executor → order summary. Chains where one executor owns everything still emit the single `UpgradeV120-<chainid>.json`.

A reviewed `scripts/ops/V120/supply/<chainid>.json` is the source of truth and skips peer-forking entirely; otherwise the script auto-generates seeds from fresh peer reads and writes `supply/generated/<chainid>.json`. **The auto-generator cannot see Somnia (its RPCs reject the EIP-1898 queries forge's fork backend needs) or Solana** — add those rows by hand. Run `scripts/ops/V120/supply/SeedSupplyLedger.s.sol` to generate them; it diffs against live chain state and emits nothing where the chain already satisfies the guard.

## Per-chain quirks

- **Aurora (1313161554)** — no EIP-1559; append `--legacy`.
- **HyperEVM (999)** — enable big blocks for the deployer before broadcasting, or the implementation deploys run out of gas; also pass `--disable-block-gas-limit`, because forge caps the simulation at the 3M gas limit of whichever small block is `latest`. The toggle is a Hyperliquid L1 `evmUserModify` action; it can be signed with the GCS key through `cast wallet sign --gcp --data` (EIP-712 `Agent` over the msgpack action hash, domain `Exchange`/`1`/chainId 1337).
- **Somnia (5031)** — cannot be fork-simulated at all. Deploy the libraries through the `0x4e59…` CREATE2 factory with `cast send --gcp` (salt 0, same addresses as everywhere else), the implementations with `forge create --gcp --libraries …`, write `implementations/5031.json` by hand and hand-build the Safe batch. Contract code is priced ~17× Ethereum: budget ~3 SOMI for the four implementations. The explorer's Etherscan-style API rejects forge's POST; verify through Blockscout's v2 `verification/via/standard-input` endpoint (strip `settings.libraries` from the standard JSON for the libraries themselves to get a full match).
- **Tempo (4217)** — LayerZero fees are paid in `LZEndpointDollar` and overpaid fees are refunded in it rather than the TIP-20 collected; see "Tempo gas payment and fee refunds" in the root README before configuring any caller. The node caps a transaction at 30M gas; pass `--gas-estimate-multiplier 115` or the Tempo OFT deploy (~24.3M) is rejected at forge's default 1.3×.
- **OP-stack chains** — third-party RPCs may return a 1 wei priority-fee hint the sequencer silently drops; broadcast through the official RPC or pass `--priority-gas-price 1000000 --with-gas-price 3000000`.
- **Ink / Plume** — Blockscout's public API throttles bursts; the verifier falls back to Sourcify automatically.
- **Zero-balance Safes** — every impersonated owner is funded in simulation before it is pranked (`_impersonate`); the fork rejects a call from a zero-balance caller with no reason, which WorldChain's ProxyAdmin owner triggers.
- **WorldChain (480)** — public RPCs rate-limit forge's fork traffic; `L0Config` uses the Tenderly gateway, and chainlist.org lists alternates if it throttles.
- **zkSync Era / Abstract** — require `foundryup-zksync`, which refuses to auto-deploy unlinked libraries in script mode and whose `--zksync` execution breaks the Safe batch writer. Deploy each library with `forge create --zksync --gcp`, then each implementation with `forge create --zksync --gcp --libraries …`, write the pin by hand and hand-build the batch on signing day. Verification: the zk explorers reject `settings.remappings`, so apply the remappings to the imports and drop the setting before submitting; the on-chain metadata records the zkVM solc fork (`llvm:1.0.1`), which the Etherscan instances cannot be told to use.

Rate limits intentionally remain disabled after the implementation upgrade; enabling them is a separate operation.
