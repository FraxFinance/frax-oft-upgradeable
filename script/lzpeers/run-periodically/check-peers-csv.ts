import { getAddress } from 'viem'
import { chains } from '../chains'
import { aptosMovementOFTs, ofts, solanaOFTs } from '../oft'
import { oft302 } from '@layerzerolabs/oft-v2-solana-sdk'
import { publicKey } from "@metaplex-foundation/umi";
import { makeBytes32 } from '@layerzerolabs/devtools'
import bs58 from 'bs58'
import fs from 'fs'
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

const bytes32Zero = '0x0000000000000000000000000000000000000000000000000000000000000000'

function generatePeerConnectionCSV(oftConnectionObj: { [srcChain: string]: string[] }) {
    // Get all the unique chains from the oft object keys
    const chains = Object.keys(oftConnectionObj);

    // Initialize an array for the CSV data
    let csvData = [];

    // Create the first row (headers) - the chain names
    let headerRow = [""];
    headerRow.push(...chains); // Add all the chains as columns
    csvData.push(headerRow.join(",")); // Add header to CSV data

    // Loop through each chain and create the rows
    chains.forEach(chain1 => {
        let row = [chain1]; // Start the row with the chain name

        // For each other chain, check if both chains are listed in each other's arrays
        chains.forEach(chain2 => {
            if (oftConnectionObj[chain1].includes(chain2) && oftConnectionObj[chain2].includes(chain1)) {
                row.push("x"); // Mark with "x" if there's a mutual relationship
            } else {
                row.push("-"); // Otherwise, mark with "-"
            }
        });

        // Push the row to the CSV data
        csvData.push(row.join(","));
    });

    // Return the CSV string
    return csvData.join("\n");
}

