import fs from 'fs'
import path from 'path'

import { BigNumber, Wallet, constants, utils } from 'ethers'
import { task, types } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import {
    ACTIVE_ASSETS,
    Batch,
    Chains,
    FRAXTAL_EID,
    FRAXTAL_HOP,
    HUB_LOCKBOX,
    eq,
    executeBatch,
    legFromAsset,
    loadChains,
    nativeOverride,
    planBatch,
    resolveAsset,
    simulateBatch,
    tip20Override,
    walletOn,
    withBps,
} from './fraxWallet'

/**
 * Ring smoketest of the mesh through the dev FraxOFTWallets: every chain on the route sends and receives all five
 * active assets once, as a relay. Each leg is one frax:wallet:send batch (direct, or HopV2 through Fraxtal when the
 * chains have no direct peers), and the next leg starts only after the destination wallet holds all five tokens.
 *
 *   frax:wallet:smoketest                      dry run (no key): checks, a zero-amount simulation of every leg, fees,
 *                                              expected waits, and what the owner and the hub hop need
 *   frax:wallet:smoketest --execute            send the legs; resumable through .frax-wallet-smoketest.json
 *   frax:wallet:smoketest --execute --max-legs 1    canary: only the next leg
 *
 * X Layer goes last on the default route: its OFTs wait 225,000 confirmations (~62.5 h) before a message leaves
 * X Layer, so its out-leg must not hold up the rest of the ring. Plume is left out: its wallet still runs the old
 * implementation. Recipients are always the destination's dev wallet with empty hop data; non-empty data to the
 * wallet makes the destination hop's compose revert and strands the tokens.
 */

const OWNER = '0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e'
const STATE_FILE = '.frax-wallet-smoketest.json'
const LZ_SCAN_API = 'https://scan.layerzero-api.com/v1/messages/tx/'
const FEE_BPS = 200 // msg.value over the quoted fee; any surplus stays in the wallet
const GAS_BPS = 3_000
const SKIPPED_TRANSFER_GAS = 400_000 // token transfers a zero-amount simulation skips
const FALLBACK_GAS = 3_500_000 // when the RPC cannot estimate with a state override
const HUB_PLAN_BPS = 1_500
const HUB_EXECUTE_BPS = 2_500
const DELIVERY_OVERHEAD_S = 120 // DVN signing + executor per LayerZero message (LayerZero Scan history)
const LONG_LEG_S = 3 * 3600
const SHARED_DECIMALS = 6

/// @dev Names for the route and the report; eids not listed print as their eid.
const CHAIN_INFO: Record<number, [key: string, name: string, symbol: string]> = {
    30255: ['fraxtal', 'Fraxtal', 'FRAX'],
    30280: ['sei', 'Sei', 'SEI'],
    30165: ['zksync', 'zkSync', 'ETH'],
    30184: ['base', 'Base', 'ETH'],
    30110: ['arbitrum', 'Arbitrum', 'ETH'],
    30111: ['optimism', 'Optimism', 'ETH'],
    30320: ['unichain', 'Unichain', 'ETH'],
    30339: ['ink', 'Ink', 'ETH'],
    30319: ['worldchain', 'World Chain', 'ETH'],
    30183: ['linea', 'Linea', 'ETH'],
    30375: ['katana', 'Katana', 'ETH'],
    30416: ['robinhood', 'Robinhood', 'ETH'],
    30125: ['celo', 'Celo', 'CELO'],
    30109: ['polygon', 'Polygon', 'POL'],
    30106: ['avalanche', 'Avalanche', 'AVAX'],
    30102: ['bnb', 'BNB Chain', 'BNB'],
    30367: ['hyperevm', 'HyperEVM', 'HYPE'],
    30332: ['sonic', 'Sonic', 'S'],
    30390: ['monad', 'Monad', 'MON'],
    30396: ['stable', 'Stable', 'USDT0'],
    30380: ['somnia', 'Somnia', 'SOMI'],
    30410: ['tempo', 'Tempo', 'USD'],
    30101: ['ethereum', 'Ethereum', 'ETH'],
    30274: ['xlayer', 'X Layer', 'OKB'],
    30370: ['plume', 'Plume', 'PLUME'],
    30243: ['blast', 'Blast', 'ETH'],
}
const DEFAULT_ROUTE = [
    'fraxtal', 'sei', 'zksync', 'base', 'arbitrum', 'optimism', 'unichain', 'ink', 'worldchain', 'linea', 'katana',
    'robinhood', 'celo', 'polygon', 'avalanche', 'bnb', 'hyperevm', 'sonic', 'monad', 'stable', 'somnia', 'tempo',
    'ethereum', 'xlayer', 'fraxtal',
] // prettier-ignore

