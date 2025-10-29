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

const bytes32Zero = '0x0000000000000000000000000000000000000000000000000000000000000000'

async function main() {
    const peerJson: PeerConnect = {}
    for (const srcChain of Object.keys(chains)) {
        if (
            srcChain === 'katana' ||
            srcChain === 'plasma' ||
            srcChain === 'solana' ||
            srcChain === 'movement' ||
            srcChain === 'aptos'
        )
            continue
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
            if (
                chainPeer.dstChain !== 'solana' &&
                chainPeer.dstChain !== 'aptos' &&
                chainPeer.dstChain !== 'movement'
            ) {
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
