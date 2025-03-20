import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { connectionConfig } from './l0-movement-connection-config'

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    address: "0x75c38D46001b0F8108c4136216bd2694982C20FC",
    contractName: "FraxOFTAdapterUpgradeable"
}

const movementContract: OmniPointHardhat = {
    eid: EndpointId.MOVEMENT_V2_MAINNET,
    contractName: 'FPI',
}

const config: OAppOmniGraphHardhat = {
    contracts: [
        {
            contract: fraxtalContract,
            config: {
                owner: '0x5f25218ed9474b721d6a38c115107428E832fA2E',
                delegate: '0x5f25218ed9474b721d6a38c115107428E832fA2E',
            },
        },
        {
            contract: movementContract,
            config: {
                delegate: '09d0eb2763c96e085fa74ba6cf0d49136f8654c48ec7dbc59279a9066c7dd409',
                owner: '09d0eb2763c96e085fa74ba6cf0d49136f8654c48ec7dbc59279a9066c7dd409',
            },
        },
    ],
    connections: [
        {
            from: movementContract,
            to: fraxtalContract,
            config: connectionConfig,
        }
    ],
}

export default config
