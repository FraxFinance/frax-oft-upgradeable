import { task, types } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { ChainType, endpointIdToChainType, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'

import { EvmArgs, sendEvm } from '../evm/sendEvm'
import { SolanaArgs, sendSolana } from '../solana/sendSolana'
import { SolanaSquadArgs, sendSolanaSquad } from '../solana/sendSolanaSquad'

import { SendResult } from './types'
import { DebugLogger, KnownOutputs, KnownWarnings, getBlockExplorerLink } from './utils'

interface MasterArgs {
    srcEid: number
    dstEid: number
    amount: string
    to: string

    /** Minimum amount to receive in case of custom slippage or fees (human readable units, e.g. "1.5") */
    minAmount?: string

    /** Extra options for sending additional gas units to lzReceive, lzCompose, or receiver address */
    extraOptions?: string

    /** Arbitrary bytes message to deliver alongside the OFT */
    composeMsg?: string

    /** EVM: 20-byte hex; Solana: base58 PDA of the store */
    oftAddress?: string

    /** Solana only: override the OFT program ID (base58) */
    oftProgramId?: string

    tokenProgram?: string
    computeUnitPriceScaleFactor?: number

    /**
     * Solana Squads mode:
     * sender = Squads vault / token owner / fee payer.
     * If sender + msig are provided on a Solana source chain,
     * this task builds an unsigned Squads tx instead of broadcasting.
     */
    sender?: string

    /** Solana Squads multisig address, used for logging/sanity only */
    msig?: string

    /** Solana Squads mode: OFT shared decimals, usually 6 */
    sharedDecimals?: number
}

task('lz:oft:send', 'Sends OFT tokens cross‐chain from any supported chain')
    .addParam('srcEid', 'Source endpoint ID', undefined, types.int)
    .addParam('dstEid', 'Destination endpoint ID', undefined, types.int)
    .addParam('amount', 'Amount to send (human readable units, e.g. "1.5", or ALL for Solana Squads)', undefined, types.string)
    .addParam('to', 'Base58 recipient (Solana) or bytes20-encoded target (EVM)', undefined, types.string)
    .addOptionalParam(
        'minAmount',
        'Minimum amount to receive in case of custom slippage or fees (human readable units, e.g. "1.5")',
        undefined,
        types.string
    )
    .addOptionalParam(
        'extraOptions',
        'Extra options for sending additional gas units to lzReceive, lzCompose, or receiver address',
        undefined,
        types.string
    )
    .addOptionalParam(
        'composeMsg',
        'Arbitrary bytes message to deliver alongside the OFT',
        undefined,
        types.string
    )
    .addOptionalParam(
        'oftAddress',
        'Override the source local deployment OFT address (20-byte hex for EVM, base58 PDA for Solana)',
        undefined,
        types.string
    )
    .addOptionalParam('oftProgramId', 'Solana only: override the OFT program ID (base58)', undefined, types.string)
    .addOptionalParam('tokenProgram', 'Solana Token Program pubkey', undefined, types.string)
    .addOptionalParam('computeUnitPriceScaleFactor', 'Solana compute unit price scale factor', 4, types.float)

    // Squads-only optional args. Existing flows remain unchanged if these are omitted.
    .addOptionalParam(
        'sender',
        'Solana Squads mode: sender vault / token owner / fee payer',
        undefined,
        types.string
    )
    .addOptionalParam(
        'msig',
        'Solana Squads mode: Squads multisig address, used for logging/sanity only',
        undefined,
        types.string
    )
    .addOptionalParam(
        'sharedDecimals',
        'Solana Squads mode: OFT shared decimals, usually 6',
        6,
        types.int
    )
    .setAction(async (args: MasterArgs, hre: HardhatRuntimeEnvironment) => {
        const chainType = endpointIdToChainType(args.srcEid)

        const hasSender = !!args.sender
        const hasMsig = !!args.msig
        const isSolanaSquadsMode = chainType === ChainType.SOLANA && hasSender && hasMsig

        if ((hasSender || hasMsig) && chainType !== ChainType.SOLANA) {
            throw new Error('Solana Squads mode args --sender/--msig are only supported when srcEid is a Solana endpoint')
        }

        if (chainType === ChainType.SOLANA && (hasSender || hasMsig) && !isSolanaSquadsMode) {
            throw new Error('Solana Squads mode requires both --sender and --msig')
        }

        if (args.oftAddress || args.oftProgramId) {
            DebugLogger.printWarning(
                KnownWarnings.USING_OVERRIDE_OFT,
                `For network: ${endpointIdToNetwork(args.srcEid)}, OFT: ${
                    args.oftAddress + (args.oftProgramId ? `, OFT program: ${args.oftProgramId}` : '')
                }`
            )
        }

        // Solana Squads mode:
        // Build unsigned tx, print BASE58/BASE64, do NOT broadcast.
        if (isSolanaSquadsMode) {
            await sendSolanaSquad(args as SolanaSquadArgs)

            DebugLogger.printLayerZeroOutput(
                KnownOutputs.SENT_VIA_OFT,
                `Built unsigned Solana Squads OFT send transaction for ${args.amount} tokens from ${endpointIdToNetwork(
                    args.srcEid
                )} to ${endpointIdToNetwork(args.dstEid)}`
            )

            return
        }

        let result: SendResult

        // Original behavior unchanged.
        if (chainType === ChainType.EVM) {
            result = await sendEvm(args as EvmArgs, hre)
        } else if (chainType === ChainType.SOLANA) {
            result = await sendSolana(args as SolanaArgs)
        } else {
            throw new Error(`The chain type ${chainType} is not implemented in sendOFT for this example`)
        }

        DebugLogger.printLayerZeroOutput(
            KnownOutputs.SENT_VIA_OFT,
            `Successfully sent ${args.amount} tokens from ${endpointIdToNetwork(args.srcEid)} to ${endpointIdToNetwork(
                args.dstEid
            )}`
        )

        const explorerLink = await getBlockExplorerLink(args.srcEid, result.txHash)

        if (explorerLink) {
            DebugLogger.printLayerZeroOutput(
                KnownOutputs.TX_HASH,
                `Explorer link for source chain ${endpointIdToNetwork(args.srcEid)}: ${explorerLink}`
            )
        }

        DebugLogger.printLayerZeroOutput(
            KnownOutputs.EXPLORER_LINK,
            `LayerZero Scan link for tracking all cross-chain transaction details: ${result.scanLink}`
        )
    })