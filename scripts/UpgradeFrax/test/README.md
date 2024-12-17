## UpgradeFrax Tests
### Summary
This directory is a production-grade test of the UpgradeFrax scripts with a zero-value test token.

### Process
#### 1. Setup test token and LZ mesh (see `setup/`)
1. Deploy "CAC" token ([link](https://basescan.org/address/0x3cfd93b6fbbd879dca6649ef27170f1d1221cc6d)) and lockbox ([link](https://basescan.org/address/0xa536976c9ca36e74af76037af555eefa632ce469)) on Base to represent legacy FRAX with lockbox on Ethereum.
2. Deploy "CAC" OFT on Fraxtal ([link](https://fraxscan.com/address/0x103c430c9fcaa863ea90386e3d0d5cd53333876e)) to represent FRAX OFT on Fraxtal
3. Connect the "CAC" Base lockbox to the Fraxtal "CAC" OFT ([link](https://basescan.org/tx/0xeb10eeb8b90dee7f14960631599861f1a1ea6432fe5e22d3a092a5fd2fc18331)) ([link](https://basescan.org/tx/0xf511715ed8d8818b0d5b2bc1c93fd6e546270eed252d8748658f383b8fefcd6a#eventlog)).
4. Send some "CAC" token on Base to Fraxtal to create (a) supply in the Base lockbox and (b) supply of "CAC" OFT on Fraxtal ([link](https://layerzeroscan.com/tx/0xd07c6df483880ea3ee256a4532f0b21214999ba5afc002b692b96feef892fc0f)).
5. Deploy "new CAC" token on Fraxtal to represent frxUSD ([link](https://fraxscan.com/address/0x7131f0ec2aac01a5d30138c2d96c25e4fbbc78ce))


#### 2. Reproduce `scripts/UpgradeFrax/README.md` steps
1. Block new outbound messages ([link](https://basescan.org/tx/0x6bf51e2eb3f5c348bcef89e8b5b6408066996dd06cc434a3470e6149d10ac0c9))
2. Deploy Mock OFT ([link](https://fraxscan.com/address/0x59dddf3e838b196c89e725d61e9e0495f6c30306)
- Setup Base destination ([link](https://basescan.org/tx/0x7f70b121bc7d47a917e931eb7f1174cb4ba1b101d57b8d213c02da253c94ffcb#eventlog))
3. Remove lockbox liquidity ([link](https://layerzeroscan.com/tx/0xb6b36d913e8a0850e780af77e87021adbbf608e859a3c95db7146807fb76885c))
4. Upgrade Fraxtal OFTs to lockboxes
5. Add liquidity to lockboxes
6. Upgrade Proxy OFT Metadata
7. Manage FRAX/sFRAX peer conections
8. Unblock new outbound messages
