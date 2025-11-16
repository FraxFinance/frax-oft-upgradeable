import { getAddress, zeroAddress } from 'viem'
// import { publicKey } from '@metaplex-foundation/umi'
// import { oft302 } from '@layerzerolabs/oft-v2-solana-sdk'
import { fetchMetadataFromSeeds } from '@metaplex-foundation/mpl-token-metadata'
import { publicKey } from '@metaplex-foundation/umi'
import { default as ENDPOINTV2_ABI } from '../abis/ENDPOINTV2_ABI.json'
import { default as OFT_MINTABLE_ADAPTER_ABI } from '../abis/OFT_MINTABLE_ADAPTER_ABI.json'
import { default as RECEIVE_ULN302_ABI } from '../abis/RECEIVE_ULN302_ABI.json'
import { default as SEND_ULN302_ABI } from '../abis/SEND_ULN302_ABI.json'
import { default as FRAX_PROXY_ADMIN_ABI } from '../abis/FRAX_PROXY_ADMIN_ABI.json'
import fs from 'fs'
import * as dotenv from 'dotenv'
import { chains } from '../chains'
import {
    ChainConfig,
    DstChainConfig,
    EndpointConfig,
    ExecutorConfigType,
    OFTEnforcedOptions,
    OFTInfo,
    Params,
    ReceiveLibraryTimeOutInfo,
    ReceiveLibraryType,
    SrcChainConfig,
    TokenConfig,
    UlnConfig,
} from '../types'
import { aptosMovementOFTs, ofts, solanaOFTs } from '../oft'
import bs58 from 'bs58'
import { Options } from '@layerzerolabs/lz-v2-utilities'

dotenv.config()

const bytes32Zero = '0x0000000000000000000000000000000000000000000000000000000000000000'

export function decodeLzReceiveOption(hex: string): { gas: number; value: number } {
    try {
        // Handle empty/undefined values first
        if (!hex || hex === '0x') throw new Error('No Options Set')
        const options = Options.fromOptions(hex)
        const lzReceiveOpt = options.decodeExecutorLzReceiveOption()
        if (!lzReceiveOpt) throw new Error('No executor options')

        return {
            gas: Number(lzReceiveOpt.gas),
            value: Number(lzReceiveOpt.value),
        }
    } catch (e) {
        throw new Error(`Invalid options (${hex.slice(0, 12)}...)`)
    }
}

function generateWiringMatrix(oftConnectionObj: ChainConfig): string {
    const chains = Object.keys(oftConnectionObj)
    const matrix: string[][] = []

    // Header row
    matrix.push(['', ...chains])

    for (const srcChain of chains) {
        const row: string[] = [srcChain]

        for (const dstChain of chains) {
            if (
                srcChain === 'aptos' ||
                srcChain === 'solana' ||
                srcChain === 'movement' ||
                dstChain === 'aptos' ||
                dstChain === 'solana' ||
                dstChain === 'movement'
            ) {
                continue
            }
            if (srcChain === dstChain) {
                row.push('-')
                continue
            }

            const src = oftConnectionObj[srcChain]
            const dst = oftConnectionObj[dstChain]

            const srcDstConfig = src.dstChains?.[dstChain]
            const dstSrcConfig = dst.dstChains?.[srcChain]

            if (!srcDstConfig || !dstSrcConfig) {
                row.push('-')
                continue
            }

            const srcOft = getAddress(src.params.oftProxy)
            const dstOft = getAddress(dst.params.oftProxy)
            const srcOftOnDst = getAddress(dstSrcConfig.peerAddress || zeroAddress)
            const dstOftOnSrc = getAddress(srcDstConfig.peerAddress || zeroAddress)

            const srcSendLib = getAddress(srcDstConfig.sendLibrary || zeroAddress)
            const srcBlockedLib = getAddress(srcDstConfig.blockedLib || zeroAddress)
            const dstSendLib = getAddress(dstSrcConfig.sendLibrary || zeroAddress)
            const dstBlockedLib = getAddress(dstSrcConfig.blockedLib || zeroAddress)

            let status = '?'

            if (srcOft !== srcOftOnDst && dstOft !== dstOftOnSrc) {
                status = '-'
            } else if (srcOft === srcOftOnDst && dstOft === dstOftOnSrc) {
                if (srcSendLib !== srcBlockedLib && dstSendLib !== dstBlockedLib) {
                    status = 'X'
                } else if (srcSendLib === srcBlockedLib) {
                    status = 'B-'
                } else if (dstSendLib === dstBlockedLib) {
                    status = '-B'
                } else {
                    status = '?'
                }
            } else if (srcOft === srcOftOnDst) {
                status = 'W-'
            } else if (dstOft === dstOftOnSrc) {
                status = '-W'
            } else {
                status = '?'
            }

            row.push(status)
        }

        matrix.push(row)
    }

    // Convert to CSV string
    return matrix.map((row) => row.join(',')).join('\n')
}

function isWiredX(config: ChainConfig, srcChain: string, dstChain: string): boolean {
    const src = config[srcChain]
    const dst = config[dstChain]
    if (!src || !dst) return false

    const srcDst = src.dstChains?.[dstChain]
    const dstSrc = dst.dstChains?.[srcChain]
    if (!srcDst || !dstSrc) return false

    const srcOft = src.params.oftProxy
    const dstOft = dst.params.oftProxy
    const srcOftOnDst = getAddress(dstSrc.peerAddress || zeroAddress)
    const dstOftOnSrc = getAddress(srcDst.peerAddress || zeroAddress)

    const srcSendLib = getAddress(srcDst.sendLibrary || zeroAddress)
    const srcBlockedLib = getAddress(srcDst.blockedLib || zeroAddress)
    const dstSendLib = getAddress(dstSrc.sendLibrary || zeroAddress)
    const dstBlockedLib = getAddress(dstSrc.blockedLib || zeroAddress)

    return (
        srcOft === srcOftOnDst && dstOft === dstOftOnSrc && srcSendLib !== srcBlockedLib && dstSendLib !== dstBlockedLib
    )
}

