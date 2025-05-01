import {
    UpdateV1InstructionAccounts,
    UpdateV1InstructionArgs,
    fetchMetadataFromSeeds,
    updateV1,
} from '@metaplex-foundation/mpl-token-metadata'
import { publicKey as pubKeyFn, transactionBuilder } from '@metaplex-foundation/umi'
import bs58 from 'bs58'
import { task } from 'hardhat/config'
import { PublicKey } from '@solana/web3.js'
import {
    OmniPoint,
    OmniSigner,
    OmniTransactionReceipt,
    OmniTransactionResponse,
    firstFactory,
    formatEid,
} from '@layerzerolabs/devtools'
import { getSolanaDeployment, useWeb3Js } from '../solana'
import { findSolanaEndpointIdInGraph } from '../solana/utils'
import assert from 'assert'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import { deriveConnection, getExplorerTxLink } from './index'
import { type LogLevel, createLogger } from '@layerzerolabs/io-devtools'
import { setTransactionSizeBuffer } from '@layerzerolabs/devtools-solana'
import { type IOApp, type OAppConfigurator, type OAppOmniGraph, configureOwnable } from '@layerzerolabs/ua-devtools'
import {
    createConnectionFactory,
    createRpcUrlFactory,
    OmniSignerSolana,
    OmniSignerSolanaSquads,
} from '@layerzerolabs/devtools-solana'
import { createOAppFactory } from '@layerzerolabs/ua-devtools-evm'
import { createConnectedContractFactory } from '@layerzerolabs/devtools-evm-hardhat'
import { createOFTFactory } from '@layerzerolabs/ua-devtools-solana'
import { Keypair } from '@solana/web3.js'
import { ChainType, endpointIdToChainType } from '@layerzerolabs/lz-definitions'
import { CLIArgumentType } from 'hardhat/types'

export const createSdkFactory = (
    userAccount: PublicKey,
    programId: PublicKey,
    connectionFactory = createSolanaConnectionFactory()
) => {
    // To create a EVM/Solana SDK factory we need to merge the EVM and the Solana factories into one
    //
    // We do this by using the firstFactory helper function that is provided by the devtools package.
    // This function will try to execute the factories one by one and return the first one that succeeds.
    const evmSdkfactory = createOAppFactory(createConnectedContractFactory())
    const solanaSdkFactory = createOFTFactory(
        // The first parameter to createOFTFactory is a user account factory
        //
        // This is a function that receives an OmniPoint ({ eid, address } object)
        // and returns a user account to be used with that SDK.
        //
        // For our purposes this will always be the user account coming from the secret key passed in
        () => userAccount,
        // The second parameter is a program ID factory
        //
        // This is a function that receives an OmniPoint ({ eid, address } object)
        // and returns a program ID to be used with that SDK.
        //
        // Since we only have one OFT deployed, this will always be the program ID passed as a CLI parameter.
        //
        // In situations where we might have multiple configs with OFTs using multiple program IDs,
        // this function needs to decide which one to use.
        () => programId,
        // Last but not least the SDK will require a connection
        connectionFactory
    )

    // We now "merge" the two SDK factories into one.
    //
    // We do this by using the firstFactory helper function that is provided by the devtools package.
    // This function will try to execute the factories one by one and return the first one that succeeds.
    return firstFactory<[OmniPoint], IOApp>(evmSdkfactory, solanaSdkFactory)
}

const publicKey: CLIArgumentType<PublicKey> = {
    name: 'keyPair',
    parse(name: string, value: string) {
        return new PublicKey(value)
    },
    validate() { },
}

export const createSolanaConnectionFactory = () =>
    createConnectionFactory(
        createRpcUrlFactory({
            [EndpointId.SOLANA_V2_MAINNET]: process.env.RPC_URL_SOLANA,
            [EndpointId.SOLANA_V2_TESTNET]: process.env.RPC_URL_SOLANA_TESTNET,
        })
    )

interface UpdateMetadataTaskArgs {
    multisigKey?: PublicKey
    eid: EndpointId
    name: string
    mint: string
    sellerFeeBasisPoints: number
    symbol: string
    uri: string
    oappConfig: string
    logLevel: LogLevel
    internalConfigurator?: OAppConfigurator
}

