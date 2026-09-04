## Launch frax asset OFTs on new chain

> Note : Use this scripts for fraxtal hub OFTs only

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
#### For bridging OFTs from fraxtal to new chain
* Create a new solidity file inside `4_SendFraxOFTFraxtalHub` with name `SendFraxOFTFraxtalTo{chain-name}` and inherit `SendFraxOFTFraxtalHub`
* In the `constructor`, assign address for each OFTs deployed in first step
* Refer to example script `SendFraxOFTFraxtalToHyperliquidmock`

```
forge script scripts/FraxtalHub/4_SendFraxOFTFraxtalHub/SendFraxOFTFraxtalToHyperliquidmock.s.sol --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast
```
#### For testing OFTs from new chain to fraxtal
    
* Create a new solidity file inside `4_SendFraxOFTFraxtalHub` with name `SendFraxOFT{chain-name}ToFraxtal` and inherit `SendFraxOFTFraxtalHub`
* In the `constructor`, assign address for each OFTs deployed in first step
* Refer to example script `SendFraxOFTHyperliquidToFraxtalmock`

```
forge script scripts/FraxtalHub/4_SendFraxOFTFraxtalHub/SendFraxOFTHyperliquidToFraxtalmock.s.sol --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast
```

### Add config to FraxtalHop