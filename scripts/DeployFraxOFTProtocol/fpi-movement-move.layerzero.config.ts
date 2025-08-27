import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { fraxtalContractConfig, movementContractConfig, movementToFraxtalconnectionConfig } from './l0-move-connection-config'

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    address: "0x75c38D46001b0F8108c4136216bd2694982C20FC",
    contractName: "FPIOFT"
}

const movementContract: OmniPointHardhat = {
    eid: EndpointId.MOVEMENT_V2_MAINNET,
    contractName: 'FPI',
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
        }
    ],
}

export default config
