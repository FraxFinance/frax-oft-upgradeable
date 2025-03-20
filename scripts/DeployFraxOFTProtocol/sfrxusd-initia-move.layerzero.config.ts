import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { GenerateConfig } from './generate-L0-move-config';


const aptosContract: OmniPointHardhat = {
    eid: EndpointId.INITIA_V2_MAINNET,
    contractName: 'sfrxUSD',
}

const config = GenerateConfig(aptosContract);

export default config