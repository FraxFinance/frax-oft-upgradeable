// tasks/solana/sendSolanaSquad.ts

import { fetchToken, findAssociatedTokenPda } from '@metaplex-foundation/mpl-toolbox'
import { createNoopSigner, publicKey, signerIdentity, transactionBuilder } from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { PublicKey, VersionedMessage, VersionedTransaction } from '@solana/web3.js'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'
import { addressToBytes32 } from '@layerzerolabs/lz-v2-utilities'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'

import { parseDecimalToUnits, silenceSolana429 } from './utils'
import {
    TransactionType,
    addComputeUnitInstructions,
    getAddressLookupTable,
    getSolanaDeployment,
} from './index'
import { createSolanaConnectionFactory } from '../common/utils'

export interface SolanaSquadArgs {
    srcEid: EndpointId
    dstEid: EndpointId
    sender: string
    msig: string
    amount: string
    to: string
    minAmount?: string
    extraOptions?: string
    composeMsg?: string
    oftAddress?: string
    oftProgramId?: string
    tokenProgram?: string
    computeUnitPriceScaleFactor?: number
    sharedDecimals?: number
}

export interface SolanaSquadResult {
    base58: string
    base64: string
}

function fmt(raw: bigint | string | number, decimals: number): string {
    const s = BigInt(raw).toString()
    const neg = s.startsWith('-')
    const x = neg ? s.slice(1) : s
    const whole = x.length > decimals ? x.slice(0, x.length - decimals) : '0'
    const frac = x.length > decimals ? x.slice(x.length - decimals) : x.padStart(decimals, '0')
    return `${neg ? '-' : ''}${whole}.${frac}`.replace(/\.?0+$/, '')
}

function removeOftDust(
    amountRaw: bigint,
    localDecimals: number,
    sharedDecimals: number
): {
    amountRaw: bigint
    dustRaw: bigint
    dustRate: bigint
} {
    if (localDecimals <= sharedDecimals) {
        return {
            amountRaw,
            dustRaw: 0n,
            dustRate: 1n,
        }
    }

    const dustRate = 10n ** BigInt(localDecimals - sharedDecimals)
    const dustlessAmount = (amountRaw / dustRate) * dustRate

    return {
        amountRaw: dustlessAmount,
        dustRaw: amountRaw - dustlessAmount,
        dustRate,
    }
}

