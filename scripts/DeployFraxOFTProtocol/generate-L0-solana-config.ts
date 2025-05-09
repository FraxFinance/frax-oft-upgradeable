import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'

import type { OAppEdgeConfig, OAppOmniGraphHardhat, OmniEdgeHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import LOCOnfig4L0 from "../L0Config4L0.json"

enum MsgType {
    SEND = 1,
    SEND_AND_CALL = 2,
}

type OmniNodeHardhat = {
    contract: {
        eid: number
        contractName?: string
        address?: string
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
    frax: string,
    fpi: string,
    frxeth: string,
    sfrxeth: string
}

function getContractConfig(lzConfig: lzConfigType[], assetName: string): OmniNodeHardhat[] {
    return lzConfig.map(_config => ({
        contract: {
            eid: _config.eid,
            // address: _config[assetName],
            contractName: _config.contractName,
        },
        // config: {
        //     owner: _config.delegate,
        //     delegate: _config.delegate
        // }
    }))
}

function getConnectionConfig(lzConfig: lzConfigType[], sourceContract: OmniPointHardhat, assetName: string): OmniEdgeHardhat<OAppEdgeConfig>[] {

    let sourceOFTConfig: lzConfigType
    LOCOnfig4L0['Non-EVM'].forEach((nonEVMConfig: lzConfigType) => {
        if (nonEVMConfig.eid == sourceContract.eid) {
            sourceOFTConfig = nonEVMConfig
        }
    });

    return lzConfig.map(config => ({
        from: sourceContract,
        to: {
            eid: config.eid,
            // address: config[assetName],
            contractName: config.contractName,
        },
        config: {
            enforcedOptions: [
                {
                    msgType: MsgType.SEND,
                    optionType: ExecutorOptionType.LZ_RECEIVE,
                    gas: 200_000,
                    value: 0
                },
                {
                    msgType: MsgType.SEND_AND_CALL,
                    optionType: ExecutorOptionType.LZ_RECEIVE,
                    gas: 200_000,
                    value: 0
                },
            ],
            sendLibrary: sourceOFTConfig.sendLib302,
            receiveLibraryConfig: {
                receiveLibrary: sourceOFTConfig.receiveLib302 ?? "",
                gracePeriod: BigInt(0),
            },
            sendConfig: {
                ulnConfig: {
                    confirmations: BigInt(32),
                    requiredDVNs: [sourceOFTConfig.dvnHorizen ?? "", sourceOFTConfig.dvnL0 ?? ""],
                    optionalDVNs: [],
                    optionalDVNThreshold: 0,
                },
            },
            // Optional Receive Configuration
            // @dev Controls how the `from` chain receives messages from the `to` chain.
            receiveConfig: {
                ulnConfig: {
                    confirmations: BigInt(5),
                    requiredDVNs: [sourceOFTConfig.dvnHorizen ?? "", sourceOFTConfig.dvnL0 ?? ""],
                    optionalDVNs: [],
                    optionalDVNThreshold: 0,
                },
            },
        }
    }))
}

export function GenerateConfig(sourceContract: OmniPointHardhat, assetName: string): OAppOmniGraphHardhat {

    const config = {
        contracts: [
            ...getContractConfig(LOCOnfig4L0.Legacy.filter(configItem => configItem.contractName != ""), assetName),
            ...getContractConfig(LOCOnfig4L0.Proxy.filter(configItem => configItem.contractName != ""), assetName),
            {
                contract: sourceContract,
                config: {
                    delegate: 'FSRTW4KPGifKL8yKcZ8mfoR9mKtAjwZiTHbHwgix8AQo',
                    owner: 'FSRTW4KPGifKL8yKcZ8mfoR9mKtAjwZiTHbHwgix8AQo',
                },
            },
        ],
        connections: [
            ...getConnectionConfig(LOCOnfig4L0.Legacy.filter(configItem => configItem.contractName != ""), sourceContract, assetName),
            ...getConnectionConfig(LOCOnfig4L0.Proxy.filter(configItem => configItem.contractName != ""), sourceContract, assetName),
        ]
    }
    return config
}