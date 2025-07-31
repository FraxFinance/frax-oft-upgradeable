import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { ethereumContractConfig, fraxtalContractConfig, getMovementToEVMConnectionConfig, movementContractConfig } from './l0-move-connection-config'

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

const movementContract: OmniPointHardhat = {
    eid: EndpointId.MOVEMENT_V2_MAINNET,
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
            contract: movementContract,
            config: movementContractConfig,
        },
    ],
    connections: [
        {
            from: movementContract,
            to: fraxtalContract,
            config: getMovementToEVMConnectionConfig(30000, 5),
        },
        {
            from: movementContract,
            to: ethereumContract,
            config: getMovementToEVMConnectionConfig(30000, 15),
        },
    ],
}

export default config
