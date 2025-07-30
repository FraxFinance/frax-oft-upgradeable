import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { ethereumContractConfig, fraxtalContractConfig, getMovementToEVMConnectionConfig, movementContractConfig } from './l0-move-connection-config'

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    address: "0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361",
    contractName: "sfrxUSDOFT"
}

const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    address: "0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126",
    contractName: "sfrxUSDOFT"
}

const movementContract: OmniPointHardhat = {
    eid: EndpointId.MOVEMENT_V2_MAINNET,
    contractName: 'sfrxUSD',
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