const nameOf = (eid: number) => CHAIN_INFO[eid]?.[1] ?? `eid ${eid}`
const symbolOf = (eid: number) => CHAIN_INFO[eid]?.[2] ?? 'native'
const norm = (s: string) =>
    s
        .trim()
        .toLowerCase()
        .replace(/[\s_-]/g, '')

function parseRoute(spec: string): number[] {
    const route = spec.split(',').map((item) => {
        if (/^\d+$/.test(item.trim())) return Number(item)
        const found = Object.entries(CHAIN_INFO).find(
            ([, [key, name]]) => key === norm(item) || norm(name) === norm(item)
        )
        if (!found) throw new Error(`unknown chain "${item}" (use an eid or one of ${DEFAULT_ROUTE.join(', ')})`)
        return Number(found[0])
    })
    if (route.length < 2) throw new Error('--route needs at least two chains')
    return route
}

/** "0.0001" in OFT shared decimals (6 for every Frax OFT). */
function toSharedDecimals(value: string): BigNumber {
    if (!/^\d+(\.\d{0,6})?$/.test(value.trim())) throw new Error(`--amount ${value}: use up to 6 decimals`)
    return utils.parseUnits(value.trim(), SHARED_DECIMALS)
}

const fmtUnits = (v: BigNumber, decimals = 18, digits = 6) => {
    const [i, f = ''] = utils.formatUnits(v, decimals).split('.')
    const frac = f.slice(0, digits).replace(/0+$/, '')
    return frac ? `${i}.${frac}` : i
}
const fmtDuration = (s: number) => (s >= 3600 ? `${(s / 3600).toFixed(1)} h` : `${Math.max(1, Math.round(s / 60))} min`)
/** Local decimals from a leg amount (shared amount x conversion rate, rate = 10^(decimals - 6)). */
const decimalsOf = (amountLD: BigNumber, amountSD: BigNumber) =>
    SHARED_DECIMALS + amountLD.div(amountSD).toString().length - 1
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const firstLine = (e: unknown) => ((e as Error).message ?? String(e)).split('\n')[0].slice(0, 220)

async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
    const out: R[] = new Array(items.length)
    let next = 0
    const worker = async () => {
        while (next < items.length) {
            const i = next++
            out[i] = await fn(items[i])
        }
    }
    await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker))
    return out
}

// ─── Per-chain facts (memoized) ─────────────────────────────────────────────────────────────

const memo = new Map<string, Promise<unknown>>()
const once = <T>(key: string, fn: () => Promise<T>) => {
    if (!memo.has(key)) memo.set(key, fn())
    return memo.get(key) as Promise<T>
}

const blockTime = (chains: Chains, eid: number) =>
    once(`blocktime:${eid}`, async () => {
        const rpc = chains.provider(eid)
        const latest = await rpc.getBlock('latest')
        const span = Math.min(2000, latest.number)
        const earlier = await rpc.getBlock(latest.number - span)
        return (latest.timestamp - earlier.timestamp) / span
    })

const rateOf = (chains: Chains, oft: string, eid: number) =>
    once(`rate:${eid}:${oft}`, async () => BigNumber.from(await chains.at(oft, eid).decimalConversionRate()))

/** Source confirmations a message from `oft` to `dstEid` waits for (ULN302 send config, type 2). */
async function confirmations(chains: Chains, eid: number, oft: string, dstEid: number) {
    const endpoint = chains.at(await chains.at(oft, eid).endpoint(), eid)
    const lib: string = await endpoint.getSendLibrary(oft, dstEid)
    const raw: string = await endpoint.getConfig(oft, lib, dstEid, 2)
    const [cfg] = utils.defaultAbiCoder.decode(['tuple(uint64,uint8,uint8,uint8,address[],address[])'], raw)
    return Number(cfg[0])
}

