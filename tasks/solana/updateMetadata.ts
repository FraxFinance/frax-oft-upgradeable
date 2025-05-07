import {
    UpdateV1InstructionAccounts,
    UpdateV1InstructionArgs,
    fetchMetadataFromSeeds,
    updateV1,
} from '@metaplex-foundation/mpl-token-metadata'
import { publicKey, transactionBuilder } from '@metaplex-foundation/umi'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import { deriveConnection, getExplorerTxLink } from './index'

import { TransactionInstruction, PublicKey } from '@solana/web3.js'


interface UpdateMetadataTaskArgs {
    eid: EndpointId
    name: string
    mint: string
    sellerFeeBasisPoints: number
    symbol: string
    uri: string
}

// note that if URI is specified, then the name and symbol in there would be used and will override the 'outer' name and symbol
task('lz:oft:solana:update-metadata', 'Updates the metaplex metadata of the SPL Token')
    .addParam('eid', 'Solana mainnet (30168) or testnet (40168)', undefined, devtoolsTypes.eid)
    .addParam('mint', 'The Token mint public key', undefined, devtoolsTypes.string)
    .addOptionalParam('name', 'Token Name', undefined, devtoolsTypes.string)
    .addOptionalParam('symbol', 'Token Symbol', undefined, devtoolsTypes.string)
    .addOptionalParam('sellerFeeBasisPoints', 'Seller fee basis points', undefined, devtoolsTypes.int)
    .addOptionalParam('uri', 'URI for token metadata', undefined, devtoolsTypes.string)
    .setAction(async ({ eid, name, mint: mintStr, sellerFeeBasisPoints, symbol, uri }: UpdateMetadataTaskArgs) => {
        const { umi, umiWalletSigner } = await deriveConnection(eid)

        const mint = publicKey(mintStr)

        const initialMetadata = await fetchMetadataFromSeeds(umi, { mint })

        // if (initialMetadata.updateAuthority !== umiWalletSigner.publicKey.toString()) {
        //     throw new Error('Only the update authority can update the metadata')
        // }

        if (initialMetadata.isMutable == false) {
            throw new Error('Metadata is not mutable')
        }

        const isTestnet = eid == EndpointId.SOLANA_V2_TESTNET

        const updateV1Args: UpdateV1InstructionAccounts & UpdateV1InstructionArgs = {
            mint,
            authority: umiWalletSigner,
            data: {
                ...initialMetadata,
                name: name || initialMetadata.name,
                symbol: symbol || initialMetadata.symbol,
                uri: uri || initialMetadata.uri,
                sellerFeeBasisPoints:
                    sellerFeeBasisPoints != undefined ? sellerFeeBasisPoints : initialMetadata.sellerFeeBasisPoints,
            },
        }

        const updateInstruction = updateV1(umi, updateV1Args).getInstructions()[0]
        // Convert UMI instruction to web3.js TransactionInstruction
        const web3Instruction = new TransactionInstruction({
            programId: new PublicKey(updateInstruction.programId),
            keys: updateInstruction.keys.map((k) => ({
                pubkey: new PublicKey(k.pubkey),
                isSigner: k.isSigner,
                isWritable: k.isWritable,
            })),
            data: Buffer.from(updateInstruction.data),
        })
        console.log('\n--- ✅ Add this to Squads UI ---')
        console.log('Program ID:', web3Instruction.programId.toBase58())
        console.log('Accounts:')
        web3Instruction.keys.forEach((k, i) => {
            console.log(
                `  ${i + 1}. pubkey: ${k.pubkey.toBase58()}, isSigner: ${k.isSigner}, isWritable: ${k.isWritable}`
            )
        })
        console.log('Data (base58):', bs58.encode(web3Instruction.data))
        // const txBuilder = transactionBuilder().add(updateV1(umi, updateV1Args))
        // const createTokenTx = await txBuilder.sendAndConfirm(umi)
        // console.log(`createTokenTx: ${getExplorerTxLink(bs58.encode(createTokenTx.signature), isTestnet)}`)
    })
