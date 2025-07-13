import { EndpointId } from '@layerzerolabs/lz-definitions'
import { getOftStoreAddress } from '../../tasks/solana'
import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'

enum MsgType {
    SEND = 1,
    SEND_AND_CALL = 2,
}

const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_MAINNET,
    address: getOftStoreAddress(EndpointId.SOLANA_V2_MAINNET),
}

const movementContract: OmniPointHardhat = {
    eid: EndpointId.MOVEMENT_V2_MAINNET,
    contractName: 'MockFraxOFT',
    address: "0xa1bb74f0d5770dfc905c508e6273fadc595ddc15326cc907889bdfffa50602c8"
}

const aptosContract: OmniPointHardhat = {
    eid: EndpointId.APTOS_V2_MAINNET,
    contractName: 'MockFraxOFT',
    address: "0xa1bb74f0d5770dfc905c508e6273fadc595ddc15326cc907889bdfffa50602c8"
}

const config = {
    contracts: [
        {
            contract: solanaContract,
            config: {
                delegate: '53dNdHXc7uruWqELhWtpx4f4UvpPk5SaT1upQNoKdi7y',
                owner: '53dNdHXc7uruWqELhWtpx4f4UvpPk5SaT1upQNoKdi7y',
            },
        },
        {
            contract: movementContract
        },
        {
            contract: aptosContract
        }
    ],
    connections: [
        {
            from: solanaContract,
            to: aptosContract,
            config: {
                enforcedOptions: [
                    {
                        msgType: MsgType.SEND,
                        optionType: ExecutorOptionType.LZ_RECEIVE,
                        gas: 80_000,
                        value: 0
                    },
                    {
                        msgType: MsgType.SEND_AND_CALL,
                        optionType: ExecutorOptionType.LZ_RECEIVE,
                        gas: 80_000,
                        value: 0
                    },
                ],
                sendLibrary: "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH",
                receiveLibraryConfig: {
                    receiveLibrary: "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH",
                    gracePeriod: BigInt(0),
                },
                sendConfig: {
                    ulnConfig: {
                        confirmations: BigInt(32),
                        requiredDVNs: ["5SBjhryFdSwrmVfm9GFJu5GhKDiphLQbay3GTfx9ArUt", "HR9NQKK1ynW9NzgdM37dU5CBtqRHTukmbMKS7qkwSkHX", "4VDjp6XQaxoZf5RGwiPU9NR1EXSZn2TP4ATMmiSzLfhb"],
                        optionalDVNs: [],
                        optionalDVNThreshold: 0,
                    },
                },
                // Optional Receive Configuration
                // @dev Controls how the `from` chain receives messages from the `to` chain.
                receiveConfig: {
                    ulnConfig: {
                        confirmations: BigInt(5),
                        requiredDVNs: ["5SBjhryFdSwrmVfm9GFJu5GhKDiphLQbay3GTfx9ArUt", "HR9NQKK1ynW9NzgdM37dU5CBtqRHTukmbMKS7qkwSkHX", "4VDjp6XQaxoZf5RGwiPU9NR1EXSZn2TP4ATMmiSzLfhb"],
                        optionalDVNs: [],
                        optionalDVNThreshold: 0,
                    },
                },
            }
        },
        {
            from: solanaContract,
            to: movementContract,
            config: {
                enforcedOptions: [
                    {
                        msgType: MsgType.SEND,
                        optionType: ExecutorOptionType.LZ_RECEIVE,
                        gas: 80_000,
                        value: 0
                    },
                    {
                        msgType: MsgType.SEND_AND_CALL,
                        optionType: ExecutorOptionType.LZ_RECEIVE,
                        gas: 80_000,
                        value: 0
                    },
                ],
                sendLibrary: "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH",
                receiveLibraryConfig: {
                    receiveLibrary: "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH",
                    gracePeriod: BigInt(0),
                },
                sendConfig: {
                    ulnConfig: {
                        confirmations: BigInt(32),
                        requiredDVNs: ["5SBjhryFdSwrmVfm9GFJu5GhKDiphLQbay3GTfx9ArUt", "HR9NQKK1ynW9NzgdM37dU5CBtqRHTukmbMKS7qkwSkHX", "4VDjp6XQaxoZf5RGwiPU9NR1EXSZn2TP4ATMmiSzLfhb"],
                        optionalDVNs: [],
                        optionalDVNThreshold: 0,
                    },
                },
                // Optional Receive Configuration
                // @dev Controls how the `from` chain receives messages from the `to` chain.
                receiveConfig: {
                    ulnConfig: {
                        confirmations: BigInt(5),
                        requiredDVNs: ["5SBjhryFdSwrmVfm9GFJu5GhKDiphLQbay3GTfx9ArUt", "HR9NQKK1ynW9NzgdM37dU5CBtqRHTukmbMKS7qkwSkHX", "4VDjp6XQaxoZf5RGwiPU9NR1EXSZn2TP4ATMmiSzLfhb"],
                        optionalDVNs: [],
                        optionalDVNThreshold: 0,
                    },
                },
            }
        }
    ]
}

export default config