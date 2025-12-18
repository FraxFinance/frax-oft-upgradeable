import { task, types } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { BigNumber, utils } from 'ethers'
import { parseUnits } from 'ethers/lib/utils'

import { ChainType, endpointIdToChainType, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'
import { createGetHreByEid } from '@layerzerolabs/devtools-evm-hardhat'

import { EvmArgs, sendEvm } from '../evm/sendEvm'
import { SolanaArgs, sendSolana } from '../solana/sendSolana'

import { SendResult } from '../common/types'
import { DebugLogger, KnownOutputs, KnownWarnings, getBlockExplorerLink } from '../common/utils'
import { addressToBytes32, Options } from '@layerzerolabs/lz-v2-utilities'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'
import { deriveConnection, getAddressLookupTable, getSolanaDeployment } from '.'
import { publicKey } from '@metaplex-foundation/umi'
import { PublicKey } from '@solana/web3.js'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { fetchMint } from '@metaplex-foundation/mpl-toolbox'
import { parseDecimalToUnits } from './utils'
import { createLogger } from '@layerzerolabs/io-devtools'
import { makeBytes32 } from '@layerzerolabs/devtools'

// struct HopMessage {
//     uint32 srcEid;
//     uint32 dstEid;
//     uint128 dstGas;
//     bytes32 sender;
//     bytes32 recipient;
//     bytes data;
// }

// lookuptable address : AxK5myLkGReGSzEywXUM7hnbQ4n1ccnbR7VL7MqPBxFy

const logger = createLogger()

const buildComposeMsg = (srcEid: number, dstEid: number, recipient: Uint8Array) =>
    utils.arrayify(
        utils.defaultAbiCoder.encode(
            [
                'tuple(uint32 srcEid, uint32 dstEid, uint128 dstGas, bytes32 sender, bytes32 recipient, bytes data)',
            ],
            [
                {
                    srcEid: srcEid,
                    dstEid: dstEid,
                    dstGas: 0,
                    sender: '0x0000000000000000000000000000000000000000000000000000000000000000',
                    recipient: recipient,
                    data: '0x'
                },
            ],
        ),
    )

interface MasterArgs {
    srcEid: number
    dstEid: number
    amount: string
    to: string
    /** Minimum amount to receive in case of custom slippage or fees (human readable units, e.g. "1.5") */
    minAmount?: string
    /** Extra options for sending additional gas units to lzReceive, lzCompose, or receiver address */
    extraOptions?: string
    /** EVM: 20-byte hex; Solana: base58 PDA of the store */
    oftAddress?: string
    /** Solana only: override the OFT program ID (base58) */
    oftProgramId?: string
    tokenProgram?: string
    computeUnitPriceScaleFactor?: number
    addressLookupTables?: string
}

task('lz:oft:send:fraxtalhop', 'Redeem nest tokens cross‐chain from Solana to any supported chain')
    .addParam('srcEid', 'Source endpoint ID', undefined, types.int)
    .addParam('dstEid', 'Destination endpoint ID', undefined, types.int)
    .addParam('amount', 'Amount to send (human readable units, e.g. "1.5")', undefined, types.string)
    .addParam('to', 'Recipient EVM address of destination chain', undefined, types.string)
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
        'oftAddress',
        'Override the source local deployment OFT address (20-byte hex for EVM, base58 PDA for Solana)',
        undefined,
        types.string
    )
    .addOptionalParam('oftProgramId', 'Solana only: override the OFT program ID (base58)', undefined, types.string)
    .addOptionalParam('tokenProgram', 'Solana Token Program pubkey', undefined, types.string)
    .addOptionalParam('computeUnitPriceScaleFactor', 'Solana compute unit price scale factor', 4, types.float)
    .addOptionalParam(
        'addressLookupTables',
        'Solana address lookup tables (comma separated base58 list)',
        undefined,
        types.string
    )
    .setAction(async (args: MasterArgs, hre: HardhatRuntimeEnvironment) => {
        const chainType = endpointIdToChainType(args.srcEid)
        let result: SendResult
        const { connection, umi, umiWalletSigner } = await deriveConnection(args.srcEid)
        if (args.oftAddress || args.oftProgramId) {
            DebugLogger.printWarning(
                KnownWarnings.USING_OVERRIDE_OFT,
                `For network: ${endpointIdToNetwork(args.srcEid)}, OFT: ${args.oftAddress + (args.oftProgramId ? `, OFT program: ${args.oftProgramId}` : '')}`
            )
        }

        // route to the correct function based on the chain type
        if (chainType === ChainType.EVM) {
            result = await sendEvm(args as EvmArgs, hre)
        } else if (chainType === ChainType.SOLANA) {
            const finalDstEid = args.dstEid // Save the final destination EID
            const finalRecipient = args.to   // Save the final recipient
            
            console.log("Final destination EID:", finalDstEid)
            console.log("Final recipient:", finalRecipient)
            
            // Build compose message for the hop
            const composeMsgBytes = buildComposeMsg(args.srcEid, finalDstEid, addressToBytes32(finalRecipient))
            const composeMsgHex = utils.hexlify(composeMsgBytes)
            console.log("Compose message:", composeMsgHex)
            
            // Get Solana OFT info
            const storePda = args.oftAddress ? publicKey(args.oftAddress) : publicKey(getSolanaDeployment(args.srcEid).oftStore)
            const oftStoreInfo = await oft.accounts.fetchOFTStore(umi, storePda)
            const mintPk = new PublicKey(oftStoreInfo.tokenMint)
            const decimals = (await fetchMint(umi, fromWeb3JsPublicKey(mintPk))).decimals
            const amountUnits = parseDecimalToUnits(args.amount, decimals)
            
            // ============================================================
            // Quote the destination hop fee (Fraxtal -> Final Destination)
            // ============================================================
            const FRAXTAL_EID = 30255
            const FRAXTAL_HOP_V2_ADDRESS = '0xe8Cd13de17CeC6FCd9dD5E0a1465Da240f951536'
            
            logger.info('Quoting destination hop fee (Fraxtal -> Final Destination)...')
            
            // Connect to Fraxtal to quote the second hop
            const getHreByEid = createGetHreByEid(hre)
            const fraxtalHre = await getHreByEid(FRAXTAL_EID)
            const evmOftAddress = (await fraxtalHre.deployments.get('OFT')).address 
            
            // Load the FraxtalHop contract (it should have quoteSend or we use the underlying OFT)
            const fraxtalOft = await fraxtalHre.ethers.getContractAt((await fraxtalHre.deployments.get('OFT')).abi, evmOftAddress)
            
            // Get decimals directly from the underlying token using minimal ABI
            const fraxtalUnderlying = await fraxtalOft.token()
            const decimalsAbi = ['function decimals() view returns (uint8)']
            const fraxtalErc20 = await fraxtalHre.ethers.getContractAt(decimalsAbi, fraxtalUnderlying)
            const fraxtalDecimals: number = await fraxtalErc20.decimals()
            const fraxtalAmountUnits = parseUnits(args.amount, fraxtalDecimals)
            
            // Build sendParam for the Fraxtal -> Final Destination quote
            const dstSendParam = {
                dstEid: finalDstEid,
                to: makeBytes32(finalRecipient),
                amountLD: fraxtalAmountUnits.toString(),
                minAmountLD: fraxtalAmountUnits.toString(),
                extraOptions: '0x',
                composeMsg: '0x',
                oftCmd: '0x',
            }
            
            // Quote the fee for the destination hop
            let destinationMsgFee: { nativeFee: BigNumber; lzTokenFee: BigNumber }
            try {
                destinationMsgFee = await fraxtalOft.quoteSend(dstSendParam, false)
                logger.info(`Destination hop fee: ${utils.formatEther(destinationMsgFee.nativeFee)} frxETH`)
            } catch (error) {
                logger.error('Failed to quote destination hop fee:', error)
                throw error
            }
            
            // ============================================================
            // Now prepare the Solana -> Fraxtal send with compose message
            // ============================================================
            
            // Override args for the first hop (Solana -> Fraxtal)
            args.dstEid = FRAXTAL_EID
            args.to = FRAXTAL_HOP_V2_ADDRESS
            
            // Add compose options with the destination native fee as nativeDrop
            // The nativeDrop is in wei (destination chain's native token)
            const nativeDropAmount = destinationMsgFee.nativeFee.toBigInt()
            args.extraOptions = Options.newOptions()
                .addExecutorComposeOption(0, 550_000, nativeDropAmount)
                .toHex()
            
            logger.info(`Compose options with nativeDrop: ${nativeDropAmount} wei`)
            
            result = await sendSolana({
                ...args,
                composeMsg: composeMsgHex,
                addressLookupTables: args.addressLookupTables ? args.addressLookupTables.split(',') : [],
            } as SolanaArgs)
        } else {
            throw new Error(`The chain type ${chainType} is not implemented in sendOFT for this example`)
        }

        DebugLogger.printLayerZeroOutput(
            KnownOutputs.SENT_VIA_OFT,
            `Successfully sent ${args.amount} tokens from ${endpointIdToNetwork(args.srcEid)} to ${endpointIdToNetwork(args.dstEid)}`
        )
        // print the explorer link for the srcEid from metadata
        const explorerLink = await getBlockExplorerLink(args.srcEid, result.txHash)
        // if explorer link is available, print the tx hash link
        if (explorerLink) {
            DebugLogger.printLayerZeroOutput(
                KnownOutputs.TX_HASH,
                `Explorer link for source chain ${endpointIdToNetwork(args.srcEid)}: ${explorerLink}`
            )
        }
        // print the LayerZero Scan link from metadata
        DebugLogger.printLayerZeroOutput(
            KnownOutputs.EXPLORER_LINK,
            `LayerZero Scan link for tracking all cross-chain transaction details: ${result.scanLink}`
        )
    })