export async function sendSolanaSquad({
    srcEid,
    dstEid,
    sender,
    msig,
    amount,
    to,
    minAmount,
    extraOptions,
    composeMsg,
    oftAddress,
    oftProgramId,
    tokenProgram: tokenProgramStr,
    computeUnitPriceScaleFactor = 4,
    sharedDecimals = 6,
}: SolanaSquadArgs): Promise<SolanaSquadResult> {
    const connectionFactory = createSolanaConnectionFactory()
    const connection = await connectionFactory(srcEid)
    silenceSolana429(connection)

    const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())

    const senderPk = new PublicKey(sender)
    const squadsSigner = createNoopSigner(publicKey(sender))

    umi.use(signerIdentity(squadsSigner))

    const deployment = getSolanaDeployment(srcEid)

    const programId = oftProgramId
        ? publicKey(oftProgramId)
        : publicKey(deployment.programId)

    const storePda = oftAddress
        ? publicKey(oftAddress)
        : publicKey(deployment.oftStore)

    const oftStoreInfo = await oft.accounts.fetchOFTStore(umi, storePda)

    const mintPk = new PublicKey(oftStoreInfo.tokenMint)
    const escrowPk = new PublicKey(oftStoreInfo.tokenEscrow)

    const mintAccountInfo = await connection.getAccountInfo(mintPk)
    if (!mintAccountInfo) {
        throw new Error(`Mint account not found: ${mintPk.toBase58()}`)
    }

    // More flexible than hardcoding TOKEN_PROGRAM_ID:
    // supports both SPL Token and Token-2022 mints.
    const tokenProgramId = tokenProgramStr
        ? publicKey(tokenProgramStr)
        : fromWeb3JsPublicKey(mintAccountInfo.owner)

    const tokenAccount = findAssociatedTokenPda(umi, {
        mint: fromWeb3JsPublicKey(mintPk),
        owner: squadsSigner.publicKey,
        tokenProgramId,
    })

    if (!tokenAccount) {
        throw new Error(`No token account for mint ${mintPk.toBase58()}`)
    }

    const tokenAccountInfo = await fetchToken(umi, tokenAccount)
    const balanceRaw = BigInt(tokenAccountInfo.amount.toString())

    const supply = await connection.getTokenSupply(mintPk)
    const decimals = supply.value.decimals

    const requestedRaw =
        amount.toUpperCase() === 'ALL'
            ? balanceRaw
            : parseDecimalToUnits(amount, decimals)

    if (requestedRaw === 0n || requestedRaw > balanceRaw) {
        throw new Error(`Insufficient balance. Need ${requestedRaw}, have ${balanceRaw}`)
    }

    // OFTs normally have sharedDecimals precision. When sending ALL from Solana,
    // avoid accidentally including unbridgeable local dust.
    const { amountRaw: amountUnits, dustRaw, dustRate } = removeOftDust(
        requestedRaw,
        decimals,
        sharedDecimals
    )

    if (amountUnits === 0n) {
        throw new Error(
            `Amount becomes zero after OFT dust removal. requested=${requestedRaw}, dustRate=${dustRate}`
        )
    }

    const minAmountUnits = minAmount
        ? parseDecimalToUnits(minAmount, decimals)
        : amountUnits

    if (minAmountUnits > amountUnits) {
        throw new Error(`minAmount cannot exceed amount`)
    }

    const recipient = new Uint8Array(addressToBytes32(to))

    const optionsBuffer = extraOptions
        ? new Uint8Array(Buffer.from(extraOptions.startsWith('0x') ? extraOptions.slice(2) : extraOptions, 'hex'))
        : new Uint8Array()

    const composeMsgBuffer = composeMsg
        ? new Uint8Array(Buffer.from(composeMsg.startsWith('0x') ? composeMsg.slice(2) : composeMsg, 'hex'))
        : undefined

    const lookupTable = await getAddressLookupTable(connection, umi, srcEid)

    console.log('RPC:', connection.rpcEndpoint)
    console.log('Squads multisig:', msig)
    console.log('Sender / vault / fee payer:', senderPk.toBase58())
    console.log('Source eid:', srcEid, endpointIdToNetwork(srcEid))
    console.log('Destination eid:', dstEid, endpointIdToNetwork(dstEid))
    console.log('Destination recipient:', to)
    console.log('OFT store:', storePda.toString())
    console.log('OFT program:', programId.toString())
    console.log('Mint:', mintPk.toBase58())
    console.log('Escrow:', escrowPk.toBase58())
    console.log('Token program:', tokenProgramId.toString())
    console.log('Sender token account:', tokenAccount[0].toString())
    console.log('Decimals:', decimals)
    console.log('Shared decimals:', sharedDecimals)
    console.log('Balance raw:', balanceRaw.toString(), 'formatted:', fmt(balanceRaw, decimals))
    console.log('Requested raw:', requestedRaw.toString(), 'formatted:', fmt(requestedRaw, decimals))
    console.log('Bridge amount raw:', amountUnits.toString(), 'formatted:', fmt(amountUnits, decimals))
    console.log('OFT dust left raw:', dustRaw.toString(), 'formatted:', fmt(dustRaw, decimals))
    console.log('Min amount raw:', minAmountUnits.toString(), 'formatted:', fmt(minAmountUnits, decimals))

    console.log('\nQuoting native LZ fee...')

    const { nativeFee } = await oft.quote(
        umi.rpc,
        {
            payer: squadsSigner.publicKey,
            tokenMint: fromWeb3JsPublicKey(mintPk),
            tokenEscrow: fromWeb3JsPublicKey(escrowPk),
        },
        {
            payInLzToken: false,
            to: recipient,
            dstEid,
            amountLd: amountUnits,
            minAmountLd: minAmountUnits,
            options: optionsBuffer,
            composeMsg: composeMsgBuffer,
        },
        { oft: programId },
        [],
        lookupTable.lookupTableAddress
    )

    console.log('Native fee lamports:', nativeFee.toString(), 'SOL:', fmt(nativeFee.toString(), 9))

    const ix = await oft.send(
        umi.rpc,
        {
            payer: squadsSigner,
            tokenMint: fromWeb3JsPublicKey(mintPk),
            tokenEscrow: fromWeb3JsPublicKey(escrowPk),
            tokenSource: tokenAccount[0],
        },
        {
            to: recipient,
            dstEid,
            amountLd: amountUnits,
            minAmountLd: minAmountUnits,
            options: optionsBuffer,
            composeMsg: composeMsgBuffer,
            nativeFee,
        },
        {
            oft: programId,
            token: tokenProgramId,
        }
    )

    let txBuilder = transactionBuilder().add([ix])

    txBuilder = await addComputeUnitInstructions(
        connection,
        umi,
        srcEid,
        txBuilder,
        squadsSigner as any,
        computeUnitPriceScaleFactor,
        TransactionType.SendOFT
    )

    txBuilder.setFeePayer(squadsSigner)
    await txBuilder.setLatestBlockhash(umi)

    const serializedTx = await txBuilder.buildWithLatestBlockhash(umi)
    const transactionDataHex = Buffer.from(serializedTx.serializedMessage).toString('hex')

    const versionedMessage = VersionedMessage.deserialize(
        new Uint8Array(Buffer.from(transactionDataHex, 'hex'))
    )

    const tx = new VersionedTransaction(versionedMessage)

    const serialized = new Uint8Array(tx.serialize())
    const base58 = bs58.encode(serialized)
    const base64 = Buffer.from(serialized).toString('base64')

    console.log('\nBASE58:\n')
    console.log(base58)

    console.log('\nBASE64:\n')
    console.log(base64)

    console.log('\nVerify in Squads simulation:')
    console.log('- Sender/vault token account decreases:', tokenAccount[0].toString())
    console.log('- Sender/vault pays native SOL fee:', senderPk.toBase58())
    console.log('- OFT escrow:', escrowPk.toBase58())
    console.log('- Destination eid:', dstEid)
    console.log('- Recipient:', to)

    return {
        base58,
        base64,
    }
}

