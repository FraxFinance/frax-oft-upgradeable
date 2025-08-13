import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { fraxtalContractConfig, aptosContractConfig, ethereumContractConfig, getAptosToEVMConnectionConfig } from './l0-move-connection-config'

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    address: "0x75c38D46001b0F8108c4136216bd2694982C20FC",
    contractName: "FPIOFT"
}

const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    address: "0x9033BAD7aA130a2466060A2dA71fAe2219781B4b",
    contractName: "FPIOFT"
}

const aptosContract: OmniPointHardhat = {
    eid: EndpointId.APTOS_V2_MAINNET,
    contractName: 'FPI',
}

const config: OAppOmniGraphHardhat = {
    contracts: [
        {
            contract: fraxtalContract,
            config: fraxtalContractConfig,
        },
        {
            contract: ethereumContract,
            config: ethereumContractConfig,
        },
        {
            contract: aptosContract,
            config: aptosContractConfig,
        },
    ],
    connections: [
        {
            from: aptosContract,
            to: fraxtalContract,
            config: getAptosToEVMConnectionConfig(30000, 5),
        },
        {
            from: aptosContract,
            to: ethereumContract,
            config: getAptosToEVMConnectionConfig(260, 15),
        }
    ],
}

export default config
