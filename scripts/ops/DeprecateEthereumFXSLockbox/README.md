## Deprecate Ethereum FXS Lockbox

### Description
Frax Protocol recently upgraded the FXS token to FRAX, now the gas token behind Fraxtal chain, as described in the official Frax [proposal](https://snapshot.box/#/s:frax.eth/proposal/0xc81e2268834ec1243e08c5d616c98c8e91e2304f7b38ee1d932f450efb18eb8a).

Part of the upgrade to FRAX is to reduce circulating FXS supply, specifically on Ethereum mainnet.  FXS on Ethereum is immutable and non-upgradeable, and because of this will always exist as FXS.  This is especially confusing if a user bridges via LayerZero to Ethereum, where their FRAX (from Fraxtal) or WFRAX (from any other chain) is converted back into FXS.  To support the future of FRAX, we are doing the following:

1. Deprecate the Ethereum FXS LayerZero lockbox.  By deprecate, we mean:
    a. Disable bridging to/from the Ethereum FXS lockbox.
    b. Move lockbox liquidity from the Ethereum lockbox to the Fraxtal lockbox.
2. Deploy an Ethereum WFRAX LayerZero OFT.
    - When bridging to Ethereum from either Fraxtal another LayerZero-supported chain via hop, users will receive WFRAX

It's important to note that this lockbox deprecation does not halt utility of the FXS token on Ethereum.  FXS holders are still able to upgrade their token to FRAX by bridging directly to Fraxtal via the Fraxtal Optimism Portal ([etherscan](https://etherscan.io/address/0x36cb65c1967A0Fb0EEE11569C51C2f2aA1Ca6f6D))([link to bridge](https://frax.com/swap?tokenA=0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0&tokenB=0x0000000000000000000000000000000000000000&originChainId=1&destinationChainId=252)).

### Technical Operations
#### 1. Bridge Modification and Deployment
1. Halt FRAX bridging through setting the send library to the blocked send library. This allows in-flight bridges to settle.
    - From LZ-supported chains (minus Fraxtal) => Ethereum
        - Fraxtal WFRAX lockbox remains operable to the Ethereum FXS lockbox
        - All mesh-connected chains cannot send WFRAX directly to Ethereum
        - Hops to Ethereum remain operable
    - From Ethereum => chains (including Fraxtal)
        - Hops from Ethereum are paused
1. Deploy WFRAX OFT on Ethereum
    - Connect only to Fraxtal through the Hub model
    - Modify Fraxtal WFRAX lockbox peer on Ethereum to WFRAX OFT
        - At this point, the supply in the Ethereum FXS lockbox will be fixed as no bridges can be done to/from the Ethereum FXS lockbox.
1. Update Hop contracts to point to the new WFRAX OFT
    - Ethereum `RemoteHop` updated via `toggleOFTApproval()`
    - Fraxtal `FraxtalHop` remains operable without modification.
    - Hops from Ethereum resume.

#### 2. Migrate Ethereum FXS lockbox liquidity
1. Deploy a mock FXS OFT on Fraxtal with supply equal to the Ethereum FXS lockbox
    - Send the supply to migrate to a custodian contract (`FXSCustodianMock`) with msig permissions.
    - On Fraxtal, wire the OFT only to Ethereum.
    - On Ethereum, set the FXS lockbox peer to the mock FXS OFT
1. Initiate sends from the custodian via Frax team msig
    - Test send, then full send to move FXS liquidity to the Ethereum Comptroller
1. Ethereum Comptroller migrates the FXS liquidity to the Fraxtal WFRAX lockbox
    1. Bridge the FXS to Fraxtal, converting it into FRAX
    1. Wrap FRAX into WFRAX
    1. Send directly to the WFRAX lockbox

#### 3. Periphery operations
1. Update Frax documentation to reflect Ethereum WFRAX OFT
1. Remove low liquidity alert by Telegram bot for Ethereum FXS lockbox