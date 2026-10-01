import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'

import { findAssociatedTokenPda, mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { createNoopSigner, publicKey } from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { toWeb3JsInstruction } from '@metaplex-foundation/umi-web3js-adapters'
import {
    AddressLookupTableAccount,
    AddressLookupTableProgram,
    ComputeBudgetProgram,
    Connection,
    Keypair,
    PublicKey,
    Transaction,
    TransactionInstruction,
    TransactionMessage,
    VersionedTransaction,
    sendAndConfirmTransaction,
} from '@solana/web3.js'
import { utils } from 'ethers'
import { task, types } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'
import { addressToBytes32, Options } from '@layerzerolabs/lz-v2-utilities'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'

import { deriveConnection, getAddressLookupTable } from './index'

/**
 * Extend Frax's Solana address lookup table so that a Fraxtal-hop `send`
 * (HopMessage compose + lzCompose native drop, see send-fraxtalhopV2.ts) fits
 * Solana's 1232-byte packet for every Frax OFT, not just frxUSD.
 *
 * A composed send references 51 accounts. LayerZero's table (AokBxha6…)
 * covers the endpoint / ULN / executor / LayerZero-Labs-DVN accounts; Frax's
 * table (AxK5my…) only holds frxUSD's mint, store and escrow, so sfrxUSD,
 * frxETH, sfrxETH and WFRAX hops serialize to 1273 bytes and cannot be sent.
 *
 * This task derives every account of each token's hop send with the LayerZero
 * SDK, subtracts what either table already holds (and what can never be in a
 * table: the signer and its token account), and extends the Frax table with
 * the rest — per-token PDAs (peer, nonce, send-library and ULN send configs),
 * the OFT event authority, the per-EID default configs and the non-LayerZero
 * DVN programs and configs. Afterwards every token's hop send is ~780 bytes.
 *
 * Dry run (no key needed) prints the additions and the projected sizes:
 *   pnpm exec hardhat lz:oft:solana:extend-hop-lookup-table --eid 30168
 *
 * Execute with the table authority's key (SOLANA_PRIVATE_KEY, the fraxOFTWallet
 * 53dNdHXc…): 
 *   pnpm exec hardhat lz:oft:solana:extend-hop-lookup-table --eid 30168 --execute
 *
 * Addresses added in slot S are usable from slot S+1. Tables only grow; run
 * again after adding a token or changing the DVN set and it adds the delta.
 */

interface Args {
    eid: EndpointId
    dstEid: number
    table?: string
    tokens: string
    execute: boolean
}

const FRAX_HOP_LOOKUP_TABLE: Partial<Record<EndpointId, string>> = {
    [EndpointId.SOLANA_V2_MAINNET]: 'AxK5myLkGReGSzEywXUM7hnbQ4n1ccnbR7VL7MqPBxFy',
}

// Canonical FraxtalHopV2. The legacy hub (0xe8Cd13de…) yields byte-identical
// account lists; only the 32-byte `to` differs, which does not affect sizing.
const FRAXTAL_HOP_V2 = '0x00000000e18aFc20Afe54d4B2C8688bB60c06B36'
const FRAXTAL_HOP_COMPOSE_GAS = 550_000
const COMPUTE_UNIT_LIMIT = 600_000
const PACKET_DATA_SIZE = 1232
// Addresses per extendLookupTable instruction; 20 keeps the legacy tx well
// under the packet limit.
const EXTEND_CHUNK = 20

const hopMessage = (srcEid: number, dstEid: number, recipient: Uint8Array) =>
    utils.arrayify(
        utils.defaultAbiCoder.encode(
            ['tuple(uint32 srcEid, uint32 dstEid, uint128 dstGas, bytes32 sender, bytes32 recipient, bytes data)'],
            [{ srcEid, dstEid, dstGas: 0, sender: '0x' + '00'.repeat(32), recipient, data: '0x' }]
        )
    )

interface Deployment {
    name: string
    programId: string
    mint: string
    mintAuthority: string
    escrow: string
    oftStore: string
}

function loadDeployments(eid: EndpointId, tokens: string[]): Deployment[] {
    const dir = path.join('deployments', endpointIdToNetwork(eid))
    return tokens.map((name) => {
        const file = path.join(dir, `${name}OFT.json`)
        if (!existsSync(file)) throw new Error(`No deployment file for ${name} at ${file}`)
        return { name, ...JSON.parse(readFileSync(file, 'utf-8')) }
    })
}

/**
 * Account labels by position in the OFT program's `send` account list (the
 * on-chain `Send` struct, then the endpoint / ULN / worker CPI accounts).
 */
function labelFor(index: number, token: string): string {
    const fixed: Record<number, string> = {
        0: 'signer',
        1: `${token} peer`,
        2: `${token} OFT store`,
        3: 'signer token account',
        4: `${token} escrow`,
        5: `${token} mint`,
        6: 'token program',
        7: 'OFT event authority',
        8: 'OFT program',
        9: 'endpoint program',
        10: `${token} OFT store`,
        11: 'send library program (ULN)',
        12: `${token} send library config`,
        13: 'default send library config',
        14: 'send library info',
        15: 'endpoint settings',
        16: `${token} nonce`,
        17: 'endpoint event authority',
        18: 'endpoint program',
        19: 'ULN settings',
        20: `${token} ULN send config`,
        21: 'default ULN send config',
        22: 'signer',
        23: 'treasury placeholder (ULN program)',
        24: 'system program',
        25: 'ULN event authority',
        26: 'ULN program',
        27: 'executor program',
        28: 'executor config',
        29: 'price feed program',
        30: 'price feed',
    }
    if (index in fixed) return fixed[index]
    const dvn = Math.floor((index - 31) / 4) + 1
    return `DVN #${dvn} ${['program', 'config', 'price feed program', 'price feed'][(index - 31) % 4]}`
}

async function buildHopSend(
    umi: ReturnType<typeof createUmi>,
    payer: PublicKey,
    deployment: Deployment,
    srcEid: EndpointId,
    dstEid: number
): Promise<TransactionInstruction> {
    const mint = publicKey(deployment.mint)
    const tokenProgram = publicKey('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA')
    const [tokenSource] = findAssociatedTokenPda(umi, {
        mint,
        owner: publicKey(payer.toBase58()),
        tokenProgramId: tokenProgram,
    })
    // A representative hop: Fraxtal hub as `to`, HopMessage to Ethereum with
    // a placeholder recipient and native drop. Sizes do not depend on values.
    const recipient = addressToBytes32('0x000000000000000000000000000000000000dEaD')
    const options = new Uint8Array(
        utils.arrayify(Options.newOptions().addExecutorComposeOption(0, FRAXTAL_HOP_COMPOSE_GAS, 1n).toHex())
    )
    const ix = await oft.send(
        umi.rpc,
        {
            payer: createNoopSigner(publicKey(payer.toBase58())),
            tokenMint: mint,
            tokenEscrow: publicKey(deployment.escrow),
            tokenSource,
        },
        {
            to: addressToBytes32(FRAXTAL_HOP_V2),
            dstEid,
            amountLd: 1_000n,
            minAmountLd: 1_000n,
            options,
            composeMsg: hopMessage(srcEid, EndpointId.ETHEREUM_V2_MAINNET, recipient),
            nativeFee: 1n,
        },
        { oft: publicKey(deployment.programId), token: tokenProgram }
    )
    return toWeb3JsInstruction(ix.instruction)
}

function transactionSize(payer: PublicKey, send: TransactionInstruction, tables: AddressLookupTableAccount[]): number {
    const message = new TransactionMessage({
        payerKey: payer,
        recentBlockhash: '11111111111111111111111111111111',
        instructions: [ComputeBudgetProgram.setComputeUnitLimit({ units: COMPUTE_UNIT_LIMIT }), send],
    }).compileToV0Message(tables)
    return new VersionedTransaction(message).serialize().length
}

function withAddresses(table: AddressLookupTableAccount, extra: PublicKey[]): AddressLookupTableAccount {
    return new AddressLookupTableAccount({
        key: table.key,
        state: { ...table.state, addresses: [...table.state.addresses, ...extra] },
    })
}

async function fetchTable(connection: Connection, key: PublicKey): Promise<AddressLookupTableAccount> {
    const { value } = await connection.getAddressLookupTable(key)
    if (!value) throw new Error(`Address lookup table ${key.toBase58()} not found`)
    return value
}

task(
    'lz:oft:solana:extend-hop-lookup-table',
    "Extend Frax's Solana lookup table so every OFT's Fraxtal-hop send fits a packet"
)
    .addParam('eid', 'The Solana endpoint ID', undefined, devtoolsTypes.eid)
    .addOptionalParam('dstEid', 'Endpoint ID the sends target (the Fraxtal hub)', EndpointId.FRAXTAL_V2_MAINNET, types.int)
    .addOptionalParam('table', 'Lookup table to extend (defaults to the Frax hop table on mainnet)', undefined, types.string)
    .addOptionalParam(
        'tokens',
        'Comma-separated deployment names under deployments/<network>/<name>OFT.json',
        'frxUSD,sfrxUSD,frxETH,sfrxETH,WFRAX',
        types.string
    )
    .addFlag('execute', 'Sign and send the extension with the local keypair, which must be the table authority')
    .setAction(async (args: Args) => {
        const { eid, dstEid, execute } = args
        const tableKeyStr = args.table ?? FRAX_HOP_LOOKUP_TABLE[eid]
        if (!tableKeyStr) throw new Error(`No default Frax lookup table for eid ${eid}; pass --table`)
        const tableKey = new PublicKey(tableKeyStr)
        const tokens = args.tokens.split(',').map((t) => t.trim()).filter(Boolean)

        const { connection, umiWalletKeyPair } = await deriveConnection(eid, !execute)
        const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())
        const signer = Keypair.fromSecretKey(umiWalletKeyPair.secretKey)

        const { lookupTableAccount: lzTable } = await getAddressLookupTable(connection, umi, eid)
        const fraxTable = await fetchTable(connection, tableKey)
        const known = new Set([...lzTable.state.addresses, ...fraxTable.state.addresses].map((k) => k.toBase58()))
        // The SDK simulates a message-library version read while building the
        // send, so the payer must exist on chain. In a dry run the ephemeral
        // keypair does not; stand in the table authority, whose signer-only
        // accounts are excluded from the additions anyway.
        const payer = execute ? signer.publicKey : (fraxTable.state.authority ?? signer.publicKey)

        console.log(`LayerZero table ${lzTable.key.toBase58()}: ${lzTable.state.addresses.length} addresses`)
        console.log(
            `Frax table ${fraxTable.key.toBase58()}: ${fraxTable.state.addresses.length} addresses, authority ${fraxTable.state.authority?.toBase58() ?? 'none (frozen)'}`
        )

        // Every account each token's hop send needs, minus what a table can
        // hold for it already or can never hold (the signer and its ATA).
        const additions: { key: PublicKey; labels: string[] }[] = []
        const sends: { token: string; ix: TransactionInstruction }[] = []
        for (const deployment of loadDeployments(eid, tokens)) {
            const ix = await buildHopSend(umi, payer, deployment, eid, dstEid)
            sends.push({ token: deployment.name, ix })
            ix.keys.forEach((meta, index) => {
                const key = meta.pubkey.toBase58()
                if (meta.isSigner || key === payer.toBase58() || key === ix.programId.toBase58()) return
                if (index === 3) return // the signer's associated token account
                if (known.has(key)) return
                const label = `${labelFor(index, deployment.name)}`
                const existing = additions.find((a) => a.key.equals(meta.pubkey))
                if (existing) {
                    if (!existing.labels.includes(label)) existing.labels.push(label)
                } else {
                    additions.push({ key: meta.pubkey, labels: [label] })
                }
            })
        }

        console.log(`\n${additions.length} addresses to add:`)
        for (const a of additions) console.log(`  ${a.key.toBase58()}  ${a.labels.join(' / ')}`)

        const projected = withAddresses(fraxTable, additions.map((a) => a.key))
        console.log('\nHop send size (bytes, limit 1232):')
        for (const { token, ix } of sends) {
            const before = transactionSize(payer, ix, [lzTable, fraxTable])
            const after = transactionSize(payer, ix, [lzTable, projected])
            console.log(`  ${token.padEnd(8)} before ${before}${before > PACKET_DATA_SIZE ? ' (too large)' : ''}  after ${after}`)
        }
        if (additions.length === 0) {
            console.log('\nNothing to add: the table already covers every hop send.')
            return
        }
        if (fraxTable.state.addresses.length + additions.length > 256) {
            throw new Error('The table would exceed 256 addresses')
        }
        const rentAfter = await connection.getMinimumBalanceForRentExemption(
            56 + 32 * (fraxTable.state.addresses.length + additions.length)
        )
        const tableInfo = await connection.getAccountInfo(tableKey)
        const rentDelta = Math.max(0, rentAfter - (tableInfo?.lamports ?? 0))
        console.log(`\nRent top-up: ${rentDelta} lamports (${(rentDelta / 1e9).toFixed(6)} SOL) plus fees`)

        if (!execute) {
            console.log('\nDry run. Re-run with --execute and SOLANA_PRIVATE_KEY of the table authority to apply.')
            return
        }
        if (!fraxTable.state.authority || !fraxTable.state.authority.equals(payer)) {
            throw new Error(
                `Local keypair ${payer.toBase58()} is not the table authority ${fraxTable.state.authority?.toBase58() ?? 'none'}`
            )
        }

        for (let i = 0; i < additions.length; i += EXTEND_CHUNK) {
            const chunk = additions.slice(i, i + EXTEND_CHUNK).map((a) => a.key)
            const tx = new Transaction().add(
                AddressLookupTableProgram.extendLookupTable({
                    lookupTable: tableKey,
                    authority: payer,
                    payer,
                    addresses: chunk,
                })
            )
            const signature = await sendAndConfirmTransaction(connection, tx, [signer], { commitment: 'confirmed' })
            console.log(`extended with ${chunk.length} addresses: ${signature}`)
        }

        // Addresses become usable one slot after the extension; re-read the
        // table and confirm every hop send now fits.
        await new Promise((resolve) => setTimeout(resolve, 2_000))
        const extended = await fetchTable(connection, tableKey)
        console.log(`\nFrax table now holds ${extended.state.addresses.length} addresses. Hop send size:`)
        let ok = true
        for (const { token, ix } of sends) {
            const size = transactionSize(payer, ix, [lzTable, extended])
            ok = ok && size <= PACKET_DATA_SIZE
            console.log(`  ${token.padEnd(8)} ${size}${size > PACKET_DATA_SIZE ? ' (still too large!)' : ''}`)
        }
        if (!ok) throw new Error('Some hop sends still exceed the packet limit')
        console.log('\nDone. Lift ROUTE_TOKEN_RESTRICTIONS for Solana in frax-lz-route-api and regenerate its registry.')
    })
