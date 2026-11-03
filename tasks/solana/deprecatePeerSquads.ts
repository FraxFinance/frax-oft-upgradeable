import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'

import { mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { createNoopSigner, publicKey, signerIdentity, transactionBuilder } from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { Connection, PublicKey as Web3PublicKey, VersionedMessage, VersionedTransaction } from '@solana/web3.js'
import bs58 from 'bs58'
import { Contract, providers, utils } from 'ethers'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { ChainType, EndpointId, endpointIdToChainType, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'
import { EndpointPDADeriver, EndpointProgram } from '@layerzerolabs/lz-solana-sdk-v2'
import { Options } from '@layerzerolabs/lz-v2-utilities'
import { OftPDA, oft } from '@layerzerolabs/oft-v2-solana-sdk'

import { createSolanaConnectionFactory } from '../common/utils'

interface Args {
    fromEid: EndpointId
    toEid: EndpointId
    toChainId?: string
    tokens?: string
    outDir?: string
    squadsAuthority?: string
    remoteRpc?: string
    keepReceiveLibrary: boolean
    dryRun: boolean
}

interface L0ConfigEntry {
    chainid: number
    eid: number
    RPC?: string
    endpoint?: string
}

interface SolanaDeployment {
    programId: string
    mint: string
    mintAuthority: string
    escrow: string
    oftStore: string
}

interface TokenDeployment {
    token: string
    filename: string
    default: boolean
}

const BLOCKED_MESSAGE_LIB = '2XrYqmhBMPJgDsb4SVbjV1PnJBprurd5bzRCkHwiFCJB'
const ZERO_PEER_BYTES_32 = new Uint8Array(32)
const EMPTY_OPTIONS = Options.newOptions().toBytes()
const ENDPOINT_OUTBOUND_NONCE_ABI = [
    'function outboundNonce(address sender, uint32 dstEid, bytes32 receiver) view returns (uint64)',
]

const TOKEN_DEPLOYMENTS: TokenDeployment[] = [
    { token: 'fpi', filename: 'FPIOFT.json', default: true },
    { token: 'frxeth', filename: 'frxETHOFT.json', default: true },
    { token: 'frxusd', filename: 'frxUSDOFT.json', default: true },
    { token: 'sfrxeth', filename: 'sfrxETHOFT.json', default: true },
    { token: 'sfrxusd', filename: 'sfrxUSDOFT.json', default: true },
    { token: 'wfrax', filename: 'WFRAXOFT.json', default: true },
    { token: 'old-frxusd', filename: 'old-frxUSDOFT.json', default: false },
]

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) return false
    return a.every((value, index) => value === b[index])
}

function optionValue<T>(option: any): T | undefined {
    if (!option || option.__option === 'None') return undefined
    if (option.__option === 'Some') return option.value as T
    return option.value as T | undefined
}

function decodedAccount<T extends object>(account: any): T {
    return (account.data ?? account) as T
}

function loadSolanaDeployment(fromEid: EndpointId, filename: string): SolanaDeployment {
    const filePath = path.join('deployments', endpointIdToNetwork(fromEid), filename)
    if (!existsSync(filePath)) throw new Error(`Missing Solana deployment file: ${filePath}`)
    return JSON.parse(readFileSync(filePath, 'utf8')) as SolanaDeployment
}

// L0Config.json drops retired chains; L0Config4L0.json still carries them (e.g. Polygon zkEVM).
function l0ConfigEntry(eid: EndpointId): L0ConfigEntry | undefined {
    for (const file of ['L0Config.json', 'L0Config4L0.json']) {
        const l0Config = JSON.parse(readFileSync(path.join('scripts', file), 'utf8')) as Record<string, unknown>
        const entry = Object.values(l0Config)
            .filter((section): section is L0ConfigEntry[] => Array.isArray(section))
            .flat()
            .find((candidate) => Number(candidate.eid) === Number(eid))
        if (entry) return entry
    }
    return undefined
}

function chainIdForEid(eid: EndpointId): number | undefined {
    return l0ConfigEntry(eid)?.chainid
}

/**
 * Blocking the receive library with no grace period strands anything already sent toward Solana, so the
 * receive side is only sealed when the remote endpoint's outbound nonce matches Solana's inbound nonce and
 * no verified message is waiting to execute.
 */
