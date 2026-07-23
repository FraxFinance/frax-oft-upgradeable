import { mkdirSync, readFileSync, readdirSync, unlinkSync, writeFileSync } from 'node:fs'
import path from 'node:path'

import { types as moveTypes } from '@layerzerolabs/lz-movevm-sdk-v2'

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
    source: MoveChainProfile
    targetChainIds: number[]
    tokens?: Set<string>
    outDir: string
    fullnodeUrl: string
    dryRun: boolean
}

interface MoveChainProfile {
    chainId: number
    eid: number
    name: 'Aptos' | 'Movement'
    slug: 'aptos' | 'movement'
    defaultFullnodeUrl: string
    fullnodeEnv: 'APTOS_FULLNODE_URL' | 'MOVEMENT_FULLNODE_URL'
    endpoint: string
    uln302: string
    blockedMessageLib: string
    peerArrayIndex: number
}

const MOVE_CHAINS: Record<number, MoveChainProfile> = {
    33333333: {
        chainId: 33333333,
        eid: 30108,
        name: 'Aptos',
        slug: 'aptos',
        defaultFullnodeUrl: 'https://fullnode.mainnet.aptoslabs.com/v1',
        fullnodeEnv: 'APTOS_FULLNODE_URL',
        endpoint: '0xe60045e20fc2c99e869c1c34a65b9291c020cd12a0d37a00a53ac1348af4f43c',
        uln302: '0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9',
        blockedMessageLib: '0x3ca0d187f1938cf9776a0aa821487a650fc7bb2ab1c1d241ba319192aae4afc6',
        peerArrayIndex: 1,
    },
    22222222: {
        chainId: 22222222,
        eid: 30325,
        name: 'Movement',
        slug: 'movement',
        defaultFullnodeUrl: 'https://mainnet.movementnetwork.xyz/v1',
        fullnodeEnv: 'MOVEMENT_FULLNODE_URL',
        endpoint: '0xe60045e20fc2c99e869c1c34a65b9291c020cd12a0d37a00a53ac1348af4f43c',
        uln302: '0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9',
        blockedMessageLib: '0x3ca0d187f1938cf9776a0aa821487a650fc7bb2ab1c1d241ba319192aae4afc6',
        peerArrayIndex: 1,
    },
}

interface TokenConfig {
    name: string
    address: string
}

interface MovePayload {
    contract_address: string
    module_name: string
    function_name: string
    function_id: string
    args: Array<{ name: string; type: string; value: unknown }>
    type_args: unknown[]
}

interface MoveRouteBundle {
    source_chain_id: number
    source_eid: number
    target_chain_id: number
    target_eid: number
    oft: TokenConfig
    transactions: Array<{ order: number; action: string; payload: MovePayload }>
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

    const sourceChainId = Number(values.get('--source-chain-id') ?? 33333333)
    const source = MOVE_CHAINS[sourceChainId]
    if (!source) {
        throw new Error(`--source-chain-id must be a supported Move chain id: ${Object.keys(MOVE_CHAINS).join(', ')}`)
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
        source,
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
            path.join('scripts', 'ops', 'DeprecateChain', 'txs', `deprecate-${source.chainId}`, source.slug),
        fullnodeUrl:
            values.get('--fullnode-url') ??
            process.env[source.fullnodeEnv] ??
            source.defaultFullnodeUrl,
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
        if (!target) throw new Error(`Move-side target ${chainId} is not an EVM Proxy chain`)
        return target
    })
}

function loadTokens(source: MoveChainProfile, selected?: Set<string>): TokenConfig[] {
    const peers = JSON.parse(readFileSync(path.join('scripts', 'NonEvmPeers.json'), 'utf8')) as {
        Peers: Array<Record<string, string>>
    }
    const movePeers = peers.Peers[source.peerArrayIndex]
    if (!movePeers) {
        throw new Error(`Missing ${source.name} peer array ${source.peerArrayIndex} in NonEvmPeers.json`)
    }

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
        throw new Error(`Unknown ${source.name} token(s): ${unknown.join(', ')}`)
    }
    return filtered
}

