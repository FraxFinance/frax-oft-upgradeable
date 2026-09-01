# v1.2.0 upgrade scripts

The V120 scripts deploy rate-limited implementations, simulate each proxy upgrade as the configured Safe, validate the upgraded state, and write Safe Transaction Builder JSON.

## Chain profiles

- Standard destinations use the WFRAX, sfrxUSD, generic OFT, frxUSD, and generic OFT implementations in the five-token active order.
- Tempo (`4217`) retains `FraxOFTUpgradeableTempo` for all four native OFTs and `FraxOFTMintableAdapterUpgradeableTIP20` for frxUSD.
- Ethereum (`1`) and Fraxtal (`252`) have dedicated scripts because their adapter implementations bind the underlying token as an immutable constructor argument.
- Polygon zkEVM (`1101`), Mode (`34443`), Berachain (`80094`), and Scroll (`534352`) are retired and are always skipped.
- FPI is not part of V120.

## Commands

```bash
# One non-Tempo destination selected by the RPC chain ID
forge script scripts/ops/V120/destinations/UpgradeV120Destination.s.sol \
  --rpc-url "$RPC_URL" --broadcast

# Tempo destination only
forge script scripts/ops/V120/destinations/UpgradeV120DestinationsTempo.s.sol \
  --rpc-url "$TEMPO_RPC_URL" --broadcast

# All active non-ZK destinations (excludes Ethereum, Fraxtal, Tempo)
forge script scripts/ops/V120/destinations/UpgradeV120DestinationsEVM.s.sol \
  --rpc-url "$RPC_URL" --broadcast

# All active ZK-stack destinations
forge script scripts/ops/V120/destinations/UpgradeV120DestinationsZK.s.sol \
  --rpc-url "$RPC_URL" --broadcast

# Ethereum lockboxes/OFT
forge script scripts/ops/V120/ethereum/UpgradeV120Ethereum.s.sol \
  --rpc-url "$ETH_RPC_URL" --broadcast

# Fraxtal lockboxes
forge script scripts/ops/V120/fraxtal/UpgradeV120Fraxtal.s.sol \
  --rpc-url "$FRAXTAL_RPC_URL" --broadcast
```

Implementation deployment can broadcast either from a funded `PK_CONFIG_DEPLOYER`, or from the Google Cloud signer with Foundry's `--gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc` flow. Broadcasting deploys only the new implementations. Proxy upgrades are simulated and emitted under the corresponding `txs/` directory for Safe review and signing.

If the target chain has supply-tracked mintable adapters, the script also appends the required supply-guard txs after the upgrade txs. A reviewed `scripts/ops/V120/supply/<chainid>.json` file takes precedence; otherwise the script auto-generates EVM-readable seeds from fresh peer-chain forks and writes the snapshot artifact to `scripts/ops/V120/supply/generated/<chainid>.json`. Fraxtal receives numeric `setInitialTotalSupply` seeds from peer `totalSupply()` reads; Ethereum and Tempo receive hub-facing `setAllowNegativeSupply(fraxtalEid, true)` calls.

Rate limits intentionally remain disabled after the implementation upgrade. Read [RATE_LIMIT_RUNBOOK.md](../RATE_LIMIT_RUNBOOK.md) before enabling them.