// ─── Legs ───────────────────────────────────────────────────────────────────────────────────

interface LegPlan {
    index: number
    src: number
    dst: number
    issues: string[]
    batch?: Batch
    /** Destination token per asset and the increase to expect there (shared amount x destination rate). */
    dstTokens: Record<string, string>
    expected: Record<string, BigNumber>
    gasCost: BigNumber
    hubCost: BigNumber
    expectedS: number
    expectedDetail: string
    tempo?: { gasToken: string; need: BigNumber; balance: BigNumber; allowance: BigNumber }
}

const spokeToSpoke = (src: number, dst: number) => src !== FRAXTAL_EID && dst !== FRAXTAL_EID

/** Build (and, for the dry run, simulate) one leg. Problems are collected, never thrown. */
async function planLeg(
    chains: Chains,
    index: number,
    src: number,
    dst: number,
    amountSD: BigNumber,
    simulate: boolean
) {
    const p: LegPlan = {
        index, src, dst, issues: [], dstTokens: {}, expected: {},
        gasCost: constants.Zero, hubCost: constants.Zero, expectedS: 0, expectedDetail: '',
    } // prettier-ignore
    const { at, codeAt } = chains
    const srcWallet = walletOn(src)
    const to = utils.hexZeroPad(walletOn(dst), 32)
    try {
        if ((await codeAt(srcWallet, src)) === '0x') throw new Error(`no wallet at ${srcWallet} on ${nameOf(src)}`)
        if ((await codeAt(walletOn(dst), dst)) === '0x')
            throw new Error(`no wallet at ${walletOn(dst)} on ${nameOf(dst)}`)
        const owner: string = await at(srcWallet, src).owner()
        if (!eq(owner, OWNER)) p.issues.push(`${nameOf(src)} wallet owner is ${owner}, not ${OWNER}`)

        // Every active asset must exist on both ends.
        const legs = []
        const zeroLegs = []
        for (const symbol of ACTIVE_ASSETS) {
            const asset = await resolveAsset(chains, symbol, src, dst, srcWallet)
            if (typeof asset === 'string') {
                p.issues.push(asset)
                continue
            }
            const [srcRate, dstRate, dstToken] = await Promise.all([
                rateOf(chains, asset.srcOft, src),
                rateOf(chains, asset.dstOft, dst),
                at(asset.dstOft, dst).token(),
            ])
            p.dstTokens[symbol] = dstToken
            p.expected[symbol] = amountSD.mul(dstRate)
            legs.push(legFromAsset(asset, amountSD.mul(srcRate)))
            zeroLegs.push(legFromAsset(asset, constants.Zero))
        }
        if (p.issues.length) return p

        const base = { srcEid: src, dstEid: dst, walletAddr: srcWallet, to, valueBps: FEE_BPS }
        p.batch = await planBatch(chains, { ...base, legs, route: 'auto' })
        const route = p.batch.route
        const hopped = route === 'hop' && spokeToSpoke(src, dst)

        // Expected wait: the slowest asset's first message, plus the hub's second message for spoke -> spoke hops.
        const firstDst = hopped ? FRAXTAL_EID : dst
        const firstConf = Math.max(
            ...(await Promise.all(legs.map((l) => confirmations(chains, src, l.srcOft, firstDst))))
        )
        p.expectedS = firstConf * (await blockTime(chains, src)) + DELIVERY_OVERHEAD_S
        p.expectedDetail = `${nameOf(src)} ${firstConf} conf`
        if (hopped) {
            const hubConf = Math.max(
                ...(await Promise.all(
                    ACTIVE_ASSETS.map((s) => confirmations(chains, FRAXTAL_EID, HUB_LOCKBOX[s], dst))
                ))
            )
            p.expectedS += hubConf * (await blockTime(chains, FRAXTAL_EID)) + DELIVERY_OVERHEAD_S
            p.expectedDetail += ` + Fraxtal ${hubConf} conf`

            // The Fraxtal hub hop pays every second leg from its own FRAX.
            const hub = at(FRAXTAL_HOP, FRAXTAL_EID)
            for (const s of ACTIVE_ASSETS) {
                const amount = amountSD.mul(await rateOf(chains, HUB_LOCKBOX[s], FRAXTAL_EID))
                const q = await hub.quote(HUB_LOCKBOX[s], dst, to, amount, 0, '0x', { from: FRAXTAL_HOP })
                p.hubCost = p.hubCost.add(q)
            }
        }

        if (p.batch.tip20) {
            const token = at(p.batch.gasToken, src)
            const [balance, allowance] = await Promise.all([token.balanceOf(OWNER), token.allowance(OWNER, srcWallet)])
            p.tempo = { gasToken: p.batch.gasToken, need: p.batch.totalFee, balance, allowance }
        }
        if (!simulate) return p

        // Zero amounts: the hop skips the token pull, so legs whose tokens have not arrived yet are still checked.
        // Fees and msg.value are real; the owner's native balance (or Tempo fee-token storage) is overridden.
        const zero = await planBatch(chains, {
            ...base,
            legs: zeroLegs,
            route,
            gasToken: p.batch.gasToken || undefined,
        })
        const override = zero.tip20
            ? tip20Override(zero.gasToken, OWNER, srcWallet, utils.parseUnits('1000000', 6))
            : nativeOverride(OWNER, zero.value)
        const gas = (await simulateBatch(chains, zero, override)) ?? BigNumber.from(FALLBACK_GAS)
        if (!zero.tip20) {
            const gasPrice = await chains.provider(src).getGasPrice()
            p.gasCost = withBps(gas.add(SKIPPED_TRANSFER_GAS), GAS_BPS).mul(withBps(gasPrice, 2_000))
        }
    } catch (e) {
        p.issues.push(firstLine(e))
    }
    return p
}

