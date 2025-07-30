import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { ethereumContractConfig, fraxtalContractConfig, getMovementToEVMConnectionConfig, movementContractConfig } from './l0-move-connection-config'

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    address: "0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604",
    contractName: "frxETHOFT"
}

const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    address: "0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6",
    contractName: "frxETHOFT"
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
