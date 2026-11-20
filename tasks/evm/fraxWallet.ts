import fs from 'fs'
import path from 'path'

import { BigNumber, Contract, Signer, constants, providers, utils } from 'ethers'

/**
 * Shared logic for the dev FraxOFTWallet tasks (frax:wallet:send, frax:wallet:smoketest).
 *
 * Nothing is per chain: RPCs come from scripts/L0Config.json (or WALLET_UPGRADE_RPC_<chainid>), and every chain's
 * OFT for an asset is the Fraxtal lockbox's `peers(eid)`, which must peer back. A batch is `direct` (IOFT.send) when
 * the source OFTs peer straight to the destination ones (always true to/from Fraxtal), otherwise `hop` (HopV2,
 * relayed through Fraxtal). A source that answers `quoteUserTokenFee` pays fees in TIP20 (Tempo). Each combination
 * maps to one wallet function.
 */

export const FRAXTAL_EID = 30255
/// @dev Fraxtal lockboxes from scripts/L0Constants.sol (fraxtal*Lockbox).
export const HUB_LOCKBOX: Record<string, string> = {
    WFRAX: '0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A',
    sfrxUSD: '0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361',
    sfrxETH: '0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168',
    frxUSD: '0x96A394058E2b84A89bac9667B19661Ed003cF5D4',
    frxETH: '0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604',
    FPI: '0x75c38D46001b0F8108c4136216bd2694982C20FC',
}
/// @dev The assets still active in the mesh (L0Constants.activeTokens); FPI is retired.
export const ACTIVE_ASSETS = ['WFRAX', 'sfrxUSD', 'sfrxETH', 'frxUSD', 'frxETH']
/// @dev HopV2 proxies (hop-v2 README, section 8): FraxtalHopV2 on the hub, RemoteHopV2 everywhere else.
export const FRAXTAL_HOP = '0x00000000e18aFc20Afe54d4B2C8688bB60c06B36'
export const REMOTE_HOP = '0x0000006D38568b00B457580b734e0076C62de659'
/// @dev Dev wallets (owner: the hot dev EOA), as in scripts/ops/UpgradeWalletBridges. List only chains
///      where the wallet is not at the default address.
export const DEFAULT_WALLET = '0x741F0d8Bde14140f62107FC60A0EE122B37D4630'
export const WALLET_BY_EID: Record<number, string> = {
    30183: '0xD555D90A6b23B285575cd6192D972e35F70b5B89', // Linea
    30165: '0x0065435a2FcC4D4D5CD2c284C5daA9588E6fe03d', // zkSync
    30390: '0x84E6F8460e5c7AeebcBC7aA7D7c037FB75D83B4d', // Monad
    30380: '0xE75177ED629a4770e2DA00e1395c28A5f9B745d4', // Somnia
}
export const TIP_FEE_MANAGER = '0xfeEC000000000000000000000000000000000000'
export const PATH_USD = '0x20C0000000000000000000000000000000000000'
const TIP20_FEE_BUFFER_BPS = 100
export const GAS_BUFFER_BPS = 2_000

const SP = 'tuple(uint32,bytes32,uint256,uint256,bytes,bytes,bytes)'
const HOP_BATCH = 'address,address[],uint32[],bytes32[],uint256[],uint128[],bytes[]'
export const ABI = [
    'function token() view returns (address)',
    'function peers(uint32) view returns (bytes32)',
    'function endpoint() view returns (address)',
    'function decimalConversionRate() view returns (uint256)',
    `function quoteSend(${SP}, bool) view returns (tuple(uint256 nativeFee, uint256 lzTokenFee))`,
    'function quoteUserTokenFee(address, uint256) view returns (uint256)',
    'function quote(address, uint32, bytes32, uint256, uint128, bytes) view returns (uint256)',
    'function approvedOft(address) view returns (bool)',
    'function remoteHop(uint32) view returns (bytes32)',
    'function paused() view returns (bool)',
    'function getSendLibrary(address, uint32) view returns (address)',
    'function getConfig(address, address, uint32, uint32) view returns (bytes)',
    'function symbol() view returns (string)',
    'function decimals() view returns (uint8)',
    'function balanceOf(address) view returns (uint256)',
    'function allowance(address, address) view returns (uint256)',
    'function approve(address, uint256) returns (bool)',
    'function owner() view returns (address)',
    'function approveToken(address, address, uint256)',
    `function batchBridgeWithEthFeeFromWallet(${SP}[], address[], address[]) payable`,
    `function batchBridgeWithTIP20FeeFromWallet(${SP}[], address[], address[])`,
    `function batchHopV2WithEthFeeFromWallet(${HOP_BATCH}) payable`,
    `function batchHopV2WithTIP20FeeFromWallet(${HOP_BATCH})`,
    'function userTokens(address) view returns (address)',
    'function setUserToken(address)',
]

