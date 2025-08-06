import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { aptosContractConfig, ethereumContractConfig, fraxtalContractConfig, getAptosToEVMConnectionConfig } from './l0-move-connection-config'

const fraxtalContract: OmniPointHardhat = {
    eid: EndpointId.FRAXTAL_V2_MAINNET,
    address: "0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168",
    contractName: "sfrxETHOFT"
}

const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    address: "0xbBc424e58ED38dd911309611ae2d7A23014Bd960",
    contractName: "sfrxETHOFT"
}

const aptosContract: OmniPointHardhat = {
    eid: EndpointId.APTOS_V2_MAINNET,
    contractName: 'sfrxETH',
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
