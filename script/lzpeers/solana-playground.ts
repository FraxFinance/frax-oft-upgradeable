import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { oft302 } from '@layerzerolabs/oft-v2-solana-sdk'
import { base58PublicKey, publicKey } from '@metaplex-foundation/umi'
import { Options } from '@layerzerolabs/lz-v2-utilities'
import { solanaOFTs } from './oft'
import { decodeLzReceiveOption } from './run-periodically/check-oft-config-csv'

async function main() {
    const solanaClient = createUmi('https://api.mainnet-beta.solana.com')

    const peerAddress = await oft302.getPeerAddress(
        solanaClient.rpc,
        publicKey(solanaOFTs['frxUSD'].oftStore),
        30255,
        publicKey(solanaOFTs['frxUSD'].programId)
    )
    console.log(`peerAddress : ${peerAddress}`)
    const delegate = await oft302.getDelegate(solanaClient.rpc, publicKey(solanaOFTs['frxUSD'].oftStore))
    console.log(`delegate : ${delegate}`)
    const endpointConfig = await oft302.getEndpointConfig(
        solanaClient.rpc,
        publicKey(solanaOFTs['frxUSD'].oftStore),
        30255
    )
    console.log('endpoint ', endpointConfig.sendLibraryConfig.header.owner)

    console.log('app send uln config : confirmations', endpointConfig.sendLibraryConfig.ulnSendConfig.uln.confirmations)
    console.log('app send uln config : requiredDvnCount', endpointConfig.sendLibraryConfig.ulnSendConfig.uln.requiredDvnCount)
    console.log('app send uln config : optionalDvnCount', endpointConfig.sendLibraryConfig.ulnSendConfig.uln.optionalDvnCount)
    console.log('app send uln config : optionalDvnThreshold', endpointConfig.sendLibraryConfig.ulnSendConfig.uln.optionalDvnThreshold)
    console.log('app send uln config : requiredDvns', endpointConfig.sendLibraryConfig.ulnSendConfig.uln.requiredDvns)
    console.log('app send uln config : optionalDvns', endpointConfig.sendLibraryConfig.ulnSendConfig.uln.optionalDvns)

    console.log('app executor : maxMessageSize', endpointConfig.sendLibraryConfig.ulnSendConfig.executor.maxMessageSize)
    console.log('app executor : executor', endpointConfig.sendLibraryConfig.ulnSendConfig.executor.executor)

    console.log('app receive uln config : confirmations', endpointConfig.receiveLibraryConfig.ulnReceiveConfig.uln.confirmations)
    console.log('app receive uln config : requiredDvnCount', endpointConfig.receiveLibraryConfig.ulnReceiveConfig.uln.requiredDvnCount)
    console.log('app receive uln config : optionalDvnCount', endpointConfig.receiveLibraryConfig.ulnReceiveConfig.uln.optionalDvnCount)
    console.log('app receive uln config : optionalDvnThreshold', endpointConfig.receiveLibraryConfig.ulnReceiveConfig.uln.optionalDvnThreshold)
    console.log('app receive uln config : requiredDvns', endpointConfig.receiveLibraryConfig.ulnReceiveConfig.uln.requiredDvns)
    console.log('app receive uln config : optionalDvns', endpointConfig.receiveLibraryConfig.ulnReceiveConfig.uln.optionalDvns)

    const enforcedOptions = await oft302.getEnforcedOptions(
        solanaClient.rpc,
        publicKey(solanaOFTs['frxUSD'].oftStore),
        30255,
        publicKey(solanaOFTs['frxUSD'].programId)
    )
    console.log('send ', decodeLzReceiveOption(`0x${Buffer.from(enforcedOptions.send).toString('hex')}`))
    console.log('sendAndCall ', decodeLzReceiveOption(`0x${Buffer.from(enforcedOptions.sendAndCall).toString('hex')}`))
}
main()
