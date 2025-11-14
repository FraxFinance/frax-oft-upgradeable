import { Aptos, AptosConfig, Network } from '@aptos-labs/ts-sdk';
import { aptosMovementOFTs } from './oft';
import { chains } from './chains';

async function main() {
    const aptos = new Aptos(new AptosConfig({
        network: Network.MAINNET,
        fullnode: 'https://full.mainnet.movementinfra.xyz/v1',
    }))

    const peerBytes32 = await aptos.view({
        payload: {
            function: `${aptosMovementOFTs["fpi"].oft}::oapp_core::get_peer`,
            functionArguments: [chains["fraxtal"].peerId],
        },
    })
    console.log(peerBytes32)
}

main()