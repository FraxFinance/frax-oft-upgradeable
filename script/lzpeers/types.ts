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
    wfrax: string;
    fpi: string;
}

export type ChainInfo = {
    client: any; // Replace `any` with the actual type from `createPublicClient`
    peerId: number;
    endpoint: string;
    receiveLib302: string;
    sendLib302: string;
    blockSendLib: string;
    fraxProxyAdmin: string;
    oApps?: assetListType;
    hop?: string;
    mintRedeemHop?: string;
};

export type OFTEnforcedOptions = {
    gas: number;
    value: number;
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
    eid: string
    isSupportedEid: string
    peerAddress: string;
    peerAddressBytes32: string;
    enforcedOptionsSend: OFTEnforcedOptions
    enforcedOptionsSendAndCall: OFTEnforcedOptions
    blockedLib: string;
    defaultReceiveLibrary: string;
    defaultReceiveLibraryTimeOut: ReceiveLibraryTimeOutInfo;
    defaultSendLibrary: string;
    appUlnConfig: EndpointConfig;
    defaultUlnConfig: EndpointConfig;
    appUlnConfigDefaultLib: EndpointConfig;
    defaultUlnConfigDefaultLib: EndpointConfig;
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
    executorConfigDefaultLib: ExecutorConfigType;
    defaultExecutorConfigDefaultLib: ExecutorConfigType;
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

export interface Params {
    oftProxy: string
    eid: string
    actualImplementation: string
    expectedImplementation: string
    actualProxyAdmin: string
    expectedProxyAdmin: string
    expectedEndpoint: string
    actualEndpoint: string
    delegate: string
    delegateThreshold: string
    delegateMembers: string[]
    owner: string
    ownerThreshold: string
    ownerMembers: string[]
    proxyAdmin: string
    proxyAdminOwner: string
    proxyAdminOwnerThreshold: string
    proxyAdminOwnermembers: string[]
}

export interface DstChainConfig {
    [dstChain: string]: OFTInfo
}

export interface SrcChainConfig {
    params: Params
    dstChains: DstChainConfig
}

export interface ChainConfig {
    [srcChain: string]: SrcChainConfig
}

export interface TokenConfig {
    [token: string]: ChainConfig
}