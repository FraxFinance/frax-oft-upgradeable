import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { GenerateConfig } from './generate-L0-aptos-config';


const contract: OmniPointHardhat = {
    eid: EndpointId.INITIA_V2_MAINNET,
    contractName: 'frxETH',
}

const config = GenerateConfig(contract);

export default config
