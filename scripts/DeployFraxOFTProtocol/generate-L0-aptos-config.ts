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
    executor?: string 
}

function getContractConfig(lzConfig: lzConfigType[]): OmniNodeHardhat[] {
    return lzConfig.map(config => ({
        contract: {
            eid: config.eid,
            contractName: 'FraxOFTUpgradeable'
        },
        config: {
            owner: config.delegate,
            delegate: config.delegate
        }
    }))
}

function getConnectionConfig(lzConfig: lzConfigType[], sourceContract: OmniPointHardhat): OmniEdgeHardhat<OAppEdgeConfig>[] {

    let sourceOFTConfig
    LOCOnfig['Non-EVM'].forEach(nonEVMConfig => {
        if (nonEVMConfig.eid == sourceContract.eid) {
            sourceOFTConfig = nonEVMConfig
        }
    });

    return lzConfig.map(config => ({
        from: sourceContract,
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
                    gas: 80_000,
                    value: 0,
                },
            ],
            sendLibrary: sourceOFTConfig.sendLib302,
            receiveLibraryConfig: {
                receiveLibrary: sourceOFTConfig.receiveLib302,
                gracePeriod: BigInt(0),
            },
            sendConfig: {
                executorConfig: {
                    maxMessageSize: 10_000,
                    executor: sourceOFTConfig.executor,
                },
                ulnConfig: {
                    confirmations: BigInt(260),
                    requiredDVNs: [sourceOFTConfig.dvnHorizen, sourceOFTConfig.dvnL0],
                    optionalDVNs: [],
                    optionalDVNThreshold: 0,
                },
            },
            // Optional Receive Configuration
            // @dev Controls how the `from` chain receives messages from the `to` chain.
            receiveConfig: {
                ulnConfig: {
                    confirmations: BigInt(5),
                    requiredDVNs: [sourceOFTConfig.dvnHorizen, sourceOFTConfig.dvnL0],
                    optionalDVNs: [],
                    optionalDVNThreshold: 0,
                },
            },
        }
    }))
}

export function GenerateConfig(sourceContract: OmniPointHardhat): OAppOmniGraphHardhat {

    return {
        contracts: [
            ...getContractConfig(LOCOnfig.Legacy),
            ...getContractConfig(LOCOnfig.Proxy),
            {
                contract: sourceContract,
                config: {
                    delegate: '',
                    owner: '',
                },
            },
        ],
        connections: [
            ...getConnectionConfig(LOCOnfig.Legacy, sourceContract),
            ...getConnectionConfig(LOCOnfig.Proxy, sourceContract)
        ]
    }
}