export const eq = (a: string, b: string) => a.toLowerCase() === b.toLowerCase()
export const toAddress = (b32: string) =>
    b32 === constants.HashZero ? undefined : utils.getAddress(utils.hexDataSlice(b32, 12))
export const walletOn = (eid: number) => WALLET_BY_EID[eid] ?? DEFAULT_WALLET
export const withBps = (v: BigNumber, bps: number) => v.mul(10_000 + bps).div(10_000)

// ─── Chains ─────────────────────────────────────────────────────────────────────────────────

export interface ChainConfig {
    eid: number
    chainid: number
    RPC: string
}

export interface Chains {
    configs: ChainConfig[]
    configOf(eid: number): ChainConfig
    rpcUrl(eid: number): string
    provider(eid: number): providers.JsonRpcProvider
    at(address: string, eid: number): Contract
    codeAt(address: string, eid: number): Promise<string>
}

/** Retries timeouts and dropped connections (public RPCs under load), never reverts or broadcasts. */
class RetryingProvider extends providers.StaticJsonRpcProvider {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    async send(method: string, params: unknown[]): Promise<any> {
        for (let attempt = 0; ; attempt++) {
            try {
                return await super.send(method, params)
            } catch (e) {
                const err = e as { code?: string; body?: string; message?: string }
                const transient =
                    ['TIMEOUT', 'SERVER_ERROR', 'NETWORK_ERROR'].includes(err.code ?? '') &&
                    !/revert/i.test(`${err.body ?? ''} ${err.message ?? ''}`)
                if (!transient || attempt >= 2 || method === 'eth_sendRawTransaction') throw e
                await new Promise((resolve) => setTimeout(resolve, 2_000 * (attempt + 1)))
            }
        }
    }
}

/** Providers for every L0Config `Proxy` chain; WALLET_UPGRADE_RPC_<chainid> overrides a flaky RPC. */
export function loadChains(root: string): Chains {
    const configs = JSON.parse(fs.readFileSync(path.join(root, 'scripts/L0Config.json'), 'utf8')).Proxy as ChainConfig[]
    const cache: Record<number, providers.JsonRpcProvider> = {}
    const configOf = (eid: number) => {
        const c = configs.find((x) => x.eid === eid)
        if (!c) throw new Error(`eid ${eid} is not in scripts/L0Config.json Proxy`)
        return c
    }
    const rpcUrl = (eid: number) => {
        const c = configOf(eid)
        return process.env[`WALLET_UPGRADE_RPC_${c.chainid}`] || c.RPC
    }
    const provider = (eid: number) => (cache[eid] ??= new RetryingProvider(rpcUrl(eid), configOf(eid).chainid))
    const at = (address: string, eid: number) => new Contract(address, ABI, provider(eid))
    const codeAt = (address: string, eid: number) =>
        provider(eid)
            .getCode(address)
            .catch((e) => {
                throw new Error(
                    `RPC for eid ${eid} (${rpcUrl(eid)}) failed: ${e.code ?? e.message} (retired chain or RPC down? ` +
                        `set WALLET_UPGRADE_RPC_${configOf(eid).chainid})`
                )
            })
    return { configs, configOf, rpcUrl, provider, at, codeAt }
}

