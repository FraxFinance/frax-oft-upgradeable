## Launch frax asset OFTs on new chain

> Note : Use this scripts for fraxtal hub OFTs only

> Note : **FPI is deprecated.** New chain expansions deploy and wire 5 active OFTs —
> WFRAX, sfrxUSD, sfrxETH, frxUSD, frxETH. Do **not** set `fpiOft` in a new chain's child scripts and
> register the chain with `fullDeterministicProxyOftsPostFpi`. Chains onboarded before the deprecation
> keep their FPI OFT and their scripts still manage it — the shared bases branch on `_managesToken(Token.FPI)`.

### Deploy OFTs

```
forge script scripts/FraxtalHub/1_DeployFraxOFTFraxtalHub/DeployFraxOFTFraxtalHub.s.sol --rpc-url $RPC_URL --broadcast
```

### Setup Source 
* Add the new chain's entry to `scripts/L0Config.json`: `RPC`, `chainid`, `eid`, `endpoint`, `delegate`, `proxyAdmin`, DVN addresses, and the chain's `sendLib302` **and** `receiveLib302` (SendUln302/ReceiveUln302 addresses from the [LayerZero metadata](https://metadata.layerzero-api.com/v1/metadata) deployment for the chain)
  * Both libraries are pinned per route by `setLibs`. Pinning `receiveLib302` matters: the ULN DVN/confirmation config is stored per library, so an OApp left on the endpoint default would silently lose its security config if LayerZero rotates the default receive library
  * `SetupSourceFraxOFTFraxtalHub` reverts if either lib is unset or not registered on the endpoint
* Create a new solidity file inside `2_SetupSourceFraxOFTFraxtalHub` with name `SetupSourceFraxOFTFraxtal{chain-name}.sol` and inherit `SetupSourceFraxOFTFraxtalHub`
* In the `constructor`, assign address for each OFTs deployed in above step
* Refer to example script `SetupSourceFraxOFTFraxtalHubHyperliquidmock.sol`
```
forge script scripts/FraxtalHub/2_SetupSourceFraxOFTFraxtalHub/SetupSourceFraxOFTFraxtalHubHyperliquidmock.s.sol --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast
```

### Setup Destination

* Create a new solidity file inside `3_SetupDestinationFraxOFTFraxtalHub` with name `SetupDestinationFraxOFTFraxtal{chain-name}.sol` and inherit `SetupDestinationFraxOFTFraxtalHub`
* In the `constructor`, assign address for each OFTs deployed in first step
* Refer to example script `SetupDestinationFraxOFTFraxtalHubHyperliquidmock.sol`

```
forge script scripts/FraxtalHub/3_SetupDestinationFraxOFTFraxtalHub/SetupDestinationFraxOFTFraxtalHubHyperliquidmock.s.sol --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast
```

### Test Bridging OFTs between fraxtal and new chain 

No per-chain code: the `frax:wallet:send` hardhat task ([tasks/evm/sendFraxWallet.ts](../../tasks/evm/sendFraxWallet.ts)) batch-sends Frax assets between any two mesh chains through the dev `FraxOFTWallet`. It reads RPCs from `scripts/L0Config.json` and finds each chain's OFT through the Fraxtal lockbox's `peers(eid)`, checking that it peers back; assets a chain does not have (FPI) are skipped. It sends directly (`IOFT.send`) when the source OFTs peer to the destination, which is always the case to/from Fraxtal, and through HopV2 otherwise (e.g. Base -> Ethereum), and pays fees in TIP20 on Tempo.

* If the dev wallet on the new chain is not at `0x741F0d8Bde14140f62107FC60A0EE122B37D4630`, add it to `WALLET_BY_EID` in the task (or pass `--wallet` / `--to`)
* Dry-run first (no key needed): it checks wiring, balances, allowances, hop routing and fees, and simulates native-fee batches
* Send Fraxtal -> new chain first: the default recipient is the dev wallet there, which funds the return leg
* Sending needs `PK_CONFIG_DEPLOYER` (the wallet owner) in the environment

```
pnpm exec hardhat frax:wallet:send --src-eid 30255 --dst-eid <new-eid> --dry-run
pnpm exec hardhat frax:wallet:send --src-eid 30255 --dst-eid <new-eid>
pnpm exec hardhat frax:wallet:send --src-eid <new-eid> --dst-eid 30255
pnpm exec hardhat frax:wallet:send --src-eid <new-eid> --dst-eid 30184 --tokens frxUSD=1,sfrxUSD=0.5   # via HopV2
```

Options: `--tokens` (assets with optional amounts, e.g. `frxUSD=10,WFRAX`; default all), `--amount` (for assets listed without one, default `0.0001`), `--route auto|direct|hop` (force the hop to test it), `--gas-token` (TIP20 fee token). Record the LayerZero scan links in `4_SendFraxOFTFraxtalHub/README.md`.

To test the whole mesh, `frax:wallet:smoketest` ([tasks/evm/smoketestFraxWallet.ts](../../tasks/evm/smoketestFraxWallet.ts)) relays all five assets around a ring of every chain, one leg at a time. Without `--execute` it is a dry run (no key) that simulates every leg and prints fees, expected waits and what the owner and the Fraxtal hub hop need. Add a new chain to its default route (X Layer stays last: 225,000 confirmations). Set `WALLET_UPGRADE_RPC_<chainid>` for a flaky L0Config RPC.

### Add config to FraxtalHop