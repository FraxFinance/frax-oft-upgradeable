import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import type { OAppEdgeConfig, OmniEdgeHardhat } from '@layerzerolabs/toolbox-hardhat'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import L0Config from "../L0Config.json"
import { readFile } from 'fs/promises'
import { zeroAddress } from 'viem'

enum MsgType {
    SEND = 1,
    SEND_AND_CALL = 2,
}

type lzConfigType = {
    RPC: string,
    chainid: number,
    delegate: string,
    dvnHorizen: string,
    dvnL0: string,
    eid: number,
    endpoint: string,
    receiveLib302: string,
    sendLib302: string
}

const dvnConfigPath = "config/dvn"
const zeroBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000'

const chainIds = [
    1, 10, 56, 130, 137, 146, 196, 252, 324, 480, 1101, 1329, 2741, 8453, 34443, 42161, 43114, 57073, 59144, 80094, 81457
];

const aptosContract: OmniPointHardhat = {
    eid: EndpointId.APTOS_V2_MAINNET,
    contractName: 'mFRAX',
}

// const solanaContract: OmniPointHardhat = {
//     eid: EndpointId.SOLANA_V2_MAINNET,
//     contractName: 'mFRAX',
// }

// const movementContract : OmniPointHardhat = {
//     eid: EndpointId.MOVEMENT_V2_MAINNET,
//     contractName: 'mFRAX',
// }

function generateContractConfig(lzConfig: lzConfigType[]) {
    return chainIds.map(_chainid => {
        let eid = 0
        for (let index = 0; index < lzConfig.length; index++) {
            const config = lzConfig[index];
            if (config.chainid == _chainid) {
                eid = config.eid
                break
            }
        }
        if (eid == 0) throw Error("EID not found")

        return {
            contract: {
                eid: eid,
                contractName: _chainid == 252 ? "FraxOFTMintableUpgradeable" : "MockFRAXUpgradeable"
            },
            config: {
                owner: '0x45dce8e4f2dc005a5f28206a46cb034697eeda8e',
                delegate: '0x45dce8e4f2dc005a5f28206a46cb034697eeda8e',
            },
        }
    }
    )
}

