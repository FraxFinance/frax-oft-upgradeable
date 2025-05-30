## Upgrade Eth Sepolia OFT
1. Deploy an Upgradeable frxUSD which has an equivalent interface to the mainnet frxUSD [implementation](https://etherscan.io/address/0xa8f9e149cce34ec7f68af720d8551cb9b39ed1f1#code) (specifically, `minter_burn_from()` and `minter_mint()`)
    - Initial supply must equal the [circulating supply on Arbitrum Sepolia](https://sepolia.arbiscan.io/token/0x0768c16445b41137f98ab68ca545c0afd65a7513#readProxyContract#F33).
2. Upgrade the Eth Sepolia [OFT](https://sepolia.etherscan.io/address/0x29a5134D3B22F47AD52e0A22A63247363e9F35c2) to a lockbox with the frxUSD from (1) as the backed token
   - Deposit the initial supply into the OFT.