async function walletBalances(chains: Chains, eid: number, tokens: Record<string, string>) {
    const out: Record<string, BigNumber> = {}
    for (const [symbol, token] of Object.entries(tokens))
        out[symbol] = await chains.at(token, eid).balanceOf(walletOn(eid))
    return out
}

// ─── Report ─────────────────────────────────────────────────────────────────────────────────

async function report(chains: Chains, route: number[], amountSD: BigNumber, plans: LegPlan[]) {
    console.log(`\nRoute (${plans.length} legs, ${fmtUnits(amountSD, SHARED_DECIMALS)} of each asset per leg):`)
    console.log('  ' + route.map(nameOf).join(' -> '))
    console.log(
        '\nLeg  Source -> Destination              route   fee (source native)       hub 2nd legs  expect    check'
    )
    for (const p of plans) {
        const b = p.batch
        const fee = !b ? '-' : b.tip20 ? `${fmtUnits(b.totalFee, 6)} USD` : `${fmtUnits(b.value)} ${symbolOf(p.src)}`
        console.log(
            `${String(p.index + 1).padStart(3)}  ${`${nameOf(p.src)} -> ${nameOf(p.dst)}`.padEnd(32)} ` +
                `${(b?.route ?? '-').padEnd(7)} ${fee.padEnd(25)} ` +
                `${p.hubCost.isZero() ? '-' : `${fmtUnits(p.hubCost, 18, 2)} FRAX`}`.padEnd(14) +
                fmtDuration(p.expectedS).padEnd(10) +
                (p.issues.length ? 'PROBLEM' : 'ok')
        )
        for (const i of p.issues) console.log(`       ! ${i}`)
    }

    const total = plans.reduce((a, p) => a + p.expectedS, 0)
    console.log(`\nExpected relay time ~${fmtDuration(total)} (each OFT's send confirmations + ~2 min per message).`)
    for (const p of plans.filter((x) => x.expectedS > 3600)) {
        const last = p.index === plans.length - 1
        console.log(
            `  ${last ? '' : '! '}leg ${p.index + 1} ${nameOf(p.src)} -> ${nameOf(p.dst)} waits ~${fmtDuration(p.expectedS)} ` +
                `(${p.expectedDetail})` +
                (last
                    ? '; it is last, so nothing waits on it'
                    : '; every later leg waits too: move it to the end with --route')
        )
    }

    let deficits = 0
    const need = new Map<number, BigNumber>()
    for (const p of plans) {
        if (!p.batch || p.batch.tip20) continue
        need.set(p.src, (need.get(p.src) ?? constants.Zero).add(p.batch.value).add(p.gasCost))
    }
    console.log(`\nOwner ${OWNER}, native per source chain (fee + ${FEE_BPS / 100}% + gas estimate +30%):`)
    console.log('  Chain           needs                     has                       deficit')
    for (const [eid, n] of need) {
        const has = await chains.provider(eid).getBalance(OWNER)
        const deficit = n.gt(has) ? n.sub(has) : constants.Zero
        if (!deficit.isZero()) deficits++
        const sym = symbolOf(eid)
        console.log(
            `  ${nameOf(eid).padEnd(15)} ${`${fmtUnits(n)} ${sym}`.padEnd(25)} ${`${fmtUnits(has)} ${sym}`.padEnd(25)} ` +
                (deficit.isZero() ? 'ok' : `${fmtUnits(deficit)} ${sym}`)
        )
    }

    for (const p of plans.filter((x) => x.tempo)) {
        const t = p.tempo!
        const needTok = t.need.add(1_000_000) // + ~1 USD for the Tempo transactions' own gas, paid in the fee token
        const deficit = needTok.gt(t.balance) ? needTok.sub(t.balance) : constants.Zero
        if (!deficit.isZero()) deficits++
        console.log(
            `\n${nameOf(p.src)}: the owner pays fees in fee token ${t.gasToken}: needs ~${fmtUnits(needTok, 6)}, ` +
                `has ${fmtUnits(t.balance, 6)}` +
                (deficit.isZero() ? ' (ok)' : `, deficit ${fmtUnits(deficit, 6)}`) +
                `; allowance to the wallet ${fmtUnits(t.allowance, 6)} (--execute approves what it needs)`
        )
    }

    const hubNeed = plans.reduce((a, p) => a.add(p.hubCost), constants.Zero)
    const hubWant = withBps(hubNeed, HUB_PLAN_BPS)
    const hubHas = await chains.provider(FRAXTAL_EID).getBalance(FRAXTAL_HOP)
    const hubDeficit = hubWant.gt(hubHas) ? hubWant.sub(hubHas) : constants.Zero
    if (!hubDeficit.isZero()) deficits++
    console.log(
        `\nFraxtal hub hop ${FRAXTAL_HOP} pays every spoke -> spoke second leg from its own FRAX: ` +
            `needs ${fmtUnits(hubNeed, 18, 2)} (+15% = ${fmtUnits(hubWant, 18, 2)}), has ${fmtUnits(hubHas, 18, 2)}` +
            (hubDeficit.isZero()
                ? ' (ok)'
                : `; top up ${fmtUnits(hubDeficit, 18, 2)} FRAX (it accepts plain transfers)`)
    )

    const first = plans[0]
    if (first?.batch) {
        const holdings = await Promise.all(
            first.batch.legs.map(
                async (l) => [l, await chains.at(l.token, first.src).balanceOf(walletOn(first.src))] as const
            )
        )
        const lacking = holdings.filter(([l, bal]) => bal.lt(l.amountLD))
        if (lacking.length) deficits++
        console.log(
            `\nStarting wallet on ${nameOf(first.src)} holds: ` +
                holdings
                    .map(([l, bal]) => `${l.symbol} ${fmtUnits(bal, decimalsOf(l.amountLD, amountSD))}`)
                    .join(', ') +
                (lacking.length
                    ? `\n  ! not enough ${lacking.map(([l]) => l.symbol).join(', ')} for ${fmtUnits(amountSD, 6)} each`
                    : ' (ok)')
        )
    }
    const problems = plans.filter((p) => p.issues.length).length
    console.log(
        deficits ? `\n${deficits} funding gap(s) above; fund them, then rerun the dry run.` : '\nNo funding gaps.'
    )
    if (problems) console.log(`${problems} leg(s) have problems (PROBLEM above); fix them before --execute.`)
    return { deficits, problems }
}

