import { /*bytesToHex, decodeAbiParameters,*/ getAddress /*, Hex, hexToBytes, padHex, toHex*/ } from 'viem'
// import { publicKey } from '@metaplex-foundation/umi'
// import { oft302 } from '@layerzerolabs/oft-v2-solana-sdk'
import { default as ENDPOINTV2_ABI } from '../abis/ENDPOINTV2_ABI.json'
import { default as OFT_MINTABLE_ADAPTER_ABI } from '../abis/OFT_MINTABLE_ADAPTER_ABI.json'
// import { default as RECEIVE_ULN302_ABI } from '../abis/RECEIVE_ULN302_ABI.json'
// import { default as SEND_ULN302_ABI } from '../abis/SEND_ULN302_ABI.json'
import { default as FRAX_PROXY_ADMIN_ABI } from '../abis/FRAX_PROXY_ADMIN_ABI.json'
import fs from 'fs'
import * as dotenv from 'dotenv'
import { chains } from '../chains'
import {
    /*assetListType,*/ ChainConfig,
    DstChainConfig,
    OFTInfo,
    Params,
    ReceiveLibraryTimeOutInfo,
    ReceiveLibraryType,
    SrcChainConfig,
    TokenConfig,
} from '../types'
import { aptosMovementOFTs, ofts, solanaOFTs } from '../oft'
import bs58 from 'bs58'

dotenv.config()

const bytes32Zero = '0x0000000000000000000000000000000000000000000000000000000000000000'

// function decodeLzReceiveOption(encodedOption: Hex) {
//     const optionBytes = hexToBytes(encodedOption)
//     const length = optionBytes.length

//     if (length < 16) throw new Error(`Invalid data length: ${length} bytes`)

//     const extractedData = optionBytes.slice(-16) // Always extract last 16 bytes
//     const isValuePresent = length >= 32

//     if (!isValuePresent) {
//         const [gas] = decodeAbiParameters([{ type: 'uint128' }], padHex(bytesToHex(extractedData), { size: 32 }))
//         return { gas, value: 0n } // If value is absent, return 0n
//     } else {
//         const extractedData32 = optionBytes.slice(-32) // Extract last 32 bytes
//         console.log(bytesToHex(extractedData32))
//         const [gas, value] = decodeAbiParameters(
//             [{ type: 'uint128' }, { type: 'uint128' }],
//             bytesToHex(extractedData32)
//         )
//         return { gas, value }
//     }
// }

const MSIG_ABI = [
    {
        inputs: [],
        name: 'getOwners',
        outputs: [
            {
                internalType: 'address[]',
                name: '',
                type: 'address[]',
            },
        ],
        stateMutability: 'view',
        type: 'function',
    },
    {
        inputs: [],
        name: 'getThreshold',
        outputs: [
            {
                internalType: 'uint256',
                name: '',
                type: 'uint256',
            },
        ],
        stateMutability: 'view',
        type: 'function',
    },
]

