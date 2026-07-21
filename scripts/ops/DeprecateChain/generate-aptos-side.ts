import { mkdirSync, readFileSync, readdirSync, unlinkSync, writeFileSync } from 'node:fs'
import path from 'node:path'

import { types as moveTypes } from '@layerzerolabs/lz-movevm-sdk-v2'

const APTOS_CHAIN_ID = 33333333
const APTOS_EID = 30108
const APTOS_ENDPOINT = '0xe60045e20fc2c99e869c1c34a65b9291c020cd12a0d37a00a53ac1348af4f43c'
const APTOS_ULN_302 = '0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9'
const APTOS_BLOCKED_MESSAGE_LIB = '0x3ca0d187f1938cf9776a0aa821487a650fc7bb2ab1c1d241ba319192aae4afc6'
const ZERO_ADDRESS = `0x${'0'.repeat(64)}`
const EMPTY_OPTIONS = Uint8Array.from([0, 3])

const DEFAULT_ULN_CONFIG = moveTypes.serializeUlnConfig({
    confirmations: BigInt(0),
    optionalDVNThreshold: 0,
    requiredDVNs: [],
    optionalDVNs: [],
    useDefaultForConfirmations: true,
    useDefaultForRequiredDVNs: true,
    useDefaultForOptionalDVNs: true,
})
const DEFAULT_EXECUTOR_CONFIG = moveTypes.serializeExecutorConfig({ maxMessageSize: 0, executorAddress: ZERO_ADDRESS })

interface ChainConfig {
    chainid: number
    eid: number
}

interface Args {
    targetChainIds: number[]
    tokens?: Set<string>
    outDir: string
    fullnodeUrl: string
    dryRun: boolean
}

interface TokenConfig {
    name: string
    address: string
}

interface AptosPayload {
    function_id: string
    args: Array<{ type: string; value: unknown }>
    type_args: unknown[]
}

interface AptosRouteBundle {
    source_chain_id: number
    source_eid: number
    target_chain_id: number
    target_eid: number
    oft: TokenConfig
    transactions: Array<{ order: number; action: string; payload: AptosPayload }>
}

function parseArgs(): Args {
    const values = new Map<string, string>()
    const flags = new Set<string>()
    for (let i = 2; i < process.argv.length; i++) {
        const arg = process.argv[i]
        if (arg === '--dry-run') {
            flags.add(arg)
            continue
        }
        const value = process.argv[++i]
        if (!value) throw new Error(`Missing value for ${arg}`)
        values.set(arg, value)
    }

    const targetChainIds = (values.get('--target-chain-ids') ?? '')
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean)
        .map(Number)
    if (targetChainIds.length === 0 || targetChainIds.some((value) => !Number.isSafeInteger(value) || value <= 0)) {
        throw new Error('--target-chain-ids must contain one or more numeric chain IDs')
    }

    const tokenValues = values.get('--tokens')
    return {
        targetChainIds: [...new Set(targetChainIds)],
        tokens: tokenValues
            ? new Set(
                  tokenValues
                      .split(',')
                      .map((value) => value.trim().toUpperCase())
                      .filter(Boolean)
              )
            : undefined,
        outDir:
            values.get('--out-dir') ??
            path.join('scripts', 'ops', 'DeprecateChain', 'txs', `deprecate-${APTOS_CHAIN_ID}`, 'aptos'),
        fullnodeUrl:
            values.get('--fullnode-url') ??
            process.env.APTOS_FULLNODE_URL ??
            'https://fullnode.mainnet.aptoslabs.com/v1',
        dryRun: flags.has('--dry-run'),
    }
}

function loadTargets(targetChainIds: number[]): ChainConfig[] {
    const config = JSON.parse(readFileSync(path.join('scripts', 'L0Config.json'), 'utf8')) as {
        Proxy: ChainConfig[]
    }
    const byChainId = new Map(config.Proxy.map((entry) => [Number(entry.chainid), entry]))
    return targetChainIds.map((chainId) => {
        const target = byChainId.get(chainId)
        if (!target) throw new Error(`Aptos-side target ${chainId} is not an EVM Proxy chain`)
        return target
    })
}

