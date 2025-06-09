## Deploy frxUSD and lockbox on Fraxtal Testnet
1. Deploy an Upgradeable frxUSD which has an equivalent interface to the Fraxtal frxUSD [implementation](https://fraxscan.com/address/0x00000afb5e62fd81bc698e418dbffe5094cb38e0#code) (specifically, `minter_burn_from()` and `minter_mint()`)
    - Mint an initial supply of 1M frxUSD to the lockbox to simulate locked supply
2. Deploy a Lockbox backed by frxUSD deployed in (1)
    - Wire it to Eth Sepolia, Arbitrum Sepolia OFTs
    - Use LZ and Frax DVNs
3. Update Sepolia(s) OFTs with Frax DVN

### Fraxtal Testnet addresses
#### frxUSD
- [Proxy](https://holesky.fraxscan.com/address/0x452420df4AC1e3db5429b5FD629f3047482C543C)
- [Implementation](https://holesky.fraxscan.com/address/0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A#code)
#### Lockbox
- [Proxy](https://holesky.fraxscan.com/address/0x7C9DF6704Ec6E18c5E656A2db542c23ab73CB24d)
- [Implementation](https://holesky.fraxscan.com/address/0x7FB2Dc5f485E01E0c627de86f7324c136F65eBB4#code)

TODO: update main README with address
- Should docs repo contain testnet addresses?