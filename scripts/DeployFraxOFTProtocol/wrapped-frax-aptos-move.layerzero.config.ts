import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { aptosContractConfig, ethereumContractConfig, fraxtalContractConfig, getAptosToEVMConnectionConfig } from './l0-move-connection-config'

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    address: "0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A",
    contractName: "WFRAXOFT"
}

const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    address: "0x04ACaF8D2865c0714F79da09645C13FD2888977f",
    contractName: "WFRAXOFT"
}

const aptosContract: OmniPointHardhat = {
    eid: EndpointId.APTOS_V2_MAINNET,
    contractName: 'WFRAX',
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
        },
    ],
}

export default config
