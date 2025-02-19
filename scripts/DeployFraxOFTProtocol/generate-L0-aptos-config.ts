import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'

import type { OAppEdgeConfig, OAppOmniGraphHardhat, OmniEdgeHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import LOCOnfig from "../L0Config.json"

enum MsgType {
    SEND = 1,
    SEND_AND_CALL = 2,
}

type OmniNodeHardhat = {
    contract: {
        eid: number
        contractName: string
    }
    config: {
        owner: string
        delegate: string
    }
}

type lzConfigType = {
    RPC: string,
    chainid: number,
    delegate: string,
    dvnHorizen?: string,
    dvnL0?: string,
    dvn1?: string,
    dvn2?: string,
    eid: number,
    endpoint: string,
    receiveLib302: string,
    sendLib302: string
}

function getContractConfig(lzConfig: lzConfigType[]): OmniNodeHardhat[] {
    return lzConfig.map(config => ({
        contract: {
            eid: config.eid,
            contractName: 'FraxOFTUpgradeable'
        },
        config: {
            owner: '',
            delegate: ''
        }
    }))
}

function getConnectionConfig(lzConfig: lzConfigType[], contract: OmniPointHardhat): OmniEdgeHardhat<OAppEdgeConfig>[] {

    return lzConfig.map(config => ({
        from: contract,
        to: {
                eid: config.eid,
                contractName: 'FraxOFTUpgradeable'
        },
        config: {
            enforcedOptions: [
                {
                    msgType: MsgType.SEND,
                    optionType: ExecutorOptionType.LZ_RECEIVE,
                    gas: 80_000,
                    value: 0,
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
            sendConfig: {
                executorConfig: {
                    maxMessageSize: 10_000,
                    // The configured Executor address on Aptos
                    executor: '0x15a5bbf1eb7998a22c9f23810d424abe40bd59ddd8e6ab7e59529853ebed41c4',
                },
                ulnConfig: {
                    // The number of block confirmations to wait on Aptos before emitting the message from the source chain.
                    confirmations: BigInt(260),
                    // The address of the DVNs you will pay to verify a sent message on the source chain.
                    // The destination tx will wait until ALL `requiredDVNs` verify the message.
                    requiredDVNs: ['0x93adea241d46ddebc207d74402ff9a150f70b9de828b8b2208d69b7d08e90bd7', '0xdf8f0a53b20f1656f998504b81259698d126523a31bdbbae45ba1e8a3078d8da'],
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
                    requiredDVNs: ['0x93adea241d46ddebc207d74402ff9a150f70b9de828b8b2208d69b7d08e90bd7', '0xdf8f0a53b20f1656f998504b81259698d126523a31bdbbae45ba1e8a3078d8da'],
                    // The address of the `optionalDVNs` you expect to receive verifications from on the `from` chain.
                    // The destination tx will wait until the configured threshold of `optionalDVNs` verify the message.
                    optionalDVNs: [],
                    // The number of `optionalDVNs` that need to successfully verify the message for it to be considered Verified.
                    optionalDVNThreshold: 0,
                },
            },
        }
    }))
}

export function GenerateConfig(contract: OmniPointHardhat): OAppOmniGraphHardhat {

    return {
        contracts: [
            ...getContractConfig(LOCOnfig.Legacy),
            ...getContractConfig(LOCOnfig.Proxy),
            {
                contract: contract,
                config: {
                    delegate: '',
                    owner: '',
                },
            },
        ],
        connections: [
            ...getConnectionConfig(LOCOnfig.Legacy, contract),
            ...getConnectionConfig(LOCOnfig.Proxy, contract)
        ]
    }
}