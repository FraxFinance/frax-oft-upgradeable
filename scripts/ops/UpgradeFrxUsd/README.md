 ## frxUSD Upgrade

### Motivation
FRAX and sFRAX are due for an upgrade.  These tokens will now be frxUSD and sfrxUSD, respectively, hosted natively on Fraxtal.

### Goals
- Migrate Ethereum FRAX/sFRAX LayerZero lockboxes into Fraxtal frxUSD/sfrxUSD lockboxes
- Maintain sufficient liquidity in Ethereum lockbox for bridged legacy liquidity (Base, Metis, Blast) to exit to Ethereum
- Connect Proxy LayerZero OFTs to the fraxtal lockboxes
- Upgrade Proxy OFTs to the new name/symbol
    - Maintain same contract addresses
- Protect users
    - No lost bridge messages during migration period

### Steps
#### 1. Block new outbound messages
Prevent new messages from being sent to other chains.  Allow already-sent messages to finish delivery & execution.

**NOTE**: After (1), team decided to resume outbound bridges.  See `revert/` directory for exeuction as (2+) did not happen.

#### 2. Deploy Mock OFT
- Deploy a FRAX/sFRAX "mock" OFT on Fraxtal with an initial supply of the lockbox (minus legacy/fraxtal circulating supply) to remove from the Ethereum lockbox.
    - Initial FRAX: [Lockbox](https://etherscan.io/token/0x853d955acef822db058eb8505911ed77f175b99e?a=0x909DBdE1eBE906Af95660033e478D59EFe831fED) - [base](https://basescan.org/token/0x909DBdE1eBE906Af95660033e478D59EFe831fED)
    - Initial sFRAX: [Lockbox](https://etherscan.io/token/0xa663b02cf0a4b149d2ad41910cb81e23e1c41c32?a=0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E) - [Metis](https://explorer.metis.io/token/0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E) - [Blast](https://blastscan.io/token/0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E) - [Base](https://basescan.org/token/0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E)
- Mint the supply to the Frax team msig.
- Set the Ethereum peer to the (m)FRAX/(m)sFRAX.  From this, bridging (m)FRAX to Ethereum will unlock the respective FRAX on Ethereum.

#### 3. Remove lockbox liquidity
From the team msig, send the (m)FRAX/(m)sFRAX to the Ethereum team msig, removing liquidity from the lockbox.

#### 4. Add liquidity to fraxtal lockboxes
Frax team to add the respective FRAX/sFRAX liquidity to the frxUSD/sfrxUSD lockboxes.

#### 5. Upgrade Proxy OFT Metadata
Upgrade the FRAX/sFRAX proxy OFT name, symbols.

#### 6. Manage FRAX/sFRAX peer conections
- Legacy OFTs
    - Resume connection to legacy peers- enables exit liquidity through Ethereum
    - Remove connection to proxy peers and Fraxtal
- Proxy OFTs
    - Resume connection to proxy peers
    - Set connection to Fraxtal lockboxes

#### 7. Unblock new outbound messages
Bridging resumes as expected.