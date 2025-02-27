import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { GenerateConfig } from './generate-L0-move-config';


const contract: OmniPointHardhat = {
    eid: EndpointId.APTOS_V2_MAINNET,
    contractName: 'FPI',
}

const config = GenerateConfig(contract);

export default config
