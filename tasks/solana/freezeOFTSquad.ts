import { task } from 'hardhat/config'
import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { TOKEN_PROGRAM_ID } from '@solana/spl-token'
import { createSolanaConnectionFactory } from '../common/utils'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { createNoopSigner, publicKey, signerIdentity } from '@metaplex-foundation/umi'
import { freezeToken, findAssociatedTokenPda, mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import {
    getSolanaDeployment,
} from './index'
import { toWeb3JsInstruction } from '@metaplex-foundation/umi-web3js-adapters';
import bs58 from 'bs58';
import { VersionedMessage, VersionedTransaction, PublicKey } from '@solana/web3.js'
import {
    getAssociatedTokenAddressSync
} from '@solana/spl-token'

interface FreezeTokenTaskArgs {
    eid: EndpointId
    owner: string
    squadsAuthority: string
    freezeAuthority?: string
    tokenAccount?: string
}

// Freeze token account instruction for Squads multisig
task('lz:oft:solana:freeze-token:squads', 'Generates a freeze instruction for Squads multisig')
    .addParam('eid', 'Solana mainnet (30168) or testnet (40168)', undefined, devtoolsTypes.eid)
    .addParam('owner', 'The owner address of the token account', undefined, devtoolsTypes.string)
    .addOptionalParam('tokenAccount', 'The token account address (if not provided, will derive ATA)', undefined, devtoolsTypes.string)
    .addParam('squadsAuthority', 'The Squads authority public key (multisig signer)', undefined, devtoolsTypes.string)
    .addOptionalParam('freezeAuthority', 'The actual freeze authority on the mint (if different from squadsAuthority)', undefined, devtoolsTypes.string)
    .setAction(async ({ eid, owner: ownerStr, squadsAuthority: squadsAuthorityStr, freezeAuthority: freezeAuthorityStr, tokenAccount: tokenAccountStr }: FreezeTokenTaskArgs) => {
        // Validate that owner is provided
        if (!ownerStr) {
            throw new Error('Must provide --owner')
        }

        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(eid)
        const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())
        const solanaDeployment = getSolanaDeployment(eid)

        let squadsAuthority = publicKey(squadsAuthorityStr)
        const squadsSigner = createNoopSigner(squadsAuthority);

        umi.use(signerIdentity(squadsSigner))

        // Derive token account from owner
        let tokenAccountPubkey: PublicKey
        if (ownerStr) {
            const ownerPubkey = new PublicKey(ownerStr)
            tokenAccountPubkey = getAssociatedTokenAddressSync(new PublicKey(solanaDeployment.mint), ownerPubkey)
            console.log('Derived token account from owner:')
            console.log('OWNER:', ownerStr)
            console.log('TOKEN ACCOUNT:', tokenAccountPubkey.toString())
        } else {
            tokenAccountPubkey = new PublicKey(tokenAccountStr!)
            console.log('TOKEN ACCOUNT:', tokenAccountStr)
        }

        const builder = freezeToken(umi, {
            account: publicKey(tokenAccountPubkey), // The token account to freeze
            mint: publicKey(solanaDeployment.mint),              // The token mint
            owner: publicKey(solanaDeployment.mintAuthority),  // The freeze authority (Squads vault)
        });

        builder.setFeePayer(squadsSigner)
        await builder.setLatestBlockhash(umi)
        const serializedTx = await builder.buildWithLatestBlockhash(umi)
        const transactionDataHex = Buffer.from(serializedTx.serializedMessage).toString("hex")
        const versionedMessage = VersionedMessage.deserialize(new Uint8Array(Buffer.from(transactionDataHex, 'hex')))

        const tx = new VersionedTransaction(versionedMessage);

        console.log('BASE58: \n')
        console.log(bs58.encode(new Uint8Array(tx.serialize())))
        console.log('\nBASE64: \n')
        console.log(Buffer.from(tx.serialize()).toString("base64"));
    })
