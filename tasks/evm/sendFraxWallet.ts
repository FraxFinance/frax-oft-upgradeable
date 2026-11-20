import { BigNumber, Wallet, utils } from 'ethers'
import { task, types } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import {
    GAS_BUFFER_BPS,
    HUB_LOCKBOX,
    Leg,
    Route,
    eq,
    executeBatch,
    legFromAsset,
    loadChains,
    nativeOverride,
    planBatch,
    resolveAsset,
    simulateBatch,
    walletOn,
    withBps,
} from './fraxWallet'

/**
 * Bridge Frax assets between any two EVM chains of the mesh through the dev FraxOFTWallet, in one batch.
 * See ./fraxWallet.ts for how chains, assets and routes are resolved.
 */

interface Args {
    srcEid: number
    dstEid: number
    tokens?: string
    amount: string
    to?: string
    wallet?: string
    route: Route
    gasToken?: string
    dryRun: boolean
}

/** `frxUSD=10,WFRAX` -> [['frxUSD','10'], ['WFRAX', defaultAmount]]; omitted -> every asset. */
function parseTokens(spec: string | undefined, defaultAmount: string): [string, string, boolean][] {
    if (!spec) return Object.keys(HUB_LOCKBOX).map((s) => [s, defaultAmount, false])
    return spec.split(',').map((item) => {
        const [name, amount] = item.split('=').map((s) => s.trim())
        const symbol = Object.keys(HUB_LOCKBOX).find((s) => eq(s, name))
        if (!symbol) throw new Error(`unknown token "${name}" (known: ${Object.keys(HUB_LOCKBOX).join(', ')})`)
        return [symbol, amount || defaultAmount, true]
    })
}

