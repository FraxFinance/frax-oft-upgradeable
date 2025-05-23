import { fetchToken, findAssociatedTokenPda, mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { createNoopSigner, publicKey, signerIdentity, transactionBuilder } from '@metaplex-foundation/umi'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { TOKEN_PROGRAM_ID } from '@solana/spl-token'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { addressToBytes32 } from '@layerzerolabs/lz-v2-utilities'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'
import { VersionedMessage, VersionedTransaction } from '@solana/web3.js'
import {
    getSolanaDeployment,
} from './index'
import { createSolanaConnectionFactory } from '../common/utils'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'

interface Args {
    fromEid: EndpointId
    peerAddress: string
    toEid: EndpointId
    tokenProgram: string
    squadsAuthority: string
}

// Define a Hardhat task for setting peer config for solana oft
task('lz:oft:solana:setpeerconfig', 'set peer config for solana oft')
    .addParam('fromEid', 'The source endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('peerAddress', 'The OFT address on the destination chain')
    .addParam('toEid', 'The destination endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('tokenProgram', 'The Token Program public key', TOKEN_PROGRAM_ID.toBase58(), devtoolsTypes.string, true)
    .addParam('squadsAuthority', 'The Squads authority public key', undefined, devtoolsTypes.string)
    .setAction(async (args: Args) => {
        const { fromEid, peerAddress, toEid, tokenProgram: tokenProgramStr, squadsAuthority: squadsAuthorityStr } = args

        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(fromEid)
        const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())

        let squadsAuthority = publicKey(squadsAuthorityStr)
        const squadsSigner = createNoopSigner(squadsAuthority);

        umi.use(signerIdentity(squadsSigner))

        const solanaDeployment = getSolanaDeployment(fromEid)

        const oftProgramId = publicKey(solanaDeployment.programId)
        const mint = publicKey(solanaDeployment.mint)
        const tokenProgramId = tokenProgramStr ? publicKey(tokenProgramStr) : fromWeb3JsPublicKey(TOKEN_PROGRAM_ID)

        const tokenAccount = findAssociatedTokenPda(umi, {
            mint,
            owner: squadsSigner.publicKey,
            tokenProgramId,
        })

        if (!tokenAccount) {
            throw new Error(
                `No token account found for mint ${mint.toString()} and owner ${squadsSigner.publicKey} in program ${tokenProgramId}`
            )
        }

        const peerAddressBytes32 = addressToBytes32(peerAddress)

        const setPeerConfigIX = await oft.setPeerConfig(
            {
                admin: squadsSigner,
                oftStore: publicKey(solanaDeployment.oftStore)
            },
            {
                __kind: 'PeerAddress',
                peer: peerAddressBytes32,
                remote: toEid
            },
            oftProgramId
        )

        let txBuilder = transactionBuilder().add([setPeerConfigIX])
        txBuilder.setFeePayer(squadsSigner)
        await txBuilder.setLatestBlockhash(umi)
        const serializedTx = await txBuilder.buildWithLatestBlockhash(umi)
        const transactionDataHex = Buffer.from(serializedTx.serializedMessage).toString("hex")
        const versionedMessage = VersionedMessage.deserialize(Buffer.from(transactionDataHex, 'hex'))

        const tx = new VersionedTransaction(versionedMessage);

        console.log('BASE58: \n')
        console.log(bs58.encode(Buffer.from(tx.serialize())))
        console.log('\nBASE64: \n')
        console.log(Buffer.from(tx.serialize()).toString("base64"));
    })
