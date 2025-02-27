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
        address: string
    }
    config?: {
        owner?: string
        delegate?: string
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
    executor?: string,
    contractName: string,
    frxUSD: string,
    sfrxUSD: string,
    fxs: string,
    fpi: string,
    frxeth: string,
    sfrxeth: string
}

function getContractConfig(lzConfig: lzConfigType[], assetName: string): OmniNodeHardhat[] {
    return lzConfig.map(config => ({
        contract: {
            eid: config.eid,
            contractName: config.contractName,
            address: lzConfig[assetName]
        },
        // config: {
        //     owner: config.delegate,
        //     delegate: config.delegate
        // }
    }))
}

function getConnectionConfig(lzConfig: lzConfigType[], sourceContract: OmniPointHardhat,assetName:string): OmniEdgeHardhat<OAppEdgeConfig>[] {

    let sourceOFTConfig: lzConfigType
    LOCOnfig['Non-EVM'].forEach((nonEVMConfig: lzConfigType) => {
        if (nonEVMConfig.eid == sourceContract.eid) {
            sourceOFTConfig = nonEVMConfig
        }
    });

    return lzConfig.map(config => ({
        from: sourceContract,
        to: {
            eid: config.eid,
            contractName: config.contractName,
            address:config[assetName]
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
                    gas: 80_000,
                    value: 0,
                },
            ],
            sendLibrary: sourceOFTConfig.sendLib302,
            receiveLibraryConfig: {
                receiveLibrary: sourceOFTConfig.receiveLib302 ?? "",
                gracePeriod: BigInt(0),
            },
            sendConfig: {
                executorConfig: {
                    maxMessageSize: 10_000,
                    executor: sourceOFTConfig.executor ?? "",
                },
                ulnConfig: {
                    confirmations: BigInt(10),
                    requiredDVNs: [sourceOFTConfig.dvnHorizen ?? "", sourceOFTConfig.dvnL0 ?? ""],
                    optionalDVNs: [],
                    optionalDVNThreshold: 0,
                },
            },
            // Optional Receive Configuration
            // @dev Controls how the `from` chain receives messages from the `to` chain.
            receiveConfig: {
                ulnConfig: {
                    confirmations: BigInt(2),
                    requiredDVNs: [sourceOFTConfig.dvnHorizen ?? "", sourceOFTConfig.dvnL0 ?? ""],
                    optionalDVNs: [],
                    optionalDVNThreshold: 0,
                },
            },
        }
    }))
}

export function GenerateConfig(sourceContract: OmniPointHardhat, assetName: string): OAppOmniGraphHardhat {

    return {
        contracts: [
            ...getContractConfig(LOCOnfig.Legacy, assetName),
            ...getContractConfig(LOCOnfig.Proxy, assetName),
            {
                contract: sourceContract,
                // config: {
                //     delegate: '',
                //     owner: '',
                // },
            },
        ],
        connections: [
            ...getConnectionConfig(LOCOnfig.Legacy, sourceContract,assetName),
            ...getConnectionConfig(LOCOnfig.Proxy, sourceContract,assetName)
        ]
    }
}