import { mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { createNoopSigner, publicKey, signerIdentity, transactionBuilder } from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { VersionedMessage, VersionedTransaction } from '@solana/web3.js'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'

import { createSolanaConnectionFactory } from '../common/utils'
import { getSolanaDeployment } from './index'

interface Args {
    fromEid: EndpointId
    toEid: EndpointId
    squadsAuthority: string
}

const ZERO_PEER_BYTES_32 = new Uint8Array(32)

/**
 * Builds a Squads-ready transaction that resets the peer (peerAddress = bytes32(0))
 * for a remote EID on the Solana OFT. Use this to disconnect Solana from a remote chain.
 *
 * Example (disconnect Polygon zkEVM from Solana):
 *   pnpm exec hardhat lz:oft:solana:disconnect-peer:squads \
 *     --from-eid 30168 \
 *     --to-eid 30267 \
 *     --squads-authority <SQUADS_VAULT_PUBKEY>
 */
task(
    'lz:oft:solana:disconnect-peer:squads',
    'Build a Squads tx that zeroes the peer of a remote EID on the Solana OFT',
)
    .addParam('fromEid', 'The Solana endpoint ID (source)', undefined, devtoolsTypes.eid)
    .addParam('toEid', 'The remote endpoint ID to disconnect', undefined, devtoolsTypes.eid)
    .addParam('squadsAuthority', 'The Squads authority public key', undefined, devtoolsTypes.string)
    .setAction(async (args: Args) => {
        const { fromEid, toEid, squadsAuthority: squadsAuthorityStr } = args

        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(fromEid)
        const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())

        const squadsAuthority = publicKey(squadsAuthorityStr)
        const squadsSigner = createNoopSigner(squadsAuthority)
        umi.use(signerIdentity(squadsSigner))

        const solanaDeployment = getSolanaDeployment(fromEid)
        const oftProgramId = publicKey(solanaDeployment.programId)

        const setPeerConfigIX = await oft.setPeerConfig(
            {
                admin: squadsSigner,
                oftStore: publicKey(solanaDeployment.oftStore),
            },
            {
                __kind: 'PeerAddress',
                peer: ZERO_PEER_BYTES_32,
                remote: toEid,
            },
            oftProgramId,
        )

        const txBuilder = transactionBuilder().add([setPeerConfigIX])
        txBuilder.setFeePayer(squadsSigner)
        await txBuilder.setLatestBlockhash(umi)
        const serializedTx = await txBuilder.buildWithLatestBlockhash(umi)

        const transactionDataHex = Buffer.from(serializedTx.serializedMessage).toString('hex')
        const versionedMessage = VersionedMessage.deserialize(new Uint8Array(Buffer.from(transactionDataHex, 'hex')))
        const tx = new VersionedTransaction(versionedMessage)

        console.log(`Disconnect Solana(${fromEid}) peer for remote eid ${toEid}`)
        console.log(`  oftStore: ${solanaDeployment.oftStore}`)
        console.log(`  programId: ${solanaDeployment.programId}`)
        console.log(`  squadsAuthority: ${squadsAuthorityStr}`)
        console.log('\nBASE58:\n')
        console.log(bs58.encode(new Uint8Array(tx.serialize())))
        console.log('\nBASE64:\n')
        console.log(Buffer.from(tx.serialize()).toString('base64'))
    })
