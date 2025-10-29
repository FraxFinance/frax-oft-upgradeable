import { getAddress } from 'viem'
import { chains } from '../chains'
import { aptosMovementOFTs, ofts, solanaOFTs } from '../oft'

interface Peer {
    token: string
    srcChain: string
    dstChain: string
    srcOft: string
    dstOft: string
    srcPeerId: string
    dstPeerId: string
}
interface PeerConnect {
    [token: string]: { [srcChain: string]: string[] }
}

// interface ResultJson {
//     [srcChain: string]: {
//         [token: string]: string[]
//     }
// }

const bytes32Zero = '0x0000000000000000000000000000000000000000000000000000000000000000'

// const resultJson: ResultJson = {}

// // Helper function to check if two entries are connected
// function isConnected(entry1: Peer, entry2: Peer): boolean {
//     return (
//         entry1.token === entry2.token &&
//         entry1.srcOft === entry2.dstOft &&
//         entry1.srcPeerId === entry2.dstPeerId &&
//         entry1.srcChain === entry2.dstChain
//     )
// }

async function main() {
    // const peers: Peer[] = []
    // const chainProcessingPromises = Object.keys(chains).map(async (srcChain) => {
    //     const chainResults: Peer[] = []

    //     let blockNumber
    //     if (srcChain !== 'solana' && srcChain !== 'movement' && srcChain !== 'aptos') {
    //         blockNumber = await chains[srcChain].client.getBlockNumber()
    //     }
    //     for (const dstChain of Object.keys(chains)) {
    //         if (srcChain === dstChain) continue

    //         if (srcChain !== 'solana' && srcChain !== 'movement' && srcChain !== 'aptos') {
    //             for (const oftSymbol of Object.keys(ofts[srcChain])) {
    //                 const dstOft = await chains[srcChain].client.readContract({
    //                     address: ofts[srcChain][oftSymbol].address,
    //                     abi: ofts[srcChain][oftSymbol].abi,
    //                     functionName: 'peers',
    //                     args: [chains[dstChain].peerId],
    //                     blockNumber,
    //                 })

    //                 if (dstOft !== bytes32Zero) {
    //                     const dstOftAddr = getAddress('0x' + dstOft.slice(-40))
    //                     if (dstOftAddr === getAddress(ofts[dstChain][oftSymbol].address)) {
    //                         chainResults.push({
    //                             token: oftSymbol,
    //                             srcChain: srcChain,
    //                             dstChain: dstChain,
    //                             // srcBlockNumber: blockNumber.toString(),
    //                             srcPeerId: chains[srcChain].peerId.toString(),
    //                             dstPeerId: chains[dstChain].peerId.toString(),
    //                             srcOft: getAddress(ofts[srcChain][oftSymbol].address),
    //                             dstOft: dstOftAddr,
    //                         })
    //                     } else {
    //                         console.log(
    //                             `token : ${oftSymbol},
    //                             srcChain: ${srcChain},
    //                             dstChain: ${dstChain},
    //                             srcPeerId : ${chains[srcChain].peerId.toString()},
    //                             dstPeerId : ${chains[dstChain].peerId.toString()},
    //                             srcOft : ${ofts[srcChain][oftSymbol].address},
    //                             expectedDstOft : ${ofts[dstChain][oftSymbol].address},
    //                             actualDstOft : ${dstOftAddr}  :
    //                             oft mismatch`
    //                         )
    //                     }
    //                 }
    //             }
    //         }
    //     }
    //     return chainResults
    // })
    // const peerResults = await Promise.all(chainProcessingPromises)

    // for (const peerResult of peerResults) {
    //     peers.push(...peerResult)
    // }

    // // Iterate over all chain results to build the final structure
    // peers.forEach((entry) => {
    //     const { token, srcChain, dstChain, srcPeerId, dstPeerId, srcOft, dstOft } = entry

    //     // Initialize srcChain object if it doesn't exist
    //     if (!resultJson[srcChain]) {
    //         resultJson[srcChain] = {}
    //     }

    //     // Initialize token array if it doesn't exist
    //     if (!resultJson[srcChain][token]) {
    //         resultJson[srcChain][token] = []
    //     }

    //     // Now, find matching pairs from previously processed chains
    //     for (let [existingChain, tokens] of Object.entries(resultJson)) {
    //         for (let [existingToken, dstChains] of Object.entries(tokens)) {
    //             // Only consider chains that match the token
    //             if (existingToken === token) {
    //                 dstChains.forEach((existingDstChain) => {
    //                     // Check if the connection conditions are met
    //                     if (
    //                         isConnected(entry, {
    //                             srcChain: existingChain,
    //                             dstChain: existingDstChain,
    //                             token: existingToken,
    //                             srcOft,
    //                             dstOft,
    //                             srcPeerId,
    //                             dstPeerId,
    //                         })
    //                     ) {
    //                         resultJson[srcChain][token].push(dstChain)
    //                     }
    //                 })
    //             }
    //         }
    //     }
    // })

    // console.log(JSON.stringify(resultJson, null, 2))

    // =========================================================
    const peerJson: PeerConnect = {}
    for (const srcChain of Object.keys(chains)) {
        if (srcChain === "katana" || srcChain === "plasma" ||
            srcChain === 'solana' || srcChain === 'movement' || srcChain === 'aptos'
        ) continue
        let contractCalls: any[] = []
        let chainPeers: Peer[] = []
        for (const dstChain of Object.keys(chains)) {
            if (srcChain === dstChain) continue
            for (const oftSymbol of Object.keys(ofts[srcChain])) {
                contractCalls.push({
                    address: ofts[srcChain][oftSymbol].address,
                    abi: ofts[srcChain][oftSymbol].abi,
                    functionName: 'peers',
                    args: [chains[dstChain].peerId],
                })
                chainPeers.push({
                    token: oftSymbol,
                    srcChain: srcChain,
                    dstChain: dstChain,
                    srcOft: ofts[srcChain][oftSymbol].address,
                    dstOft:
                        dstChain === 'solana'
                            ? solanaOFTs[oftSymbol].mint
                            : dstChain === 'movement' || dstChain === 'aptos'
                                ? aptosMovementOFTs[oftSymbol].oft
                                : ofts[dstChain][oftSymbol].address,
                    srcPeerId: chains[srcChain].peerId.toString(),
                    dstPeerId: chains[dstChain].peerId.toString(),
                })
            }
        }
        let blockNumber = await chains[srcChain].client.getBlockNumber()

        const peers = await chains[srcChain].client.multicall({
            contracts: contractCalls,
            blockNumber,
        })
        chainPeers.forEach((chainPeer, index) => {
            if (chainPeer.dstChain !== "solana" && chainPeer.dstChain !== "aptos" && chainPeer.dstChain !== "movement") {
                if (peers[index].status === 'success' && peers[index].result !== bytes32Zero) {
                    const dstPeerAddr = getAddress('0x' + peers[index].result.slice(-40))
                    if (dstPeerAddr === getAddress(chainPeer.dstOft)) {
                        if (!peerJson[chainPeer.token]) {
                            peerJson[chainPeer.token] = {}
                        }

                        if (!peerJson[chainPeer.token][chainPeer.srcChain]) {
                            peerJson[chainPeer.token][chainPeer.srcChain] = [] as string[]
                        }

                        peerJson[chainPeer.token][chainPeer.srcChain].push(chainPeer.dstChain)
                    } else {
                        console.log(
                            `token : ${chainPeer.token},
                        srcChain: ${chainPeer.srcChain},
                        dstChain: ${chainPeer.dstChain},
                        srcPeerId : ${chains[chainPeer.srcChain].peerId.toString()},
                        dstPeerId : ${chains[chainPeer.dstChain].peerId.toString()},
                        srcOft : ${ofts[chainPeer.srcChain][chainPeer.token].address},
                        expectedDstOft : ${ofts[chainPeer.dstChain][chainPeer.token].address},
                        actualDstOft : ${dstPeerAddr}  :
                        oft mismatch`
                        )
                    }
                }
            }
        })
    }
    console.log(peerJson)
}

main().catch(console.error)