async function main() {
    const oftObj: TokenConfig = {}
    // const chainArr = Object.keys(chains)

    let contractcalls: any[] = []

    // 1. endpoint, owner, proxyAdmin, implementation
    for (const srcChain of Object.keys(chains)) {
        for (const oftName of Object.keys(
            srcChain === 'solana'
                ? solanaOFTs
                : srcChain === 'movement' || srcChain === 'aptos'
                  ? aptosMovementOFTs
                  : ofts[srcChain]
        )) {
            if (oftObj[oftName] === undefined) {
                oftObj[oftName] = {} as ChainConfig
            }
            if (oftObj[oftName][srcChain] === undefined) {
                oftObj[oftName][srcChain] = {} as SrcChainConfig
            }
            if (oftObj[oftName][srcChain].params === undefined) {
                oftObj[oftName][srcChain].params = {} as Params
            }
            if (srcChain === 'solana') {
            } else if (srcChain === 'aptos' || srcChain === 'movement') {
            } else if (srcChain === 'plasma' || srcChain === 'katana') {
                const endpointAddress = await chains[srcChain].client.readContract({
                    address: ofts[srcChain][oftName].address,
                    abi: OFT_MINTABLE_ADAPTER_ABI,
                    functionName: 'endpoint',
                })
                const ownerAddress = await chains[srcChain].client.readContract({
                    address: ofts[srcChain][oftName].address,
                    abi: OFT_MINTABLE_ADAPTER_ABI,
                    functionName: 'owner',
                })

                const expectedImplementationAddress = await chains[srcChain].client.readContract({
                    address: chains[srcChain].fraxProxyAdmin,
                    abi: FRAX_PROXY_ADMIN_ABI,
                    functionName: 'getProxyImplementation',
                    args: [ofts[srcChain][oftName].address],
                })

                const expectedProxyAdminAddress = await chains[srcChain].client.readContract({
                    address: chains[srcChain].fraxProxyAdmin,
                    abi: FRAX_PROXY_ADMIN_ABI,
                    functionName: 'getProxyAdmin',
                    args: [ofts[srcChain][oftName].address],
                })

                // TODO : actualImplementationAddress : get from OFT Proxy contract
                // get storage at : 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
                // TODO : actualProxyAdminAddress : get from OFT proxy contract
                // get storage at : 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc

                oftObj[oftName][srcChain].params.oftProxy = ofts[srcChain][oftName].address
                oftObj[oftName][srcChain].params.expectedEndpoint = chains[srcChain].endpoint
                oftObj[oftName][srcChain].params.actualEndpoint = endpointAddress
                oftObj[oftName][srcChain].params.owner = ownerAddress
                oftObj[oftName][srcChain].params.expectedImplementation = expectedImplementationAddress
                oftObj[oftName][srcChain].params.expectedProxyAdmin = expectedProxyAdminAddress
            } else {
                contractcalls.push({
                    address: ofts[srcChain][oftName].address,
                    abi: OFT_MINTABLE_ADAPTER_ABI,
                    functionName: 'endpoint',
                })
                contractcalls.push({
                    address: ofts[srcChain][oftName].address,
                    abi: OFT_MINTABLE_ADAPTER_ABI,
                    functionName: 'owner',
                })
                contractcalls.push({
                    address: chains[srcChain].fraxProxyAdmin,
                    abi: FRAX_PROXY_ADMIN_ABI,
                    functionName: 'getProxyImplementation',
                    args: [ofts[srcChain][oftName].address],
                })
                contractcalls.push({
                    address: chains[srcChain].fraxProxyAdmin,
                    abi: FRAX_PROXY_ADMIN_ABI,
                    functionName: 'getProxyAdmin',
                    args: [ofts[srcChain][oftName].address],
                })
            }
        }

        if (
            srcChain !== 'movement' &&
            srcChain !== 'aptos' &&
            srcChain !== 'solana' &&
            srcChain !== 'plasma' &&
            srcChain !== 'katana'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []

            Object.keys(ofts[srcChain]).forEach((oftName, index) => {
                oftObj[oftName][srcChain].params.oftProxy = ofts[srcChain][oftName].address
                oftObj[oftName][srcChain].params.expectedEndpoint = chains[srcChain].endpoint
                // 0 -> endpoint
                oftObj[oftName][srcChain].params.actualEndpoint = authParams[index * 4].result
                // 1 -> owner
                oftObj[oftName][srcChain].params.owner = authParams[index * 4 + 1].result
                // 2 -> expectedImplementation
                oftObj[oftName][srcChain].params.expectedImplementation = authParams[index * 4 + 2].result
                // 3 -> expectedProxyAdmin
                oftObj[oftName][srcChain].params.expectedProxyAdmin = authParams[index * 4 + 3].result
            })
        }
    }

    // 2. delegate, owner msig threshold, owner msig members,
    //    proxyAdminOwner threshold, proxyAdminOwner members
    for (const srcChain of Object.keys(chains)) {
        for (const oftName of Object.keys(
            srcChain === 'solana'
                ? solanaOFTs
                : srcChain === 'movement' || srcChain === 'aptos'
                  ? aptosMovementOFTs
                  : ofts[srcChain]
        )) {
            if (srcChain === 'solana') {
            } else if (srcChain === 'aptos' || srcChain === 'movement') {
            } else if (srcChain === 'plasma' || srcChain === 'katana') {
                const delegateAddress = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.actualEndpoint,
                    abi: ENDPOINTV2_ABI,
                    functionName: 'delegates',
                    args: [ofts[srcChain][oftName].address],
                })

                const ownerMsigThreshold = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.owner,
                    abi: MSIG_ABI,
                    functionName: 'getThreshold',
                })

                const ownerMsigMembers = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.owner,
                    abi: MSIG_ABI,
                    functionName: 'getOwners',
                })

                const proxyAdminOwner = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.expectedProxyAdmin,
                    abi: FRAX_PROXY_ADMIN_ABI,
                    functionName: 'owner',
                })

                oftObj[oftName][srcChain].params.delegate = delegateAddress
                oftObj[oftName][srcChain].params.ownerThreshold = Number(ownerMsigThreshold).toString()
                oftObj[oftName][srcChain].params.ownerMembers = ownerMsigMembers
                oftObj[oftName][srcChain].params.proxyAdminOwner = proxyAdminOwner
            } else {
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.actualEndpoint,
                    abi: ENDPOINTV2_ABI,
                    functionName: 'delegates',
                    args: [ofts[srcChain][oftName].address],
                })
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.owner,
                    abi: MSIG_ABI,
                    functionName: 'getThreshold',
                })
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.owner,
                    abi: MSIG_ABI,
                    functionName: 'getOwners',
                })
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.expectedProxyAdmin,
                    abi: FRAX_PROXY_ADMIN_ABI,
                    functionName: 'owner',
                })
            }
        }

        if (
            srcChain !== 'movement' &&
            srcChain !== 'aptos' &&
            srcChain !== 'solana' &&
            srcChain !== 'plasma' &&
            srcChain !== 'katana'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []

            Object.keys(ofts[srcChain]).forEach((oftName, index) => {
                // 0 -> delegate
                oftObj[oftName][srcChain].params.delegate = authParams[index * 4].result
                // 1 -> owner msig threshold
                oftObj[oftName][srcChain].params.ownerThreshold = Number(authParams[index * 4 + 1].result).toString()
                // 2 -> owner msig members
                oftObj[oftName][srcChain].params.ownerMembers = authParams[index * 4 + 2].result
                // 3 -> proxyAdmin owner
                oftObj[oftName][srcChain].params.proxyAdminOwner = authParams[index * 4 + 3].result
            })
        }
    }

    // 3. delegate msig threshold, delegate msig members,
    //    proxy Admin msig threshold, proxy Admin msig members
    for (const srcChain of Object.keys(chains)) {
        for (const oftName of Object.keys(
            srcChain === 'solana'
                ? solanaOFTs
                : srcChain === 'movement' || srcChain === 'aptos'
                  ? aptosMovementOFTs
                  : ofts[srcChain]
        )) {
            if (srcChain === 'solana') {
            } else if (srcChain === 'aptos' || srcChain === 'movement') {
            } else if (srcChain === 'plasma' || srcChain === 'katana') {
                const delegateMsigThreshold = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.delegate,
                    abi: MSIG_ABI,
                    functionName: 'getThreshold',
                })

                const delegateMsigMembers = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.delegate,
                    abi: MSIG_ABI,
                    functionName: 'getOwners',
                })

                const proxyAdminOwnerMsigThreshold = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.proxyAdminOwner,
                    abi: MSIG_ABI,
                    functionName: 'getThreshold',
                })

                const proxyAdminOwnerMsigMembers = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.proxyAdminOwner,
                    abi: MSIG_ABI,
                    functionName: 'getOwners',
                })

                oftObj[oftName][srcChain].params.delegateThreshold = Number(delegateMsigThreshold).toString()
                oftObj[oftName][srcChain].params.delegateMembers = delegateMsigMembers
                oftObj[oftName][srcChain].params.proxyAdminOwnerThreshold =
                    Number(proxyAdminOwnerMsigThreshold).toString()
                oftObj[oftName][srcChain].params.proxyAdminOwnermembers = proxyAdminOwnerMsigMembers
            } else {
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.delegate,
                    abi: MSIG_ABI,
                    functionName: 'getThreshold',
                })
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.delegate,
                    abi: MSIG_ABI,
                    functionName: 'getOwners',
                })
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.proxyAdminOwner,
                    abi: MSIG_ABI,
                    functionName: 'getThreshold',
                })
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.proxyAdminOwner,
                    abi: MSIG_ABI,
                    functionName: 'getOwners',
                })
            }
        }

        if (
            srcChain !== 'movement' &&
            srcChain !== 'aptos' &&
            srcChain !== 'solana' &&
            srcChain !== 'plasma' &&
            srcChain !== 'katana'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []

            Object.keys(ofts[srcChain]).forEach((oftName, index) => {
                oftObj[oftName][srcChain].params.eid = chains[srcChain].peerId.toString()
                // 0 -> delegate Msig threshold
                oftObj[oftName][srcChain].params.delegateThreshold = Number(authParams[index * 4].result).toString()
                // 1 -> delegate msig members
                oftObj[oftName][srcChain].params.delegateMembers = authParams[index * 4 + 1].result
                // 2 -> proxy admin owner msig threshold
                oftObj[oftName][srcChain].params.proxyAdminOwnerThreshold = Number(
                    authParams[index * 4 + 2].result
                ).toString()
                // 3 -> proxy Admin owner msig members
                oftObj[oftName][srcChain].params.proxyAdminOwnermembers = authParams[index * 4 + 3].result
            })
        }
    }

    // 4. peers
    for (const srcChain of Object.keys(chains)) {
        let resSchema: { srcChain: string; dstChain: string; oftName: string; dstPeerId: string }[] = []
        for (const dstChain of Object.keys(chains)) {
            if (srcChain === dstChain) continue
            for (const oftName of Object.keys(
                srcChain === 'solana'
                    ? solanaOFTs
                    : srcChain === 'movement' || srcChain === 'aptos'
                      ? aptosMovementOFTs
                      : ofts[srcChain]
            )) {
                if (oftObj[oftName][srcChain].dstChains == undefined) {
                    oftObj[oftName][srcChain].dstChains = {} as DstChainConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain] == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain] = {} as OFTInfo
                }
                if (srcChain === 'solana') {
                } else if (srcChain === 'aptos' || srcChain === 'movement') {
                } else if (srcChain === 'plasma' || srcChain === 'katana') {
                    const peerBytes32 = await chains[srcChain].client.readContract({
                        address: ofts[srcChain][oftName].address,
                        abi: OFT_MINTABLE_ADAPTER_ABI,
                        functionName: 'peers',
                        args: [chains[dstChain].peerId],
                    })
                    const isSupportedEid = await chains[srcChain].client.readContract({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'isSupportedEid',
                        args: [chains[dstChain].peerId],
                    })
                    oftObj[oftName][srcChain].dstChains[dstChain].isSupportedEid = isSupportedEid
                    if (peerBytes32 !== bytes32Zero) {
                        oftObj[oftName][srcChain].dstChains[dstChain].peerAddressBytes32 = peerBytes32
                        oftObj[oftName][srcChain].dstChains[dstChain].peerAddress = getAddress(
                            '0x' + peerBytes32.slice(-40)
                        )
                    }
                } else {
                    contractcalls.push({
                        address: ofts[srcChain][oftName].address,
                        abi: OFT_MINTABLE_ADAPTER_ABI,
                        functionName: 'peers',
                        args: [chains[dstChain].peerId],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'isSupportedEid',
                        args: [chains[dstChain].peerId],
                    })
                    resSchema.push({
                        srcChain,
                        dstChain,
                        oftName,
                        dstPeerId: chains[dstChain].peerId.toString(),
                    })
                }
            }
        }
        if (
            srcChain !== 'movement' &&
            srcChain !== 'aptos' &&
            srcChain !== 'solana' &&
            srcChain !== 'plasma' &&
            srcChain !== 'katana'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []

            resSchema.forEach(({ srcChain, dstChain, oftName, dstPeerId }, index) => {
                oftObj[oftName][srcChain].dstChains[dstChain].eid = dstPeerId
                if (authParams[index].result !== bytes32Zero) {
                    oftObj[oftName][srcChain].dstChains[dstChain].peerAddressBytes32 = authParams[index * 2].result
                    oftObj[oftName][srcChain].dstChains[dstChain].peerAddressBytes32 = authParams[index * 2].result
                    if (dstChain === 'solana') {
                        oftObj[oftName][srcChain].dstChains[dstChain].peerAddress = bs58.encode(
                            Buffer.from(authParams[index * 2].result.slice(-64), 'hex')
                        )
                    } else if (dstChain === 'movement' || dstChain === 'aptos') {
                        oftObj[oftName][srcChain].dstChains[dstChain].peerAddress = authParams[index * 2].result
                    } else {
                        oftObj[oftName][srcChain].dstChains[dstChain].peerAddress = getAddress(
                            '0x' + authParams[index * 2].result.slice(-40)
                        )
                    }
                    oftObj[oftName][srcChain].dstChains[dstChain].isSupportedEid = authParams[index * 2 + 1].result
                }
            })
            resSchema = []
        }
    }

    // 5. send/rcv lib
    for (const srcChain of Object.keys(chains)) {
        let resSchema: { srcChain: string; dstChain: string; oftName: string }[] = []
        for (const dstChain of Object.keys(chains)) {
            if (srcChain === dstChain) continue
            for (const oftName of Object.keys(
                srcChain === 'solana'
                    ? solanaOFTs
                    : srcChain === 'movement' || srcChain === 'aptos'
                      ? aptosMovementOFTs
                      : ofts[srcChain]
            )) {
                if (oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary = {} as ReceiveLibraryType
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].receiveLibraryTimeOut == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].receiveLibraryTimeOut =
                        {} as ReceiveLibraryTimeOutInfo
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibraryTimeOut == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibraryTimeOut =
                        {} as ReceiveLibraryTimeOutInfo
                }
                if (srcChain === 'solana') {
                } else if (srcChain === 'aptos' || srcChain === 'movement') {
                } else if (srcChain === 'plasma' || srcChain === 'katana') {
                    if (oftObj[oftName][srcChain].dstChains[dstChain].isSupportedEid) {
                        const blockedLib = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'blockedLibrary',
                        })
                        const sendLib = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'getSendLibrary',
                            args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                        })
                        const rcvLib = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'getReceiveLibrary',
                            args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                        }) // receive two vals -> addr, bool
                        const receiveLibraryTimeout = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'receiveLibraryTimeout',
                            args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                        }) // address lib, uint2256 expiry
                        const defaultSendLib = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'defaultSendLibrary',
                            args: [chains[dstChain].peerId],
                        })
                        const defaultReceiveLib = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'defaultReceiveLibrary',
                            args: [chains[dstChain].peerId],
                        })
                        const defaultReceiveLibTimeout = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'defaultReceiveLibraryTimeout',
                            args: [chains[dstChain].peerId],
                        }) // address lib, uint2256 expiry
                        const isDefaultSendLibrary = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'isDefaultSendLibrary',
                            args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].blockedLib = blockedLib
                        oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary = sendLib
                        oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress = rcvLib[0]
                        oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.isDefault = rcvLib[1]
                        oftObj[oftName][srcChain].dstChains[dstChain].receiveLibraryTimeOut.libAddress =
                            receiveLibraryTimeout[0]
                        oftObj[oftName][srcChain].dstChains[dstChain].receiveLibraryTimeOut.expiry = Number(
                            receiveLibraryTimeout[1]
                        ).toString()
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary = defaultSendLib
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary = defaultReceiveLib
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibraryTimeOut.libAddress =
                            defaultReceiveLibTimeout[0]
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibraryTimeOut.expiry = Number(
                            defaultReceiveLibTimeout[1]
                        ).toString()
                        oftObj[oftName][srcChain].dstChains[dstChain].isDefaultSendLibrary = isDefaultSendLibrary
                    }
                } else {
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'blockedLibrary',
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'getSendLibrary',
                        args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'getReceiveLibrary',
                        args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                    }) // receive two vals -> addr, bool
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'receiveLibraryTimeout',
                        args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                    }) // address lib, uint2256 expiry
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'defaultSendLibrary',
                        args: [chains[dstChain].peerId],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'defaultReceiveLibrary',
                        args: [chains[dstChain].peerId],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'defaultReceiveLibraryTimeout',
                        args: [chains[dstChain].peerId],
                    }) // address lib, uint2256 expiry
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'isDefaultSendLibrary',
                        args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                    })
                    resSchema.push({
                        srcChain,
                        dstChain,
                        oftName,
                    })
                }
            }
        }
        if (
            srcChain !== 'movement' &&
            srcChain !== 'aptos' &&
            srcChain !== 'solana' &&
            srcChain !== 'plasma' &&
            srcChain !== 'katana'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []
            resSchema.forEach(({ srcChain, dstChain, oftName }, index) => {
                if (authParams[index * 8].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].blockedLib = authParams[index * 8].result
                } else {
                    console.log(`${oftName}:${srcChain}:${dstChain}:blockedLib`)
                }
                if (authParams[index * 8 + 1].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary = authParams[index * 8 + 1].result
                } else {
                    console.log(`${oftName}:${srcChain}:${dstChain}:sendLibrary`)
                }
                if (authParams[index * 8 + 2].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress =
                        authParams[index * 8 + 2].result[0]
                    oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.isDefault =
                        authParams[index * 8 + 2].result[1]
                } else {
                    console.log(`${oftName}:${srcChain}:${dstChain}:receiveLibrary`)
                }
                if (authParams[index * 8 + 3].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].receiveLibraryTimeOut.libAddress =
                        authParams[index * 8 + 3].result[0]
                    oftObj[oftName][srcChain].dstChains[dstChain].receiveLibraryTimeOut.expiry = Number(
                        authParams[index * 8 + 3].result[1]
                    ).toString()
                } else {
                    console.log(`${oftName}:${srcChain}:${dstChain}:receiveLibraryTimeOut`)
                }
                if (authParams[index * 8 + 4].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary = authParams[index * 8 + 4].result
                } else {
                    console.log(`${oftName}:${srcChain}:${dstChain}:defaultSendLibrary`)
                }
                if (authParams[index * 8 + 5].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary =
                        authParams[index * 8 + 5].result
                } else {
                    console.log(`${oftName}:${srcChain}:${dstChain}:defaultReceiveLibrary`)
                }
                if (authParams[index * 8 + 6].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibraryTimeOut.libAddress =
                        authParams[index * 8 + 6].result[0]
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibraryTimeOut.expiry = Number(
                        authParams[index * 8 + 6].result[1]
                    ).toString()
                } else {
                    console.log(`${oftName}:${srcChain}:${dstChain}:defaultReceiveLibraryTimeOut`)
                }
                if (authParams[index * 8 + 7].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].isDefaultSendLibrary =
                        authParams[index * 8 + 7].result
                } else {
                    console.log(`${oftName}:${srcChain}:${dstChain}:isDefaultSendLibrary`)
                }
            })
            resSchema = []
        }
    }

    // 6. enforced options

    // 7. combined options

    // 8. sendUln302

    // 9. rcvUln 302

    for (const oftName of Object.keys(oftObj)) {
        fs.writeFileSync(
            `./run-periodically/check-oft-config-csv/check-${oftName}-config-peer.json`,
            JSON.stringify(oftObj[oftName], null, 2)
        )
    }
}

main()
