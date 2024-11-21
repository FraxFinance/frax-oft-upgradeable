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

#### 2. Deploy Mock OFT
- Deploy a FRAX/sFRAX "mock" OFT on Fraxtal with an initial supply of the lockbox (minus legacy circulating supply) to remove from the Ethereum lockbox.
- Mint the supply to the Frax team msig.
- Set the Ethereum peer to the (m)FRAX/(m)sFRAX.  From this, bridging (m)FRAX to Ethereum will unlock the respective FRAX on Ethereum.

#### 3. Remove lockbox liquidity
From the team msig, send the (m)FRAX/(m)sFRAX to the Ethereum team msig, removing liquidity from the lockbox.

#### 4. Deploy Fraxtal lockboxes
Deploy frxUSD/sfrxUSD lockboxes on Fraxtal. These lockboxes will be connected to the upgradeable OFTs.

#### 5. Add liquidity to lockboxes
Frax team to add the respective FRAX/sFRAX liquidity to the frxUSD/sfrxUSD lockboxes.

#### 6. Manage FRAX/sFRAX peer conections
- On Ethereum lockboxes, remove the peer connection to Fraxtal (m)FRAX/(m)sFRAX and to proxy OFTs
- On Proxy OFTs, remove peer connection to Ethereum lockbox and legacy OFTS
- On Legacy OFTs, remove peer connection to proxy OFTs. Maintain peer connection to Ethereum lockbox & legacy OFTs to enable exit liquidity. 

#### 7. Unblock new outbound messages
Bridging resumes as expected.