import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import type { OAppEdgeConfig, OmniEdgeHardhat } from '@layerzerolabs/toolbox-hardhat'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import L0Config from "../L0Config.json"

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

const chainIds = [
    1, 10, 56, 130, 137, 146, 196, 252, 324, 480, 1101, 1329, 2741, 8453, 34443, 42161, 43114, 57073, 59144, 80094, 81457
];

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    contractName: 'FraxOFTMintableUpgradeable',
}

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
    return chainIds.filter(id => id != 252).map(_chainid => {
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
                contractName: "MockFRAXUpgradeable"
            }
        }
    }
    )
}

function generateConnectionConfig(lzConfig: lzConfigType[]): OmniEdgeHardhat<OAppEdgeConfig>[] {
    return chainIds.filter(id => id != 252).map(_chainid => {
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
            from: aptosContract,
            to: {
                eid: eid,
                contractName: "MockFRAXUpgradeable"
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
                        requiredDVNs: ['0x2b696b3ee859b7eb624e1fd5de49f4d3806f49862f1177d6827fd1beffde9179', '0xdf8f0a53b20f1656f998504b81259698d126523a31bdbbae45ba1e8a3078d8da'],
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
                        requiredDVNs: ['0x2b696b3ee859b7eb624e1fd5de49f4d3806f49862f1177d6827fd1beffde9179', '0xdf8f0a53b20f1656f998504b81259698d126523a31bdbbae45ba1e8a3078d8da'],
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
}

const config: OAppOmniGraphHardhat = {
    contracts: [
        {
            contract: fraxtalContract,
            config: {
                owner: '0x45dce8e4f2dc005a5f28206a46cb034697eeda8e',
                delegate: '0x45dce8e4f2dc005a5f28206a46cb034697eeda8e',
            },
        },
        ...generateContractConfig(L0Config.Proxy.filter(config => config.chainid != 252)),
        {
            contract: aptosContract,
            config: {
                delegate: '',
                owner: '',
            },
        },
    ],
    connections: [
        ...generateConnectionConfig(L0Config.Proxy.filter(config => config.chainid != 252)),
    ],
}

export default config