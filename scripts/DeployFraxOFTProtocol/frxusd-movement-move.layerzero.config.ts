import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { ethereumContractConfig, fraxtalContractConfig, getMovementToEVMConnectionConfig, movementContractConfig } from './l0-move-connection-config'

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    address: "0x96A394058E2b84A89bac9667B19661Ed003cF5D4",
    contractName: "frxUSDOFT"
}

const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    address: "0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0",
    contractName: "frxUSDOFT"
}

const movementContract: OmniPointHardhat = {
    eid: EndpointId.MOVEMENT_V2_MAINNET,
    contractName: 'frxUSD',
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
            config: getMovementToEVMConnectionConfig(30000, 5)
        },
        {
            from: movementContract,
            to: ethereumContract,
            config: getMovementToEVMConnectionConfig(30000, 15)
        },
    ],
}

export default config
