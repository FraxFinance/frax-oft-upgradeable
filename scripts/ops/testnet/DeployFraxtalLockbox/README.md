## Deploy frxUSD and lockbox on Fraxtal Testnet
1. Deploy an Upgradeable frxUSD which has an equivalent interface to the Fraxtal frxUSD [implementation](https://fraxscan.com/address/0x00000afb5e62fd81bc698e418dbffe5094cb38e0#code) (specifically, `minter_burn_from()` and `minter_mint()`)
    - Mint an initial supply of 1M frxUSD to the lockbox to simulate locked supply
2. Deploy a Lockbox backed by frxUSD deployed in (1)
    - Wire it to Eth Sepolia, Arbitrum Sepolia OFTs
    - Use LZ and Frax DVNs
3. Update Sepolia(s) OFTs with Frax DVN

### Fraxtal Testnet addresses
#### frxUSD
- [Proxy](TODO)
- [Implementation](TODO)
#### Lockbox
- [Proxy](TODO)
- [Implementation](TODO)

TODO: update README with address
- Should docs repo contain testnet addresses?