import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { GenerateConfig } from './generate-L0-solana-config';

const assetName = "frxeth"

const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_MAINNET,
    address: '4pyqBQFhzsuL7ED76x3AyzT4bCVpMpQWXhS1LqEsfQtz', // NOTE: update this with the OFTStore address.
}

const config = GenerateConfig(solanaContract,assetName);

export default config