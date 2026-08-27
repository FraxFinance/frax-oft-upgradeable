import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { OAppEdgeConfig } from '@layerzerolabs/toolbox-hardhat'

enum MsgType {
    SEND = 1,
    SEND_AND_CALL = 2,
}

// TODO : blockSendLibrary (move and aptos) : 0x3ca0d187f1938cf9776a0aa821487a650fc7bb2ab1c1d241ba319192aae4afc6

export const movementToFraxtalconnectionConfig: OAppEdgeConfig = {

    enforcedOptions: [
        {
            msgType: MsgType.SEND,
            optionType: ExecutorOptionType.LZ_RECEIVE,
            gas: 200_000, // gas limit in wei for EndpointV2.lzReceive
            value: 0, // msg.value in wei for EndpointV2.lzReceive
        },
        {
            msgType: MsgType.SEND_AND_CALL,
            optionType: ExecutorOptionType.LZ_RECEIVE,
            gas: 200_000, // gas limit in wei for EndpointV2.lzReceive
            value: 0, // msg.value in wei for EndpointV2.lzReceive
        },
    ],
    sendLibrary: '0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9',
    receiveLibraryConfig: {
        // Required Receive Library Address on Movement
        receiveLibrary: '0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9',
        // Optional Grace Period for Switching Receive Library Address on Movement
        gracePeriod: BigInt(0),
    },
    // Optional Receive Library Timeout for when the Old Receive Library Address will no longer be valid on Movement
    // receiveLibraryTimeoutConfig: {
    //     lib: '',
    //     expiry: BigInt(1000000000),
    // },
    sendConfig: {
        executorConfig: {
            maxMessageSize: 10_000,
            // The configured Executor address on Movement
            executor: '0x15a5bbf1eb7998a22c9f23810d424abe40bd59ddd8e6ab7e59529853ebed41c4',
        },
        ulnConfig: {
            // The number of block confirmations to wait on Aptos before emitting the message from the source chain.
            confirmations: BigInt(30000),
            // The address of the DVNs you will pay to verify a sent message on the source chain.
            // The destination tx will wait until ALL `requiredDVNs` verify the message.
            requiredDVNs: ['0xc4a5d892efdf6689d2595c3f438e465702b5a7db0bed8125c4e218464a14ba28', '0x2b696b3ee859b7eb624e1fd5de49f4d3806f49862f1177d6827fd1beffde9179', '0xdf8f0a53b20f1656f998504b81259698d126523a31bdbbae45ba1e8a3078d8da', '0x0da7ab938aa044372db0d66a3a370d4479042b3f31e2a30940a157647065b46b'],
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
            requiredDVNs: ['0xc4a5d892efdf6689d2595c3f438e465702b5a7db0bed8125c4e218464a14ba28', '0x2b696b3ee859b7eb624e1fd5de49f4d3806f49862f1177d6827fd1beffde9179', '0xdf8f0a53b20f1656f998504b81259698d126523a31bdbbae45ba1e8a3078d8da', '0x0da7ab938aa044372db0d66a3a370d4479042b3f31e2a30940a157647065b46b'],
            // The address of the `optionalDVNs` you expect to receive verifications from on the `from` chain.
            // The destination tx will wait until the configured threshold of `optionalDVNs` verify the message.
            optionalDVNs: [],
            // The number of `optionalDVNs` that need to successfully verify the message for it to be considered Verified.
            optionalDVNThreshold: 0,
        },
    },
}

export const aptosToFraxtalconnectionConfig: OAppEdgeConfig = {

    enforcedOptions: [
        {
            msgType: MsgType.SEND,
            optionType: ExecutorOptionType.LZ_RECEIVE,
            gas: 200_000, // gas limit in wei for EndpointV2.lzReceive
            value: 0, // msg.value in wei for EndpointV2.lzReceive
        },
        {
            msgType: MsgType.SEND_AND_CALL,
            optionType: ExecutorOptionType.LZ_RECEIVE,
            gas: 200_000, // gas limit in wei for EndpointV2.lzReceive
            value: 0, // msg.value in wei for EndpointV2.lzReceive
        },
    ],
    sendLibrary: '0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9',
    receiveLibraryConfig: {
        // Required Receive Library Address on Movement
        receiveLibrary: '0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9',
        // Optional Grace Period for Switching Receive Library Address on Movement
        gracePeriod: BigInt(0),
    },
    // Optional Receive Library Timeout for when the Old Receive Library Address will no longer be valid on Movement
    // receiveLibraryTimeoutConfig: {
    //     lib: '',
    //     expiry: BigInt(1000000000),
    // },
    sendConfig: {
        executorConfig: {
            maxMessageSize: 10_000,
            // The configured Executor address on Movement
            executor: '0x15a5bbf1eb7998a22c9f23810d424abe40bd59ddd8e6ab7e59529853ebed41c4',
        },
        ulnConfig: {
            // The number of block confirmations to wait on Aptos before emitting the message from the source chain.
            confirmations: BigInt(30000),
            // The address of the DVNs you will pay to verify a sent message on the source chain.
            // The destination tx will wait until ALL `requiredDVNs` verify the message.
            requiredDVNs: ['0x3d5c8533fa5dfa60c953036e9a2afe3e9d3fc614197feebf8599ec1f54e8f2ec', '0x9880ed7ade7e7f8f8eb070ce72c51b231921e29e65b3d51fa3810814bba32c00', '0xf3f0a412626edba5ddd3613d91109b241893873ac5479ade231cf0b3130572b5', '0x07ad47ea4f858e7189d2c6e7327f166993e8f884386db9564d732bcff63fe4ff'],
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
            requiredDVNs: ['0x3d5c8533fa5dfa60c953036e9a2afe3e9d3fc614197feebf8599ec1f54e8f2ec', '0x9880ed7ade7e7f8f8eb070ce72c51b231921e29e65b3d51fa3810814bba32c00', '0xf3f0a412626edba5ddd3613d91109b241893873ac5479ade231cf0b3130572b5', '0x07ad47ea4f858e7189d2c6e7327f166993e8f884386db9564d732bcff63fe4ff'],
            // The address of the `optionalDVNs` you expect to receive verifications from on the `from` chain.
            // The destination tx will wait until the configured threshold of `optionalDVNs` verify the message.
            optionalDVNs: [],
            // The number of `optionalDVNs` that need to successfully verify the message for it to be considered Verified.
            optionalDVNThreshold: 0,
        },
    },
}

export const fraxtalContractConfig = {
    owner: '0x5f25218ed9474b721d6a38c115107428E832fA2E',
    delegate: '0x5f25218ed9474b721d6a38c115107428E832fA2E',
}

export const movementContractConfig = {
    delegate: '0xda80fe6404a059e99569ba06f8d87814b3a9521c8d6c78ac5ed4ca75ad867ab3',
    owner: '0xda80fe6404a059e99569ba06f8d87814b3a9521c8d6c78ac5ed4ca75ad867ab3',
}

export const aptosContractConfig = {
    delegate: '0x6f9e27569fb34873f13a6868b3732b384f81c89fb525a623a969fdba155de21c',
    owner: '0x6f9e27569fb34873f13a6868b3732b384f81c89fb525a623a969fdba155de21c',
}