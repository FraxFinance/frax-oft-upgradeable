import * as fs from 'fs';
import { findAssociatedTokenPda, mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { createNoopSigner, publicKey, signerIdentity, transactionBuilder } from '@metaplex-foundation/umi'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { TOKEN_PROGRAM_ID } from '@solana/spl-token'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
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
    library: string
    toEid: EndpointId
    tokenProgram: string
    squadsAuthority: string
    path: string
    outputFilename: string
}

// Define a Hardhat task for setting send library for solana oft
task('lz:oft:solana:setsendlibrary', 'set send library for solana oft')
    .addParam('fromEid', 'The source endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('library', 'The send library address on source chain')
    .addParam('toEid', 'The destination endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('tokenProgram', 'The Token Program public key', TOKEN_PROGRAM_ID.toBase58(), devtoolsTypes.string, true)
    .addParam('squadsAuthority', 'The Squads authority public key', undefined, devtoolsTypes.string)
    .addParam('path', 'The path of the output file', './scripts/ops/fix/FixDVNs/txs', devtoolsTypes.string)
    .addParam('outputFilename', 'Name of file created for writing bs58 transaction', undefined, devtoolsTypes.string)
    .setAction(async (args: Args) => {
        const { fromEid, library, toEid, tokenProgram: tokenProgramStr, squadsAuthority: squadsAuthorityStr, path, outputFilename } = args

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

        const setSetLibraryIX = await oft.setSendLibrary(
            {
                admin: squadsSigner,
                oftStore: publicKey(solanaDeployment.oftStore)
            },
            {
                sendLibraryProgram: publicKey(library),
                remoteEid: toEid
            })

        let txBuilder = transactionBuilder().add([setSetLibraryIX])
        txBuilder.setFeePayer(squadsSigner)
        await txBuilder.setLatestBlockhash(umi)
        const serializedTx = await txBuilder.buildWithLatestBlockhash(umi)
        const transactionDataHex = Buffer.from(serializedTx.serializedMessage).toString("hex")
        const versionedMessage = VersionedMessage.deserialize(Buffer.from(transactionDataHex, 'hex'))

        const tx = new VersionedTransaction(versionedMessage);
        const unixTimestamp = Math.floor(Date.now() / 1000);
        const base58Tx = bs58.encode(Buffer.from(tx.serialize()));
        fs.writeFileSync(`${path}/${unixTimestamp}-${outputFilename}`, base58Tx, 'utf8');
    })
