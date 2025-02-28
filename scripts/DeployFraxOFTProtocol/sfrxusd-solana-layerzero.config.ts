import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { GenerateConfig } from './generate-L0-solana-config';

const assetName = "sfrxUSD"

const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_MAINNET,
    address: 'A28EK6j1euK4e6taP1KLFpGEoR1mDpXR4vtfiyCE1Nxv', // NOTE: update this with the OFTStore address.
}

const config = GenerateConfig(solanaContract,assetName);

export default config