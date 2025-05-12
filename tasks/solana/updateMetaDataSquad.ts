import {
    UpdateV1InstructionAccounts,
    UpdateV1InstructionArgs,
    fetchMetadataFromSeeds,
    updateV1,
} from '@metaplex-foundation/mpl-token-metadata'
import { createNoopSigner, publicKey, signerIdentity, transactionBuilder } from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import { VersionedMessage, VersionedTransaction } from '@solana/web3.js'
import { mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { createSolanaConnectionFactory } from '../common/utils'

interface UpdateMetadataTaskArgs {
    eid: EndpointId
    name: string
    mint: string
    sellerFeeBasisPoints: number
    symbol: string
    uri: string
    squadsAuthority: string
}

// note that if URI is specified, then the name and symbol in there would be used and will override the 'outer' name and symbol
task('lz:oft:solana:update-metadata:squads', 'Updates the metaplex metadata of the SPL Token')
    .addParam('eid', 'Solana mainnet (30168) or testnet (40168)', undefined, devtoolsTypes.eid)
    .addParam('mint', 'The Token mint public key', undefined, devtoolsTypes.string)
    .addParam('squadsAuthority', 'The Squads authority public key', undefined, devtoolsTypes.string)
    .addOptionalParam('name', 'Token Name', undefined, devtoolsTypes.string)
    .addOptionalParam('symbol', 'Token Symbol', undefined, devtoolsTypes.string)
    .addOptionalParam('sellerFeeBasisPoints', 'Seller fee basis points', undefined, devtoolsTypes.int)
    .addOptionalParam('uri', 'URI for token metadata', undefined, devtoolsTypes.string)
    .setAction(async ({ eid, name, mint: mintStr, squadsAuthority: squadsAuthorityStr, sellerFeeBasisPoints, symbol, uri }: UpdateMetadataTaskArgs) => {
        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(eid)
        const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())

        let squadsAuthority = publicKey(squadsAuthorityStr);
        const squadsSigner = createNoopSigner(squadsAuthority);

        umi.use(signerIdentity(squadsSigner))

        const mint = publicKey(mintStr)

        const initialMetadata = await fetchMetadataFromSeeds(umi, { mint })

        if (initialMetadata.isMutable == false) {
            throw new Error('Metadata is not mutable')
        }

        const isTestnet = eid == EndpointId.SOLANA_V2_TESTNET

        const updateV1Args: UpdateV1InstructionAccounts & UpdateV1InstructionArgs = {
            mint,
            authority: squadsSigner,
            data: {
                ...initialMetadata,
                name: name || initialMetadata.name,
                symbol: symbol || initialMetadata.symbol,
                uri: uri || initialMetadata.uri,
                sellerFeeBasisPoints:
                    sellerFeeBasisPoints != undefined ? sellerFeeBasisPoints : initialMetadata.sellerFeeBasisPoints,
            },
        }

        const txBuilder = transactionBuilder().add(updateV1(umi, updateV1Args))
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