async function receiveSideDrained(
    connection: Connection,
    endpointDeriver: EndpointPDADeriver,
    fromEid: EndpointId,
    toEid: EndpointId,
    oftStore: Web3PublicKey,
    remotePeer: Uint8Array,
    remoteRpc?: string
): Promise<{ drained: boolean; reason: string }> {
    if (endpointIdToChainType(toEid) !== ChainType.EVM) {
        return { drained: false, reason: 'remote is not EVM, check in-flight messages manually' }
    }
    const entry = l0ConfigEntry(toEid)
    const rpc = remoteRpc ?? entry?.RPC
    if (!rpc || !entry?.endpoint) {
        return { drained: false, reason: `no RPC/endpoint for eid ${toEid} in L0Config (or pass --remote-rpc)` }
    }

    let outbound: bigint
    try {
        const endpoint = new Contract(
            entry.endpoint,
            ENDPOINT_OUTBOUND_NONCE_ABI,
            new providers.StaticJsonRpcProvider(rpc)
        )
        const sender = utils.getAddress(utils.hexlify(remotePeer.slice(12)))
        outbound = BigInt((await endpoint.outboundNonce(sender, fromEid, utils.hexlify(oftStore.toBytes()))).toString())
    } catch (error) {
        return { drained: false, reason: `remote outboundNonce read failed: ${(error as Error).message}` }
    }

    const [noncePda] = endpointDeriver.nonce(oftStore, toEid, remotePeer)
    const nonceInfo = await connection.getAccountInfo(noncePda)
    const inbound = nonceInfo
        ? BigInt(EndpointProgram.accounts.Nonce.fromAccountInfo(nonceInfo)[0].inboundNonce.toString())
        : 0n
    const [pendingNoncePda] = endpointDeriver.pendingNonce(oftStore, toEid, remotePeer)
    const pendingNonceInfo = await connection.getAccountInfo(pendingNoncePda)
    const pending = pendingNonceInfo
        ? EndpointProgram.accounts.PendingInboundNonce.fromAccountInfo(pendingNonceInfo)[0].nonces.length
        : 0

    if (pending > 0) return { drained: false, reason: `${pending} verified message(s) not yet executed` }
    if (outbound > inbound) {
        return {
            drained: false,
            reason: `${outbound - inbound} message(s) in flight (remote outbound ${outbound}, Solana inbound ${inbound})`,
        }
    }
    return { drained: true, reason: `nothing in flight (nonce ${inbound})` }
}

function selectedTokenDeployments(tokens?: string): TokenDeployment[] {
    if (!tokens) return TOKEN_DEPLOYMENTS.filter((deployment) => deployment.default)

    const requested = new Set(
        tokens
            .split(',')
            .map((token) => token.trim().toLowerCase())
            .filter(Boolean)
    )
    const selected = TOKEN_DEPLOYMENTS.filter((deployment) => requested.has(deployment.token.toLowerCase()))
    if (selected.length !== requested.size) {
        const known = TOKEN_DEPLOYMENTS.map((deployment) => deployment.token).join(', ')
        throw new Error(`Unknown token in '${tokens}'. Known tokens: ${known}`)
    }
    return selected
}

async function buildBase58Transaction(
    umi: ReturnType<typeof createUmi>,
    signer: ReturnType<typeof createNoopSigner>,
    instructions: any[]
) {
    const txBuilder = transactionBuilder().add(instructions)
    txBuilder.setFeePayer(signer)
    await txBuilder.setLatestBlockhash(umi)
    const serializedTx = await txBuilder.buildWithLatestBlockhash(umi)
    const versionedMessage = VersionedMessage.deserialize(serializedTx.serializedMessage)
    const tx = new VersionedTransaction(versionedMessage)

    return {
        base58: bs58.encode(new Uint8Array(tx.serialize())),
        base64: Buffer.from(tx.serialize()).toString('base64'),
    }
}

