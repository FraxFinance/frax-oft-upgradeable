// import { bytesToHex, decodeAbiParameters, getAddress, Hex, hexToBytes, padHex, toHex } from 'viem'
// import { publicKey } from '@metaplex-foundation/umi'
// import { oft302 } from '@layerzerolabs/oft-v2-solana-sdk'
import { default as ENDPOINTV2_ABI } from '../abis/ENDPOINTV2_ABI.json'
import { default as OFT_MINTABLE_ADAPTER_ABI } from '../abis/OFT_MINTABLE_ADAPTER_ABI.json'
// import { default as RECEIVE_ULN302_ABI } from '../abis/RECEIVE_ULN302_ABI.json'
// import { default as SEND_ULN302_ABI } from '../abis/SEND_ULN302_ABI.json'
import { default as FRAX_PROXY_ADMIN_ABI } from '../abis/FRAX_PROXY_ADMIN_ABI.json'
// import fs from 'fs'
import * as dotenv from 'dotenv'
import { chains } from '../chains'
import { /*assetListType,*/ OFTInfo } from '../types'
import { aptosMovementOFTs, ofts, solanaOFTs } from '../oft'

dotenv.config()

// const bytes32Zero = '0x0000000000000000000000000000000000000000000000000000000000000000'

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

interface Params {
    oftProxy: string
    actualImplementation: string
    expectedImplementation: string
    actualProxyAdmin: string
    expectedProxyAdmin: string
    endpoint: string
    delegate: string
    delegateThreshold: string
    delegateMembers: string[]
    owner: string
    ownerThreshold: string
    ownerMembers: string[]
    proxyAdmin: string
    proxyAdminOwner: string
    proxyAdminOwnerThreshold: string
    proxyAdminOwnermembers: string[]
}

interface DstChainConfig {
    [dstChain: string]: OFTInfo
}

interface SrcChainConfig {
    params: Params
    dstChains: DstChainConfig
}

interface ChainConfig {
    [srcChain: string]: SrcChainConfig
}

