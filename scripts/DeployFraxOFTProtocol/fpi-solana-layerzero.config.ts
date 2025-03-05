import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { GenerateConfig } from './generate-L0-solana-config';

const assetName = "fpi"

const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_MAINNET,
    address: 'FFozEKoFQ1CZD6Kn7bpwAxaWhK1jEA76pjucvBBHf9ZH', // NOTE: update this with the OFTStore address.
}

const config = GenerateConfig(solanaContract,assetName);

export default config