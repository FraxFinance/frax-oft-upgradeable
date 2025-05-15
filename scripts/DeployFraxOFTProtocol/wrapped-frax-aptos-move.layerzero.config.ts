import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { aptosContractConfig, aptosToFraxtalconnectionConfig, fraxtalContractConfig } from './l0-move-connection-config'

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    address: "0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A",
    contractName: "FraxOFTAdapterUpgradeable"
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
            contract: aptosContract,
            config: aptosContractConfig,
        },
    ],
    connections: [
        {
            from: aptosContract,
            to: fraxtalContract,
            config: aptosToFraxtalconnectionConfig,
        },
    ],
}

export default config
