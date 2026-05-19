## Build for Aptos

* [ ] `pnpm run lz:sdk:move:build --oapp-config scripts/DeployFraxOFTProtocol/fpi-aptos-move.layerzero.config.ts --named-addresses oft=$APTOS_ACCOUNT_ADDRESS,oft_admin=$APTOS_ACCOUNT_ADDRESS --force-build true`

* [ ] `pnpm run lz:sdk:move:build --oapp-config scripts/DeployFraxOFTProtocol/fxs-aptos-move.layerzero.config.ts --named-addresses oft=$APTOS_ACCOUNT_ADDRESS,oft_admin=$APTOS_ACCOUNT_ADDRESS --force-build true`

* [ ] `pnpm run lz:sdk:move:build --oapp-config scripts/DeployFraxOFTProtocol/frxeth-aptos-move.layerzero.config.ts --named-addresses oft=$APTOS_ACCOUNT_ADDRESS,oft_admin=$APTOS_ACCOUNT_ADDRESS --force-build true`

* [ ] `pnpm run lz:sdk:move:build --oapp-config scripts/DeployFraxOFTProtocol/frxusd-aptos-move.layerzero.config.ts --named-addresses oft=$APTOS_ACCOUNT_ADDRESS,oft_admin=$APTOS_ACCOUNT_ADDRESS --force-build true`

* [ ] `pnpm run lz:sdk:move:build --oapp-config scripts/DeployFraxOFTProtocol/sfrxusd-aptos-move.layerzero.config.ts --named-addresses oft=$APTOS_ACCOUNT_ADDRESS,oft_admin=$APTOS_ACCOUNT_ADDRESS --force-build true`

* [ ] `pnpm run lz:sdk:move:build --oapp-config scripts/DeployFraxOFTProtocol/sfrxeth-aptos-move.layerzero.config.ts --named-addresses oft=$APTOS_ACCOUNT_ADDRESS,oft_admin=$APTOS_ACCOUNT_ADDRESS --force-build true`

## Wire Movement Move

Movement is a MoveVM chain, not Movement EVM. Use an Aptos-style Movement fullnode and GraphQL indexer.

The repo-local `.aptos/config.yaml` can hold the Movement `rest_url`, account, and key material, but the LayerZero Move SDK `wire` path still reads Movement RPCs from environment variables:

```bash
export MOVEMENT_FULLNODE_URL=https://rpc.ankr.com/http/movement_mainnet/v1
export MOVEMENT_INDEXER_URL=https://indexer.mainnet.movementnetwork.xyz/v1/graphql
```

`MOVEMENT_FULLNODE_URL` may also be set to the official fullnode:

```bash
export MOVEMENT_FULLNODE_URL=https://mainnet.movementnetwork.xyz/v1
```

Prefer a URL containing `movement` in the host or path. The SDK identifies Movement by checking whether the fullnode URL contains `movement`; otherwise it may treat the connection as Aptos.

Example wire command:

```bash
MOVEMENT_FULLNODE_URL=https://rpc.ankr.com/http/movement_mainnet/v1 \
MOVEMENT_INDEXER_URL=https://indexer.mainnet.movementnetwork.xyz/v1/graphql \
pnpm run lz:sdk:move:wire --oapp-config ./scripts/DeployFraxOFTProtocol/fpi-movement-move.layerzero.config.ts
```

At the review prompt, use `e` to export JSON for multisig execution. Do not use `y` unless intentionally broadcasting from the local signer.

Expected harmless warnings:

- `bigint: Failed to load bindings, pure JS will be used`
- `MODULE_TYPELESS_PACKAGE_JSON`

Do not add `"type": "module"` to `package.json` just to silence the module warning without auditing the repo's CommonJS scripts.
