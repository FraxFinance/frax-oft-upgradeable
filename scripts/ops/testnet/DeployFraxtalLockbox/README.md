## Deploy frxUSD and lockbox on Fraxtal Testnet
1. Deploy an Upgradeable frxUSD which has an equivalent interface to the Fraxtal frxUSD [implementation](https://fraxscan.com/address/0x00000afb5e62fd81bc698e418dbffe5094cb38e0#code) (specifically, `minter_burn_from()` and `minter_mint()`)
    - Mint an initial supply of 1M frxUSD to the lockbox to simulate locked supply
2. Deploy a Lockbox backed by frxUSD deployed in (1)
    - Wire it to Eth Sepolia, Arbitrum Sepolia OFTs
    - Use LZ and Frax DVNs
3. Update Sepolia(s) OFTs with Frax DVN

### Fraxtal Testnet addresses
#### frxUSD
- [Proxy](https://holesky.fraxscan.com/address/0x452420df4ac1e3db5429b5fd629f3047482c543c)
- [Implementation](https://holesky.fraxscan.com/address/0x7a07d606c87b7251c2953a30fa445d8c5f856c7a#code)
#### Lockbox
- [Proxy](TODO)
- [Implementation](TODO)

TODO: update README with address
- Should docs repo contain testnet addresses?