export const createSolanaSignerFactory = (
    wallet: Keypair,
    connectionFactory = createSolanaConnectionFactory(),
    multisigKey?: PublicKey
) => {
    return async (eid: EndpointId): Promise<OmniSigner<OmniTransactionResponse<OmniTransactionReceipt>>> => {
        assert(
            endpointIdToChainType(eid) === ChainType.SOLANA,
            `Solana signer factory can only create signers for Solana networks. Received ${formatEid(eid)}`
        )

        return multisigKey
            ? new OmniSignerSolanaSquads(eid, await connectionFactory(eid), multisigKey, wallet)
            : new OmniSignerSolana(eid, await connectionFactory(eid), wallet)
    }
}

// note that if URI is specified, then the name and symbol in there would be used and will override the 'outer' name and symbol
task('lz:oft:solana:update-metadata', 'Updates the metaplex metadata of the SPL Token')
    .addParam('eid', 'Solana mainnet (30168) or testnet (40168)', undefined, devtoolsTypes.eid)
    .addParam('mint', 'The Token mint public key', undefined, devtoolsTypes.string)
    .addOptionalParam('name', 'Token Name', undefined, devtoolsTypes.string)
    .addOptionalParam('symbol', 'Token Symbol', undefined, devtoolsTypes.string)
    .addOptionalParam('sellerFeeBasisPoints', 'Seller fee basis points', undefined, devtoolsTypes.int)
    .addOptionalParam('uri', 'URI for token metadata', undefined, devtoolsTypes.string)
    .addParam('multisigKey', 'The MultiSig key', undefined, publicKey, true)
    .setAction(async ({ eid, name, mint: mintStr, sellerFeeBasisPoints, symbol, uri, logLevel, oappConfig, internalConfigurator, multisigKey }: UpdateMetadataTaskArgs, hre) => {

        const logger = createLogger(logLevel)

        //
        //
        // ENVIRONMENT SETUP
        //
        //

        // The Solana transaction size estimation algorithm is not very accurate, so we increase its tolerance by 192 bytes
        setTransactionSizeBuffer(192)

        // construct the user's keypair via the SOLANA_PRIVATE_KEY env var
        const keypair = (await useWeb3Js()).web3JsKeypair // note: this can be replaced with getSolanaKeypair() if we are okay to export that
        const userAccount = keypair.publicKey

        const solanaEid = await findSolanaEndpointIdInGraph(hre, oappConfig)
        const solanaDeployment = getSolanaDeployment(solanaEid)
        // Then we grab the programId from the args
        const programId = new PublicKey(solanaDeployment.programId)

        // TODO: refactor to instead use a function such as verifySolanaDeployment that also checks for oftStore key
        if (!programId) {
            logger.error('Missing programId in solana deployment')
            return
        }

        const configurator = internalConfigurator

        //
        //
        // TOOLING SETUP
        //
        //

        // We'll need a connection factory to be able to query the Solana network
        //
        // If you haven't set RPC_URL_SOLANA and/or RPC_URL_SOLANA_TESTNET environment variables,
        // the factory will use the default public RPC URLs
        const connectionFactory = createSolanaConnectionFactory()

        // We'll need SDKs to be able to use devtools
        const sdkFactory = createSdkFactory(userAccount, programId, connectionFactory)

        // We'll also need a signer factory
        const solanaSignerFactory = createSolanaSignerFactory(keypair, connectionFactory, multisigKey)

        const { umi, umiWalletSigner } = await deriveConnection(eid)

        const mint = pubKeyFn(mintStr)

        const initialMetadata = await fetchMetadataFromSeeds(umi, { mint })

        // if (initialMetadata.updateAuthority !== umiWalletSigner.publicKey.toString()) {
        //     throw new Error('Only the update authority can update the metadata')
        // }

        if (initialMetadata.isMutable == false) {
            throw new Error('Metadata is not mutable')
        }

        const isTestnet = eid == EndpointId.SOLANA_V2_TESTNET

        const updateV1Args: UpdateV1InstructionAccounts & UpdateV1InstructionArgs = {
            mint,
            authority: umiWalletSigner,
            data: {
                ...initialMetadata,
                name: name || initialMetadata.name,
                symbol: symbol || initialMetadata.symbol,
                uri: uri || initialMetadata.uri,
                sellerFeeBasisPoints:
                    sellerFeeBasisPoints != undefined ? sellerFeeBasisPoints : initialMetadata.sellerFeeBasisPoints,
            },
        }

        const txBuilder = transactionBuilder().add(updateV1(umi, updateV1Args))
        const createTokenTx = await txBuilder.sendAndConfirm(umi)
        console.log(`createTokenTx: ${getExplorerTxLink(bs58.encode(createTokenTx.signature), isTestnet)}`)
    })