function loadTokens(selected?: Set<string>): TokenConfig[] {
    const peers = JSON.parse(readFileSync(path.join('scripts', 'NonEvmPeers.json'), 'utf8')) as {
        Peers: Array<Record<string, string>>
    }
    const movePeers = peers.Peers[1]
    if (!movePeers) throw new Error('Missing shared Movement/Aptos peer array in NonEvmPeers.json')

    const tokens: TokenConfig[] = [
        { name: 'WFRAX', address: movePeers.wfrax },
        { name: 'SFRXUSD', address: movePeers.sfrxUSD },
        { name: 'SFRXETH', address: movePeers.sfrxEth },
        { name: 'FRXUSD', address: movePeers.frxUSD },
        { name: 'FRXETH', address: movePeers.frxEth },
        { name: 'FPI', address: movePeers.fpi },
    ]
    if (!selected) return tokens

    const filtered = tokens.filter((token) => selected.has(token.name))
    if (filtered.length !== selected.size) {
        const unknown = [...selected].filter((name) => !tokens.some((token) => token.name === name))
        throw new Error(`Unknown Aptos token(s): ${unknown.join(', ')}`)
    }
    return filtered
}

async function view(fullnodeUrl: string, functionId: string, args: unknown[]): Promise<unknown[]> {
    const response = await fetch(`${fullnodeUrl.replace(/\/$/, '')}/view`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ function: functionId, type_arguments: [], arguments: args }),
    })
    if (!response.ok) throw new Error(`${functionId}: Aptos view failed (${response.status}): ${await response.text()}`)
    return (await response.json()) as unknown[]
}

function normalizeAddress(value: unknown): string {
    const raw = String(value).toLowerCase().replace(/^0x/, '')
    return `0x${raw.padStart(64, '0')}`
}

function bytesFromView(value: unknown): Uint8Array {
    if (Array.isArray(value)) return Uint8Array.from(value.map(Number))
    const raw = String(value).replace(/^0x/, '')
    return Uint8Array.from(Buffer.from(raw, 'hex'))
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
    return a.length === b.length && a.every((value, index) => value === b[index])
}

function optionsAreEmpty(options: Uint8Array): boolean {
    // An untouched entry reads as empty bytes. set_enforced_options rejects empty
    // bytes, so deprecation writes the canonical empty type-3 prefix instead.
    return options.length === 0 || bytesEqual(options, EMPTY_OPTIONS)
}

function boolFromView(value: unknown): boolean {
    return value === true || value === 'true'
}

function payload(oapp: string, action: string, args: AptosPayload['args']): AptosPayload {
    return { function_id: `${oapp}::oapp_core::${action}`, args, type_args: [] }
}

function writeRouteBundle(args: Args, target: ChainConfig, token: TokenConfig, txs: Array<[string, AptosPayload]>) {
    const filename = `DeprecateAptos-${APTOS_EID}-${target.eid}-${token.name}.json`
    const output = path.join(args.outDir, filename)
    const bundle: AptosRouteBundle = {
        source_chain_id: APTOS_CHAIN_ID,
        source_eid: APTOS_EID,
        target_chain_id: target.chainid,
        target_eid: target.eid,
        oft: token,
        transactions: txs.map(([action, tx], index) => ({ order: index + 1, action, payload: tx })),
    }
    if (!args.dryRun) writeFileSync(output, `${JSON.stringify(bundle, null, 2)}\n`)
    console.log(
        `${args.dryRun ? 'PLAN' : 'WRITE'} ${token.name} -> ${target.chainid}: ${txs.length} transaction(s) (${output})`
    )
}

function removeStalePayloads(args: Args, target: ChainConfig, token: TokenConfig): void {
    if (args.dryRun) return

    const prefix = `DeprecateAptos-${APTOS_EID}-${target.eid}-${token.name}-`
    for (const filename of readdirSync(args.outDir)) {
        if (filename.startsWith(prefix) && filename.endsWith('.json')) {
            unlinkSync(path.join(args.outDir, filename))
        }
    }
}

