import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'

import { mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { createNoopSigner, publicKey, signerIdentity, transactionBuilder } from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { PublicKey as Web3PublicKey, VersionedMessage, VersionedTransaction } from '@solana/web3.js'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'
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
    dryRun: boolean
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

function chainIdForEid(eid: EndpointId): number | undefined {
    const l0Config = JSON.parse(readFileSync(path.join('scripts', 'L0Config.json'), 'utf8')) as {
        Proxy: Array<{ chainid: number; eid: number }>
        'Non-EVM': Array<{ chainid: number; eid: number }>
    }
    return [...l0Config.Proxy, ...l0Config['Non-EVM']].find((entry) => Number(entry.eid) === Number(eid))?.chainid
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
    'Build Solana Squads txs to deprecate a remote peer by blocking send lib and zeroing peer config'
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
    .addFlag('dryRun', 'Print planned transactions without writing files')
    .setAction(async (args: Args) => {
        const { fromEid, toEid, tokens, squadsAuthority, dryRun } = args
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

            if (sendLibraryConfig && previousSendLibrary !== BLOCKED_MESSAGE_LIB) {
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