// ─── Assets ─────────────────────────────────────────────────────────────────────────────────

export interface Asset {
    symbol: string
    srcOft: string
    dstOft: string
    token: string
    decimals: number
    balance: BigNumber
    /** The source OFT peers straight to the destination OFT. */
    direct: boolean
}

/** One asset on both chains through the hub, or the reason it is not on one of them. */
export async function resolveAsset(
    chains: Chains,
    symbol: string,
    srcEid: number,
    dstEid: number,
    walletAddr: string
): Promise<Asset | string> {
    const { at } = chains
    const lockbox = at(HUB_LOCKBOX[symbol], FRAXTAL_EID)
    const oftOn = async (eid: number) => {
        if (eid === FRAXTAL_EID) return lockbox.address
        const oft = toAddress(await lockbox.peers(eid))
        if (oft && !eq(toAddress(await at(oft, eid).peers(FRAXTAL_EID)) ?? '', lockbox.address)) {
            throw new Error(`${symbol}: OFT ${oft} on eid ${eid} does not peer back to the Fraxtal lockbox`)
        }
        return oft
    }
    const [srcOft, dstOft] = await Promise.all([oftOn(srcEid), oftOn(dstEid)])
    if (!srcOft || !dstOft) return `${symbol}: not on eid ${srcOft ? dstEid : srcEid} (no Fraxtal lockbox peer)`
    const src = at(srcOft, srcEid)
    const token: string = await src.token()
    const erc20 = at(token, srcEid)
    const [srcSymbol, dstSymbol, decimals, balance, peer] = await Promise.all([
        erc20.symbol(),
        at(await at(dstOft, dstEid).token(), dstEid).symbol(),
        erc20.decimals(),
        erc20.balanceOf(walletAddr),
        src.peers(dstEid),
    ])
    if (!eq(srcSymbol, symbol) || !eq(dstSymbol, symbol)) {
        throw new Error(`${symbol}: token symbols on chain are ${srcSymbol} / ${dstSymbol}`)
    }
    return { symbol, srcOft, dstOft, token, decimals, balance, direct: eq(toAddress(peer) ?? '', dstOft) }
}

// ─── Batches ────────────────────────────────────────────────────────────────────────────────

export type Route = 'auto' | 'direct' | 'hop'

export interface Leg {
    symbol: string
    srcOft: string
    token: string
    amountLD: BigNumber
    direct: boolean
    approve?: boolean
    fee: BigNumber
}

export interface Batch {
    srcEid: number
    dstEid: number
    walletAddr: string
    to: string
    legs: Leg[]
    route: 'direct' | 'hop'
    hop: string
    tip20: boolean
    gasToken: string
    /** Native wei, or TIP20 fee-token units (with the TIP20 buffer). */
    totalFee: BigNumber
    owner: string
    fn: string
    callArgs: unknown[]
    /** msg.value sent with the batch (native-fee batches). */
    value: BigNumber
}

export const legFromAsset = (a: Asset, amountLD: BigNumber): Leg => ({
    symbol: a.symbol,
    srcOft: a.srcOft,
    token: a.token,
    amountLD,
    direct: a.direct,
    fee: constants.Zero,
})

/**
 * Choose the route, check it (hop paused/approvedOft/remoteHop, or adapter allowances), quote every leg (hop quotes
 * from the wallet's address: HopV2 encodes msg.sender), and build the wallet call. Throws on a wiring problem.
 */