interface TokenConfig {
    [token: string]: ChainConfig
}

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
                oftObj[oftName][srcChain].params.endpoint = endpointAddress
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
                // 0 -> endpoint
                oftObj[oftName][srcChain].params.endpoint = authParams[index * 4].result
                // 1 -> owner
                oftObj[oftName][srcChain].params.owner = authParams[(index * 4) + 1].result
                // 2 -> expectedImplementation
                oftObj[oftName][srcChain].params.expectedImplementation = authParams[(index * 4) + 2].result
                // 3 -> expectedProxyAdmin
                oftObj[oftName][srcChain].params.expectedProxyAdmin = authParams[(index * 4) + 3].result
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
                    address: oftObj[oftName][srcChain].params.endpoint,
                    abi: ENDPOINTV2_ABI,
                    functionName: 'delegates',
                    args: [ofts[srcChain][oftName].address]
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
                    address: oftObj[oftName][srcChain].params.endpoint,
                    abi: ENDPOINTV2_ABI,
                    functionName: 'delegates',
                    args: [ofts[srcChain][oftName].address]
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
                oftObj[oftName][srcChain].params.ownerThreshold = Number(authParams[(index * 4) + 1].result).toString()
                // 2 -> owner msig members
                oftObj[oftName][srcChain].params.ownerMembers = authParams[(index * 4) + 2].result
                // 3 -> proxyAdmin owner
                oftObj[oftName][srcChain].params.proxyAdminOwner = authParams[(index * 4) + 3].result
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
                    functionName: 'getThreshold'
                })

                const delegateMsigMembers = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.delegate,
                    abi: MSIG_ABI,
                    functionName: 'getOwners',
                })

                const proxyAdminOwnerMsigThreshold = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.proxyAdminOwner,
                    abi: MSIG_ABI,
                    functionName: 'getThreshold'
                })

                const proxyAdminOwnerMsigMembers = await chains[srcChain].client.readContract({
                    address: oftObj[oftName][srcChain].params.proxyAdminOwner,
                    abi: MSIG_ABI,
                    functionName: 'getOwners',
                })

                oftObj[oftName][srcChain].params.delegateThreshold = Number(delegateMsigThreshold).toString()
                oftObj[oftName][srcChain].params.delegateMembers = delegateMsigMembers
                oftObj[oftName][srcChain].params.proxyAdminOwnerThreshold = Number(proxyAdminOwnerMsigThreshold).toString()
                oftObj[oftName][srcChain].params.proxyAdminOwnermembers = proxyAdminOwnerMsigMembers
            } else {
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.delegate,
                    abi: MSIG_ABI,
                    functionName: 'getThreshold'
                })
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.delegate,
                    abi: MSIG_ABI,
                    functionName: 'getOwners',
                })
                contractcalls.push({
                    address: oftObj[oftName][srcChain].params.proxyAdminOwner,
                    abi: MSIG_ABI,
                    functionName: 'getThreshold'
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
                // 0 -> delegate Msig threshold
                oftObj[oftName][srcChain].params.delegateThreshold = Number(authParams[index * 4].result).toString()
                // 1 -> delegate msig members
                oftObj[oftName][srcChain].params.delegateMembers = authParams[(index * 4) + 1].result
                // 2 -> proxy admin owner msig threshold
                oftObj[oftName][srcChain].params.proxyAdminOwnerThreshold = Number(authParams[(index * 4) + 2].result).toString()
                // 3 -> proxy Admin owner msig members
                oftObj[oftName][srcChain].params.proxyAdminOwnermembers = authParams[(index * 4) + 3].result
            })
        }
    }

    console.log(JSON.stringify(oftObj["sfrxUSD"],null,2))

    // 4. peers

    // 5. enforced options

    // 6. combined options

    // 7. send/rcv lib

    // 8. sendUln302

    // 9. rcvUln 302

    // for (let chainArrIndex = 0; chainArrIndex < chainArr.length; chainArrIndex++) {
    //     const srcChain = chainArr[chainArrIndex]
    //     if (chains[srcChain].oApps === undefined) {
    //         continue
    //     }

    //     for (const oAppName of Object.keys(chains[srcChain].oApps as assetListType)) {
    //         let contractCalls: any[] = []
    //         const oApp = chains[srcChain].oApps?.[oAppName as keyof assetListType]
    //         const oftContract = {
    //             address: oApp,
    //             abi: OFT_ADAPTER_ABI,
    //         } as const

    //         if (ofts[oAppName] === undefined) {
    //             ofts[oAppName] = {} as Record<string, Record<string, OFTInfo>>
    //         }
    //         if (ofts[oAppName][srcChain] === undefined) {
    //             ofts[oAppName][srcChain] = {} as Record<string, OFTInfo>
    //         }

    //         if (srcChain === 'solana') {
    //             // add to ofts
    //             for (const destChainName of Object.keys(chains)) {
    //                 const peerInfo = await oft302.getPeerAddress(
    //                     chains[srcChain].client.rpc,
    //                     publicKey(solanaOFTs[oAppName].oftStore), //oftStore
    //                     chains[destChainName].peerId,
    //                     publicKey(solanaOFTs[oAppName].programId) //programId
    //                 )

    //                 if (peerInfo && peerInfo !== bytes32Zero) {
    //                     ofts[oAppName][srcChain][destChainName] = {} as OFTInfo
    //                     ofts[oAppName][srcChain][destChainName].peerAddressBytes32 = peerInfo
    //                     ofts[oAppName][srcChain][destChainName].peerAddress = getAddress('0x' + peerInfo.slice(-40))
    //                     if (chains[destChainName].oApps === undefined) {
    //                         chains[destChainName].oApps = {} as assetListType
    //                     }
    //                     chains[destChainName].oApps[oAppName as keyof assetListType] =
    //                         ofts[oAppName][srcChain][destChainName].peerAddress
    //                 }
    //             }
    //         } else if (srcChain === 'ink') {
    //             // add to ofts
    //             for (const destChainName of Object.keys(chains)) {
    //                 const peerInfo = await chains[srcChain].client.readContract({
    //                     ...oftContract,
    //                     functionName: 'peers',
    //                     args: [chains[destChainName].peerId],
    //                 })

    //                 if (peerInfo && peerInfo !== bytes32Zero) {
    //                     ofts[oAppName][srcChain][destChainName] = {} as OFTInfo
    //                     ofts[oAppName][srcChain][destChainName].peerAddressBytes32 = peerInfo
    //                     ofts[oAppName][srcChain][destChainName].peerAddress = getAddress('0x' + peerInfo.slice(-40))
    //                     if (chains[destChainName].oApps === undefined) {
    //                         chains[destChainName].oApps = {} as assetListType
    //                     }
    //                     chains[destChainName].oApps[oAppName as keyof assetListType] =
    //                         ofts[oAppName][srcChain][destChainName].peerAddress
    //                 }
    //             }
    //         } else {
    //             // get peers
    //             Object.keys(chains).forEach(async (destChainName) => {
    //                 contractCalls.push({
    //                     ...oftContract,
    //                     functionName: 'peers',
    //                     args: [chains[destChainName].peerId],
    //                 })
    //             })

    //             const peers = await chains[srcChain].client.multicall({
    //                 contracts: contractCalls,
    //             })

    //             // add to ofts
    //             Object.keys(chains).forEach((destChainName, index) => {
    //                 if (peers[index].result) {
    //                     if (peers[index].result != bytes32Zero) {
    //                         ofts[oAppName][srcChain][destChainName] = {} as OFTInfo
    //                         ofts[oAppName][srcChain][destChainName].peerAddressBytes32 = peers[index].result
    //                         ofts[oAppName][srcChain][destChainName].peerAddress = getAddress(
    //                             '0x' + peers[index].result.slice(-40)
    //                         )
    //                         if (chains[destChainName].oApps === undefined) {
    //                             chains[destChainName].oApps = {} as assetListType
    //                         }
    //                         chains[destChainName].oApps[oAppName as keyof assetListType] =
    //                             ofts[oAppName][srcChain][destChainName].peerAddress
    //                     }
    //                 }
    //             })
    //         }

    //         if (srcChain === 'solana') {
    //             for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
    //                 let oftres = await oft302.getEnforcedOptions(
    //                     chains[srcChain].client.rpc,
    //                     publicKey(solanaOFTs[oAppName].oftStore), //oftStore,
    //                     chains[destChainName].peerId,
    //                     publicKey(solanaOFTs[oAppName].programId) //programId
    //                 )

    //                 let opt
    //                 if (oftres.send.length > 0) {
    //                     opt = decodeLzReceiveOption(toHex(oftres.send))
    //                     ofts[oAppName][srcChain][destChainName].combinedOptionsSend = {} as OFTEnforcedOptions
    //                     ofts[oAppName][srcChain][destChainName].combinedOptionsSend.gas = opt.gas.toString()
    //                     ofts[oAppName][srcChain][destChainName].combinedOptionsSend.value = opt.value.toString()
    //                 }

    //                 if (oftres.sendAndCall.length > 0) {
    //                     opt = decodeLzReceiveOption(toHex(oftres.sendAndCall))
    //                     ofts[oAppName][srcChain][destChainName].enforcedOptions = {} as OFTEnforcedOptions
    //                     ofts[oAppName][srcChain][destChainName].enforcedOptions.gas = opt.gas.toString()
    //                     ofts[oAppName][srcChain][destChainName].enforcedOptions.value = opt.value.toString()
    //                 }
    //             }
    //         } else if (srcChain === 'ink') {
    //             for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
    //                 let oftres = await chains[srcChain].client.readContract({
    //                     ...oftContract,
    //                     functionName: 'combineOptions',
    //                     args: [chains[destChainName].peerId, 1, '0x'],
    //                 })
    //                 let opt
    //                 if (oftres !== '0x') {
    //                     opt = decodeLzReceiveOption(oftres)
    //                     ofts[oAppName][srcChain][destChainName].combinedOptionsSend = {} as OFTEnforcedOptions
    //                     ofts[oAppName][srcChain][destChainName].combinedOptionsSend.gas = opt.gas.toString()
    //                     ofts[oAppName][srcChain][destChainName].combinedOptionsSend.value = opt.value.toString()
    //                 }

    //                 // TODO
    //                 // oftres = oftOptions[(index * 4) + 1]
    //                 // opt = decodeLzReceiveOption(oftres.result)
    //                 // ofts[destChainName].combinedOptionsSendAndCall = {} as OFTEnforceedOptions
    //                 // ofts[destChainName].combinedOptionsSendAndCall.gas = opt.gas.toString()
    //                 // ofts[destChainName].combinedOptionsSendAndCall.value = opt.value.toString()
    //                 oftres = await chains[srcChain].client.readContract({
    //                     ...oftContract,
    //                     functionName: 'enforcedOptions',
    //                     args: [chains[destChainName].peerId, 3],
    //                 })
    //                 if (oftres !== '0x') {
    //                     opt = decodeLzReceiveOption(oftres)
    //                     ofts[oAppName][srcChain][destChainName].enforcedOptions = {} as OFTEnforcedOptions
    //                     ofts[oAppName][srcChain][destChainName].enforcedOptions.gas = opt.gas.toString()
    //                     ofts[oAppName][srcChain][destChainName].enforcedOptions.value = opt.value.toString()
    //                 }
    //             }
    //         } else {
    //             contractCalls = []
    //             Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName) => {
    //                 // oft.combineOptions (_eid (uint32), _msgType (uint16), _extraOptions (bytes)) : bytes
    //                 contractCalls.push({
    //                     ...oftContract,
    //                     functionName: 'combineOptions',
    //                     args: [chains[destChainName].peerId, 1, '0x'],
    //                 })
    //                 contractCalls.push({
    //                     ...oftContract,
    //                     functionName: 'combineOptions',
    //                     args: [chains[destChainName].peerId, 2, '0x'],
    //                 })
    //                 // oft.enforcedOptions (_eid (uint32), _msgType (uint16)) : bytes
    //                 contractCalls.push({
    //                     ...oftContract,
    //                     functionName: 'enforcedOptions',
    //                     args: [chains[destChainName].peerId, 3],
    //                 })
    //                 // oft.isPeer (_eid (uint32), _peer (bytes32)) : bool
    //                 contractCalls.push({
    //                     ...oftContract,
    //                     functionName: 'isPeer',
    //                     args: [
    //                         chains[destChainName].peerId,
    //                         ofts[oAppName][srcChain][destChainName].peerAddressBytes32,
    //                     ],
    //                 })
    //             })

    //             const oftOptions = await chains[srcChain].client.multicall({
    //                 contracts: contractCalls,
    //             })

    //             // add to ofts
    //             Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName, index) => {
    //                 let oftres = oftOptions[index * 4]
    //                 let opt
    //                 if (oftres.result) {
    //                     opt = decodeLzReceiveOption(oftres.result)
    //                     ofts[oAppName][srcChain][destChainName].combinedOptionsSend = {} as OFTEnforcedOptions
    //                     if (oftres.result !== '0x') {
    //                         ofts[oAppName][srcChain][destChainName].combinedOptionsSend.gas = opt.gas.toString()
    //                         ofts[oAppName][srcChain][destChainName].combinedOptionsSend.value = opt.value.toString()
    //                     }
    //                 }
    //                 // TODO
    //                 // oftres = oftOptions[(index * 4) + 1]
    //                 // opt = decodeLzReceiveOption(oftres.result)
    //                 // ofts[destChainName].combinedOptionsSendAndCall = {} as OFTEnforceedOptions
    //                 // ofts[destChainName].combinedOptionsSendAndCall.gas = opt.gas.toString()
    //                 // ofts[destChainName].combinedOptionsSendAndCall.value = opt.value.toString()
    //                 oftres = oftOptions[index * 4 + 2]
    //                 if (oftres.result) {
    //                     ofts[oAppName][srcChain][destChainName].enforcedOptions = {} as OFTEnforcedOptions
    //                     if (oftres.result !== '0x') {
    //                         opt = decodeLzReceiveOption(oftres.result)
    //                         ofts[oAppName][srcChain][destChainName].enforcedOptions.gas = opt.gas.toString()
    //                         ofts[oAppName][srcChain][destChainName].enforcedOptions.value = opt.value.toString()
    //                     }
    //                 }
    //             })
    //         }

    //         // OFT
    //         // TODO oft.sharedDecimals : uint8
    //         // TODO oft.token : address

    //         // // endpoint.delegates (oapp (address)) : delegate address
    //         // contractCalls.push({
    //         //     ...endpointContract,
    //         //     functionName: "delegates",
    //         //     args: [USDT_lockbox],
    //         // });

    //         // endpoint
    //         let endpointContract: any
    //         if (srcChain !== 'solana') {
    //             // oft.endpoint : address
    //             const endpointAddress = await chains[srcChain].client.readContract({
    //                 address: oApp,
    //                 abi: OFT_ADAPTER_ABI,
    //                 functionName: 'endpoint',
    //             })
    //             endpointContract = {
    //                 address: endpointAddress,
    //                 abi: ENDPOINTV2_ABI,
    //             } as const
    //             if (srcChain !== 'ink') {
    //                 contractCalls = []
    //                 Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName) => {
    //                     // endpoint.defaultReceiveLibrary (srcEid (uint32)) : lib address
    //                     contractCalls.push({
    //                         ...endpointContract,
    //                         functionName: 'defaultReceiveLibrary',
    //                         args: [chains[destChainName].peerId],
    //                     })
    //                     // endpoint.defaultReceiveLibraryTimeout (srcEid (uint32)) : lib address, expiry uint256
    //                     contractCalls.push({
    //                         ...endpointContract,
    //                         functionName: 'defaultReceiveLibraryTimeout',
    //                         args: [chains[destChainName].peerId],
    //                     })
    //                     // endpoint.defaultSendLibrary (dstEid (uint32)) : lib address
    //                     contractCalls.push({
    //                         ...endpointContract,
    //                         functionName: 'defaultSendLibrary',
    //                         args: [chains[destChainName].peerId],
    //                     })
    //                 })

    //                 const endpointInfo = await chains[srcChain].client.multicall({
    //                     contracts: contractCalls,
    //                 })

    //                 // add to ofts
    //                 Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName, index) => {
    //                     let oftres = endpointInfo[index * 3]
    //                     ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary = oftres.result
    //                     oftres = endpointInfo[index * 3 + 1]
    //                     ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut =
    //                         {} as ReceiveLibraryTimeOutInfo
    //                     ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.libAddress =
    //                         oftres.result[0]
    //                     ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.expiry =
    //                         oftres.result[1].toString()
    //                     oftres = endpointInfo[index * 3 + 2]
    //                     ofts[oAppName][srcChain][destChainName].defaultSendLibrary = oftres.result
    //                 })
    //             } else {
    //                 // add to ofts
    //                 for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
    //                     let oftres = await chains[srcChain].client.readContract({
    //                         ...endpointContract,
    //                         functionName: 'defaultReceiveLibrary',
    //                         args: [chains[destChainName].peerId],
    //                     })
    //                     ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary = oftres
    //                     oftres = await chains[srcChain].client.readContract({
    //                         ...endpointContract,
    //                         functionName: 'defaultReceiveLibraryTimeout',
    //                         args: [chains[destChainName].peerId],
    //                     })
    //                     ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut =
    //                         {} as ReceiveLibraryTimeOutInfo
    //                     ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.libAddress = oftres[0]
    //                     ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.expiry =
    //                         oftres[1].toString()
    //                     oftres = await chains[srcChain].client.readContract({
    //                         ...endpointContract,
    //                         functionName: 'defaultSendLibrary',
    //                         args: [chains[destChainName].peerId],
    //                     })
    //                     ofts[oAppName][srcChain][destChainName].defaultSendLibrary = oftres
    //                 }
    //             }
    //         } else if (srcChain === 'solana') {
    //             // add to ofts
    //             // for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
    //             // let oftres = await oft302.li.getEndpointConfig(
    //             //     chains[srcChain].client.rpc,
    //             //     publicKey(solanaOFTs[oAppName].oftStore), //oftStore
    //             // chains[destChainName].peerId,
    //             // publicKey(solanaOFTs[oAppName].programId), //programId
    //             // )
    //             // let oftres = await chains[srcChain].client.readContract({
    //             //     ...endpointContract,
    //             //     functionName: "defaultReceiveLibrary",
    //             //     args: [chains[destChainName].peerId],
    //             // })
    //             // ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary = oftres
    //             // oftres = await chains[srcChain].client.readContract({
    //             //     ...endpointContract,
    //             //     functionName: "defaultReceiveLibraryTimeout",
    //             //     args: [chains[destChainName].peerId],
    //             // })
    //             // ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut = {} as ReceiveLibraryTimeOutInfo
    //             // ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.libAddress = oftres[0]
    //             // ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.expiry = oftres[1].toString()
    //             // oftres = await chains[srcChain].client.readContract({
    //             //     ...endpointContract,
    //             //     functionName: "defaultSendLibrary",
    //             //     args: [chains[destChainName].peerId],
    //             // })
    //             // ofts[oAppName][srcChain][destChainName].defaultSendLibrary = oftres
    //             // }
    //         }

    //         // TODO endpoint.eid : 30101 uint32
    //         // TODO endpoint.getRegisteredLibraries : address[]

    //         if (srcChain !== 'ink') {
    //             contractCalls = []
    //             Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName) => {
    //                 // endpoint.getReceiveLibrary (_receiver (address), _srcEid (uint32)) : lib address, isDefault bool
    //                 contractCalls.push({
    //                     ...endpointContract,
    //                     functionName: 'getReceiveLibrary',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 // endpoint.getSendLibrary (_sender (address),_dstEid (uint32)) : lib address
    //                 contractCalls.push({
    //                     ...endpointContract,
    //                     functionName: 'getSendLibrary',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 // endpoint.isDefaultSendLibrary (_sender (address),_dstEid (uint32)) : bool
    //                 contractCalls.push({
    //                     ...endpointContract,
    //                     functionName: 'isDefaultSendLibrary',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 // endpoint.receiveLibraryTimeout (receiver (address), srcEid (uint32)) : lib address, expiry uint256
    //                 contractCalls.push({
    //                     ...endpointContract,
    //                     functionName: 'receiveLibraryTimeout',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //             })

    //             // TODO endpoint.getSendContext : eid uint32, sender address

    //             const endpointInfo2 = await chains[srcChain].client.multicall({
    //                 contracts: contractCalls,
    //             })

    //             // add to ofts
    //             Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName, index) => {
    //                 ofts[oAppName][srcChain][destChainName].receiveLibrary = {} as ReceiveLibraryType
    //                 ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut = {} as ReceiveLibraryTimeOutInfo
    //                 // let oftres = endpointInfo2[index * 6]
    //                 // let decoded = decodeUlnConfig(oftres.result)
    //                 // ofts[oAppName][srcChain][destChainName].config.receive.confirmations = Number(decoded.confirmations)
    //                 // ofts[oAppName][srcChain][destChainName].config.receive.requiredDVNCount = decoded.requiredDVNCount
    //                 // ofts[oAppName][srcChain][destChainName].config.receive.optionalDVNCount = decoded.optionalDVNCount
    //                 // ofts[oAppName][srcChain][destChainName].config.receive.optionalDVNThreshold = decoded.optionalDVNThreshold
    //                 // oftres = endpointInfo2[(index * 6) + 1]
    //                 // decoded = decodeUlnConfig(oftres.result)
    //                 // ofts[oAppName][srcChain][destChainName].config.send.confirmations = Number(decoded.confirmations)
    //                 // ofts[oAppName][srcChain][destChainName].config.send.requiredDVNCount = decoded.requiredDVNCount
    //                 // ofts[oAppName][srcChain][destChainName].config.send.optionalDVNCount = decoded.optionalDVNCount
    //                 // ofts[oAppName][srcChain][destChainName].config.send.optionalDVNThreshold = decoded.optionalDVNThreshold
    //                 let oftres = endpointInfo2[index * 4]
    //                 ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress = oftres.result[0]
    //                 ofts[oAppName][srcChain][destChainName].receiveLibrary.isDefault = oftres.result[1]
    //                 oftres = endpointInfo2[index * 4 + 1]
    //                 ofts[oAppName][srcChain][destChainName].sendLibrary = oftres.result
    //                 oftres = endpointInfo2[index * 4 + 2]
    //                 ofts[oAppName][srcChain][destChainName].isDefaultSendLibrary = oftres.result
    //                 oftres = endpointInfo2[index * 4 + 3]
    //                 ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut.libAddress = oftres.result[0]
    //                 ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut.expiry = oftres.result[1].toString()
    //             })
    //         } else {
    //             // add to ofts
    //             for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
    //                 // endpoint.getReceiveLibrary (_receiver (address), _srcEid (uint32)) : lib address, isDefault bool
    //                 contractCalls.push()
    //                 // endpoint.getSendLibrary (_sender (address),_dstEid (uint32)) : lib address
    //                 contractCalls.push()
    //                 // endpoint.isDefaultSendLibrary (_sender (address),_dstEid (uint32)) : bool
    //                 contractCalls.push()
    //                 // endpoint.receiveLibraryTimeout (receiver (address), srcEid (uint32)) : lib address, expiry uint256
    //                 contractCalls.push()
    //                 ofts[oAppName][srcChain][destChainName].receiveLibrary = {} as ReceiveLibraryType
    //                 ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut = {} as ReceiveLibraryTimeOutInfo

    //                 let oftres = await chains[srcChain].client.readContract({
    //                     ...endpointContract,
    //                     functionName: 'getReceiveLibrary',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress = oftres[0]
    //                 ofts[oAppName][srcChain][destChainName].receiveLibrary.isDefault = oftres[1]
    //                 oftres = await chains[srcChain].client.readContract({
    //                     ...endpointContract,
    //                     functionName: 'getSendLibrary',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].sendLibrary = oftres
    //                 oftres = await chains[srcChain].client.readContract({
    //                     ...endpointContract,
    //                     functionName: 'isDefaultSendLibrary',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].isDefaultSendLibrary = oftres
    //                 oftres = await chains[srcChain].client.readContract({
    //                     ...endpointContract,
    //                     functionName: 'receiveLibraryTimeout',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut.libAddress = oftres[0]
    //                 ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut.expiry = oftres[1].toString()
    //             }
    //         }

    //         // ReceiveUln302
    //         if (srcChain !== 'ink') {
    //             contractCalls = []
    //             Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName) => {
    //                 // receiveUln302.getAppUlnConfig (_oapp (address), _remoteEid (uint32)) : tuple
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'getAppUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'getAppUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 // receiveUln302.getUlnConfig (_oapp (address), _remoteEid (uint32)) : rtnConfig tuple
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'getUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'getUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 // receiveUln302.isSupportedEid (_eid (uint32)) : bool
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'isSupportedEid',
    //                     args: [chains[destChainName].peerId],
    //                 })
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'isSupportedEid',
    //                     args: [chains[destChainName].peerId],
    //                 })
    //             })

    //             const receiveULN302Info = await chains[srcChain].client.multicall({
    //                 contracts: contractCalls,
    //             })

    //             // add to ofts
    //             Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName, index) => {
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig = {} as EndpointConfig
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive = {} as UlnConfig
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig = {} as EndpointConfig
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive = {} as UlnConfig

    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig = {} as EndpointConfig
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive = {} as UlnConfig
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig = {} as EndpointConfig
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive = {} as UlnConfig

    //                 let oftres = receiveULN302Info[index * 6]
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.confirmations = Number(
    //                     oftres.result.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.requiredDVNCount =
    //                     oftres.result.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNCount =
    //                     oftres.result.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNThreshold =
    //                     oftres.result.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.requiredDVNs = [
    //                     ...oftres.result.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNs = [
    //                     ...oftres.result.optionalDVNs,
    //                 ]
    //                 oftres = receiveULN302Info[index * 6 + 1]
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.confirmations = Number(
    //                     oftres.result.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.requiredDVNCount =
    //                     oftres.result.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNCount =
    //                     oftres.result.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNThreshold =
    //                     oftres.result.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.requiredDVNs = [
    //                     ...oftres.result.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNs = [
    //                     ...oftres.result.optionalDVNs,
    //                 ]
    //                 oftres = receiveULN302Info[index * 6 + 2]
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.confirmations = Number(
    //                     oftres.result.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.requiredDVNCount =
    //                     oftres.result.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNCount =
    //                     oftres.result.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNThreshold =
    //                     oftres.result.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.requiredDVNs = [
    //                     ...oftres.result.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNs = [
    //                     ...oftres.result.optionalDVNs,
    //                 ]
    //                 oftres = receiveULN302Info[index * 6 + 3]
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.confirmations = Number(
    //                     oftres.result.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.requiredDVNCount =
    //                     oftres.result.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNCount =
    //                     oftres.result.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNThreshold =
    //                     oftres.result.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.requiredDVNs = [
    //                     ...oftres.result.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNs = [
    //                     ...oftres.result.optionalDVNs,
    //                 ]
    //                 oftres = receiveULN302Info[index * 6 + 4]
    //                 ofts[oAppName][srcChain][destChainName].defaultReceiveLibSupportEid = oftres.result
    //                 oftres = receiveULN302Info[index * 6 + 5]
    //                 ofts[oAppName][srcChain][destChainName].receiveLibSupportEid = oftres.result
    //             })
    //         } else {
    //             for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig = {} as EndpointConfig
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive = {} as UlnConfig
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig = {} as EndpointConfig
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive = {} as UlnConfig

    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig = {} as EndpointConfig
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive = {} as UlnConfig
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig = {} as EndpointConfig
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive = {} as UlnConfig

    //                 let oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'getAppUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.confirmations = Number(
    //                     oftres.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.requiredDVNCount =
    //                     oftres.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNCount =
    //                     oftres.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNThreshold =
    //                     oftres.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.requiredDVNs = [
    //                     ...oftres.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNs = [
    //                     ...oftres.optionalDVNs,
    //                 ]

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'getAppUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.confirmations = Number(
    //                     oftres.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.requiredDVNCount =
    //                     oftres.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNCount =
    //                     oftres.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNThreshold =
    //                     oftres.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.requiredDVNs = [...oftres.requiredDVNs]
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNs = [...oftres.optionalDVNs]

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'getUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.confirmations = Number(
    //                     oftres.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.requiredDVNCount = oftres.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNCount = oftres.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNThreshold =
    //                     oftres.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.requiredDVNs = [...oftres.requiredDVNs]
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNs = [...oftres.optionalDVNs]

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'getUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.confirmations = Number(
    //                     oftres.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.requiredDVNCount =
    //                     oftres.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNCount =
    //                     oftres.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNThreshold =
    //                     oftres.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.requiredDVNs = [
    //                     ...oftres.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNs = [
    //                     ...oftres.optionalDVNs,
    //                 ]

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'isSupportedEid',
    //                     args: [chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].defaultReceiveLibSupportEid = oftres

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
    //                     abi: RECEIVE_ULN302_ABI,
    //                     functionName: 'isSupportedEid',
    //                     args: [chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].receiveLibSupportEid = oftres
    //             }
    //         }

    //         // SendUln302
    //         if (srcChain !== 'ink') {
    //             contractCalls = []
    //             Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName) => {
    //                 // senduln302.getAppUlnConfig (_oapp (address), _remoteEid (uint32)) : tuple
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getAppUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].sendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getAppUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 // senduln302.getExecutorConfig (_oapp (address) , _remoteEid (uint32)) :  rtnConfig tuple
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getExecutorConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].sendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getExecutorConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 // senduln302.getUlnConfig (_oapp (address), _remoteEid (uint32)) : rtnConfig tuple
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].sendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 // senduln302.isSupportedEid (_eid (uint32)) : bool
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'isSupportedEid',
    //                     args: [chains[destChainName].peerId],
    //                 })
    //                 contractCalls.push({
    //                     address: ofts[oAppName][srcChain][destChainName].sendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'isSupportedEid',
    //                     args: [chains[destChainName].peerId],
    //                 })
    //             })

    //             const sendULN302Info = await chains[srcChain].client.multicall({
    //                 contracts: contractCalls,
    //             })

    //             // add to ofts
    //             Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName, index) => {
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send = {} as UlnConfig
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send = {} as UlnConfig

    //                 ofts[oAppName][srcChain][destChainName].defaultExecutorConfig = {} as ExecutorConfigType
    //                 ofts[oAppName][srcChain][destChainName].executorConfig = {} as ExecutorConfigType

    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send = {} as UlnConfig
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send = {} as UlnConfig

    //                 let oftres = sendULN302Info[index * 8]
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.confirmations = Number(
    //                     oftres.result.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.requiredDVNCount =
    //                     oftres.result.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNCount =
    //                     oftres.result.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNThreshold =
    //                     oftres.result.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.requiredDVNs = [
    //                     ...oftres.result.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNs = [
    //                     ...oftres.result.optionalDVNs,
    //                 ]

    //                 oftres = sendULN302Info[index * 8 + 1]
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.confirmations = Number(
    //                     oftres.result.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.requiredDVNCount =
    //                     oftres.result.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNCount =
    //                     oftres.result.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNThreshold =
    //                     oftres.result.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.requiredDVNs = [
    //                     ...oftres.result.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNs = [
    //                     ...oftres.result.optionalDVNs,
    //                 ]

    //                 oftres = sendULN302Info[index * 8 + 2]
    //                 ofts[oAppName][srcChain][destChainName].defaultExecutorConfig.maxMessageSize =
    //                     oftres.result.maxMessageSize
    //                 ofts[oAppName][srcChain][destChainName].defaultExecutorConfig.executorAddress =
    //                     oftres.result.executor

    //                 oftres = sendULN302Info[index * 8 + 3]
    //                 ofts[oAppName][srcChain][destChainName].executorConfig.maxMessageSize = oftres.result.maxMessageSize
    //                 ofts[oAppName][srcChain][destChainName].executorConfig.executorAddress = oftres.result.executor

    //                 oftres = sendULN302Info[index * 8 + 4]
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.confirmations = Number(
    //                     oftres.result.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.requiredDVNCount =
    //                     oftres.result.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNCount =
    //                     oftres.result.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNThreshold =
    //                     oftres.result.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.requiredDVNs = [
    //                     ...oftres.result.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNs = [
    //                     ...oftres.result.optionalDVNs,
    //                 ]

    //                 oftres = sendULN302Info[index * 8 + 5]
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.confirmations = Number(
    //                     oftres.result.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.requiredDVNCount =
    //                     oftres.result.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNCount =
    //                     oftres.result.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNThreshold =
    //                     oftres.result.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.requiredDVNs = [
    //                     ...oftres.result.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNs = [
    //                     ...oftres.result.optionalDVNs,
    //                 ]

    //                 oftres = sendULN302Info[index * 8 + 6]
    //                 ofts[oAppName][srcChain][destChainName].defaultSendLibSupportEid = oftres.result

    //                 oftres = sendULN302Info[index * 8 + 7]
    //                 ofts[oAppName][srcChain][destChainName].sendLibSupportEid = oftres.result
    //             })
    //         } else {
    //             // add to ofts
    //             for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send = {} as UlnConfig
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send = {} as UlnConfig

    //                 ofts[oAppName][srcChain][destChainName].defaultExecutorConfig = {} as ExecutorConfigType
    //                 ofts[oAppName][srcChain][destChainName].executorConfig = {} as ExecutorConfigType

    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send = {} as UlnConfig
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send = {} as UlnConfig

    //                 let oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getAppUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.confirmations = Number(
    //                     oftres.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.requiredDVNCount =
    //                     oftres.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNCount =
    //                     oftres.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNThreshold =
    //                     oftres.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.requiredDVNs = [
    //                     ...oftres.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNs = [
    //                     ...oftres.optionalDVNs,
    //                 ]

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].sendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getAppUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.confirmations = Number(
    //                     oftres.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.requiredDVNCount = oftres.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNCount = oftres.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNThreshold =
    //                     oftres.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.requiredDVNs = [...oftres.requiredDVNs]
    //                 ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNs = [...oftres.optionalDVNs]

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getExecutorConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].defaultExecutorConfig.maxMessageSize = oftres.maxMessageSize
    //                 ofts[oAppName][srcChain][destChainName].defaultExecutorConfig.executorAddress = oftres.executor

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].sendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getExecutorConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].executorConfig.maxMessageSize = oftres.maxMessageSize
    //                 ofts[oAppName][srcChain][destChainName].executorConfig.executorAddress = oftres.executor

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.confirmations = Number(
    //                     oftres.confirmations
    //                 )
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.requiredDVNCount =
    //                     oftres.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNCount =
    //                     oftres.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNThreshold =
    //                     oftres.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.requiredDVNs = [
    //                     ...oftres.requiredDVNs,
    //                 ]
    //                 ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNs = [
    //                     ...oftres.optionalDVNs,
    //                 ]

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].sendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'getUlnConfig',
    //                     args: [oApp, chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.confirmations = Number(oftres.confirmations)
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.requiredDVNCount = oftres.requiredDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNCount = oftres.optionalDVNCount
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNThreshold =
    //                     oftres.optionalDVNThreshold
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.requiredDVNs = [...oftres.requiredDVNs]
    //                 ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNs = [...oftres.optionalDVNs]

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'isSupportedEid',
    //                     args: [chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].defaultSendLibSupportEid = oftres.result

    //                 oftres = await chains[srcChain].client.readContract({
    //                     address: ofts[oAppName][srcChain][destChainName].sendLibrary,
    //                     abi: SEND_ULN302_ABI,
    //                     functionName: 'isSupportedEid',
    //                     args: [chains[destChainName].peerId],
    //                 })
    //                 ofts[oAppName][srcChain][destChainName].sendLibSupportEid = oftres.result
    //             }
    //         }
    //     }
    // }
    // // Assuming `ofts` is already defined
    // fs.writeFileSync('config-all.json', JSON.stringify(ofts, null, 2), 'utf-8')

    // console.log('Data written to output.json')
}

main()
