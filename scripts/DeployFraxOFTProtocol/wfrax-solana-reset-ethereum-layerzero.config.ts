import { EndpointId } from '@layerzerolabs/lz-definitions'

import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'

import { generateConnectionsConfig } from '@layerzerolabs/metadata-tools';
import type { OAppEnforcedOption, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'


const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_MAINNET,
    address: '5vqBiG7nxNnoCst8mEVVS6ax7C1ypEEenPfcZ4kLgj9B', // NOTE: update this with the OFTStore address.
}

enum MsgType {
    SEND = 1,
    SEND_AND_CALL = 2,
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

export default async function () {
    const connections = await generateConnectionsConfig([
        [
            solanaContract,
            {
                eid: EndpointId.ETHEREUM_V2_MAINNET,
                contractName: "FraxOFTAdapterUpgradeable"
            },
            [['LayerZero Labs', 'Horizen'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
            [32, 5], // [A to B confirmations, B to A confirmations]
            [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain B enforcedOptions, Chain A enforcedOptions
        ]
    ])

    return {
        contracts: [{ contract: solanaContract }, {
            contract: {
                eid: EndpointId.ETHEREUM_V2_MAINNET,
                contractName: "FraxOFTAdapterUpgradeable"
            }
        }],
        connections
    }
}