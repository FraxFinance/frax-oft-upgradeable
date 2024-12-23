## Deploy Ink
### Introduction
Ink. Kraken's optimistic L2.  Deployment of Frax protocol's OFTs (LayerZero tokens) onto Ink requires a different process than the usual.  This README documents the process and operation of Ink OFTs until their configuration is synced with the other OFT frameworks.

### Description
As part of the Frax [North Star hard fork](https://x.com/fraxfinance/status/1867677016742670473), Frax is upgrading several offered tokens, notably, FRAX to frxUSD and sFRAX to sfrxUSD.  Part of the token upgrade initiative requires upgrading LayerZero's OFT mesh as well, because the OFTs need to be modified to reflect the new symbols.  The Frax team has developed the required upgrade scripts ([here](https://github.com/FraxFinance/frax-oft-upgradeable/pull/25)) and plans to complete the upgrade across the LZ mesh early 2025.

In the interim, blockchain never sleeps and neither do chain deployments.  Part of the Frax strategy with Ink is to bridge over fresh FRAX and sFRAX from Fraxtal, which will be seen respectively as frxUSD and sfrxUSD on Ink upon transfer.  Currently, the Frax OFT framework is designed with a FRAX/sFRAX "lockbox" on Ethereum mainnet, and part of the North Star upgrade moves this lockbox to be hosted on Frax's own chain, Fraxtal, by upgrading the existing Fraxtal OFT to a lockbox implementation.

Until the North Star, Frax will operate standalone Fraxtal lockboxes to manage Ink liquidity.  Post North Star, lockbox liquidity will be moved from the standalone lockboxes to the upgraded OFT lockboxes.

### Process
#### 1. Deploy Fraxtal Lockboxes
See `1_DeployFraxtalLockboxes.s.sol`.  This step creates the `frxUSD` and `sfrxUSD` lockbox on Fraxtal.

**Lockbox Addresses:**
- `frxUSD`: [`0x96A394058E2b84A89bac9667B19661Ed003cF5D4`](https://fraxscan.com/address/0x96a394058e2b84a89bac9667b19661ed003cf5d4)
- `sfrxUSD`: [`0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361`](https://fraxscan.com/address/0x88aa7854d3b2daa5e37e7ce73a1f39669623a361)