task('sendSolanaSquad', 'Build unsigned Solana OFT send tx for Squads')
    .addParam('srcEid', 'Source endpoint ID. Solana mainnet = 30168', undefined, devtoolsTypes.eid)
    .addParam('dstEid', 'Destination endpoint ID. Ethereum mainnet = 30101', undefined, devtoolsTypes.eid)
    .addParam('sender', 'Solana sender / Squads vault / token owner / fee payer', undefined, devtoolsTypes.string)
    .addParam('msig', 'Squads multisig address, logging/sanity only', undefined, devtoolsTypes.string)
    .addParam('amount', 'Amount to send, human readable, or ALL', undefined, devtoolsTypes.string)
    .addParam('to', 'Destination recipient address, e.g. Ethereum msig 0x...', undefined, devtoolsTypes.string)
    .addOptionalParam('minAmount', 'Minimum amount to receive, human readable. Defaults to dustless amount', undefined, devtoolsTypes.string)
    .addOptionalParam('extraOptions', 'Extra LZ options hex', undefined, devtoolsTypes.string)
    .addOptionalParam('composeMsg', 'Compose message hex', undefined, devtoolsTypes.string)
    .addOptionalParam('oftAddress', 'Override source OFT store PDA. Defaults to deployment file', undefined, devtoolsTypes.string)
    .addOptionalParam('oftProgramId', 'Override Solana OFT program ID. Defaults to deployment file', undefined, devtoolsTypes.string)
    .addOptionalParam('tokenProgram', 'Solana token program override', undefined, devtoolsTypes.string)
    .addOptionalParam('computeUnitPriceScaleFactor', 'Compute unit price scale factor', 4, devtoolsTypes.float)
    .addOptionalParam('sharedDecimals', 'OFT shared decimals, usually 6', 6, devtoolsTypes.int)
    .setAction(async (args: SolanaSquadArgs) => {
        await sendSolanaSquad(args)
    })