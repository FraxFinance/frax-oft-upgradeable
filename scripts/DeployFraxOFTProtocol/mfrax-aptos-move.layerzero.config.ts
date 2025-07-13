import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import type { OAppEdgeConfig, OmniEdgeHardhat } from '@layerzerolabs/toolbox-hardhat'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import L0Config from "../L0Config.json"
import { checksumAddress, zeroAddress } from 'viem'
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

const executors = {
    1: "0x173272739Bd7Aa6e4e214714048a9fE699453059",
    10: "0x2D2ea0697bdbede3F01553D2Ae4B8d0c486B666e",
    56: "0x3ebD570ed38B1b3b4BC886999fcF507e9D584859",
    130: "0x4208D6E27538189bB48E603D6123A94b8Abe0A0b",
    137: "0xCd3F213AD101472e1713C72B1697E727C803885b",
    146: "0x4208D6E27538189bB48E603D6123A94b8Abe0A0b",
    196: "0xcCE466a522984415bC91338c232d98869193D46e",
    252: "0x41Bdb4aa4A63a5b2Efc531858d3118392B1A1C3d",
    324: "0x664e390e672A811c12091db8426cBb7d68D5D8A6",
    480: "0xcCE466a522984415bC91338c232d98869193D46e",
    1101: "0xbE4fB271cfB7bcbB47EA9573321c7bfe309fc220",
    1329: "0xc097ab8CD7b053326DFe9fB3E3a31a0CCe3B526f",
    2741: "0x643E1471f37c4680Df30cF0C540Cd379a0fF58A5",
    8453: "0x2CCA08ae69E0C44b18a57Ab2A87644234dAebaE4",
    34443: "0x4208D6E27538189bB48E603D6123A94b8Abe0A0b",
    42161: "0x31CAe3B7fB82d847621859fb1585353c5720660D",
    43114: "0x90E595783E43eb89fF07f63d27B8430e6B44bD9c",
    57073: "0xFEbCF17b11376C724AB5a5229803C6e838b6eAe5",
    59144: "0x0408804C5dcD9796F22558464E6fE5bDdF16A7c7",
    80094: "0x4208D6E27538189bB48E603D6123A94b8Abe0A0b",
    81457: "0x4208D6E27538189bB48E603D6123A94b8Abe0A0b"
}

interface ConfirmationType {
    send: number;
    receive: number;
}

interface ConfirmationsMap {
    [chainId: number]: ConfirmationType;
}

const confirmations: ConfirmationsMap = {
    1: {
        send: 260,
        receive: 15
    },
    10: {
        send: 260,
        receive: 20
    },
    56: {
        send: 260,
        receive: 20
    },
    130: {
        send: 260,
        receive: 20,
    },
    137: {
        send: 260,
        receive: 512
    },
    146: {
        send: 260,
        receive: 20
    },
    196: {
        send: 260,
        receive: 225000
    },
    252: {
        send: 260,
        receive: 5
    },
    324: {
        send: 260,
        receive: 20
    },
    1329: {
        send: 260,
        receive: 5
    },
    8453: {
        send: 260,
        receive: 10
    },
    34443: {
        send: 260,
        receive: 5
    },
    42161: {
        send: 260,
        receive: 20
    },
    43114: {
        send: 260,
        receive: 12
    },
    59144: {
        send: 260,
        receive: 10
    },
    80094: {
        send: 260,
        receive: 20
    },
    81457: {
        send: 260,
        receive: 5
    }
}

const aptosContract: OmniPointHardhat = {
    eid: EndpointId.APTOS_V2_MAINNET,
    contractName: 'MockFraxOFT',
    address: "0xa1bb74f0d5770dfc905c508e6273fadc595ddc15326cc907889bdfffa50602c8"
}

const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_MAINNET,
    contractName: 'mFRAX',
    address: "12fneM2nVTNuxDkrFZ82FQkYB7DMLHtBeu8A55rvnz8U" // oftstore
}

// Note. aptos is not yet a peer of movement