async function generateSrcConnectionConfig(lzConfig: lzConfigType[]): Promise<OmniEdgeHardhat<OAppEdgeConfig>[]> {
    const srcDVNConfig = JSON.parse(await readFile(`${__dirname}/../../${dvnConfigPath}/aptos.json`, 'utf8'))
    return await Promise.all(
        chainIds.map(async (_chainid) => {
            // read from config/dvn for dvn address
            let eid = 0
            for (let index = 0; index < lzConfig.length; index++) {
                const config = lzConfig[index];
                if (config.chainid == _chainid) {
                    eid = config.eid
                    break
                }
            }
            if (eid == 0) throw Error("EID not found")
            const dstDVNConfig = JSON.parse(await readFile(`${__dirname}/../../${dvnConfigPath}/${_chainid}.json`, 'utf8'))

            const requiredSrcDVNs: string[] = []

            const dstBcwGroupDVN = dstDVNConfig["aptos"].bcwGroup
            const dstFraxDVN = dstDVNConfig["aptos"].frax
            const dstHorizenDVN = dstDVNConfig["aptos"].horizen
            const dstLZDVN = dstDVNConfig["aptos"].lz
            const dstNethermindDVN = dstDVNConfig["aptos"].nethermind
            const dstStargateDVN = dstDVNConfig["aptos"].stargate
            const srcBcwGroupDVN = srcDVNConfig[_chainid].bcwGroup
            const srcFraxDVN = srcDVNConfig[_chainid].frax
            const srcHorizenDVN = dstDVNConfig[_chainid].horizen
            const srcLZDVN = dstDVNConfig[_chainid].lz
            const srcNethermindDVN = dstDVNConfig[_chainid].nethermind
            const srcStargateDVN = dstDVNConfig[_chainid].stargate

            if (dstBcwGroupDVN !== zeroAddress || srcBcwGroupDVN !== zeroBytes32) {
                if (dstBcwGroupDVN === zeroAddress || srcBcwGroupDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:aptos<>${_chainid}-bcwGroup`)
                }
                requiredSrcDVNs.push(srcBcwGroupDVN)
            }
            if (dstFraxDVN !== zeroAddress || srcFraxDVN !== zeroBytes32) {
                if (dstFraxDVN === zeroAddress || srcFraxDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:aptos<>${_chainid}-Frax`)
                }
                requiredSrcDVNs.push(srcFraxDVN)
            }
            if (dstHorizenDVN !== zeroAddress || srcHorizenDVN !== zeroBytes32) {
                if (dstHorizenDVN === zeroAddress || srcHorizenDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:aptos<>${_chainid}-Horizen`)
                }
                requiredSrcDVNs.push(srcHorizenDVN)
            }
            if (dstLZDVN !== zeroAddress || srcLZDVN !== zeroBytes32) {
                if (dstLZDVN === zeroAddress || srcLZDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:aptos<>${_chainid}-LZ`)
                }
                requiredSrcDVNs.push(srcLZDVN)
            }
            if (dstNethermindDVN !== zeroAddress || srcNethermindDVN !== zeroBytes32) {
                if (dstNethermindDVN === zeroAddress || srcNethermindDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:aptos<>${_chainid}-Nethermind`)
                }
                requiredSrcDVNs.push(srcNethermindDVN)
            }
            if (dstStargateDVN !== zeroAddress || srcStargateDVN !== zeroBytes32) {
                if (dstStargateDVN === zeroAddress || srcStargateDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:aptos<>${_chainid}-Stargate`)
                }
                requiredSrcDVNs.push(srcStargateDVN)
            }

            return {
                from: aptosContract,
                to: {
                    eid: eid,
                    contractName: _chainid == 252 ? "FraxOFTMintableUpgradeable" : "MockFRAXUpgradeable"
                },
                config: {
                    enforcedOptions: [
                        {
                            msgType: MsgType.SEND,
                            optionType: ExecutorOptionType.LZ_RECEIVE,
                            gas: 80_000, // gas limit in wei for EndpointV2.lzReceive
                            value: 0, // msg.value in wei for EndpointV2.lzReceive
                        },
                        {
                            msgType: MsgType.SEND_AND_CALL,
                            optionType: ExecutorOptionType.LZ_RECEIVE,
                            gas: 80_000, // gas limit in wei for EndpointV2.lzReceive
                            value: 0, // msg.value in wei for EndpointV2.lzReceive
                        },
                    ],
                    sendLibrary: '0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9',
                    receiveLibraryConfig: {
                        // Required Receive Library Address on Aptos
                        receiveLibrary: '0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9',
                        // Optional Grace Period for Switching Receive Library Address on Aptos
                        gracePeriod: BigInt(0),
                    },
                    // Optional Receive Library Timeout for when the Old Receive Library Address will no longer be valid on Aptos
                    // receiveLibraryTimeoutConfig: {
                    //     lib: '0xbe533727aebe97132ec0a606d99e0ce137dbdf06286eb07d9e0f7154df1f3f10',
                    //     expiry: BigInt(1000000000),
                    // },
                    sendConfig: {
                        executorConfig: {
                            maxMessageSize: 10_000,
                            // The configured Executor address on Aptos
                            executor: '0x15a5bbf1eb7998a22c9f23810d424abe40bd59ddd8e6ab7e59529853ebed41c4',
                        },
                        ulnConfig: {
                            // The number of block confirmations to wait on Aptos before emitting the message from the source chain.
                            confirmations: BigInt(5),
                            // The address of the DVNs you will pay to verify a sent message on the source chain.
                            // The destination tx will wait until ALL `requiredDVNs` verify the message.
                            requiredDVNs: requiredSrcDVNs,
                            // The address of the DVNs you will pay to verify a sent message on the source chain.
                            // The destination tx will wait until the configured threshold of `optionalDVNs` verify a message.
                            optionalDVNs: [],
                            // The number of `optionalDVNs` that need to successfully verify the message for it to be considered Verified.
                            optionalDVNThreshold: 0,
                        },
                    },
                    // Optional Receive Configuration
                    // @dev Controls how the `from` chain receives messages from the `to` chain.
                    receiveConfig: {
                        ulnConfig: {
                            // The number of block confirmations to expect from the `to` chain.
                            confirmations: BigInt(5),
                            // The address of the DVNs your `receiveConfig` expects to receive verifications from on the `from` chain.
                            // The `from` chain's OApp will wait until the configured threshold of `requiredDVNs` verify the message.
                            requiredDVNs: requiredSrcDVNs,
                            // The address of the `optionalDVNs` you expect to receive verifications from on the `from` chain.
                            // The destination tx will wait until the configured threshold of `optionalDVNs` verify the message.
                            optionalDVNs: [],
                            // The number of `optionalDVNs` that need to successfully verify the message for it to be considered Verified.
                            optionalDVNThreshold: 0,
                        },
                    },
                },
            }
        })
    )
}

