import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { GenerateConfig } from './generate-L0-solana-config';

const assetName = "sfrxeth"

const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_MAINNET,
    address: 'DsJYjDF5yVSopMC15q9W42v833MhWGhCxcU2J39oS3wN', // NOTE: update this with the OFTStore address.
}

export default async function () {
    const config = await GenerateConfig(solanaContract, assetName);
    return config
}