task('frax:wallet:send', 'Batch-bridge Frax assets between two mesh chains through the dev FraxOFTWallet')
    .addParam('srcEid', 'Source eid', undefined, types.int)
    .addParam('dstEid', 'Destination eid', undefined, types.int)
    .addOptionalParam(
        'tokens',
        'Assets and amounts, e.g. frxUSD=10,sfrxUSD=2,WFRAX (default: all)',
        undefined,
        types.string
    )
    .addOptionalParam('amount', 'Amount for assets listed without one', '0.0001', types.string)
    .addOptionalParam('to', 'Recipient (default: the dev wallet on the destination)', undefined, types.string)
    .addOptionalParam('wallet', 'Sending wallet (default: the dev wallet on the source)', undefined, types.string)
    .addOptionalParam('route', 'auto | direct | hop', 'auto', types.string)
    .addOptionalParam('gasToken', 'TIP20 fee token (default: your current one, else pathUSD)', undefined, types.string)
    .addFlag('dryRun', 'Check wiring, balances and fees and simulate; send nothing. Needs no key')
    .setAction(async (args: Args, hre: HardhatRuntimeEnvironment) => {
        const { srcEid, dstEid } = args
        if (srcEid === dstEid) throw new Error('source and destination are the same chain')
        if (!['auto', 'direct', 'hop'].includes(args.route)) throw new Error('--route must be auto, direct or hop')

        const chains = loadChains(hre.config.paths.root)
        const { at, codeAt, provider } = chains
        const walletAddr = utils.getAddress(args.wallet ?? walletOn(srcEid))
        const to = utils.hexZeroPad(utils.getAddress(args.to ?? walletOn(dstEid)), 32)
        console.log(`\neid ${srcEid} -> ${dstEid}: wallet ${walletAddr} -> ${utils.hexDataSlice(to, 12)}`)
        const hint = 'add it to WALLET_BY_EID in tasks/evm/fraxWallet.ts'
        if ((await codeAt(walletAddr, srcEid)) === '0x') {
            throw new Error(`no wallet contract at ${walletAddr} on eid ${srcEid}: pass --wallet or ${hint}`)
        }
        if (!args.to && (await codeAt(utils.hexDataSlice(to, 12), dstEid)) === '0x') {
            throw new Error(`no dev wallet at ${utils.hexDataSlice(to, 12)} on eid ${dstEid}: pass --to or ${hint}`)
        }

        // ── Resolve each asset on both chains through the hub ────────────────────────────
        const problems: string[] = []
        const legs: Leg[] = []
        let tokensShort = false
        for (const [symbol, amount, explicit] of parseTokens(args.tokens, args.amount)) {
            const asset = await resolveAsset(chains, symbol, srcEid, dstEid, walletAddr)
            if (typeof asset === 'string') {
                if (explicit) throw new Error(asset)
                console.log(`  skip ${asset}`)
                continue
            }
            const amountLD = utils.parseUnits(amount, asset.decimals)
            if (asset.balance.lt(amountLD)) {
                tokensShort = true
                problems.push(
                    `${symbol}: wallet holds ${utils.formatUnits(asset.balance, asset.decimals)}, needs ${amount}`
                )
            }
            legs.push(legFromAsset(asset, amountLD))
        }
        if (legs.length === 0)
            throw new Error('nothing to send: no requested asset is wired to Fraxtal on both chains (retired chain?)')

        // ── Route, fees and the wallet call ───────────────────────────────────────────────
        const batch = await planBatch(chains, {
            srcEid,
            dstEid,
            walletAddr,
            to,
            legs,
            route: args.route,
            gasToken: args.gasToken,
        })
        const { tip20, gasToken, totalFee, owner } = batch
        for (const l of legs) {
            console.log(
                `  ${l.symbol.padEnd(8)} ${l.srcOft}  ${l.amountLD}  fee ${l.fee}${l.approve ? '  (approves first)' : ''}`
            )
        }

        // ── Simulate, estimate gas, check the owner can pay ───────────────────────────────
        // As the owner with its balance topped up through a state override, so a funding gap does not hide
        // other reverts. Batches that depend on txs a real run sends first (approvals, TIP20 fee setup) or
        // on wallet tokens it lacks cannot be simulated; a real run estimates them right before the batch.
        const rpc = provider(srcEid)
        const gasPrice = await rpc.getGasPrice()
        let gasCost: BigNumber | undefined
        if (tip20 || tokensShort || legs.some((l) => l.approve)) {
            console.log('simulation skipped: needs wallet tokens, approvals, or the TIP20 fee setup first')
        } else {
            const gas = await simulateBatch(chains, batch, nativeOverride(owner, totalFee))
            console.log(`simulated ${batch.fn}: ok`)
            if (gas) gasCost = withBps(gas.mul(gasPrice), GAS_BUFFER_BPS)
        }
        const funds: BigNumber = tip20 ? await at(gasToken, srcEid).balanceOf(owner) : await rpc.getBalance(owner)
        const fmt = (v: BigNumber) => (tip20 ? `${v} of ${gasToken}` : utils.formatEther(v))
        const gasNote = tip20
            ? 'tx gas (paid in the fee token) not estimated'
            : gasCost
              ? `gas ~${fmt(gasCost)}`
              : 'gas not estimated'
        console.log(`route ${batch.route}, fees ${fmt(totalFee)}, ${gasNote}; owner ${owner} holds ${fmt(funds)}`)
        if (funds.lt(totalFee.add(gasCost ?? 0))) {
            problems.push(`owner holds ${fmt(funds)}, needs fees ${fmt(totalFee)} + ${gasNote}`)
        }

        if (args.dryRun) {
            for (const p of problems) console.log(`  WARNING: ${p}`)
            console.log(`dry run: nothing sent${problems.length ? `, ${problems.length} problem(s) to fix first` : ''}`)
            return
        }
        if (problems.length) throw new Error(problems.join('\n'))

        // ── Send ──────────────────────────────────────────────────────────────────────────
        const pk = process.env.PK_CONFIG_DEPLOYER || process.env.PRIVATE_KEY
        if (!pk) throw new Error('set PK_CONFIG_DEPLOYER (or PRIVATE_KEY) to the wallet owner key')
        const signer = new Wallet(pk, rpc)
        if (!eq(signer.address, owner)) throw new Error(`signer ${signer.address} is not the wallet owner ${owner}`)
        const receipt = await executeBatch(chains, signer, batch)
        console.log(`\nhttps://layerzeroscan.com/tx/${receipt.transactionHash}`)
    })
