import bs58 from 'bs58'
import { BigNumber, ContractTransaction, Signer } from 'ethers'
import { parseUnits } from 'ethers/lib/utils'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { makeBytes32 } from '@layerzerolabs/devtools'
import { createGetHreByEid } from '@layerzerolabs/devtools-evm-hardhat'
import { createLogger } from '@layerzerolabs/io-devtools'
import { ChainType, endpointIdToChainType, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'

import layerzeroConfig from '../../layerzero.config'
import { SendResult } from '../common/types'
import { DebugLogger, KnownErrors } from '../common/utils'
import { getLayerZeroScanLink } from '../solana'
const logger = createLogger()

type NamedSigner = Signer & { address: string }

// Human-readable ABIs for exactly the calls this task makes. See the note at the
// getContractAt call site for why artifacts are not used.
const SEND_PARAM =
    '(uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd)'
const MESSAGING_FEE = '(uint256 nativeFee, uint256 lzTokenFee)'

const OFT_ABI = [
    'function token() view returns (address)',
    // True on adapter/lockbox OFTs, which escrow an underlying ERC-20 and
    // therefore need an allowance. False on mint/burn OFTs.
    'function approvalRequired() view returns (bool)',
    'function decimalConversionRate() view returns (uint256)',
    `function quoteSend(${SEND_PARAM} sendParam, bool payInLzToken) view returns (${MESSAGING_FEE} msgFee)`,
    `function send(${SEND_PARAM} sendParam, ${MESSAGING_FEE} fee, address refundAddress) payable returns ((bytes32 guid, uint64 nonce, ${MESSAGING_FEE} fee) msgReceipt, (uint256 amountSentLD, uint256 amountReceivedLD) oftReceipt)`,
]

const ERC20_ABI = [
    'function decimals() view returns (uint8)',
    'function balanceOf(address) view returns (uint256)',
    'function allowance(address owner, address spender) view returns (uint256)',
    'function approve(address spender, uint256 amount) returns (bool)',
]

export interface EvmArgs {
    srcEid: number
    dstEid: number
    amount: string
    to: string
    minAmount?: string
    extraOptions?: string
    composeMsg?: string
    oftAddress?: string
}

export async function sendEvm(
    { srcEid, dstEid, amount, to, minAmount, extraOptions, composeMsg, oftAddress }: EvmArgs,
    hre: HardhatRuntimeEnvironment
): Promise<SendResult> {
    if (endpointIdToChainType(srcEid) !== ChainType.EVM) {
        throw new Error(`non-EVM srcEid (${srcEid}) not supported here`)
    }

    const getHreByEid = createGetHreByEid(hre)
    let srcEidHre: HardhatRuntimeEnvironment
    try {
        srcEidHre = await getHreByEid(srcEid)
    } catch (error) {
        DebugLogger.printErrorAndFixSuggestion(
            KnownErrors.ERROR_GETTING_HRE,
            `For network: ${endpointIdToNetwork(srcEid)}, OFT: ${oftAddress}`
        )
        throw error
    }
    // `getNamedSigner` is a hardhat-deploy-ethers API, but this project loads
    // @nomiclabs/hardhat-ethers, so it was always undefined and every EVM send
    // died on "getNamedSigner is not a function" before reaching the OFT.
    // hardhat-deploy IS loaded, so resolve the named account through it and then
    // ask ethers for that specific signer. That stays correct even if
    // namedAccounts.deployer later gains per-network overrides, which a bare
    // getSigners()[0] would silently ignore.
    const { deployer } = await srcEidHre.getNamedAccounts()
    const signer = deployer
        ? ((await srcEidHre.ethers.getSigner(deployer)) as NamedSigner)
        : ((await srcEidHre.ethers.getSigners())[0] as NamedSigner)
    if (!signer) {
        throw new Error(
            `No signer available for ${endpointIdToNetwork(srcEid)} - set PRIVATE_KEY or MNEMONIC in the environment`
        )
    }

    // 1️⃣ resolve the OFT wrapper address
    let wrapperAddress: string
    if (oftAddress) {
        wrapperAddress = oftAddress
    } else {
        const maybeLayerZeroConfig = layerzeroConfig as unknown as
            | typeof layerzeroConfig
            | (() => Promise<typeof layerzeroConfig> | typeof layerzeroConfig)
        const { contracts } =
            typeof maybeLayerZeroConfig === 'function' ? await maybeLayerZeroConfig() : maybeLayerZeroConfig
        const wrapper = contracts.find((c: (typeof contracts)[number]) => c.contract.eid === srcEid)
        if (!wrapper) throw new Error(`No config for EID ${srcEid}`)
        wrapperAddress = wrapper.contract.contractName
            ? (await srcEidHre.deployments.get(wrapper.contract.contractName)).address
            : wrapper.contract.address!
    }

    // 2️⃣ attach to the OFT using an inline ABI rather than a hardhat artifact.
    // This repo compiles with foundry, `npx hardhat compile` fails outright on an
    // unresolvable @tempo/interfaces import, and there is no artifacts/ directory
    // — so readArtifact('IOFT') and getContractAt('ERC20', ...) both threw HH700
    // and no EVM send could ever run. Declaring the four functions we call keeps
    // the task independent of which compiler produced the build output.
    const oft = await srcEidHre.ethers.getContractAt(OFT_ABI, wrapperAddress, signer)

    // 3️⃣ fetch the underlying ERC-20
    const underlying = await oft.token()

    // 4️⃣ fetch decimals from the underlying token
    const erc20 = await srcEidHre.ethers.getContractAt(ERC20_ABI, underlying, signer)
    const decimals: number = await erc20.decimals()

    // 5️⃣ normalize the user-supplied amount
    const amountUnits: BigNumber = parseUnits(amount, decimals)

    // Decide how to encode `to` based on target chain:
    const dstChain = endpointIdToChainType(dstEid)
    let toBytes: string
    if (dstChain === ChainType.SOLANA) {
        // Base58→32-byte buffer
        toBytes = makeBytes32(bs58.decode(to))
    } else {
        // hex string → Uint8Array → zero-pad to 32 bytes
        toBytes = makeBytes32(to)
    }

    // 6️⃣ build sendParam and dispatch.
    //
    // minAmountLD must be floored to a multiple of decimalConversionRate. _debit
    // calls _removeDust on amountLD and then asserts amountReceivedLD >=
    // minAmountLD, so defaulting minAmountLD to the raw amount reverts with
    // SlippageExceeded for any amount finer than the shared decimals — e.g. with
    // rate 1e12 (sharedDecimals 6), `--amount 1.0000001` sends 1.0 and demands
    // 1.0000001. An explicit --min-amount is taken at face value: that is the
    // caller stating their own floor.
    let defaultMinAmount: BigNumber = amountUnits
    try {
        const rate: BigNumber = await oft.decimalConversionRate()
        if (rate.gt(1)) defaultMinAmount = amountUnits.div(rate).mul(rate)
    } catch {
        // Older OFTs may not expose it; leave the default unfloored rather than
        // failing the send outright.
    }

    const sendParam = {
        dstEid,
        to: toBytes,
        amountLD: amountUnits.toString(),
        minAmountLD: minAmount ? parseUnits(minAmount, decimals).toString() : defaultMinAmount.toString(),
        extraOptions: extraOptions ? extraOptions.toString() : '0x',
        composeMsg: composeMsg ? composeMsg.toString() : '0x',
        oftCmd: '0x',
    }

    // 7️⃣ Quote (MessagingFee = { nativeFee, lzTokenFee })
    logger.info('Quoting the native gas cost for the send transaction...')
    let msgFee: { nativeFee: BigNumber; lzTokenFee: BigNumber }
    try {
        msgFee = await oft.quoteSend(sendParam, false)
    } catch (error) {
        DebugLogger.printErrorAndFixSuggestion(
            KnownErrors.ERROR_QUOTING_NATIVE_GAS_COST,
            `For network: ${endpointIdToNetwork(srcEid)}, OFT: ${oftAddress}`
        )
        throw error
    }

    // 8️⃣ Approve only once the quote has succeeded. An adapter/lockbox OFT
    // escrows an underlying ERC-20 and its _debit spends the caller's allowance,
    // so without this the send reverts on allowance with no indication of why.
    // Doing it AFTER the quote matters: quoteSend does not depend on allowance,
    // so approving first would mine a real transaction and grant a standing
    // allowance before discovering that the send itself is unquotable (missing
    // peer, wrong --oft-address, endpoint misconfig). Mint/burn OFTs report
    // approvalRequired() == false and are skipped.
    if (await oft.approvalRequired()) {
        const owner = await signer.getAddress()
        const allowance: BigNumber = await erc20.allowance(owner, wrapperAddress)
        if (allowance.lt(amountUnits)) {
            logger.info(`Approving ${wrapperAddress} to spend the underlying token...`)
            await (await erc20.approve(wrapperAddress, amountUnits)).wait()
        }
    }

    logger.info('Sending the transaction...')
    let tx: ContractTransaction
    try {
        tx = await oft.send(sendParam, msgFee, signer.address, {
            value: msgFee.nativeFee,
        })
    } catch (error) {
        DebugLogger.printErrorAndFixSuggestion(
            KnownErrors.ERROR_SENDING_TRANSACTION,
            `For network: ${endpointIdToNetwork(srcEid)}, OFT: ${oftAddress}`
        )
        throw error
    }
    const receipt = await tx.wait()

    const txHash = receipt.transactionHash
    const scanLink = getLayerZeroScanLink(txHash, srcEid >= 40_000 && srcEid < 50_000)

    return { txHash, scanLink }
}
