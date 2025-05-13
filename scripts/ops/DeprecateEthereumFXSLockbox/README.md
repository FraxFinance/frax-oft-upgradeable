## Deprecate Ethereum FXS Lockbox

### Description
Frax Protocol recently upgraded the FXS token to FRAX, now the gas token behind Fraxtal chain, as described in the official Frax [proposal](https://snapshot.box/#/s:frax.eth/proposal/0xc81e2268834ec1243e08c5d616c98c8e91e2304f7b38ee1d932f450efb18eb8a).

Part of the upgrade to FRAX is to reduce circulating FXS supply, specifically on Ethereum mainnet.  FXS on Ethereum is immutable and non-upgradeable, and because of this will always exist as FXS.  This is especially confusing if a user bridges via LayerZero to Ethereum, where their FRAX (from Fraxtal) or WFRAX (from any other chain) is converted back into FXS.  To support the future of FRAX, we are doing the following:

1. Deprecate the Ethereum FXS LayerZero lockbox.  By deprecate, we mean:
    a. Disable bridging to/from the Ethereum FXS lockbox.
    b. Move lockbox liquidity from the Ethereum lockbox to the Fraxtal lockbox.
2. Deploy an Ethereum WFRAX LayerZero OFT.
    - When bridging to Ethereum from either Fraxtal or a LayerZero-supported chain, users will receive WFRAX

It's important to note that this lockbox deprecation does not halt utility of the FXS token on Ethereum.  FXS holders are still able to upgrade their token to FRAX by bridging directly to Fraxtal via the Fraxtal Optimism Portal ([etherscan](https://etherscan.io/address/0x36cb65c1967A0Fb0EEE11569C51C2f2aA1Ca6f6D))([link to bridge](https://frax.com/swap?tokenA=0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0&tokenB=0x0000000000000000000000000000000000000000&originChainId=1&destinationChainId=252)).

### Technical Operations
1. Halt FXS bridging through setting the send library to the blocked send library. This allows in-flight bridges to settle.
    - From chains => Ethereum
    - From Ethereum => chains
2. Deploy a mock FXS OFT on Fraxtal with supply equal to the Ethereum FXS lockbox
    - Connect the Fraxtal OFT to the Ethereum lockbox
3. Send the mock FXS OFT to Ethereum, unlocking the Ethereum FXS lockbox supply by sending the locked FXS to the Frax multisig.
4. Frax multisig upgrades the FXS to FRAX on Fraxtal and sends the upgraded FRAX as WFRAX to the Fraxtal WFRAX lockbox.
5. Deploy WFRAX OFT on Ethereum
    - Connect only to Fraxtal
6. Upgrade Hop contracts (on Ethereum and Fraxtal) to point to the new WFRAX OFT