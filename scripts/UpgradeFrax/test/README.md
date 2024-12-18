## UpgradeFrax Tests
### Summary
This directory is a production-grade test of the UpgradeFrax scripts with a zero-value test token.

### Process
#### 1. Setup test token and LZ mesh (see `setup/`)
1. Deploy "CAC" token ([link](https://basescan.org/address/0x3cfd93b6fbbd879dca6649ef27170f1d1221cc6d)) and lockbox ([link](https://basescan.org/address/0xa536976c9ca36e74af76037af555eefa632ce469)) on Base to represent legacy FRAX with lockbox on Ethereum.
2. Deploy "CAC" OFTs
- Fraxtal ([link](https://fraxscan.com/address/0x103c430c9fcaa863ea90386e3d0d5cd53333876e))
- X-Layer ([link](https://www.oklink.com/xlayer/address/0x45682729Bdc0f68e7A02E76E9CfdA57D0cD4d20b/contract))
3. Connect OFTs
- Connect the "CAC" Base lockbox to the Fraxtal "CAC" OFT ([link](https://basescan.org/tx/0xeb10eeb8b90dee7f14960631599861f1a1ea6432fe5e22d3a092a5fd2fc18331)) ([link](https://basescan.org/tx/0xf511715ed8d8818b0d5b2bc1c93fd6e546270eed252d8748658f383b8fefcd6a#eventlog))
- Connect Fraxtal OFT to X-Layer ([link](https://fraxscan.com/tx/0x8a7fb3045bf962c6c94e14e0979f6911731ce9a4cdb67359b8ec5b1eaf7dbe60#eventlog))
4. Send some "CAC" token on Base to Fraxtal to create (a) supply in the Base lockbox and (b) supply of "CAC" OFT on Fraxtal ([link](https://layerzeroscan.com/tx/0xd07c6df483880ea3ee256a4532f0b21214999ba5afc002b692b96feef892fc0f)).
5. Deploy "new CAC" token on Fraxtal to represent frxUSD ([link](https://fraxscan.com/address/0x7131f0ec2aac01a5d30138c2d96c25e4fbbc78ce))


#### 2. Reproduce `scripts/UpgradeFrax/README.md` steps
1. Block new outbound messages ([link](https://basescan.org/tx/0x6bf51e2eb3f5c348bcef89e8b5b6408066996dd06cc434a3470e6149d10ac0c9))
2. Deploy Mock OFT ([link](https://fraxscan.com/address/0x59dddf3e838b196c89e725d61e9e0495f6c30306))
- Setup Base destination ([link](https://basescan.org/tx/0x7f70b121bc7d47a917e931eb7f1174cb4ba1b101d57b8d213c02da253c94ffcb#eventlog))
3. Remove lockbox liquidity ([link](https://layerzeroscan.com/tx/0xb6b36d913e8a0850e780af77e87021adbbf608e859a3c95db7146807fb76885c))
4. Upgrade Fraxtal OFTs to lockboxes ([(a) link](https://fraxscan.com/address/0xcd223049c07c10ba31612d6fbce1731e9cc20bbf#code)) ([(b) link](https://fraxscan.com/tx/0x7c1e39e843e34ed8788f6cd823734fc75e25f38a8bc87cdec6daacdd0c9ab3d4#eventlog))
5. Add liquidity to lockboxes ([link](https://fraxscan.com/tx/0x10cb540565cc77ff33fc9571d65a00fab161d11d73147ad66dedb9048da75faf))
6. Upgrade Proxy OFT Metadata ([link](https://www.oklink.com/xlayer/tx/0xe49747610d8372a83a5272436b1f9ce6fed6307f338664ffbfcccb9aaa5b2462))
7. Manage FRAX/sFRAX peer conections ([(a) link](https://basescan.org/tx/0x78a901df2cb3dfe5b6afac30ac7636c895e91e708b1cdd2aa3c9d845176f5e63)) ([(b) link](https://fraxscan.com/tx/0x6036791c08032c421d2de2e29f7ad6d61bbc3eb440d160303f42525b94f28bf6#eventlog))
8. Unblock new outbound messages ([Base link](https://basescan.org/tx/0x0ae91ddba42e5bfc54e044a5166bcfe533d17455ddbfcd352328cb3395490e88#eventlog))

#### 3. Resume bridging upgradeable OFT
We are now bridging from Fraxtal to X-Layer using the new Fraxtal lockbox.
- [lockbox spend approval](https://fraxscan.com/tx/0xff878cd0cf0a8f466eabafb99e22fbb0624e2902b17d830a2ccc10dbc4cca3e4)
- [send](https://layerzeroscan.com/tx/0xea5dbb9ce5e478127fa9688c90fd94f8639463b451b3a6c8427eb58769915100)