// ─── Execute ────────────────────────────────────────────────────────────────────────────────

interface LegState {
    index: number
    src: number
    dst: number
    txHash?: string
    sentAt?: string
    before?: Record<string, string>
    expected?: Record<string, string>
    deliveredAt?: string
}
interface RelayState {
    route: number[]
    amountSD: string
    legs: LegState[]
}

async function lzStatus(txHash: string): Promise<string> {
    try {
        const res = await fetch(LZ_SCAN_API + txHash, { signal: AbortSignal.timeout(15_000) })
        if (!res.ok) return `LayerZero Scan HTTP ${res.status}`
        const body = (await res.json()) as {
            data?: { status?: { name?: string }; pathway?: { srcEid?: number; dstEid?: number } }[]
        }
        const msgs = body.data ?? []
        if (!msgs.length) return 'LayerZero Scan: not indexed yet'
        return (
            'LayerZero Scan: ' +
            msgs.map((m) => `${m.pathway?.srcEid}->${m.pathway?.dstEid} ${m.status?.name ?? '?'}`).join(', ')
        )
    } catch {
        return 'LayerZero Scan unreachable'
    }
}

async function execute(
    chains: Chains,
    root: string,
    route: number[],
    amountSD: BigNumber,
    opts: { maxLegs: number; reset: boolean }
) {
    const pk = process.env.PK_CONFIG_DEPLOYER || process.env.PRIVATE_KEY
    if (!pk) throw new Error('--execute needs PK_CONFIG_DEPLOYER (or PRIVATE_KEY): the wallets owner key')
    const signerAddress = new Wallet(pk).address
    if (!eq(signerAddress, OWNER)) throw new Error(`signer ${signerAddress} is not the wallets' owner ${OWNER}`)

    const file = path.join(root, STATE_FILE)
    const fresh: RelayState = {
        route,
        amountSD: amountSD.toString(),
        legs: route.slice(1).map((dst, i) => ({ index: i, src: route[i], dst })),
    }
    let state = fresh
    if (!opts.reset && fs.existsSync(file)) {
        state = JSON.parse(fs.readFileSync(file, 'utf8')) as RelayState
        if (state.route.join(',') !== route.join(',') || state.amountSD !== amountSD.toString()) {
            throw new Error(`${STATE_FILE} is for another route or amount; pass --reset to start over`)
        }
    }
    const save = () => fs.writeFileSync(file, JSON.stringify(state, null, 2) + '\n')

    let ran = 0
    for (const ls of state.legs) {
        if (ls.deliveredAt) continue
        if (ran >= opts.maxLegs) break
        ran++
        const { src, dst } = ls
        console.log(`\n── Leg ${ls.index + 1}/${state.legs.length}: ${nameOf(src)} -> ${nameOf(dst)}`)
        const p = await planLeg(chains, ls.index, src, dst, amountSD, false)
        if (p.issues.length || !p.batch) throw new Error(`leg ${ls.index + 1}: ${p.issues.join('; ')}`)

        if (!ls.txHash) {
            // The source wallet holds this leg's tokens, and the hub can pay its second legs.
            const short = []
            for (const l of p.batch.legs) {
                if ((await chains.at(l.token, src).balanceOf(walletOn(src))).lt(l.amountLD)) short.push(l.symbol)
            }
            if (short.length) throw new Error(`${nameOf(src)} wallet lacks ${short.join(', ')} for this leg; stopping`)
            if (!p.hubCost.isZero()) {
                const hubHas = await chains.provider(FRAXTAL_EID).getBalance(FRAXTAL_HOP)
                if (hubHas.lt(withBps(p.hubCost, HUB_EXECUTE_BPS))) {
                    throw new Error(
                        `Fraxtal hub hop holds ${fmtUnits(hubHas, 18, 2)} FRAX, this leg's second legs need ` +
                            `~${fmtUnits(p.hubCost, 18, 2)}; top it up first`
                    )
                }
            }
            const before = await walletBalances(chains, dst, p.dstTokens)
            ls.before = Object.fromEntries(Object.entries(before).map(([s, v]) => [s, v.toString()]))
            ls.expected = Object.fromEntries(Object.entries(p.expected).map(([s, v]) => [s, v.toString()]))
            const signer = new Wallet(pk, chains.provider(src))
            const receipt = await executeBatch(chains, signer, p.batch, (hash) => {
                ls.txHash = hash
                ls.sentAt = new Date().toISOString()
                save()
            })
            console.log(
                `   confirmed in block ${receipt.blockNumber}: https://layerzeroscan.com/tx/${receipt.transactionHash}`
            )
        } else {
            console.log(`   resuming: already sent ${ls.txHash}`)
        }

        // Wait until every asset landed; the timeout follows the leg's confirmation config.
        const sentMs = Date.parse(ls.sentAt ?? new Date().toISOString())
        if (p.expectedS > LONG_LEG_S) {
            save()
            console.log(
                `   this leg waits ~${fmtDuration(p.expectedS)} (${p.expectedDetail}); expected on ${nameOf(dst)} around ` +
                    `${new Date(sentMs + p.expectedS * 1000).toISOString()}. Rerun --execute after that (nothing is resent).`
            )
            return
        }
        const timeoutMs = Math.max(45 * 60_000, p.expectedS * 1500 + 10 * 60_000)
        const started = Date.now()
        let lastLog = 0
        for (;;) {
            const now = await walletBalances(chains, dst, p.dstTokens).catch(() => undefined)
            if (now) {
                const pending = Object.keys(p.dstTokens).filter((s) => now[s].sub(ls.before![s]).lt(ls.expected![s]))
                if (!pending.length) break
                if (Date.now() - lastLog > 60_000) {
                    lastLog = Date.now()
                    const mins = ((Date.now() - started) / 60_000).toFixed(1)
                    console.log(
                        `   ${mins} min: waiting for ${pending.join(', ')} on ${nameOf(dst)}; ${await lzStatus(ls.txHash!)}`
                    )
                }
            }
            if (Date.now() - started > timeoutMs) {
                save()
                console.log(
                    `   timed out after ${Math.round(timeoutMs / 60_000)} min (expected ~${fmtDuration(p.expectedS)}). ` +
                        `${await lzStatus(ls.txHash!)}\n   Check https://layerzeroscan.com/tx/${ls.txHash}. On a spoke -> ` +
                        `spoke leg, a stuck compose on Fraxtal usually means the hub hop ran out of FRAX. ` +
                        `Rerun --execute to keep waiting (nothing is resent).`
                )
                process.exitCode = 2
                return
            }
            await sleep(15_000)
        }
        ls.deliveredAt = new Date().toISOString()
        save()
        const mins = ((Date.parse(ls.deliveredAt) - sentMs) / 60_000).toFixed(1)
        console.log(
            `   delivered: all ${ACTIVE_ASSETS.length} assets arrived on ${nameOf(dst)} (${mins} min after sending)`
        )
    }
    const done = state.legs.filter((l) => l.deliveredAt).length
    console.log(`\n${done}/${state.legs.length} legs delivered. State: ${file}`)
}

