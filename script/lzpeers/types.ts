// Define the UlnConfig type
export interface UlnConfig {
    confirmations: number;
    requiredDVNCount: number;
    optionalDVNCount: number;
    optionalDVNThreshold: number;
    requiredDVNs: string[];
    optionalDVNs: string[];
}

export type assetListType = {
    frxUSD: string;
    sfrxUSD: string;
    frxETH: string;
    sfrxETH: string;
    WFRAX: string;
    FPI: string;
}

export type ChainInfo = {
    client: any; // Replace `any` with the actual type from `createPublicClient`
    peerId: number;
    endpoint: string;
    receiveLib302: string;
    sendLib302: string;
    oApps?: assetListType;
    hop?:string;
    mintRedeemHop?:string;
};

export type OFTEnforcedOptions = {
    gas: string;
    value: string;
}

export type ReceiveLibraryTimeOutInfo = {
    libAddress: string;
    expiry: string;
}

export type EndpointConfig = {
    send: UlnConfig;
    receive: UlnConfig;
}

export type ReceiveLibraryType = {
    receiveLibraryAddress: string
    isDefault: boolean
}

export type OFTMetadata = {
    address: string,
    abi: any
}

export type ExecutorConfigType = {
    maxMessageSize: number
    executorAddress: string
}

export type OFTInfo = {
    peerAddress: string;
    peerAddressBytes32: string;
    combinedOptionsSend: OFTEnforcedOptions
    combinedOptionsSendAndCall: OFTEnforcedOptions
    enforcedOptions: OFTEnforcedOptions
    defaultReceiveLibrary: string;
    defaultReceiveLibraryTimeOut: ReceiveLibraryTimeOutInfo;
    defaultSendLibrary: string;
    appUlnConfig: EndpointConfig;
    appUlnDefaultConfig: EndpointConfig;
    ulnConfig: EndpointConfig;
    ulnDefaultConfig: EndpointConfig;
    receiveLibSupportEid: boolean;
    defaultReceiveLibSupportEid: boolean;
    sendLibSupportEid: boolean;
    defaultSendLibSupportEid: boolean;
    receiveLibrary: ReceiveLibraryType;
    sendLibrary: string;
    isDefaultSendLibrary: boolean;
    receiveLibraryTimeOut: ReceiveLibraryTimeOutInfo;
    executorConfig: ExecutorConfigType;
    defaultExecutorConfig: ExecutorConfigType;
}

export interface TokenSupplyData {
    chain: string
    blockNumber?: string
    token: string
    rawSupply: string
    totalTransferFromFraxtal?: string
    totalTransferToFraxtal?: string
    totalTransferFromEthereum?: string
    totalTransferToEthereum?: string
    supply: string
}