function generateUlnAndDvnComparisonCSV(config: ChainConfig): string {
    const chains = Object.keys(config)
    const rows: string[][] = []

    rows.push([
        'srcChain',
        'dstChain',

        'receive.confirmations (default)',
        'receive.confirmations (app)',
        'receive.requiredDVNCount (default)',
        'receive.requiredDVNCount (app)',
        'receive.optionalDVNCount (default)',
        'receive.optionalDVNCount (app)',
        'receive.optionalDVNThreshold (default)',
        'receive.optionalDVNThreshold (app)',
        'receive.requiredDVNs (default)',
        'receive.requiredDVNs (app)',
        'receive.optionalDVNs (default)',
        'receive.optionalDVNs (app)',

        '',

        'send.confirmations (default)',
        'send.confirmations (app)',
        'send.requiredDVNCount (default)',
        'send.requiredDVNCount (app)',
        'send.optionalDVNCount (default)',
        'send.optionalDVNCount (app)',
        'send.optionalDVNThreshold (default)',
        'send.optionalDVNThreshold (app)',
        'send.requiredDVNs (default)',
        'send.requiredDVNs (app)',
        'send.optionalDVNs (default)',
        'send.optionalDVNs (app)',
    ])

    const safeJoin = (arr?: string[]) => (arr?.length ? arr.join(';') : '-')

    for (const srcChain of chains) {
        for (const dstChain of chains) {
            if (
                srcChain === 'aptos' ||
                srcChain === 'solana' ||
                srcChain === 'movement' ||
                dstChain === 'aptos' ||
                dstChain === 'solana' ||
                dstChain === 'movement'
            ) {
                continue
            }
            if (srcChain === dstChain) continue
            if (!isWiredX(config, srcChain, dstChain)) continue // only wired pairs

            const src = config[srcChain]
            const dstCfg = src.dstChains[dstChain]
            const app = dstCfg.appUlnConfig
            const def = dstCfg.defaultUlnConfig

            const rApp = app?.receive || {}
            const rDef = def?.receive || {}
            const sApp = app?.send || {}
            const sDef = def?.send || {}

            rows.push([
                srcChain,
                dstChain,

                // Receive
                rDef.confirmations?.toString() ?? '-',
                rApp.confirmations?.toString() ?? '-',
                rDef.requiredDVNCount?.toString() ?? '-',
                rApp.requiredDVNCount?.toString() ?? '-',
                rDef.optionalDVNCount?.toString() ?? '-',
                rApp.optionalDVNCount?.toString() ?? '-',
                rDef.optionalDVNThreshold?.toString() ?? '-',
                rApp.optionalDVNThreshold?.toString() ?? '-',
                safeJoin(rDef.requiredDVNs),
                safeJoin(rApp.requiredDVNs),
                safeJoin(rDef.optionalDVNs),
                safeJoin(rApp.optionalDVNs),

                '',

                // Send
                sDef.confirmations?.toString() ?? '-',
                sApp.confirmations?.toString() ?? '-',
                sDef.requiredDVNCount?.toString() ?? '-',
                sApp.requiredDVNCount?.toString() ?? '-',
                sDef.optionalDVNCount?.toString() ?? '-',
                sApp.optionalDVNCount?.toString() ?? '-',
                sDef.optionalDVNThreshold?.toString() ?? '-',
                sApp.optionalDVNThreshold?.toString() ?? '-',
                safeJoin(sDef.requiredDVNs),
                safeJoin(sApp.requiredDVNs),
                safeJoin(sDef.optionalDVNs),
                safeJoin(sApp.optionalDVNs),
            ])
        }
    }

    return rows.map((r) => r.join(',')).join('\n')
}

export function generateEnforcedOptionsCSV(config: ChainConfig): string {
    const chains = Object.keys(config)
    const rows: string[][] = []

    rows.push([
        'srcChain',
        'dstChain',
        'enforcedOptionsSend.gas',
        'enforcedOptionsSend.value',
        '',
        'enforcedOptionsSendAndCall.gas',
        'enforcedOptionsSendAndCall.value',
    ])

    for (const srcChain of chains) {
        for (const dstChain of chains) {
            if (
                srcChain === 'aptos' ||
                srcChain === 'solana' ||
                srcChain === 'movement' ||
                dstChain === 'aptos' ||
                dstChain === 'solana' ||
                dstChain === 'movement'
            ) {
                continue
            }
            if (srcChain === dstChain) continue
            if (!isWiredX(config, srcChain, dstChain)) continue

            const src = config[srcChain]
            const dstCfg = src.dstChains[dstChain]

            const eos = dstCfg.enforcedOptionsSend ?? {}
            const eosac = dstCfg.enforcedOptionsSendAndCall ?? {}

            const asStr = (v?: string | number) => (v !== undefined ? String(v) : '-')

            rows.push([srcChain, dstChain, asStr(eos.gas), asStr(eos.value), '', asStr(eosac.gas), asStr(eosac.value)])
        }
    }

    return rows.map((r) => r.join(',')).join('\n')
}

export function generateExecutorConfigCSV(config: ChainConfig): string {
    const chains = Object.keys(config)
    const rows: string[][] = []

    // Header
    rows.push([
        'srcChain',
        'dstChain',
        'defaultExecutorConfig.maxMessageSize',
        'defaultExecutorConfig.executorAddress',
        '',
        'executorConfig.maxMessageSize',
        'executorConfig.executorAddress',
    ])

    const asStr = (v?: string | number) => (v !== undefined ? String(v) : '-')

    for (const srcChain of chains) {
        for (const dstChain of chains) {
            if (
                srcChain === 'aptos' ||
                srcChain === 'solana' ||
                srcChain === 'movement' ||
                dstChain === 'aptos' ||
                dstChain === 'solana' ||
                dstChain === 'movement'
            ) {
                continue
            }
            if (srcChain === dstChain) continue
            if (!isWiredX(config, srcChain, dstChain)) continue

            const dstCfg = config[srcChain]?.dstChains?.[dstChain]
            if (!dstCfg) continue

            const def = dstCfg.defaultExecutorConfig ?? {}
            const app = dstCfg.executorConfig ?? {}

            rows.push([
                srcChain,
                dstChain,
                asStr(def.maxMessageSize),
                asStr(def.executorAddress),
                '',
                asStr(app.maxMessageSize),
                asStr(app.executorAddress),
            ])
        }
    }

    return rows.map((r) => r.join(',')).join('\n')
}