function generateContractConfig(lzConfig: lzConfigType[]) {
    const contractConfig: any[] = []

    // aptos mainnet is not yet connected to zkpolygon(1101), worldchain(480), abstract(2741) 
    // and ink(57073) while this config was developed
    const filteredChainIds = chainIds.filter(id => id !== 1101
        && id !== 480 && id !== 2741 && id !== 57073)

    for (const _chainid of filteredChainIds) {
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
    const srcDVNConfig = JSON.parse(readFileSync(path.join(__dirname, `../../${dvnConfigPath}/33333333.json`), "utf8"));

    // aptos mainnet is not yet connected to zkpolygon(1101), worldchain(480), abstract(2741) 
    // and ink(57073) while this config was developed
    const filteredChainIds = chainIds.filter(id => id !== 1101
        && id !== 480 && id !== 2741 && id !== 57073)

    for (const _chainid of filteredChainIds) {
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
            const dst = dstDVNConfig["33333333"]?.[key] ?? zeroAddress;
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
                        executor: "0x15a5bbf1eb7998a22c9f23810d424abe40bd59ddd8e6ab7e59529853ebed41c4",
                    },
                    ulnConfig: {
                        // The number of block confirmations to wait on Aptos before emitting the message from the source chain.
                        confirmations: BigInt(confirmations[_chainid].send),
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
                        confirmations: BigInt(confirmations[_chainid].receive),
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
    const dstDVNConfig = JSON.parse(readFileSync(path.join(__dirname, `../../${dvnConfigPath}/33333333.json`), "utf8"));

    // aptos mainnet is not yet connected to zkpolygon(1101), worldchain(480), abstract(2741) 
    // and ink(57073) while this config was developed
    const filteredChainIds = chainIds.filter(id => id !== 1101
        && id !== 480 && id !== 2741 && id !== 57073)

    for (const _chainid of filteredChainIds) {
        let dstConfig: lzConfigType | undefined;
        let executorAddress
        for (const config of lzConfig) {
            if (config.chainid === _chainid) {
                dstConfig = config
                executorAddress = executors[config.chainid]
                break;
            }
        }
        if (!dstConfig || dstConfig.eid === 0) throw Error(`EID not found for chainid: ${_chainid}`)

        if (!dstConfig || dstConfig.eid === 0) throw Error("EID not found")
        if (!dstConfig || dstConfig.sendLib302 == zeroAddress) throw Error("sendlibrary not found")
        if (!dstConfig || dstConfig.receiveLib302 == zeroAddress) throw Error("receivelibrary not found")

        const requiredDstDVNs: string[] = []
        const srcDVNConfig = JSON.parse(readFileSync(path.join(__dirname, `../../${dvnConfigPath}/${_chainid}.json`), "utf8"));

        dvnKeys.forEach(key => {
            const dst = dstDVNConfig[_chainid]?.[key] ?? zeroBytes32;
            const src = srcDVNConfig["33333333"]?.[key] ?? zeroAddress;

            if (dst !== zeroBytes32 || src !== zeroAddress) {
                if (dst === zeroBytes32 || src === zeroAddress) {
                    throw new Error(`DVN Stack misconfigured: ${_chainid}<>aptos-${key}`);
                }
                requiredDstDVNs.push(checksumAddress(src));
            }
        });

        connectionConfig.push({
            from: {
                eid: dstConfig.eid,
                contractName: _chainid == 252 ? "FraxOFTMintableUpgradeable" : "MockFRAXUpgradeable"
            },
            to: aptosContract,
            config: {
                enforcedOptions: [
                    {
                        msgType: MsgType.SEND,
                        optionType: ExecutorOptionType.LZ_RECEIVE,
                        gas: 5_000, // gas limit in wei for EndpointV2.lzReceive
                        value: 0, // msg.value in wei for EndpointV2.lzReceive
                    },
                    {
                        msgType: MsgType.SEND_AND_CALL,
                        optionType: ExecutorOptionType.LZ_RECEIVE,
                        gas: 5_000, // gas limit in wei for EndpointV2.lzCompose
                        value: 0, // msg.value in wei for EndpointV2.lzCompose
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
                        executor: executorAddress,
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
        {
            contract: solanaContract,
        },
    ],
    connections: [
        ...generateSrcConnectionConfig(L0Config.Proxy),
        ...generateDstConnectionConfig(L0Config.Proxy),
        {
            from: aptosContract,
            to: solanaContract,
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
                        maxMessageSize: 200,
                        // The configured Executor address on Aptos
                        executor: "0x15a5bbf1eb7998a22c9f23810d424abe40bd59ddd8e6ab7e59529853ebed41c4",
                    },
                    ulnConfig: {
                        // The number of block confirmations to wait on Aptos before emitting the message from the source chain.
                        confirmations: BigInt(1000000),
                        // The address of the DVNs you will pay to verify a sent message on the source chain.
                        // The destination tx will wait until ALL `requiredDVNs` verify the message.
                        requiredDVNs: ["0x3d5c8533fa5dfa60c953036e9a2afe3e9d3fc614197feebf8599ec1f54e8f2ec", "0x93adea241d46ddebc207d74402ff9a150f70b9de828b8b2208d69b7d08e90bd7", "0xdf8f0a53b20f1656f998504b81259698d126523a31bdbbae45ba1e8a3078d8da"],
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
                        confirmations: BigInt(32),
                        // The address of the DVNs your `receiveConfig` expects to receive verifications from on the `from` chain.
                        // The `from` chain's OApp will wait until the configured threshold of `requiredDVNs` verify the message.
                        requiredDVNs: ["0x3d5c8533fa5dfa60c953036e9a2afe3e9d3fc614197feebf8599ec1f54e8f2ec", "0x93adea241d46ddebc207d74402ff9a150f70b9de828b8b2208d69b7d08e90bd7", "0xdf8f0a53b20f1656f998504b81259698d126523a31bdbbae45ba1e8a3078d8da"],
                        // The address of the `optionalDVNs` you expect to receive verifications from on the `from` chain.
                        // The destination tx will wait until the configured threshold of `optionalDVNs` verify the message.
                        optionalDVNs: [],
                        // The number of `optionalDVNs` that need to successfully verify the message for it to be considered Verified.
                        optionalDVNThreshold: 0,
                    },
                },
            },
        },
    ],
}

export default config