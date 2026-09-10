# v1.2.0 upgrade scripts

The V120 scripts deploy rate-limited implementations, simulate each proxy upgrade as the actual ProxyAdmin owner, validate the upgraded state, and write Safe Transaction Builder JSON.

## Chain profiles

- Standard destinations use the WFRAX, sfrxUSD, generic OFT, frxUSD, and generic OFT implementations in the five-token active order.
- Tempo (`4217`) retains `FraxOFTUpgradeableTempo` for all four native OFTs and `FraxOFTMintableAdapterUpgradeableTIP20` for frxUSD.
- Ethereum (`1`) and Fraxtal (`252`) have dedicated scripts because their adapter implementations bind the underlying token as an immutable constructor argument.
- Retired and always skipped: Polygon zkEVM (`1101`), Mode (`34443`), Berachain (`80094`), Scroll (`534352`), Botanix (`3637`), and the non-EVM pair Movement / Aptos. Solana is the only active non-EVM chain.
- Blast (`81457`) is skipped as legacy-mesh only: it appears in both the Legacy and Proxy sections of `L0Config`, but its proxy OFTs peer outward to active chains without any of them peering back, so the wiring is one-way and stale. The legacy mesh is not in scope for v1.2.0.
- FPI is not part of V120.

## Commands

All runs need `--ffi` (the Safe batch writer shells out to post-process its JSON).

```bash
# One non-Tempo destination selected by the RPC chain ID
forge script scripts/ops/V120/destinations/UpgradeV120Destination.s.sol \
  --rpc-url "$RPC_URL" --broadcast --ffi

# Tempo destination only
forge script scripts/ops/V120/destinations/UpgradeV120DestinationsTempo.s.sol \
  --rpc-url "$TEMPO_RPC_URL" --broadcast --ffi

# All active non-ZK destinations (excludes Ethereum, Fraxtal, Tempo)
forge script scripts/ops/V120/destinations/UpgradeV120DestinationsEVM.s.sol \
  --rpc-url "$RPC_URL" --broadcast --ffi

# All active ZK-stack destinations (requires foundryup-zksync)
forge script scripts/ops/V120/destinations/UpgradeV120DestinationsZK.s.sol \
  --rpc-url "$RPC_URL" --broadcast --ffi --zksync

# Ethereum lockboxes/OFT — needs a modern EVM spec; the live sfrxUSD token and the
# ProxyAdmin's timelock use opcodes newer than forge's default simulation spec.
forge script scripts/ops/V120/ethereum/UpgradeV120Ethereum.s.sol \
  --rpc-url "$ETH_RPC_URL" --broadcast --ffi --evm-version osaka

# Fraxtal lockboxes — do NOT pass --evm-version osaka here; op-revm then expects Isthmus
# L1Block fields Fraxtal does not have and forge panics.
forge script scripts/ops/V120/fraxtal/UpgradeV120Fraxtal.s.sol \
  --rpc-url "$FRAXTAL_RPC_URL" --broadcast --ffi
```

Implementation deployment can broadcast either from a funded `PK_CONFIG_DEPLOYER`, or from the Google Cloud signer with Foundry's `--gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc` flow. Broadcasting deploys only the new implementations. Proxy upgrades are simulated and emitted under the corresponding `txs/` directory for Safe review and signing.

## Externally linked libraries

The v1.2.0 implementations link `contracts/libraries/*.sol` (rate limiter, EIP-3009, permit, EIP-712, freeze/thaw, pause, Tempo fee routing) to stay under the EIP-170 code size limit. `forge script --broadcast` deploys them via CREATE2 in the same run and links automatically, so no extra step is needed — but **explorer verification requires the `--libraries` mapping**. Use `scripts/ops/V120/verify-v120-implementations.sh <broadcast run-latest.json>` (or `--all`), which reads the library addresses out of the broadcast file and routes each chain to the right verifier.

`FrxUSDOFTUpgradeable` sits ~227 bytes under the limit — re-check its size on any change to it or its modules.

## Batch ordering and executors

Supply-tracked chains emit **ordered step files** rather than one batch, because the ProxyAdmin owner is not the config `delegate` on the hubs:

1. `seed` — numeric `setInitialTotalSupply`, executed by each OFT's owner **before** the upgrade. The v1.1.0 lockboxes already expose the setter and the namespaced storage survives the upgrade, so seeding first removes the guard's freeze window.
2. `upgrade` — direct `ProxyAdmin.upgrade*` by its owner Safe; on Ethereum the owner is a Compound-style timelock, so this becomes a `queue` step and, after the delay, an `execute` step signed by the timelock's admin Safe (`eta` defaults to now + delay + 3 days, override with `V120_TIMELOCK_ETA`).
3. `allow-negative` — `setAllowNegativeSupply` (v1.2.0-only), executed by the OFT owner after the upgrade; folded into the execute step when the same Safe owns both.

Steps must execute in ascending order; the script prints the file → executor → order summary. Chains where one executor owns everything (all destinations, Tempo) still emit the single `UpgradeV120-<chainid>.json`.

A reviewed `scripts/ops/V120/supply/<chainid>.json` is the source of truth and skips peer-forking entirely; otherwise the script auto-generates seeds from fresh peer reads and writes `supply/generated/<chainid>.json`. **The auto-generator cannot see Somnia (its RPCs reject the EIP-1898 queries forge's fork backend needs) or Solana** — add those rows by hand. Run `scripts/ops/V120/supply/SeedSupplyLedger.s.sol` to generate them; it diffs against live chain state and emits nothing where the chain already satisfies the guard.

## Per-chain quirks

- **Aurora (1313161554)** — no EIP-1559; append `--legacy`.
- **HyperEVM (999)** — enable big blocks for the deployer before broadcasting, or the implementation deploys run out of gas.
- **Somnia (5031)** — cannot be fork-simulated at all; deploy with `forge create` and hand-build the Safe batch.
- **WorldChain (480)** — public RPCs rate-limit forge's fork traffic; `L0Config` uses the Tenderly gateway, and chainlist.org lists alternates if it throttles.
- **zkSync Era / Abstract** — require `foundryup-zksync`; under `--zksync` the batch writer prints the JSON to console instead of writing it.

Rate limits intentionally remain disabled after the implementation upgrade; enabling them is a separate operation.