async function view(fullnodeUrl: string, functionId: string, args: unknown[]): Promise<unknown[]> {
    const response = await fetch(`${fullnodeUrl.replace(/\/$/, '')}/view`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ function: functionId, type_arguments: [], arguments: args }),
    })
    if (!response.ok) throw new Error(`${functionId}: Move view failed (${response.status}): ${await response.text()}`)
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

function payload(oapp: string, action: string, args: MovePayload['args']): MovePayload {
    return {
        contract_address: oapp,
        module_name: 'oapp_core',
        function_name: action,
        function_id: `${oapp}::oapp_core::${action}`,
        args,
        type_args: [],
    }
}

function writeRouteBundle(args: Args, target: ChainConfig, token: TokenConfig, txs: Array<[string, MovePayload]>) {
    const filename = `${routeBundleBasename(args.source, target, token)}.json`
    const output = path.join(args.outDir, filename)
    const bundle: MoveRouteBundle = {
        source_chain_id: args.source.chainId,
        source_eid: args.source.eid,
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

function routeBundleBasename(source: MoveChainProfile, target: ChainConfig, token: TokenConfig): string {
    return `Deprecate${source.name}-${source.eid}-${target.eid}-${token.name}`
}

function removeStalePayloads(args: Args, target: ChainConfig, token: TokenConfig): void {
    if (args.dryRun) return

    const basename = routeBundleBasename(args.source, target, token)
    for (const filename of readdirSync(args.outDir)) {
        if (filename === `${basename}.json` || (filename.startsWith(`${basename}-`) && filename.endsWith('.json'))) {
            unlinkSync(path.join(args.outDir, filename))
        }
    }
}

async function buildTokenTarget(args: Args, target: ChainConfig, token: TokenConfig): Promise<void> {
    const core = `${token.address}::oapp_core`
    const [hasPeerResult, optionOneResult, optionTwoResult] = await Promise.all([
        view(args.fullnodeUrl, `${core}::has_peer`, [target.eid]),
        view(args.fullnodeUrl, `${core}::get_enforced_options`, [target.eid, 1]),
        view(args.fullnodeUrl, `${core}::get_enforced_options`, [target.eid, 2]),
    ])

    const hasPeer = boolFromView(hasPeerResult[0])
    const optionOne = bytesFromView(optionOneResult[0])
    const optionTwo = bytesFromView(optionTwoResult[0])
    const hasDirtyOptions = !optionsAreEmpty(optionOne) || !optionsAreEmpty(optionTwo)

    const [sendLibraryView, receiveLibraryView] = await Promise.allSettled([
        view(args.fullnodeUrl, `${args.source.endpoint}::endpoint::get_effective_send_library`, [token.address, target.eid]),
        view(args.fullnodeUrl, `${args.source.endpoint}::endpoint::get_effective_receive_library`, [token.address, target.eid]),
    ])

    // Some EIDs have no endpoint default libraries. With no peer or enforced
    // options, an effective-library lookup abort means the route is unwired,
    // not that generation for every later target should fail.
    if (sendLibraryView.status === 'rejected' || receiveLibraryView.status === 'rejected') {
        if (hasPeer || hasDirtyOptions) {
            if (sendLibraryView.status === 'rejected') throw sendLibraryView.reason
            if (receiveLibraryView.status === 'rejected') throw receiveLibraryView.reason
        }
        removeStalePayloads(args, target, token)
        console.log(`SKIP ${token.name} -> ${target.chainid}: no configured endpoint libraries`)
        return
    }

    const sendLibraryResult = sendLibraryView.value
    const receiveLibraryResult = receiveLibraryView.value
    const sendLibrary = normalizeAddress(sendLibraryResult[0])
    const sendLibraryIsDefault = boolFromView(sendLibraryResult[1])
    const receiveLibraryIsDefault = boolFromView(receiveLibraryResult[1])
    const sendLibraryIsBlocked = sendLibrary === normalizeAddress(args.source.blockedMessageLib)
    const hasActiveSendLibrary = !sendLibraryIsDefault && !sendLibraryIsBlocked
    const hasRouteEvidence = hasPeer || hasDirtyOptions || hasActiveSendLibrary || !receiveLibraryIsDefault

    // Replace only this token/route's generated payloads. This prevents an old
    // remove-peer or options payload surviving a partial execution and rerun.
    removeStalePayloads(args, target, token)

    if (!hasRouteEvidence) {
        console.log(`SKIP ${token.name} -> ${target.chainid}: ${args.source.name} side already deprecated`)
        return
    }

    const txs: Array<[string, MovePayload]> = []
    // Clear all app-level configs on the registered ULN before switching the send library.
    txs.push([
        'set-send-uln-default',
        payload(token.address, 'set_config', [
            { name: 'msglib', type: 'address', value: args.source.uln302 },
            { name: 'eid', type: 'u32', value: target.eid },
            { name: 'config_type', type: 'u32', value: 2 },
            { name: 'config', type: 'vector<u8>', value: Array.from(DEFAULT_ULN_CONFIG) },
        ]),
    ])
    txs.push([
        'set-executor-default',
        payload(token.address, 'set_config', [
            { name: 'msglib', type: 'address', value: args.source.uln302 },
            { name: 'eid', type: 'u32', value: target.eid },
            { name: 'config_type', type: 'u32', value: 1 },
            { name: 'config', type: 'vector<u8>', value: Array.from(DEFAULT_EXECUTOR_CONFIG) },
        ]),
    ])
    txs.push([
        'set-receive-uln-default',
        payload(token.address, 'set_config', [
            { name: 'msglib', type: 'address', value: args.source.uln302 },
            { name: 'eid', type: 'u32', value: target.eid },
            { name: 'config_type', type: 'u32', value: 3 },
            { name: 'config', type: 'vector<u8>', value: Array.from(DEFAULT_ULN_CONFIG) },
        ]),
    ])

    if (!sendLibraryIsBlocked) {
        txs.push([
            'set-send-library-blocked',
            payload(token.address, 'set_send_library', [
                { name: 'remote_eid', type: 'u32', value: target.eid },
                { name: 'msglib', type: 'address', value: args.source.blockedMessageLib },
            ]),
        ])
    }
    if (!receiveLibraryIsDefault) {
        txs.push([
            'set-receive-library-default',
            payload(token.address, 'set_receive_library', [
                { name: 'remote_eid', type: 'u32', value: target.eid },
                { name: 'msglib', type: 'address', value: ZERO_ADDRESS },
                { name: 'grace_period', type: 'u64', value: '0' },
            ]),
        ])
    }
    if (!optionsAreEmpty(optionOne)) {
        txs.push([
            'clear-enforced-options-1',
            payload(token.address, 'set_enforced_options', [
                { name: 'eid', type: 'u32', value: target.eid },
                { name: 'msg_type', type: 'u16', value: 1 },
                { name: 'enforced_options', type: 'vector<u8>', value: Array.from(EMPTY_OPTIONS) },
            ]),
        ])
    }
    if (!optionsAreEmpty(optionTwo)) {
        txs.push([
            'clear-enforced-options-2',
            payload(token.address, 'set_enforced_options', [
                { name: 'eid', type: 'u32', value: target.eid },
                { name: 'msg_type', type: 'u16', value: 2 },
                { name: 'enforced_options', type: 'vector<u8>', value: Array.from(EMPTY_OPTIONS) },
            ]),
        ])
    }
    if (hasPeer) {
        txs.push([
            'remove-peer',
            payload(token.address, 'remove_peer', [{ name: 'eid', type: 'u32', value: target.eid }]),
        ])
    }

    writeRouteBundle(args, target, token, txs)
}

async function main() {
    const args = parseArgs()
    const targets = loadTargets(args.targetChainIds)
    const tokens = loadTokens(args.source, args.tokens)
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