export async function planBatch(
    chains: Chains,
    p: {
        srcEid: number
        dstEid: number
        walletAddr: string
        to: string
        legs: Leg[]
        route: Route
        gasToken?: string
        valueBps?: number
    }
): Promise<Batch> {
    const { at, codeAt } = chains
    const { srcEid, dstEid, walletAddr, to, legs } = p
    const allDirect = legs.every((l) => l.direct)
    const route = p.route === 'auto' ? (allDirect ? 'direct' : 'hop') : p.route
    if (route === 'direct' && !allDirect) {
        const missing = legs.filter((l) => !l.direct).map((l) => l.symbol)
        throw new Error(`no direct peer to eid ${dstEid} for ${missing.join(', ')}; use --route hop`)
    }
    const hop = at(srcEid === FRAXTAL_EID ? FRAXTAL_HOP : REMOTE_HOP, srcEid)
    if (route === 'hop') {
        if ((await codeAt(hop.address, srcEid)) === '0x') throw new Error(`no HopV2 on eid ${srcEid}`)
        if (await hop.paused()) throw new Error(`HopV2 on eid ${srcEid} is paused`)
        if (dstEid !== FRAXTAL_EID && !toAddress(await at(FRAXTAL_HOP, FRAXTAL_EID).remoteHop(dstEid))) {
            throw new Error(`FraxtalHopV2 has no remoteHop for eid ${dstEid}`)
        }
        for (const l of legs) {
            if (!(await hop.approvedOft(l.srcOft))) throw new Error(`${l.symbol}: HopV2 does not approve ${l.srcOft}`)
        }
    } else {
        // Adapters and lockboxes pull the token from the wallet (the hop path approves inside the wallet).
        for (const l of legs.filter((x) => !eq(x.token, x.srcOft))) {
            l.approve = (await at(l.token, srcEid).allowance(walletAddr, l.srcOft)).lt(l.amountLD)
        }
    }

    const sendParam = (l: Leg) => [dstEid, to, l.amountLD, 0, '0x', '0x', '0x']
    for (const l of legs) {
        l.fee =
            route === 'direct'
                ? (await at(l.srcOft, srcEid).quoteSend(sendParam(l), false)).nativeFee
                : await hop.quote(l.srcOft, dstEid, to, l.amountLD, 0, '0x', { from: walletAddr })
    }
    const feeQuoter = (l: Leg) => at(route === 'direct' ? l.srcOft : hop.address, srcEid)
    const tip20 = await feeQuoter(legs[0])
        .quoteUserTokenFee(PATH_USD, 1)
        .then(
            () => true,
            () => false
        )
    const owner: string = await at(walletAddr, srcEid).owner()
    let gasToken = ''
    let totalFee = BigNumber.from(0)
    if (tip20) {
        const current: string = await at(TIP_FEE_MANAGER, srcEid).userTokens(owner)
        gasToken = utils.getAddress(p.gasToken ?? (current === constants.AddressZero ? PATH_USD : current))
        for (const l of legs) totalFee = totalFee.add(await feeQuoter(l).quoteUserTokenFee(gasToken, l.fee))
        totalFee = withBps(totalFee, TIP20_FEE_BUFFER_BPS).add(1)
    } else {
        totalFee = legs.reduce((sum, l) => sum.add(l.fee), BigNumber.from(0))
    }

    const fn = `batch${route === 'direct' ? 'Bridge' : 'HopV2'}With${tip20 ? 'TIP20' : 'Eth'}FeeFromWallet`
    const callArgs =
        route === 'direct'
            ? [legs.map(sendParam), legs.map((l) => l.srcOft), legs.map(() => walletAddr)]
            : [
                  hop.address,
                  legs.map((l) => l.srcOft),
                  legs.map(() => dstEid),
                  legs.map(() => to),
                  legs.map((l) => l.amountLD),
                  legs.map(() => 0),
                  legs.map(() => '0x'),
              ]
    const value = tip20 ? constants.Zero : withBps(totalFee, p.valueBps ?? 0)
    return { ...p, legs, route, hop: hop.address, tip20, gasToken, totalFee, owner, fn, callArgs, value }
}

// ─── Simulation ─────────────────────────────────────────────────────────────────────────────

export type StateOverride = Record<string, { balance?: string; stateDiff?: Record<string, string> }>

/** Give the owner enough native balance to pay `value` plus gas. */
export const nativeOverride = (owner: string, value: BigNumber): StateOverride => ({
    [owner]: { balance: utils.hexValue(value.mul(2).add(utils.parseEther('1000'))) },
})

