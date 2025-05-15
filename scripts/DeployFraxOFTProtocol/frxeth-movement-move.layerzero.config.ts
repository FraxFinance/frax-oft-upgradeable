import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { fraxtalContractConfig, movementContractConfig, movementToFraxtalconnectionConfig } from './l0-move-connection-config'

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    address: "0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604",
    contractName: "FraxOFTAdapterUpgradeable"
}

const movementContract: OmniPointHardhat = {
    eid: EndpointId.MOVEMENT_V2_MAINNET,
    contractName: 'frxETH',
}

const config: OAppOmniGraphHardhat = {
    contracts: [
        {
            contract: fraxtalContract,
            config: fraxtalContractConfig,
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
            config: movementToFraxtalconnectionConfig,
        },
    ],
}

export default config
