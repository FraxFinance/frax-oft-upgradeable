# Set Legacy OFT Libraries

Generates per-OFT Safe batch JSON for explicit `setSendLibrary` and `setReceiveLibrary` calls on legacy OFTs.

Default run:

```bash
forge script scripts/ops/fix/SetLegacyOFTLibs/SetLegacyOFTLibs.s.sol --rpc-url https://rpc.frax.com --ffi
```

Useful filters:

```bash
SOURCE_CHAIN_ID=8453 DST_CHAIN_ID=1 \
  forge script scripts/ops/fix/SetLegacyOFTLibs/SetLegacyOFTLibs.s.sol --rpc-url https://mainnet.base.org --ffi
```

```bash
LEGACY_OFTS=0x909DBdE1eBE906Af95660033e478D59EFe831fED,0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E \
  forge script scripts/ops/fix/SetLegacyOFTLibs/SetLegacyOFTLibs.s.sol --rpc-url https://rpc.frax.com --ffi
```

`LEGACY_OFT_MASK` selects from `ethLockboxesLegacy` when `LEGACY_OFTS` is unset. Bit `0` is `ethFraxLockboxLegacy`, bit `1` is `ethSFraxLockboxLegacy`, bit `2` is `ethSFrxEthLockboxLegacy`, bit `3` is `ethFrxUsdLockboxLegacy`, bit `4` is `ethFrxEthLockboxLegacy`, and bit `5` is `ethFpiLockboxLegacy`.

Generated JSON lands in `scripts/ops/fix/SetLegacyOFTLibs/txs/`. Each output file contains calls for one OFT on one source chain.