async function main() {
    const peerJson: PeerConnect = {}
    for (const srcChain of Object.keys(chains)) {
        let contractCalls: any[] = []
        let chainPeers: Peer[] = []
        for (const dstChain of Object.keys(chains)) {
            if (srcChain === dstChain) continue
            for (const oftSymbol of Object.keys(
                srcChain === 'solana'
                    ? solanaOFTs
                    : srcChain === 'movement' || srcChain === 'aptos'
                        ? aptosMovementOFTs
                        : ofts[srcChain]
            )) {
                if (srcChain === 'solana' || srcChain === 'movement' || srcChain === 'aptos') {
                    if (srcChain === 'solana') {
                        try {
                            const peerBytes32 = await oft302.getPeerAddress(
                                chains['solana'].client.rpc,
                                publicKey(solanaOFTs[oftSymbol].oftStore), //oftStore
                                chains[dstChain].peerId,
                                publicKey(solanaOFTs[oftSymbol].programId) //programId
                            )
                            if (peerBytes32 !== bytes32Zero) {
                                const dstPeerAddr = getAddress('0x' + peerBytes32.slice(-40))
                                if (dstPeerAddr === getAddress(ofts[dstChain][oftSymbol].address)) {
                                    if (!peerJson[oftSymbol]) {
                                        peerJson[oftSymbol] = {}
                                    }

                                    if (!peerJson[oftSymbol][srcChain]) {
                                        peerJson[oftSymbol][srcChain] = [] as string[]
                                    }

                                    peerJson[oftSymbol][srcChain].push(dstChain)
                                } else {
                                    console.log(
                                        `token : ${oftSymbol},
                                    srcChain: ${srcChain},
                                    dstChain: ${dstChain},
                                    srcPeerId : ${chains[srcChain].peerId.toString()},
                                    dstPeerId : ${chains[dstChain].peerId.toString()},
                                    srcOft : ${ofts[srcChain][oftSymbol].address},
                                    expectedDstOft : ${ofts[dstChain][oftSymbol].address},
                                    actualDstOft : ${dstPeerAddr}  :
                                    oft mismatch`
                                    )
                                }
                            } else {
                                console.log(`solana X ${dstChain} for ${oftSymbol}`)
                            }
                        } catch (e) {
                            console.log(`Error : solana ${oftSymbol} ${dstChain}`)
                        }
                    } else if (srcChain === 'movement' || srcChain === 'aptos') {
                        try {
                            const peerBytes32 = await chains[srcChain].client.view({
                                payload: {
                                    function: `${aptosMovementOFTs[oftSymbol].oft}::oapp_core::get_peer`,
                                    functionArguments: [chains[dstChain].peerId],
                                },
                            })
                            if (peerBytes32[0] !== bytes32Zero) {
                                const dstPeerAddr = getAddress('0x' + peerBytes32[0].slice(-40))
                                if (dstPeerAddr === getAddress(ofts[dstChain][oftSymbol].address)) {
                                    if (!peerJson[oftSymbol]) {
                                        peerJson[oftSymbol] = {}
                                    }

                                    if (!peerJson[oftSymbol][srcChain]) {
                                        peerJson[oftSymbol][srcChain] = [] as string[]
                                    }

                                    peerJson[oftSymbol][srcChain].push(dstChain)
                                } else {
                                    console.log(
                                        `token : ${oftSymbol},
                                    srcChain: ${srcChain},
                                    dstChain: ${dstChain},
                                    srcPeerId : ${chains[srcChain].peerId.toString()},
                                    dstPeerId : ${chains[dstChain].peerId.toString()},
                                    srcOft : ${aptosMovementOFTs[oftSymbol].oft},
                                    expectedDstOft : ${ofts[dstChain][oftSymbol].address},
                                    actualDstOft : ${dstPeerAddr}
                                    oft mismatch`
                                    )
                                }
                            }
                        } catch (e) {
                            console.log(`Error : ${srcChain} ${oftSymbol} ${dstChain}`)
                        }
                    }
                } else {
                    if (srcChain === 'katana' || srcChain === 'plasma') {
                        const peerBytes32 = await chains[srcChain].client.readContract({
                            address: ofts[srcChain][oftSymbol].address,
                            abi: ofts[srcChain][oftSymbol].abi,
                            functionName: 'peers',
                            args: [chains[dstChain].peerId],
                        })
                        if (peerBytes32 !== bytes32Zero) {
                            const dstPeerAddr = getAddress('0x' + peerBytes32.slice(-40))
                            if (dstPeerAddr === getAddress(ofts[dstChain][oftSymbol].address)) {
                                if (!peerJson[oftSymbol]) {
                                    peerJson[oftSymbol] = {}
                                }

                                if (!peerJson[oftSymbol][srcChain]) {
                                    peerJson[oftSymbol][srcChain] = [] as string[]
                                }

                                peerJson[oftSymbol][srcChain].push(dstChain)
                            } else {
                                console.log(
                                    `token : ${oftSymbol},
                                    srcChain: ${srcChain},
                                    dstChain: ${dstChain},
                                    srcPeerId : ${chains[srcChain].peerId.toString()},
                                    dstPeerId : ${chains[dstChain].peerId.toString()},
                                    srcOft : ${ofts[srcChain][oftSymbol].address},
                                    expectedDstOft : ${ofts[dstChain][oftSymbol].address},
                                    actualDstOft : ${dstPeerAddr}  :
                                    oft mismatch`
                                )
                            }
                        }
                    } else {
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
                                    ? solanaOFTs[oftSymbol].oftStore
                                    : dstChain === 'movement' || dstChain === 'aptos'
                                        ? aptosMovementOFTs[oftSymbol].oft
                                        : ofts[dstChain][oftSymbol].address,
                            srcPeerId: chains[srcChain].peerId.toString(),
                            dstPeerId: chains[dstChain].peerId.toString(),
                        })
                    }
                }
            }
        }
        if (
            srcChain !== 'solana' &&
            srcChain !== 'movement' &&
            srcChain !== 'aptos' &&
            srcChain !== 'katana' &&
            srcChain !== 'plasma'
        ) {
            const peers = await chains[srcChain].client.multicall({
                contracts: contractCalls,
            })
            chainPeers.forEach((chainPeer, index) => {
                if (peers[index].status === 'success' && peers[index].result !== bytes32Zero) {
                    let actualDstPeerAddr
                    let expectedDstOft
                    if (
                        chainPeer.dstChain === 'solana' ||
                        chainPeer.dstChain === 'aptos' ||
                        chainPeer.dstChain === 'movement'
                    ) {
                        actualDstPeerAddr = peers[index].result
                        if (chainPeer.dstChain === 'solana') {
                            expectedDstOft = makeBytes32(bs58.decode(chainPeer.dstOft))
                        } else if (chainPeer.dstChain === 'aptos' || chainPeer.dstChain === 'movement') {
                            expectedDstOft = chainPeer.dstOft
                        }
                    } else {
                        actualDstPeerAddr = getAddress('0x' + peers[index].result.slice(-40))
                        expectedDstOft = getAddress(chainPeer.dstOft)
                    }
                    if (actualDstPeerAddr === expectedDstOft) {
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
                                expectedDstOft : ${expectedDstOft},
                                actualDstOft : ${actualDstPeerAddr}  :
                                oft mismatch`
                        )
                    }
                }
            })
        }
    }
    for (const oft of Object.keys(peerJson)) {
        fs.writeFileSync(
            `./check-peers-csv/check-${oft}-peer.csv`,
            generatePeerConnectionCSV(peerJson[oft])
        )
    }
}
main().catch(console.error)