task(
    'lz:oft:solana:deprecate-peer:squads',
    'Build Solana Squads txs to deprecate a remote peer by blocking send and receive libs and zeroing peer config'
)
    .addOptionalParam('fromEid', 'The Solana endpoint ID', EndpointId.SOLANA_V2_MAINNET, devtoolsTypes.eid)
    .addParam('toEid', 'The remote endpoint ID to deprecate', undefined, devtoolsTypes.eid)
    .addOptionalParam('toChainId', 'The remote native chain ID for output naming', undefined, devtoolsTypes.string)
    .addOptionalParam(
        'tokens',
        'Comma-separated token list, defaults to current Solana OFTs',
        undefined,
        devtoolsTypes.string
    )
    .addOptionalParam('outDir', 'Output directory for base58 Squads transactions', undefined, devtoolsTypes.string)
    .addOptionalParam(
        'squadsAuthority',
        'Expected OFT admin/Squads authority override',
        undefined,
        devtoolsTypes.string
    )
    .addOptionalParam(
        'remoteRpc',
        'Remote chain RPC for the in-flight check before blocking the receive library, overrides L0Config',
        undefined,
        devtoolsTypes.string
    )
    .addFlag('keepReceiveLibrary', 'Leave the receive library as is on lanes this run cuts')
    .addFlag('dryRun', 'Print planned transactions without writing files')
    .setAction(async (args: Args) => {
        const { fromEid, toEid, tokens, squadsAuthority, remoteRpc, keepReceiveLibrary, dryRun } = args
        const toChainId = args.toChainId ? Number(args.toChainId) : chainIdForEid(toEid)
        if (!toChainId) throw new Error(`Unable to derive native chain ID for toEid ${toEid}`)
        const fromChainId = chainIdForEid(fromEid) ?? Number(fromEid)

        const outDir =
            args.outDir ?? path.join('scripts', 'ops', 'DeprecateChain', 'txs', `deprecate-${toChainId}`, 'solana')
        if (!dryRun) mkdirSync(outDir, { recursive: true })

        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(fromEid)
        const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())
        const endpointDeriver = new EndpointPDADeriver(new Web3PublicKey(EndpointProgram.PROGRAM_ID.toBase58()))
        const blockedMessageLib = publicKey(BLOCKED_MESSAGE_LIB)

        for (const tokenDeployment of selectedTokenDeployments(tokens)) {
            const deployment = loadSolanaDeployment(fromEid, tokenDeployment.filename)
            const oftProgramId = publicKey(deployment.programId)
            const oftStore = publicKey(deployment.oftStore)
            const oftStoreAccount = await oft.accounts.fetchOFTStore({ rpc: umi.rpc }, oftStore)
            const oftStoreData = decodedAccount<{ admin: { toString(): string }; endpointProgram: any }>(
                oftStoreAccount
            )
            const admin = oftStoreData.admin.toString()

            if (squadsAuthority && publicKey(squadsAuthority).toString() !== admin) {
                throw new Error(
                    `${tokenDeployment.token} admin mismatch: live admin is ${admin}, provided squadsAuthority is ${squadsAuthority}`
                )
            }

            const signer = createNoopSigner(publicKey(squadsAuthority ?? admin))
            umi.use(signerIdentity(signer))

            const [peerPda] = new OftPDA(oftProgramId).peer(oftStore, toEid)
            const peerConfig = await oft.accounts.safeFetchPeerConfig({ rpc: umi.rpc }, peerPda)

            const [sendLibraryConfigPda] = endpointDeriver.sendLibraryConfig(
                new Web3PublicKey(deployment.oftStore),
                toEid
            )
            const sendLibraryInfo = await connection.getAccountInfo(sendLibraryConfigPda)
            const sendLibraryConfig = sendLibraryInfo
                ? EndpointProgram.accounts.SendLibraryConfig.fromAccountInfo(sendLibraryInfo)[0]
                : null

            const [receiveLibraryConfigPda] = endpointDeriver.receiveLibraryConfig(
                new Web3PublicKey(deployment.oftStore),
                toEid
            )
            const receiveLibraryInfo = await connection.getAccountInfo(receiveLibraryConfigPda)

            const instructions: any[] = []
            const instructionNames: string[] = []
            const peerData = peerConfig
                ? decodedAccount<{
                    peerAddress: Uint8Array
                    enforcedOptions: { send: Uint8Array; sendAndCall: Uint8Array }
                    feeBps: any
                }>(peerConfig)
                : null
            const previousSendLibrary = sendLibraryConfig?.messageLib.toBase58() ?? null
            const blockedMessageLibProgram = new Web3PublicKey(BLOCKED_MESSAGE_LIB)
            // derive ["MessageLib"] under blockedMessageLibProgram
            const [blockedMessageLibPda] = Web3PublicKey.findProgramAddressSync(
                [Buffer.from('MessageLib')],
                blockedMessageLibProgram
            )
            if (sendLibraryConfig && previousSendLibrary !== blockedMessageLibPda.toBase58()) {
                instructions.push(
                    oft.setSendLibrary(
                        { admin: signer, oftStore },
                        { sendLibraryProgram: blockedMessageLib, remoteEid: toEid },
                        oftStoreData.endpointProgram
                    )
                )
                instructionNames.push('setSendLibrary(blocked)')
            }

            if (peerData && !bytesEqual(peerData.peerAddress, ZERO_PEER_BYTES_32)) {
                instructions.push(
                    await oft.setPeerConfig(
                        { admin: signer, oftStore },
                        { __kind: 'PeerAddress', peer: ZERO_PEER_BYTES_32, remote: toEid },
                        oftProgramId
                    )
                )
                instructionNames.push('setPeerConfig(peer=0x00)')
            }

            const enforcedOptions = peerData?.enforcedOptions
            if (
                enforcedOptions &&
                (!bytesEqual(enforcedOptions.send, EMPTY_OPTIONS) ||
                    !bytesEqual(enforcedOptions.sendAndCall, EMPTY_OPTIONS))
            ) {
                instructions.push(
                    await oft.setPeerConfig(
                        { admin: signer, oftStore },
                        { __kind: 'EnforcedOptions', send: EMPTY_OPTIONS, sendAndCall: EMPTY_OPTIONS, remote: toEid },
                        oftProgramId
                    )
                )
                instructionNames.push('setPeerConfig(enforcedOptions=0x0003)')
            }

            const feeBps = optionValue<number>(peerData?.feeBps)
            if (feeBps && feeBps !== 0) {
                instructions.push(
                    await oft.setPeerConfig(
                        { admin: signer, oftStore },
                        { __kind: 'FeeBps', feeBps: 0, remote: toEid },
                        oftProgramId
                    )
                )
                instructionNames.push('setPeerConfig(feeBps=0)')
            }

            // Seal the receive side only on lanes this run cuts; lanes cut earlier are left alone.
            const receiveLibraryConfig = receiveLibraryInfo
                ? EndpointProgram.accounts.ReceiveLibraryConfig.fromAccountInfo(receiveLibraryInfo)[0]
                : null
            const receiveLibrary = receiveLibraryConfig?.messageLib.toBase58() ?? null
            if (
                peerData &&
                !bytesEqual(peerData.peerAddress, ZERO_PEER_BYTES_32) &&
                receiveLibrary !== blockedMessageLibPda.toBase58()
            ) {
                let check: { drained: boolean; reason: string }
                if (keepReceiveLibrary) {
                    check = { drained: false, reason: '--keep-receive-library' }
                } else if (!receiveLibrary) {
                    check = { drained: false, reason: 'no OApp receive library config (endpoint default)' }
                } else {
                    check = await receiveSideDrained(
                        connection,
                        endpointDeriver,
                        fromEid,
                        toEid,
                        new Web3PublicKey(deployment.oftStore),
                        peerData.peerAddress,
                        remoteRpc
                    )
                }
                if (check.drained) {
                    instructions.push(
                        oft.setReceiveLibrary(
                            { admin: signer, oftStore },
                            { receiveLibraryProgram: blockedMessageLib, remoteEid: toEid, gracePeriod: 0n },
                            oftStoreData.endpointProgram
                        )
                    )
                    instructionNames.push(`setReceiveLibrary(blocked, ${check.reason})`)
                } else {
                    console.warn(`WARN ${tokenDeployment.token}: receive library left open, ${check.reason}`)
                }
            }

            if (instructions.length === 0) {
                const skipped =
                    peerConfig || sendLibraryConfig || receiveLibraryInfo
                        ? 'already deprecated or no mutable Solana-side action needed'
                        : 'no Solana-side peer/send/receive config exists'
                console.log(`SKIP ${tokenDeployment.token}: ${skipped}`)
                continue
            }

            const tx = await buildBase58Transaction(umi, signer, instructions)
            const outputFile = path.join(
                outDir,
                `DeprecateSolana-${fromChainId}-${toChainId}-${tokenDeployment.token}.txt`
            )
            if (!dryRun) writeFileSync(outputFile, tx.base58, 'utf8')

            console.log(
                `${dryRun ? 'PLAN' : 'WRITE'} ${tokenDeployment.token}: ${instructionNames.join(', ')} -> ${outputFile}`
            )
            console.log(`  BASE64: ${tx.base64}`)
        }
    })