// ─── Task ───────────────────────────────────────────────────────────────────────────────────

task('frax:wallet:smoketest', 'Relay all active assets around a ring of mesh chains through the dev wallets')
    .addOptionalParam(
        'route',
        'Comma-separated eids or names (default: the full ring, X Layer last)',
        undefined,
        types.string
    )
    .addOptionalParam('amount', 'Amount of each asset per leg, up to 6 decimals', '0.0001', types.string)
    .addOptionalParam('maxLegs', 'With --execute: run at most this many legs', undefined, types.int)
    .addFlag('execute', 'Send the legs (default is a dry run that needs no key)')
    .addFlag('reset', 'With --execute: forget the saved progress and start over')
    .setAction(
        async (
            args: { route?: string; amount: string; maxLegs?: number; execute: boolean; reset: boolean },
            hre: HardhatRuntimeEnvironment
        ) => {
            const root = hre.config.paths.root
            const chains = loadChains(root)
            const route = parseRoute(args.route ?? DEFAULT_ROUTE.join(','))
            const amountSD = toSharedDecimals(args.amount)
            if (amountSD.isZero()) throw new Error('--amount must be positive')
            for (const eid of route) chains.configOf(eid)

            console.log(`Planning ${route.length - 1} legs over ${new Set(route).size} chains...`)
            const legs = route.slice(1).map((dst, i) => ({ i, src: route[i], dst }))
            const plans = await mapLimit(legs, 4, (l) => planLeg(chains, l.i, l.src, l.dst, amountSD, true))
            const { problems } = await report(chains, route, amountSD, plans)

            if (!args.execute) {
                console.log('\nDry run: nothing sent. Add --execute to send (start with --max-legs 1 as a canary).')
                return
            }
            if (problems) throw new Error('refusing to execute while a leg has problems')
            await execute(chains, root, route, amountSD, { maxLegs: args.maxLegs ?? Infinity, reset: args.reset })
        }
    )
