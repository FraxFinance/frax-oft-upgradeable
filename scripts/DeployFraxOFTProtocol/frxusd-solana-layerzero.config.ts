import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { GenerateConfig } from './generate-L0-solana-config';

const assetName = "frxUSD"

const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_MAINNET,
    address: '7LS6y37WXXCyBHkBU6zVpiqaqbkXLr4P85ZhQi3eonSp', // NOTE: update this with the OFTStore address.
}

export default async function () {
    const config = await GenerateConfig(solanaContract, assetName);
    return config
}