function deepCopy<T>(obj: T): T {
    if (obj === null || typeof obj !== 'object') {
        if (typeof obj === 'bigint') {
            return Number(obj) as T
        }
        return obj
    }

    if (Array.isArray(obj)) {
        return obj.map(deepCopy) as unknown as T
    }

    const newObj: any = {}
    for (const key in obj) {
        if (obj.hasOwnProperty(key)) {
            newObj[key] = deepCopy(obj[key])
        }
    }
    return newObj
}

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
                oftObj[oftName][srcChain].params.oftProxy = solanaOFTs[oftName].mint
                oftObj[oftName][srcChain].params.expectedEndpoint = chains[srcChain].endpoint
                // TODO : actual endpoint
                const initialMetadata = await fetchMetadataFromSeeds(chains[srcChain].client, {
                    mint: publicKey(solanaOFTs[oftName].mint),
                })
                oftObj[oftName][srcChain].params.owner = initialMetadata.updateAuthority
            } else if (srcChain === 'aptos' || srcChain === 'movement') {
            } else if (srcChain === 'plasma' || srcChain === 'katana' || srcChain === 'stable') {
                oftObj[oftName][srcChain].params.oftProxy = ofts[srcChain][oftName].address
                oftObj[oftName][srcChain].params.expectedEndpoint = chains[srcChain].endpoint
                try {
                    const endpointAddress = await chains[srcChain].client.readContract({
                        address: ofts[srcChain][oftName].address,
                        abi: OFT_MINTABLE_ADAPTER_ABI,
                        functionName: 'endpoint',
                    })
                    oftObj[oftName][srcChain].params.actualEndpoint = endpointAddress
                } catch (e) {
                    console.log(`${oftName}:${srcChain}:oft(${ofts[srcChain][oftName].address}).endpoint()`)
                }
                try {
                    const ownerAddress = await chains[srcChain].client.readContract({
                        address: ofts[srcChain][oftName].address,
                        abi: OFT_MINTABLE_ADAPTER_ABI,
                        functionName: 'owner',
                    })
                    oftObj[oftName][srcChain].params.owner = ownerAddress
                } catch (e) {
                    console.log(`${oftName}:${srcChain}:oft(${ofts[srcChain][oftName].address}).owner()`)
                }
                try {
                    const expectedImplementationAddress = await chains[srcChain].client.readContract({
                        address: chains[srcChain].fraxProxyAdmin,
                        abi: FRAX_PROXY_ADMIN_ABI,
                        functionName: 'getProxyImplementation',
                        args: [ofts[srcChain][oftName].address],
                    })
                    oftObj[oftName][srcChain].params.expectedImplementation = expectedImplementationAddress
                } catch (e) {
                    console.log(
                        `${oftName}:${srcChain}:proxyAdmin(${chains[srcChain].fraxProxyAdmin}).getProxyImplementation(${ofts[srcChain][oftName].address})`
                    )
                }
                try {
                    const expectedProxyAdminAddress = await chains[srcChain].client.readContract({
                        address: chains[srcChain].fraxProxyAdmin,
                        abi: FRAX_PROXY_ADMIN_ABI,
                        functionName: 'getProxyAdmin',
                        args: [ofts[srcChain][oftName].address],
                    })
                    oftObj[oftName][srcChain].params.expectedProxyAdmin = expectedProxyAdminAddress
                } catch (e) {
                    console.log(
                        `${oftName}:${srcChain}:proxyAdmin(${chains[srcChain].fraxProxyAdmin}).getProxyAdmin(${ofts[srcChain][oftName].address})`
                    )
                }

                // TODO : actualImplementationAddress : get from OFT Proxy contract
                // get storage at : 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
                // TODO : actualProxyAdminAddress : get from OFT proxy contract
                // get storage at : 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
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
            srcChain !== 'katana' &&
            srcChain !== 'stable'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []

            Object.keys(ofts[srcChain]).forEach((oftName, index) => {
                oftObj[oftName][srcChain].params.oftProxy = ofts[srcChain][oftName].address
                oftObj[oftName][srcChain].params.expectedEndpoint = chains[srcChain].endpoint
                // 0 -> endpoint
                if (authParams[index * 4].status === 'success') {
                    oftObj[oftName][srcChain].params.actualEndpoint = authParams[index * 4].result
                } else {
                    console.log(`${oftName}:${srcChain}:oft(${ofts[srcChain][oftName].address}).endpoint()`)
                }
                // 1 -> owner
                if (authParams[index * 4 + 1].status === 'success') {
                    oftObj[oftName][srcChain].params.owner = authParams[index * 4 + 1].result
                } else {
                    console.log(`${oftName}:${srcChain}:oft${ofts[srcChain][oftName].address}.owner()`)
                }
                // 2 -> expectedImplementation
                if (authParams[index * 4 + 2].status === 'success') {
                    oftObj[oftName][srcChain].params.expectedImplementation = authParams[index * 4 + 2].result
                } else {
                    console.log(
                        `${oftName}:${srcChain}:proxyAdmin${chains[srcChain].fraxProxyAdmin}.getProxyImplementation(${ofts[srcChain][oftName].address})`
                    )
                }
                // 3 -> expectedProxyAdmin
                if (authParams[index * 4 + 3].status === 'success') {
                    oftObj[oftName][srcChain].params.expectedProxyAdmin = authParams[index * 4 + 3].result
                } else {
                    console.log(
                        `${oftName}:${srcChain}:proxyAdmin(${chains[srcChain].fraxProxyAdmin}).getProxyAdmin(${ofts[srcChain][oftName].address})`
                    )
                }
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
            } else if (srcChain === 'plasma' || srcChain === 'katana' || srcChain === 'stable') {
                try {
                    const delegateAddress = await chains[srcChain].client.readContract({
                        address: oftObj[oftName][srcChain].params.actualEndpoint,
                        abi: ENDPOINTV2_ABI,
                        functionName: 'delegates',
                        args: [ofts[srcChain][oftName].address],
                    })
                    oftObj[oftName][srcChain].params.delegate = delegateAddress
                } catch (e) {
                    console.log(
                        `${oftName}:${srcChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).delegates(${ofts[srcChain][oftName].address})`
                    )
                }

                try {
                    const ownerMsigThreshold = await chains[srcChain].client.readContract({
                        address: oftObj[oftName][srcChain].params.owner,
                        abi: MSIG_ABI,
                        functionName: 'getThreshold',
                    })
                    oftObj[oftName][srcChain].params.ownerThreshold = Number(ownerMsigThreshold).toString()
                } catch (e) {
                    console.log(`${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.owner}).getThreshold()`)
                }

                try {
                    const ownerMsigMembers = await chains[srcChain].client.readContract({
                        address: oftObj[oftName][srcChain].params.owner,
                        abi: MSIG_ABI,
                        functionName: 'getOwners',
                    })
                    oftObj[oftName][srcChain].params.ownerMembers = ownerMsigMembers
                } catch (e) {
                    console.log(`${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.owner}).getOwners()`)
                }

                try {
                    const proxyAdminOwner = await chains[srcChain].client.readContract({
                        address: oftObj[oftName][srcChain].params.expectedProxyAdmin,
                        abi: FRAX_PROXY_ADMIN_ABI,
                        functionName: 'owner',
                    })
                    oftObj[oftName][srcChain].params.proxyAdminOwner = proxyAdminOwner
                } catch (e) {
                    console.log(
                        `${oftName}:${srcChain}:proxyAdmin(${oftObj[oftName][srcChain].params.expectedProxyAdmin}).owner()`
                    )
                }
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
            srcChain !== 'katana' &&
            srcChain !== 'stable'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []

            Object.keys(ofts[srcChain]).forEach((oftName, index) => {
                // 0 -> delegate
                if (authParams[index * 4].status === 'success') {
                    oftObj[oftName][srcChain].params.delegate = authParams[index * 4].result
                } else {
                    console.log(
                        `${oftName}:${srcChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).delegates(${ofts[srcChain][oftName].address})`
                    )
                }
                // 1 -> owner msig threshold
                if (authParams[index * 4 + 1].status === 'success') {
                    oftObj[oftName][srcChain].params.ownerThreshold = Number(
                        authParams[index * 4 + 1].result
                    ).toString()
                } else {
                    console.log(`${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.owner}).getThreshold()`)
                }
                // 2 -> owner msig members
                if (authParams[index * 4 + 2].status === 'success') {
                    oftObj[oftName][srcChain].params.ownerMembers = authParams[index * 4 + 2].result
                } else {
                    console.log(`${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.owner}).getOwners()`)
                }
                // 3 -> proxyAdmin owner
                if (authParams[index * 4 + 3].status === 'success') {
                    oftObj[oftName][srcChain].params.proxyAdminOwner = authParams[index * 4 + 3].result
                } else {
                    console.log(
                        `${oftName}:${srcChain}:proxyAdmin(${oftObj[oftName][srcChain].params.expectedProxyAdmin}).owner()`
                    )
                }
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
            } else if (srcChain === 'plasma' || srcChain === 'katana' || srcChain === 'stable') {
                try {
                    const delegateMsigThreshold = await chains[srcChain].client.readContract({
                        address: oftObj[oftName][srcChain].params.delegate,
                        abi: MSIG_ABI,
                        functionName: 'getThreshold',
                    })
                    oftObj[oftName][srcChain].params.delegateThreshold = Number(delegateMsigThreshold).toString()
                } catch (e) {
                    console.log(
                        `${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.delegate}).getThreshold()`
                    )
                }

                try {
                    const delegateMsigMembers = await chains[srcChain].client.readContract({
                        address: oftObj[oftName][srcChain].params.delegate,
                        abi: MSIG_ABI,
                        functionName: 'getOwners',
                    })
                    oftObj[oftName][srcChain].params.delegateMembers = delegateMsigMembers
                } catch (e) {
                    console.log(`${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.delegate}).getOwners()`)
                }

                try {
                    const proxyAdminOwnerMsigThreshold = await chains[srcChain].client.readContract({
                        address: oftObj[oftName][srcChain].params.proxyAdminOwner,
                        abi: MSIG_ABI,
                        functionName: 'getThreshold',
                    })
                    oftObj[oftName][srcChain].params.proxyAdminOwnerThreshold =
                        Number(proxyAdminOwnerMsigThreshold).toString()
                } catch (e) {
                    console.log(
                        `${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.proxyAdminOwner}).getThreshold()`
                    )
                }

                try {
                    const proxyAdminOwnerMsigMembers = await chains[srcChain].client.readContract({
                        address: oftObj[oftName][srcChain].params.proxyAdminOwner,
                        abi: MSIG_ABI,
                        functionName: 'getOwners',
                    })
                    oftObj[oftName][srcChain].params.proxyAdminOwnermembers = proxyAdminOwnerMsigMembers
                } catch (e) {
                    console.log(
                        `${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.proxyAdminOwner}).getOwners()`
                    )
                }
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
            srcChain !== 'katana' &&
            srcChain !== 'stable'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []

            Object.keys(ofts[srcChain]).forEach((oftName, index) => {
                oftObj[oftName][srcChain].params.eid = chains[srcChain].peerId.toString()
                // 0 -> delegate Msig threshold
                if (authParams[index * 4].status === 'success') {
                    oftObj[oftName][srcChain].params.delegateThreshold = Number(authParams[index * 4].result).toString()
                } else {
                    console.log(
                        `${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.delegate}).getThreshold()`
                    )
                }
                // 1 -> delegate msig members
                if (authParams[index * 4 + 1].status === 'success') {
                    oftObj[oftName][srcChain].params.delegateMembers = authParams[index * 4 + 1].result
                } else {
                    console.log(`${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.delegate}).getOwners()`)
                }
                // 2 -> proxy admin owner msig threshold
                if (authParams[index * 4 + 2].status === 'success') {
                    oftObj[oftName][srcChain].params.proxyAdminOwnerThreshold = Number(
                        authParams[index * 4 + 2].result
                    ).toString()
                } else {
                    console.log(
                        `${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.proxyAdminOwner}).getThreshold()`
                    )
                }
                // 3 -> proxy Admin owner msig members
                if (authParams[index * 4 + 3].status === 'success') {
                    oftObj[oftName][srcChain].params.proxyAdminOwnermembers = authParams[index * 4 + 3].result
                } else {
                    console.log(
                        `${oftName}:${srcChain}:msig(${oftObj[oftName][srcChain].params.proxyAdminOwner}).getOwners()`
                    )
                }
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
                } else if (srcChain === 'plasma' || srcChain === 'katana' || srcChain === 'stable') {
                    try {
                        const peerBytes32 = await chains[srcChain].client.readContract({
                            address: ofts[srcChain][oftName].address,
                            abi: OFT_MINTABLE_ADAPTER_ABI,
                            functionName: 'peers',
                            args: [chains[dstChain].peerId],
                        })
                        if (peerBytes32 !== bytes32Zero) {
                            oftObj[oftName][srcChain].dstChains[dstChain].peerAddressBytes32 = peerBytes32
                            oftObj[oftName][srcChain].dstChains[dstChain].peerAddress = getAddress(
                                '0x' + peerBytes32.slice(-40)
                            )
                        }
                    } catch (e) {
                        console.log('===============================')
                        console.log(e)
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:oft(${ofts[srcChain][oftName].address}).peers(${chains[dstChain].peerId})`
                        )
                        console.log('===============================')
                    }
                    try {
                        const isSupportedEid = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'isSupportedEid',
                            args: [chains[dstChain].peerId],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].isSupportedEid = isSupportedEid
                    } catch (e) {
                        console.log('===============================')
                        console.log(e)
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).isSupportedEid(${chains[dstChain].peerId})`
                        )
                        console.log('===============================')
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
            srcChain !== 'katana' &&
            srcChain !== 'stable'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []

            resSchema.forEach(({ srcChain, dstChain, oftName, dstPeerId }, index) => {
                oftObj[oftName][srcChain].dstChains[dstChain].eid = dstPeerId
                if (authParams[index * 2].status === 'success') {
                    if (authParams[index * 2].result !== bytes32Zero) {
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
                    }
                } else {
                    console.log('===============================')
                    console.log(authParams[index * 2])
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:oft(${ofts[srcChain][oftName].address}).peers(${chains[dstChain].peerId})`
                    )
                    console.log('===============================')
                }
                if (authParams[index * 2 + 1].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].isSupportedEid = authParams[index * 2 + 1].result
                } else {
                    console.log('===============================')
                    console.log(authParams[index * 2 + 1])
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:oft(${ofts[srcChain][oftName].address}).isSupportedEid(${chains[dstChain].peerId})`
                    )
                    console.log('===============================')
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
                } else if (srcChain === 'plasma' || srcChain === 'katana' || srcChain === 'stable') {
                    try {
                        const blockedLib = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'blockedLibrary',
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].blockedLib = blockedLib
                    } catch (e) {
                        console.log('===============================')
                        console.log(e)
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).blockedLibrary()`
                        )
                        console.log('===============================')
                    }
                    try {
                        const sendLib = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'getSendLibrary',
                            args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary = sendLib
                    } catch (e) {
                        console.log('===============================')
                        console.log(e)
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).getSendLibrary(${ofts[srcChain][oftName].address},${chains[dstChain].peerId})`
                        )
                        console.log('===============================')
                    }
                    try {
                        const rcvLib = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'getReceiveLibrary',
                            args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                        }) // receive two vals -> addr, bool
                        oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress = rcvLib[0]
                        oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.isDefault = rcvLib[1]
                    } catch (e) {
                        console.log('===============================')
                        console.log(e)
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).getReceiveLibrary(${ofts[srcChain][oftName].address},${chains[dstChain].peerId})`
                        )
                        console.log('===============================')
                    }
                    try {
                        const receiveLibraryTimeout = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'receiveLibraryTimeout',
                            args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                        }) // address lib, uint2256 expiry
                        oftObj[oftName][srcChain].dstChains[dstChain].receiveLibraryTimeOut.libAddress =
                            receiveLibraryTimeout[0]
                        oftObj[oftName][srcChain].dstChains[dstChain].receiveLibraryTimeOut.expiry = Number(
                            receiveLibraryTimeout[1]
                        ).toString()
                    } catch (e) {
                        console.log('===============================')
                        console.log(e)
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).receiveLibraryTimeout(${ofts[srcChain][oftName].address},${chains[dstChain].peerId})`
                        )
                        console.log('===============================')
                    }
                    try {
                        const defaultSendLib = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'defaultSendLibrary',
                            args: [chains[dstChain].peerId],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary = defaultSendLib
                    } catch (e) {
                        console.log('===============================')
                        console.log(e)
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).defaultSendLibrary(${chains[dstChain].peerId})`
                        )
                        console.log('===============================')
                    }
                    try {
                        const defaultReceiveLib = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'defaultReceiveLibrary',
                            args: [chains[dstChain].peerId],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary = defaultReceiveLib
                    } catch (e) {
                        console.log('===============================')
                        console.log(e)
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).defaultReceiveLibrary(${chains[dstChain].peerId})`
                        )
                        console.log('===============================')
                    }
                    try {
                        const defaultReceiveLibTimeout = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'defaultReceiveLibraryTimeout',
                            args: [chains[dstChain].peerId],
                        }) // address lib, uint2256 expiry
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibraryTimeOut.libAddress =
                            defaultReceiveLibTimeout[0]
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibraryTimeOut.expiry = Number(
                            defaultReceiveLibTimeout[1]
                        ).toString()
                    } catch (e) {
                        console.log('===============================')
                        console.log(e)
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).defaultReceiveLibraryTimeout(${chains[dstChain].peerId})`
                        )
                        console.log('===============================')
                    }
                    try {
                        const isDefaultSendLibrary = await chains[srcChain].client.readContract({
                            address: oftObj[oftName][srcChain].params.actualEndpoint,
                            abi: ENDPOINTV2_ABI,
                            functionName: 'isDefaultSendLibrary',
                            args: [ofts[srcChain][oftName].address, chains[dstChain].peerId],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].isDefaultSendLibrary = isDefaultSendLibrary
                    } catch (e) {
                        console.log('===============================')
                        console.log(e)
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).isDefaultSendLibrary(${ofts[srcChain][oftName].address},${chains[dstChain].peerId})`
                        )
                        console.log('===============================')
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
            srcChain !== 'katana' &&
            srcChain !== 'stable'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []
            resSchema.forEach(({ srcChain, dstChain, oftName }, index) => {
                if (authParams[index * 8].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].blockedLib = authParams[index * 8].result
                } else {
                    console.log('===============================')
                    console.log(authParams[index * 8])
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).blockedLibrary()`
                    )
                    console.log('===============================')
                }
                if (authParams[index * 8 + 1].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary = authParams[index * 8 + 1].result
                } else {
                    console.log('===============================')
                    console.log(authParams[index * 8 + 1])
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).getSendLibrary(${ofts[srcChain][oftName].address},${chains[dstChain].peerId})`
                    )
                    console.log('===============================')
                }
                if (authParams[index * 8 + 2].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress =
                        authParams[index * 8 + 2].result[0]
                    oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.isDefault =
                        authParams[index * 8 + 2].result[1]
                } else {
                    console.log('===============================')
                    console.log(authParams[index * 8 + 2])
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).getReceiveLibrary(${ofts[srcChain][oftName].address},${chains[dstChain].peerId})`
                    )
                    console.log('===============================')
                }
                if (authParams[index * 8 + 3].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].receiveLibraryTimeOut.libAddress =
                        authParams[index * 8 + 3].result[0]
                    oftObj[oftName][srcChain].dstChains[dstChain].receiveLibraryTimeOut.expiry = Number(
                        authParams[index * 8 + 3].result[1]
                    ).toString()
                } else {
                    console.log('===============================')
                    console.log(authParams[index * 8 + 3])
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).receiveLibraryTimeout(${ofts[srcChain][oftName].address},${chains[dstChain].peerId})`
                    )
                    console.log('===============================')
                }
                if (authParams[index * 8 + 4].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary = authParams[index * 8 + 4].result
                } else {
                    console.log('===============================')
                    console.log(authParams[index * 8 + 4])
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).defaultSendLibrary(${chains[dstChain].peerId})`
                    )
                    console.log('===============================')
                }
                if (authParams[index * 8 + 5].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary =
                        authParams[index * 8 + 5].result
                } else {
                    console.log('===============================')
                    console.log(authParams[index * 8 + 5])
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).defaultReceiveLibrary(${chains[dstChain].peerId})`
                    )
                    console.log('===============================')
                }
                if (authParams[index * 8 + 6].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibraryTimeOut.libAddress =
                        authParams[index * 8 + 6].result[0]
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibraryTimeOut.expiry = Number(
                        authParams[index * 8 + 6].result[1]
                    ).toString()
                } else {
                    console.log('===============================')
                    console.log(authParams[index * 8 + 6])
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).defaultReceiveLibraryTimeout(${chains[dstChain].peerId})`
                    )
                    console.log('===============================')
                }
                if (authParams[index * 8 + 7].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].isDefaultSendLibrary =
                        authParams[index * 8 + 7].result
                } else {
                    console.log('===============================')
                    console.log(authParams[index * 8 + 7])
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:endpoint(${oftObj[oftName][srcChain].params.actualEndpoint}).isDefaultSendLibrary(${ofts[srcChain][oftName].address},${chains[dstChain].peerId})`
                    )
                    console.log('===============================')
                }
            })
            resSchema = []
        }
    }

    // 6. executor options, uln config
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
                if (oftObj[oftName][srcChain].dstChains[dstChain].enforcedOptionsSend == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].enforcedOptionsSend = {} as OFTEnforcedOptions
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].enforcedOptionsSendAndCall == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].enforcedOptionsSendAndCall = {} as OFTEnforcedOptions
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].executorConfig == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].executorConfig = {} as ExecutorConfigType
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].executorConfigDefaultLib == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].executorConfigDefaultLib = {} as ExecutorConfigType
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfig == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfig = {} as ExecutorConfigType
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfigDefaultLib == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfigDefaultLib =
                        {} as ExecutorConfigType
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfig == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfig = {} as EndpointConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfig.receive == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfig.receive = {} as UlnConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfig.send == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfig.send = {} as UlnConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfigDefaultLib == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfigDefaultLib = {} as EndpointConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfigDefaultLib.receive == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfigDefaultLib.receive = {} as UlnConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfigDefaultLib.send == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfigDefaultLib.send = {} as UlnConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfig == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfig = {} as EndpointConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfig.receive == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfig.receive = {} as UlnConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfig.send == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfig.send = {} as UlnConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfigDefaultLib == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfigDefaultLib = {} as EndpointConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfigDefaultLib.receive == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfigDefaultLib.receive = {} as UlnConfig
                }
                if (oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfigDefaultLib.send == undefined) {
                    oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfigDefaultLib.send = {} as UlnConfig
                }
                if (srcChain === 'solana') {
                } else if (srcChain === 'aptos' || srcChain === 'movement') {
                } else if (srcChain === 'plasma' || srcChain === 'katana' || srcChain === 'stable') {
                    // enforcedOptions msgType 1
                    try {
                        const enforcedOptionsSend = await chains[oftName].client.readContract({
                            address: ofts[srcChain][oftName].address,
                            abi: ofts[srcChain][oftName].abi,
                            functionName: 'enforcedOptions',
                            args: [chains[dstChain].peerId, 1],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].enforcedOptionsSend = deepCopy(
                            decodeLzReceiveOption(enforcedOptionsSend)
                        )
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:oft(${ofts[srcChain][oftName].address}).enforcedOptions(${chains[dstChain].peerId},1)`
                        )
                    }

                    // enforcedOptions msgType 2
                    try {
                        const enforcedOptionsSendAndCall = await chains[oftName].client.readContract({
                            address: ofts[srcChain][oftName].address,
                            abi: ofts[srcChain][oftName].abi,
                            functionName: 'enforcedOptions',
                            args: [chains[dstChain].peerId, 2],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].enforcedOptionsSendAndCall = deepCopy(
                            decodeLzReceiveOption(enforcedOptionsSendAndCall)
                        )
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:oft(${ofts[srcChain][oftName].address}).enforcedOptions(${chains[dstChain].peerId},2)`
                        )
                    }

                    // send default executor config : sendUln302.executorConfigs(address(0),_remoteEid)
                    try {
                        const sendDefaultExecutorConfig = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary,
                            abi: SEND_ULN302_ABI,
                            functionName: 'executorConfigs',
                            args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfig.maxMessageSize =
                            sendDefaultExecutorConfig.result[0]
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfig.executorAddress =
                            sendDefaultExecutorConfig.result[1]
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:sendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary}).executorConfigs(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // send app executor config : sendUln302.executorConfigs(oft,_remoteEid)
                    try {
                        const sendAppExecutorConfig = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary,
                            abi: SEND_ULN302_ABI,
                            functionName: 'executorConfigs',
                            args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].executorConfig.maxMessageSize =
                            sendAppExecutorConfig.result[0]
                        oftObj[oftName][srcChain].dstChains[dstChain].executorConfig.executorAddress =
                            sendAppExecutorConfig.result[1]
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:sendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary}).executorConfigs(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // default send default executor config : sendUln302.executorConfigs(address(0),_remoteEid)
                    try {
                        const sendDefaultExecutorConfigDefault = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary,
                            abi: SEND_ULN302_ABI,
                            functionName: 'executorConfigs',
                            args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfigDefaultLib.maxMessageSize =
                            sendDefaultExecutorConfigDefault.result[0]
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfigDefaultLib.executorAddress =
                            sendDefaultExecutorConfigDefault.result[1]
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:defaultSendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary}).executorConfigs(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // default send app executor config : sendUln302.executorConfigs(oft,_remoteEid)
                    try {
                        const sendAppExecutorConfigDefault = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary,
                            abi: SEND_ULN302_ABI,
                            functionName: 'executorConfigs',
                            args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].executorConfigDefaultLib.maxMessageSize =
                            sendAppExecutorConfigDefault.result[0]
                        oftObj[oftName][srcChain].dstChains[dstChain].executorConfigDefaultLib.executorAddress =
                            sendAppExecutorConfigDefault.result[1]
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:defaultSendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary}).executorConfigs(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // send default uln config : sendUln302.getAppUlnConfig(address(0),_remoteEid)
                    try {
                        const sendDefaultUlnConfig = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary,
                            abi: SEND_ULN302_ABI,
                            functionName: 'getAppUlnConfig',
                            args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfig.send =
                            deepCopy(sendDefaultUlnConfig) // sendDefaultUlnConfig
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:sendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary}).getAppUlnConfig(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // send app uln config : sendUln302.getAppUlnConfig(oft,_remoteEid)
                    try {
                        const sendAppUlnConfig = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary,
                            abi: SEND_ULN302_ABI,
                            functionName: 'getAppUlnConfig',
                            args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfig.send = deepCopy(sendAppUlnConfig) // sendAppUlnConfig
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:sendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary}).getAppUlnConfig(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // send default uln config : sendUln302.getAppUlnConfig(address(0),_remoteEid)
                    try {
                        const sendDefaultUlnConfigDefault = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary,
                            abi: SEND_ULN302_ABI,
                            functionName: 'getAppUlnConfig',
                            args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfigDefaultLib.send =
                            deepCopy(sendDefaultUlnConfigDefault) // sendDefaultUlnConfigDefault
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:defaultSendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary}).getAppUlnConfig(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // send app uln config : sendUln302.getAppUlnConfig(oft,_remoteEid)
                    try {
                        const sendAppUlnConfigDefault = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary,
                            abi: SEND_ULN302_ABI,
                            functionName: 'getAppUlnConfig',
                            args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfigDefaultLib.send =
                            deepCopy(sendAppUlnConfigDefault) // sendAppUlnConfigDefault
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:defaultSendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary}).getAppUlnConfig(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // receive default uln config : sendUln302.getAppUlnConfig(address(0),_remoteEid)
                    try {
                        const receiveDefaultUlnConfig = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress,
                            abi: RECEIVE_ULN302_ABI,
                            functionName: 'getAppUlnConfig',
                            args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfig.receive =
                            deepCopy(receiveDefaultUlnConfig) // receiveDefaultUlnConfig
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:receiveLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress}).getAppUlnConfig(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // receive app uln config : sendUln302.getAppUlnConfig(oft,_remoteEid)
                    try {
                        const receiveApptUlnConfig = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress,
                            abi: RECEIVE_ULN302_ABI,
                            functionName: 'getAppUlnConfig',
                            args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfig.receive =
                            deepCopy(receiveApptUlnConfig) // receiveApptUlnConfig
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:receiveLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress}).getAppUlnConfig(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // receive default uln config : sendUln302.getAppUlnConfig(address(0),_remoteEid)
                    try {
                        const receiveDefaultUlnConfigDefault = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary,
                            abi: RECEIVE_ULN302_ABI,
                            functionName: 'getAppUlnConfig',
                            args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfigDefaultLib.receive =
                            deepCopy(receiveDefaultUlnConfigDefault) // receiveDefaultUlnConfigDefault
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:defaultReceiveLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary}).getAppUlnConfig(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }

                    // receive app uln config : sendUln302.getAppUlnConfig(oft,_remoteEid)
                    try {
                        const receiveAppUlnConfigDefault = await chains[oftName].client.readContract({
                            address: oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary,
                            abi: RECEIVE_ULN302_ABI,
                            functionName: 'getAppUlnConfig',
                            args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                        })
                        oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfigDefaultLib.receive =
                            deepCopy(receiveAppUlnConfigDefault) // receiveAppUlnConfigDefault
                    } catch (e) {
                        console.log(
                            `${oftName}:${srcChain}:${dstChain}:defaultReceiveLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary}).getAppUlnConfig(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                        )
                    }
                } else {
                    contractcalls.push({
                        address: ofts[srcChain][oftName].address,
                        abi: ofts[srcChain][oftName].abi,
                        functionName: 'enforcedOptions',
                        args: [chains[dstChain].peerId, 1],
                    })
                    contractcalls.push({
                        address: ofts[srcChain][oftName].address,
                        abi: ofts[srcChain][oftName].abi,
                        functionName: 'enforcedOptions',
                        args: [chains[dstChain].peerId, 2],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: 'executorConfigs',
                        args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: 'executorConfigs',
                        args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: 'executorConfigs',
                        args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: 'executorConfigs',
                        args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: 'getAppUlnConfig',
                        args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: 'getAppUlnConfig',
                        args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: 'getAppUlnConfig',
                        args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: 'getAppUlnConfig',
                        args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: 'getAppUlnConfig',
                        args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: 'getAppUlnConfig',
                        args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: 'getAppUlnConfig',
                        args: [zeroAddress, oftObj[oftName][srcChain].dstChains[dstChain].eid],
                    })
                    contractcalls.push({
                        address: oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: 'getAppUlnConfig',
                        args: [ofts[srcChain][oftName].address, oftObj[oftName][srcChain].dstChains[dstChain].eid],
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
            srcChain !== 'katana' &&
            srcChain !== 'stable'
        ) {
            const authParams = await chains[srcChain].client.multicall({
                contracts: contractcalls,
            })
            contractcalls = []
            resSchema.forEach(({ srcChain, dstChain, oftName }, index) => {
                if (authParams[index * 14].status === 'success') {
                    if (authParams[index * 14].result !== '0x') {
                        try {
                            oftObj[oftName][srcChain].dstChains[dstChain].enforcedOptionsSend = deepCopy(
                                decodeLzReceiveOption(authParams[index * 14].result)
                            )
                        } catch (e) {
                            console.log('===============================')
                            console.log(e)
                            console.log(authParams[index * 14])
                            console.log(
                                `${oftName}:${srcChain}:${dstChain}:oft(${ofts[srcChain][oftName].address}).enforcedOptions(${chains[dstChain].peerId},1)`
                            )
                            console.log('===============================')
                        }
                    }
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:oft(${ofts[srcChain][oftName].address}).enforcedOptions(${chains[dstChain].peerId},1)`
                    )
                }
                if (authParams[index * 14 + 1].status === 'success') {
                    if (authParams[index * 14 + 1].result !== '0x') {
                        try {
                            oftObj[oftName][srcChain].dstChains[dstChain].enforcedOptionsSendAndCall = deepCopy(
                                decodeLzReceiveOption(authParams[index * 14 + 1].result)
                            )
                        } catch (e) {
                            console.log('===============================')
                            console.log(e)
                            console.log(authParams[index * 14])
                            console.log(
                                `${oftName}:${srcChain}:${dstChain}:oft(${ofts[srcChain][oftName].address}).enforcedOptions(${chains[dstChain].peerId},1)`
                            )
                            console.log('===============================')
                        }
                    }
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:oft(${ofts[srcChain][oftName].address}).enforcedOptions(${chains[dstChain].peerId},2)`
                    )
                }

                if (authParams[index * 14 + 2].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfig.maxMessageSize =
                        authParams[index * 14 + 2].result[0]
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfig.executorAddress =
                        authParams[index * 14 + 2].result[1]
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:sendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary}).executorConfigs(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }

                if (authParams[index * 14 + 3].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].executorConfig.maxMessageSize =
                        authParams[index * 14 + 3].result[0]
                    oftObj[oftName][srcChain].dstChains[dstChain].executorConfig.executorAddress =
                        authParams[index * 14 + 3].result[1]
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:sendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary}).executorConfigs(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }
                if (authParams[index * 14 + 4].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfigDefaultLib.maxMessageSize =
                        authParams[index * 14 + 4].result[0]
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultExecutorConfigDefaultLib.executorAddress =
                        authParams[index * 14 + 4].result[1]
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:defaultSendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary}).executorConfigs(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }
                if (authParams[index * 14 + 5].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].executorConfigDefaultLib.maxMessageSize =
                        authParams[index * 14 + 5].result[0]
                    oftObj[oftName][srcChain].dstChains[dstChain].executorConfigDefaultLib.executorAddress =
                        authParams[index * 14 + 5].result[1]
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:defaultSendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary}).executorConfigs(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }
                if (authParams[index * 14 + 6].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfig.send = deepCopy(
                        authParams[index * 14 + 6].result
                    ) // sendDefaultUlnConfig
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:sendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary}).getAppUlnConfig(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }

                if (authParams[index * 14 + 7].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfig.send = deepCopy(
                        authParams[index * 14 + 7].result
                    ) // sendAppUlnConfig
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:sendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].sendLibrary}).getAppUlnConfig(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }

                if (authParams[index * 14 + 8].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfigDefaultLib.send = deepCopy(
                        authParams[index * 14 + 8].result
                    ) // sendDefaultUlnConfigDefault
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:defaultSendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary}).getAppUlnConfig(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }

                if (authParams[index * 14 + 9].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfigDefaultLib.send = deepCopy(
                        authParams[index * 14 + 9].result
                    ) // sendAppUlnConfigDefault
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:defaultSendLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultSendLibrary}).getAppUlnConfig(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }

                if (authParams[index * 14 + 10].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfig.receive = deepCopy(
                        authParams[index * 14 + 10].result
                    ) // receiveDefaultUlnConfig
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:receiveLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress}).getAppUlnConfig(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }

                if (authParams[index * 14 + 11].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfig.receive = deepCopy(
                        authParams[index * 14 + 11].result
                    ) // receiveApptUlnConfig
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:receiveLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].receiveLibrary.receiveLibraryAddress}).getAppUlnConfig(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }

                if (authParams[index * 14 + 12].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].defaultUlnConfigDefaultLib.receive = deepCopy(
                        authParams[index * 14 + 12].result
                    ) // receiveDefaultUlnConfigDefault
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:defaultReceiveLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary}).getAppUlnConfig(${zeroAddress}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }

                if (authParams[index * 14 + 13].status === 'success') {
                    oftObj[oftName][srcChain].dstChains[dstChain].appUlnConfigDefaultLib.receive = deepCopy(
                        authParams[index * 14 + 13].result
                    ) // receiveAppUlnConfigDefault
                } else {
                    console.log(
                        `${oftName}:${srcChain}:${dstChain}:defaultReceiveLibrary(${oftObj[oftName][srcChain].dstChains[dstChain].defaultReceiveLibrary}).getAppUlnConfig(${ofts[srcChain][oftName].address}, ${oftObj[oftName][srcChain].dstChains[dstChain].eid})`
                    )
                }
            })
            resSchema = []
        }
    }
    for (const oftName of Object.keys(oftObj)) {
        fs.writeFileSync(
            `./run-periodically/check-oft-config-csv/check-${oftName}-config-peer.json`,
            JSON.stringify(oftObj[oftName], null, 2)
        )
    }

    // wire config
    for (const oftName of Object.keys(oftObj)) {
        fs.writeFileSync(
            `./run-periodically/check-oft-config-csv/check-wire-${oftName}-peer.csv`,
            generateWiringMatrix(oftObj[oftName])
        )
    }
    // dvn
    for (const oftName of Object.keys(oftObj)) {
        fs.writeFileSync(
            `./run-periodically/check-oft-config-csv/check-dvn-${oftName}-peer.csv`,
            generateUlnAndDvnComparisonCSV(oftObj[oftName])
        )
    }

    // enforcedOptions
    for (const oftName of Object.keys(oftObj)) {
        fs.writeFileSync(
            `./run-periodically/check-oft-config-csv/check-enforcedOptions-${oftName}-peer.csv`,
            generateEnforcedOptionsCSV(oftObj[oftName])
        )
    }

    // executorConfig
    for (const oftName of Object.keys(oftObj)) {
        fs.writeFileSync(
            `./run-periodically/check-oft-config-csv/check-executorConfig-${oftName}-peer.csv`,
            generateExecutorConfigCSV(oftObj[oftName])
        )
    }
}

main()
