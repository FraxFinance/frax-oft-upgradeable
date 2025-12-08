import {
    createThawAccountInstruction,
    getAssociatedTokenAddressSync,
    TOKEN_PROGRAM_ID,
} from '@solana/spl-token'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import { VersionedTransaction, PublicKey, TransactionMessage, AccountMeta } from '@solana/web3.js'
import bs58 from 'bs58'
import { createSolanaConnectionFactory } from '../common/utils'

interface ThawTokenTaskArgs {
    eid: EndpointId
    tokenAccount?: string
    owner?: string
    mint: string
    squadsAuthority: string
}

// Thaw (unfreeze) token account instruction for Squads multisig
task('lz:oft:solana:thaw-token:squads', 'Generates a thaw (unfreeze) instruction for Squads multisig')
    .addParam('eid', 'Solana mainnet (30168) or testnet (40168)', undefined, devtoolsTypes.eid)
    .addOptionalParam('tokenAccount', 'The token account address to thaw (use this OR owner)', undefined, devtoolsTypes.string)
    .addOptionalParam('owner', 'The owner address to derive token account from (use this OR tokenAccount)', undefined, devtoolsTypes.string)
    .addParam('mint', 'The Token mint public key', undefined, devtoolsTypes.string)
    .addParam('squadsAuthority', 'The Squads authority public key (freeze authority)', undefined, devtoolsTypes.string)
    .setAction(async ({ eid, tokenAccount: tokenAccountStr, owner: ownerStr, mint: mintStr, squadsAuthority: squadsAuthorityStr }: ThawTokenTaskArgs) => {
        // Validate that either tokenAccount or owner is provided
        if (!tokenAccountStr && !ownerStr) {
            throw new Error('Must provide either --token-account or --owner')
        }
        if (tokenAccountStr && ownerStr) {
            throw new Error('Cannot provide both --token-account and --owner')
        }

        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(eid)

        const mintPubkey = new PublicKey(mintStr)
        const squadsAuthorityPubkey = new PublicKey(squadsAuthorityStr)

        // Derive token account from owner if needed
        let tokenAccountPubkey: PublicKey
        if (ownerStr) {
            const ownerPubkey = new PublicKey(ownerStr)
            tokenAccountPubkey = getAssociatedTokenAddressSync(mintPubkey, ownerPubkey)
            console.log('Derived token account from owner:')
            console.log('OWNER:', ownerStr)
            console.log('TOKEN ACCOUNT:', tokenAccountPubkey.toString())
        } else {
            tokenAccountPubkey = new PublicKey(tokenAccountStr!)
            console.log('TOKEN ACCOUNT:', tokenAccountStr)
        }

        const thawInstruction = createThawAccountInstruction(
            tokenAccountPubkey,
            mintPubkey,
            squadsAuthorityPubkey,
            []
        )

        // Mark the Squads authority as a signer by modifying instruction accounts
        thawInstruction.keys = thawInstruction.keys.map(account => {
            if (account.pubkey.equals(squadsAuthorityPubkey)) {
                return { ...account, isSigner: true }
            }
            return account
        })

        const latestBlockhash = await connection.getLatestBlockhash()

        const message = new TransactionMessage({
            instructions: [thawInstruction],
            payerKey: squadsAuthorityPubkey, // Squads multisig pays fees
            recentBlockhash: latestBlockhash.blockhash,
        }).compileToV0Message()

        const tx = new VersionedTransaction(message)
        const serialized = tx.serialize()

        console.log('MINT:', mintStr)
        console.log('FREEZE AUTHORITY (Squads):', squadsAuthorityStr)
        console.log('\n========================================')
        console.log('BASE58 (for Squads UI):')
        console.log('========================================\n')
        console.log(bs58.encode(Uint8Array.from(serialized)))
        console.log('\n========================================')
        console.log('BASE64 (alternative):')
        console.log('========================================\n')
        console.log(Buffer.from(serialized).toString("base64"));
    })
