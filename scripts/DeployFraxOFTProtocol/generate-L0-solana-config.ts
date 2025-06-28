import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { generateConnectionsConfig, TwoWayConfig } from '@layerzerolabs/metadata-tools'
import type { OAppEnforcedOption, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

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


const SOLANA_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: MsgType.SEND,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 200_000,
        value: 0,
    },
    {
        msgType: MsgType.SEND_AND_CALL,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 200_000,
        value: 0,
    },
]

const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: MsgType.SEND,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 80000,
        value: 0,
    },
    {
        msgType: MsgType.SEND_AND_CALL,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 80000,
        value: 0,
    },
]

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

function getConnectionConfig(lzConfig: lzConfigType[], sourceContract: OmniPointHardhat, assetName: string): TwoWayConfig[] {

    let sourceOFTConfig: lzConfigType
    LOCOnfig4L0['Non-EVM'].forEach((nonEVMConfig: lzConfigType) => {
        if (nonEVMConfig.eid == sourceContract.eid) {
            sourceOFTConfig = nonEVMConfig
        }
    });

    return lzConfig.map(config => [
        sourceContract, // Chain A
        {
            eid: config.eid,
            contractName: config.contractName
        }, // Chain B
        [['LayerZero Labs', 'Horizen'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
        [32, 5], // [A to B confirmations, B to A confirmations]
        [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain B enforcedOptions, Chain A enforcedOptions
    ])
}

export async function GenerateConfig(sourceContract: OmniPointHardhat, assetName: string) {
    const connections = await generateConnectionsConfig([
        ...getConnectionConfig(LOCOnfig4L0.Legacy.filter(configItem => configItem.contractName != ""), sourceContract, assetName),
        ...getConnectionConfig(LOCOnfig4L0.Proxy.filter(configItem => configItem.contractName != ""), sourceContract, assetName),
    ])

    return {
        contracts: [
            {
                contract: sourceContract,
                config: {
                    delegate: 'FSRTW4KPGifKL8yKcZ8mfoR9mKtAjwZiTHbHwgix8AQo',
                    owner: 'FSRTW4KPGifKL8yKcZ8mfoR9mKtAjwZiTHbHwgix8AQo',
                }
            },
            ...getContractConfig(LOCOnfig4L0.Legacy.filter(configItem => configItem.contractName != ""), assetName),
            ...getContractConfig(LOCOnfig4L0.Proxy.filter(configItem => configItem.contractName != ""), assetName),
        ],
        connections,
    }
}