async function generateDstConnectionConfig(lzConfig: lzConfigType[]): Promise<OmniEdgeHardhat<OAppEdgeConfig>[]> {
    const dstDVNConfig = JSON.parse(await readFile(`${__dirname}/../../${dvnConfigPath}/aptos.json`, 'utf8'))
    return await Promise.all(
        chainIds.map(async (_chainid) => {
            // read from config/dvn for dvn address
            let eid = 0
            let sendLibrary: string = zeroAddress
            let receiveLibrary: string = zeroAddress
            // let executor = zeroAddress
            for (let index = 0; index < lzConfig.length; index++) {
                const config = lzConfig[index];
                if (config.chainid == _chainid) {
                    eid = config.eid
                    sendLibrary = config.sendLib302
                    receiveLibrary = config.receiveLib302
                    // executor = config.ex
                    break
                }
            }
            
            if (eid == 0) throw Error("EID not found")
            if (sendLibrary == zeroAddress) throw Error("sendlibrary not found")
            if (receiveLibrary == zeroAddress) throw Error("receivelibrary not found")

            const srcDVNConfig = JSON.parse(await readFile(`${__dirname}/../../${dvnConfigPath}/${_chainid}.json`, 'utf8'))

            const requiredDstDVNs: string[] = []

            const dstBcwGroupDVN = dstDVNConfig[_chainid].bcwGroup
            const dstFraxDVN = dstDVNConfig[_chainid].frax
            const dstHorizenDVN = dstDVNConfig[_chainid].horizen
            const dstLZDVN = dstDVNConfig[_chainid].lz
            const dstNethermindDVN = dstDVNConfig[_chainid].nethermind
            const dstStargateDVN = dstDVNConfig[_chainid].stargate
            const srcBcwGroupDVN = srcDVNConfig["aptos"].bcwGroup
            const srcFraxDVN = srcDVNConfig["aptos"].frax
            const srcHorizenDVN = dstDVNConfig["aptos"].horizen
            const srcLZDVN = dstDVNConfig["aptos"].lz
            const srcNethermindDVN = dstDVNConfig["aptos"].nethermind
            const srcStargateDVN = dstDVNConfig["aptos"].stargate

            if (dstBcwGroupDVN !== zeroAddress || srcBcwGroupDVN !== zeroBytes32) {
                if (dstBcwGroupDVN === zeroAddress || srcBcwGroupDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:${_chainid}<>aptos-bcwGroup`)
                }
                requiredDstDVNs.push(srcBcwGroupDVN)
            }
            if (dstFraxDVN !== zeroAddress || srcFraxDVN !== zeroBytes32) {
                if (dstFraxDVN === zeroAddress || srcFraxDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:${_chainid}<>aptos-Frax`)
                }
                requiredDstDVNs.push(srcFraxDVN)
            }
            if (dstHorizenDVN !== zeroAddress || srcHorizenDVN !== zeroBytes32) {
                if (dstHorizenDVN === zeroAddress || srcHorizenDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:${_chainid}<>aptos-Horizen`)
                }
                requiredDstDVNs.push(srcHorizenDVN)
            }
            if (dstLZDVN !== zeroAddress || srcLZDVN !== zeroBytes32) {
                if (dstLZDVN === zeroAddress || srcLZDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:${_chainid}<>aptos-LZ`)
                }
                requiredDstDVNs.push(srcLZDVN)
            }
            if (dstNethermindDVN !== zeroAddress || srcNethermindDVN !== zeroBytes32) {
                if (dstNethermindDVN === zeroAddress || srcNethermindDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:${_chainid}<>aptos-Nethermind`)
                }
                requiredDstDVNs.push(srcNethermindDVN)
            }
            if (dstStargateDVN !== zeroAddress || srcStargateDVN !== zeroBytes32) {
                if (dstStargateDVN === zeroAddress || srcStargateDVN === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured:${_chainid}<>aptos-Stargate`)
                }
                requiredDstDVNs.push(srcStargateDVN)
            }

            return {
                from: aptosContract,
                to: {
                    eid: eid,
                    contractName: _chainid == 252 ? "FraxOFTMintableUpgradeable" : "MockFRAXUpgradeable"
                },
                config: {
                    enforcedOptions: [
                        {
                            msgType: MsgType.SEND,
                            optionType: ExecutorOptionType.LZ_RECEIVE,
                            gas: 80_000, // gas limit in wei for EndpointV2.lzReceive
                            value: 0, // msg.value in wei for EndpointV2.lzReceive
                        },
                        {
                            msgType: MsgType.SEND_AND_CALL,
                            optionType: ExecutorOptionType.LZ_RECEIVE,
                            gas: 80_000, // gas limit in wei for EndpointV2.lzReceive
                            value: 0, // msg.value in wei for EndpointV2.lzReceive
                        },
                    ],
                    sendLibrary: sendLibrary,
                    receiveLibraryConfig: {
                        // Required Receive Library Address on Aptos
                        receiveLibrary: receiveLibrary,
                        // Optional Grace Period for Switching Receive Library Address on Aptos
                        gracePeriod: BigInt(0),
                    },
                    // Optional Receive Library Timeout for when the Old Receive Library Address will no longer be valid on Aptos
                    // receiveLibraryTimeoutConfig: {
                    //     lib: '0xbe533727aebe97132ec0a606d99e0ce137dbdf06286eb07d9e0f7154df1f3f10',
                    //     expiry: BigInt(1000000000),
                    // },
                    sendConfig: {
                        // executorConfig: {
                        //     maxMessageSize: 10_000,
                        //     // The configured Executor address on Aptos
                        //     executor: '0x15a5bbf1eb7998a22c9f23810d424abe40bd59ddd8e6ab7e59529853ebed41c4',
                        // },
                        ulnConfig: {
                            // The number of block confirmations to wait on Aptos before emitting the message from the source chain.
                            confirmations: BigInt(5),
                            // The address of the DVNs you will pay to verify a sent message on the source chain.
                            // The destination tx will wait until ALL `requiredDVNs` verify the message.
                            requiredDVNs: requiredDstDVNs,
                            // The address of the DVNs you will pay to verify a sent message on the source chain.
                            // The destination tx will wait until the configured threshold of `optionalDVNs` verify a message.
                            optionalDVNs: [],
                            // The number of `optionalDVNs` that need to successfully verify the message for it to be considered Verified.
                            optionalDVNThreshold: 0,
                        },
                    },
                    // Optional Receive Configuration
                    // @dev Controls how the `from` chain receives messages from the `to` chain.
                    receiveConfig: {
                        ulnConfig: {
                            // The number of block confirmations to expect from the `to` chain.
                            confirmations: BigInt(5),
                            // The address of the DVNs your `receiveConfig` expects to receive verifications from on the `from` chain.
                            // The `from` chain's OApp will wait until the configured threshold of `requiredDVNs` verify the message.
                            requiredDVNs: requiredDstDVNs,
                            // The address of the `optionalDVNs` you expect to receive verifications from on the `from` chain.
                            // The destination tx will wait until the configured threshold of `optionalDVNs` verify the message.
                            optionalDVNs: [],
                            // The number of `optionalDVNs` that need to successfully verify the message for it to be considered Verified.
                            optionalDVNThreshold: 0,
                        },
                    },
                },
            }
        })
    )
}

const config: OAppOmniGraphHardhat = {
    contracts: [
        ...generateContractConfig(L0Config.Proxy.filter(config => config.chainid != 252)),
        {
            contract: aptosContract,
            config: {
                delegate: '0x09d0eb2763c96e085fa74ba6cf0d49136f8654c48ec7dbc59279a9066c7dd409',
                owner: '0x09d0eb2763c96e085fa74ba6cf0d49136f8654c48ec7dbc59279a9066c7dd409',
            },
        },
    ],
    connections: [
        ...await generateSrcConnectionConfig(L0Config.Proxy),
        ...await generateDstConnectionConfig(L0Config.Proxy),
    ],
}

export default config