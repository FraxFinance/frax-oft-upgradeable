import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import type { OAppEdgeConfig, OmniEdgeHardhat } from '@layerzerolabs/toolbox-hardhat'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import L0Config from "../L0Config.json"
import { readFile } from 'fs/promises'
import { zeroAddress } from 'viem'
import { readFileSync } from 'fs'
import path from 'path'

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
] as const;
const dvnKeys = ['bcwGroup', 'frax', 'horizen', 'lz', 'nethermind', 'stargate'] as const;

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
    const contractConfig: any[] = []

    for (const _chainid of chainIds) {
        let eid = 0
        for (const config of lzConfig) {
            if (config.chainid === _chainid) {
                eid = config.eid;
                break;
            }
        }
        if (eid === 0) throw Error(`EID not found for chainid: ${_chainid}`)

        contractConfig.push({
            contract: {
                eid: eid,
                contractName: _chainid == 252 ? "FraxOFTMintableUpgradeable" : "MockFRAXUpgradeable"
            },
            config: {
                owner: '0x45dce8e4f2dc005a5f28206a46cb034697eeda8e',
                delegate: '0x45dce8e4f2dc005a5f28206a46cb034697eeda8e',
            },
        })
    }

    return contractConfig
}

function generateSrcConnectionConfig(lzConfig: lzConfigType[]): OmniEdgeHardhat<OAppEdgeConfig>[] {
    const connectionConfig: any[] = []
    const srcDVNConfig = JSON.parse(readFileSync(path.join(__dirname, `../../${dvnConfigPath}/aptos.json`), "utf8"));
    for (const _chainid of chainIds) {
        let dstConfig: lzConfigType | undefined;
        for (const config of lzConfig) {
            if (config.chainid === _chainid) {
                dstConfig = config;
                break;
            }
        }
        if (!dstConfig || dstConfig.eid === 0) throw Error(`EID not found for chainid: ${_chainid}`)

        const requiredSrcDVNs: any = []
        const dstDVNConfig = JSON.parse(readFileSync(path.join(__dirname, `../../${dvnConfigPath}/${_chainid}.json`), "utf8"));

        dvnKeys.forEach(key => {
            const dst = dstDVNConfig["aptos"]?.[key] ?? zeroAddress;
            const src = srcDVNConfig[_chainid]?.[key] ?? zeroBytes32;

            if (dst !== zeroAddress || src !== zeroBytes32) {
                if (dst === zeroAddress || src === zeroBytes32) {
                    throw new Error(`DVN Stack misconfigured: ${_chainid}<>aptos-${key}`);
                }
                requiredSrcDVNs.push(src);
            }
        });

        connectionConfig.push({
            from: aptosContract,
            to: {
                eid: dstConfig.eid,
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
                        executor: '',
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
        })

    }
    return connectionConfig
}

function generateDstConnectionConfig(lzConfig: lzConfigType[]): OmniEdgeHardhat<OAppEdgeConfig>[] {
    const connectionConfig: any[] = []
    const dstDVNConfig = JSON.parse(readFileSync(path.join(__dirname, `../../${dvnConfigPath}/aptos.json`), "utf8"));
    for (const _chainid of chainIds) {
        let dstConfig: lzConfigType | undefined;
        for (const config of lzConfig) {
            if (config.chainid === _chainid) {
                dstConfig = config
                // executor = config.ex
                break;
            }
        }
        if (!dstConfig || dstConfig.eid === 0) throw Error(`EID not found for chainid: ${_chainid}`)

        if (!dstConfig || dstConfig.eid === 0) throw Error("EID not found")
        if (!dstConfig || dstConfig.sendLib302 == zeroAddress) throw Error("sendlibrary not found")
        if (!dstConfig || dstConfig.receiveLib302 == zeroAddress) throw Error("receivelibrary not found")

        const requiredDstDVNs: any = []
        const srcDVNConfig = JSON.parse(readFileSync(path.join(__dirname, `../../${dvnConfigPath}/${_chainid}.json`), "utf8"));

        dvnKeys.forEach(key => {
            const dst = dstDVNConfig[_chainid]?.[key] ?? zeroBytes32;
            const src = srcDVNConfig["aptos"]?.[key] ?? zeroAddress;

            if (dst !== zeroBytes32 || src !== zeroAddress) {
                if (dst === zeroBytes32 || src === zeroAddress) {
                    throw new Error(`DVN Stack misconfigured: ${_chainid}<>aptos-${key}`);
                }
                requiredDstDVNs.push(src);
            }
        });

        connectionConfig.push({
            from: aptosContract,
            to: {
                eid: dstConfig.eid,
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
                sendLibrary: dstConfig.sendLib302,
                receiveLibraryConfig: {
                    // Required Receive Library Address on Aptos
                    receiveLibrary: dstConfig.receiveLib302,
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
                        executor: '',
                    },
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
        })
    }
    return connectionConfig
}

const config: OAppOmniGraphHardhat = {
    contracts: [
        ...generateContractConfig(L0Config.Proxy),
        {
            contract: aptosContract,
            config: {
                delegate: '0x09d0eb2763c96e085fa74ba6cf0d49136f8654c48ec7dbc59279a9066c7dd409',
                owner: '0x09d0eb2763c96e085fa74ba6cf0d49136f8654c48ec7dbc59279a9066c7dd409',
            },
        },
    ],
    connections: [
        ...generateSrcConnectionConfig(L0Config.Proxy),
        ...generateDstConnectionConfig(L0Config.Proxy),
    ],
}

export default config