/**
 * TIP-20 precompile storage (verified layout): balances mapping at slot 9, allowances at slot 10, keyed
 * keccak(spender . keccak(owner . 10)). A stateDiff only, never a full state override (that would wipe the token).
 */
export function tip20Override(token: string, owner: string, spender: string, amount: BigNumber): StateOverride {
    const word = utils.hexZeroPad(amount.toHexString(), 32)
    const slot = (key: string, keyType: string, base: string | number) =>
        utils.keccak256(
            utils.defaultAbiCoder.encode([keyType, typeof base === 'number' ? 'uint256' : 'bytes32'], [key, base])
        )
    const balanceSlot = slot(owner, 'address', 9)
    const allowanceSlot = slot(spender, 'address', slot(owner, 'address', 10))
    return { [token]: { stateDiff: { [balanceSlot]: word, [allowanceSlot]: word } } }
}

/** eth_call the batch as the owner under `override` (throws on revert); returns eth_estimateGas, if the RPC can. */
export async function simulateBatch(chains: Chains, b: Batch, override: StateOverride): Promise<BigNumber | undefined> {
    const rpc = chains.provider(b.srcEid)
    const data = chains.at(b.walletAddr, b.srcEid).interface.encodeFunctionData(b.fn, b.callArgs)
    const call = { from: b.owner, to: b.walletAddr, data, value: utils.hexValue(b.value) }
    await rpc.send('eth_call', [call, 'latest', override]).catch((e) => {
        throw new Error(`simulated ${b.fn} reverted: ${e.error?.message ?? e.body ?? e.message}`)
    })
    const gas = await rpc.send('eth_estimateGas', [call, 'latest', override]).catch(() => undefined)
    return gas ? BigNumber.from(gas) : undefined
}

// ─── Execution ──────────────────────────────────────────────────────────────────────────────

/**
 * Approvals, TIP20 fee setup, a final static call and gas/balance check, then the batch. Returns its receipt.
 * `onSent` runs with the batch tx hash before its receipt is awaited (to record it and never resend).
 */
export async function executeBatch(
    chains: Chains,
    signer: Signer,
    b: Batch,
    onSent?: (hash: string) => Promise<void> | void
): Promise<providers.TransactionReceipt> {
    const { at } = chains
    const rpc = chains.provider(b.srcEid)
    const send = async (label: string, tx: Promise<providers.TransactionResponse>, onHash?: typeof onSent) => {
        const sent = await tx
        console.log(`  ${label}: ${sent.hash}`)
        await onHash?.(sent.hash)
        const receipt = await sent.wait()
        if (receipt.status !== 1) throw new Error(`${label} reverted`)
        return receipt
    }
    const w = at(b.walletAddr, b.srcEid).connect(signer)
    for (const l of b.legs.filter((x) => x.approve)) {
        await send(`approve ${l.symbol}`, w.approveToken(l.token, l.srcOft, l.amountLD))
    }
    const overrides = b.tip20 ? {} : { value: b.value }
    if (b.tip20) {
        const feeManager = at(TIP_FEE_MANAGER, b.srcEid).connect(signer)
        if (!eq(await feeManager.userTokens(b.owner), b.gasToken)) {
            await send('setUserToken', feeManager.setUserToken(b.gasToken))
        }
        await send('approve fee token', at(b.gasToken, b.srcEid).connect(signer).approve(b.walletAddr, b.totalFee))
    }
    await w.callStatic[b.fn](...b.callArgs, overrides)
    if (!b.tip20) {
        const gasPrice = await rpc.getGasPrice()
        const gasCost = withBps((await w.estimateGas[b.fn](...b.callArgs, overrides)).mul(gasPrice), GAS_BUFFER_BPS)
        const balance = await rpc.getBalance(b.owner)
        const cost = b.value.add(gasCost)
        if (balance.lt(cost)) {
            throw new Error(
                `owner holds ${utils.formatEther(balance)}, the batch needs ${utils.formatEther(cost)} with gas`
            )
        }
    }
    return send(b.fn, w[b.fn](...b.callArgs, overrides), onSent)
}