async function buildTokenTarget(args: Args, target: ChainConfig, token: TokenConfig): Promise<void> {
    const core = `${token.address}::oapp_core`
    const [hasPeerResult, optionOneResult, optionTwoResult, sendLibraryResult, receiveLibraryResult] =
        await Promise.all([
            view(args.fullnodeUrl, `${core}::has_peer`, [target.eid]),
            view(args.fullnodeUrl, `${core}::get_enforced_options`, [target.eid, 1]),
            view(args.fullnodeUrl, `${core}::get_enforced_options`, [target.eid, 2]),
            view(args.fullnodeUrl, `${APTOS_ENDPOINT}::endpoint::get_effective_send_library`, [
                token.address,
                target.eid,
            ]),
            view(args.fullnodeUrl, `${APTOS_ENDPOINT}::endpoint::get_effective_receive_library`, [
                token.address,
                target.eid,
            ]),
        ])

    const hasPeer = boolFromView(hasPeerResult[0])
    const optionOne = bytesFromView(optionOneResult[0])
    const optionTwo = bytesFromView(optionTwoResult[0])
    const sendLibrary = normalizeAddress(sendLibraryResult[0])
    const sendLibraryIsDefault = boolFromView(sendLibraryResult[1])
    const receiveLibraryIsDefault = boolFromView(receiveLibraryResult[1])
    const sendLibraryIsBlocked = sendLibrary === normalizeAddress(APTOS_BLOCKED_MESSAGE_LIB)
    const hasDirtyOptions = !optionsAreEmpty(optionOne) || !optionsAreEmpty(optionTwo)
    const hasActiveSendLibrary = !sendLibraryIsDefault && !sendLibraryIsBlocked
    const hasRouteEvidence = hasPeer || hasDirtyOptions || hasActiveSendLibrary || !receiveLibraryIsDefault

    // Replace only this token/route's generated payloads. This prevents an old
    // remove-peer or options payload surviving a partial execution and rerun.
    removeStalePayloads(args, target, token)

    if (!hasRouteEvidence) {
        console.log(`SKIP ${token.name} -> ${target.chainid}: Aptos side already deprecated`)
        return
    }

    const txs: Array<[string, AptosPayload]> = []
    // Clear all app-level configs on the registered ULN before switching the send library.
    txs.push([
        'set-send-uln-default',
        payload(token.address, 'set_config', [
            { type: 'address', value: APTOS_ULN_302 },
            { type: 'u32', value: target.eid },
            { type: 'u32', value: 2 },
            { type: 'u8', value: Array.from(DEFAULT_ULN_CONFIG) },
        ]),
    ])
    txs.push([
        'set-executor-default',
        payload(token.address, 'set_config', [
            { type: 'address', value: APTOS_ULN_302 },
            { type: 'u32', value: target.eid },
            { type: 'u32', value: 1 },
            { type: 'u8', value: Array.from(DEFAULT_EXECUTOR_CONFIG) },
        ]),
    ])
    txs.push([
        'set-receive-uln-default',
        payload(token.address, 'set_config', [
            { type: 'address', value: APTOS_ULN_302 },
            { type: 'u32', value: target.eid },
            { type: 'u32', value: 3 },
            { type: 'u8', value: Array.from(DEFAULT_ULN_CONFIG) },
        ]),
    ])

    if (!sendLibraryIsBlocked) {
        txs.push([
            'set-send-library-blocked',
            payload(token.address, 'set_send_library', [
                { type: 'u32', value: target.eid },
                { type: 'address', value: APTOS_BLOCKED_MESSAGE_LIB },
            ]),
        ])
    }
    if (!receiveLibraryIsDefault) {
        txs.push([
            'set-receive-library-default',
            payload(token.address, 'set_receive_library', [
                { type: 'u32', value: target.eid },
                { type: 'address', value: ZERO_ADDRESS },
                { type: 'u64', value: '0' },
            ]),
        ])
    }
    if (!optionsAreEmpty(optionOne)) {
        txs.push([
            'clear-enforced-options-1',
            payload(token.address, 'set_enforced_options', [
                { type: 'u32', value: target.eid },
                { type: 'u16', value: 1 },
                { type: 'u8', value: Array.from(EMPTY_OPTIONS) },
            ]),
        ])
    }
    if (!optionsAreEmpty(optionTwo)) {
        txs.push([
            'clear-enforced-options-2',
            payload(token.address, 'set_enforced_options', [
                { type: 'u32', value: target.eid },
                { type: 'u16', value: 2 },
                { type: 'u8', value: Array.from(EMPTY_OPTIONS) },
            ]),
        ])
    }
    if (hasPeer) {
        txs.push(['remove-peer', payload(token.address, 'remove_peer', [{ type: 'u32', value: target.eid }])])
    }

    writeRouteBundle(args, target, token, txs)
}

async function main() {
    const args = parseArgs()
    const targets = loadTargets(args.targetChainIds)
    const tokens = loadTokens(args.tokens)
    if (!args.dryRun) mkdirSync(args.outDir, { recursive: true })

    // Keep RPC pressure bounded per target while still batching all token reads.
    for (const target of targets) {
        await Promise.all(tokens.map((token) => buildTokenTarget(args, target, token)))
    }
}

main().catch((error) => {
    console.error(error instanceof Error ? error.message : error)
    process.exitCode = 1
})
