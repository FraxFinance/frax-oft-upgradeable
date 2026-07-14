import { mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { fetchMetadataFromSeeds } from '@metaplex-foundation/mpl-token-metadata'
import { createNoopSigner, publicKey, signerIdentity, transactionBuilder } from '@metaplex-foundation/umi'
import bs58 from 'bs58'
import { task } from 'hardhat/config'
import { mkdir, writeFile } from 'node:fs/promises'
import path from 'node:path'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { EndpointProgram, SetConfigType, UlnProgram } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'
import { Uln302ConfigType, Uln302UlnConfig } from '@layerzerolabs/protocol-devtools'
import { EndpointV2 } from '@layerzerolabs/protocol-devtools-solana'
import { PublicKey, VersionedMessage, VersionedTransaction } from '@solana/web3.js'

import { getSolanaReceiveConfig, getSolanaSendConfig } from '../common/taskHelper'
import { createSolanaConnectionFactory } from '../common/utils'
import { getSolanaDeployment } from './index'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'

const NIL_DVN_COUNT = 255
const MAX_SOLANA_TX_BYTES = 1232

interface Args {
    fromEid: EndpointId
    toEid: EndpointId
    squadsAuthority: string
    outputPath: string
}

function toPinnedUlnConfig(config: Uln302UlnConfig): UlnProgram.types.UlnConfig {
    return {
        confirmations: BigInt(config.confirmations.toString()),
        requiredDvnCount: config.requiredDVNs.length,
        optionalDvnCount: NIL_DVN_COUNT,
        optionalDvnThreshold: 0,
        requiredDvns: config.requiredDVNs.map((dvn) => publicKey(dvn)),
        optionalDvns: [],
    }
}

function toSafeFileSlug(value: string): string {
    return value
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
}

async function buildAndSerializeTx(
    umi: ReturnType<typeof createUmi>,
    feePayer: ReturnType<typeof createNoopSigner>,
    instructions: Awaited<ReturnType<EndpointProgram.Endpoint['setOAppConfig']>>[]
) {
    const txBuilder = transactionBuilder().add(instructions)
    txBuilder.setFeePayer(feePayer)
    await txBuilder.setLatestBlockhash(umi)
    const serializedTx = await txBuilder.buildWithLatestBlockhash(umi)
    const transactionDataHex = Buffer.from(serializedTx.serializedMessage).toString('hex')
    const versionedMessage = VersionedMessage.deserialize(new Uint8Array(Buffer.from(transactionDataHex, 'hex')))
    const tx = new VersionedTransaction(versionedMessage)
    const serialized = tx.serialize()

    return {
        byteLength: serialized.length,
        base58: bs58.encode(new Uint8Array(serialized)),
        base64: Buffer.from(serialized).toString('base64'),
    }
}

task('lz:oft:solana:pin-optionaldvn', 'Pins optional DVN count to 255 on Solana ULN app config and emits a Squads-ready tx')
    .addParam('fromEid', 'The source Solana endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('toEid', 'The destination endpoint ID', undefined, devtoolsTypes.eid)
    .addParam('squadsAuthority', 'The Squads authority public key', undefined, devtoolsTypes.string)
    .addParam('outputPath', 'Directory to write BASE58 tx files', undefined, devtoolsTypes.string)
    .setAction(async (args: Args) => {
        const { fromEid, toEid, squadsAuthority: squadsAuthorityStr, outputPath } = args

        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(fromEid)
        const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())

        const squadsAuthority = publicKey(squadsAuthorityStr)
        const squadsSigner = createNoopSigner(squadsAuthority)

        umi.use(signerIdentity(squadsSigner))

        const solanaDeployment = getSolanaDeployment(fromEid)
        const oftStore = publicKey(solanaDeployment.oftStore)
        const oftStoreInfo = await oft.accounts.fetchOFTStore(umi, oftStore)
        const mint = publicKey(oftStoreInfo.tokenMint)
        const metadata = await fetchMetadataFromSeeds(umi, { mint })
        const oftSymbolSlug = toSafeFileSlug(metadata.symbol)
        if (!oftSymbolSlug) {
            throw new Error(`Failed to derive OFT symbol slug from on-chain metadata symbol: "${metadata.symbol}"`)
        }
        const endpointV2Sdk = new EndpointV2(
            connection,
            {
                eid: fromEid,
                address: oftStore.toString(),
            },
            new PublicKey(squadsAuthorityStr)
        )

        let sendConfig: Uln302UlnConfig
        let receiveConfig: Uln302UlnConfig
        let usedSendFallback = false
        let usedReceiveFallback = false

        try {
            const sendConfigEntry = await getSolanaSendConfig(endpointV2Sdk, toEid, oftStore.toString())
            if (!sendConfigEntry) {
                throw new Error(`No send ULN config found for remote eid ${toEid}`)
            }
            ;[, sendConfig] = sendConfigEntry
        } catch (error) {
            usedSendFallback = true
            console.warn(
                `Failed to resolve send library for remote eid ${toEid}. Falling back to direct ULN app config lookup.`
            )
            sendConfig = await endpointV2Sdk.getAppUlnConfig(
                oftStore.toString(),
                UlnProgram.ULN_PROGRAM_ID.toString(),
                toEid,
                Uln302ConfigType.Send
            )
        }

        try {
            const receiveConfigEntry = await getSolanaReceiveConfig(endpointV2Sdk, toEid, oftStore.toString())
            if (!receiveConfigEntry) {
                throw new Error(`No receive ULN config found for remote eid ${toEid}`)
            }
            ;[, receiveConfig] = receiveConfigEntry
        } catch (error) {
            usedReceiveFallback = true
            console.warn(
                `Failed to resolve receive library for remote eid ${toEid}. Falling back to direct ULN app config lookup.`
            )
            receiveConfig = await endpointV2Sdk.getAppUlnConfig(
                oftStore.toString(),
                UlnProgram.ULN_PROGRAM_ID.toString(),
                toEid,
                Uln302ConfigType.Receive
            )
        }

        const endpoint = new EndpointProgram.Endpoint(EndpointProgram.ENDPOINT_PROGRAM_ID)
        const msgLibProgram = UlnProgram.ULN_PROGRAM_ID
        const msgLibVersion = {
            major: 3n,
            minor: 0,
            endpointVersion: 2,
        }

        console.log('PIN_OPTIONAL_DVN_AUDIT', {
            fromEid,
            toEid,
            oftStore: oftStore.toString(),
            msgLibProgram: msgLibProgram.toString(),
            msgLibVersion: {
                major: msgLibVersion.major.toString(),
                minor: msgLibVersion.minor,
                endpointVersion: msgLibVersion.endpointVersion,
            },
            configSource: {
                send: usedSendFallback ? 'fallback:getAppUlnConfig' : 'primary:getSolanaSendConfig',
                receive: usedReceiveFallback ? 'fallback:getAppUlnConfig' : 'primary:getSolanaReceiveConfig',
            },
        })

        const sendInstruction = await endpoint.setOAppConfig(umi.rpc, squadsSigner, {
            oapp: oftStore,
            eid: toEid,
            config: {
                configType: SetConfigType.SEND_ULN,
                value: toPinnedUlnConfig(sendConfig),
            },
            msgLibProgram,
            msgLibVersion,
        })

        const receiveInstruction = await endpoint.setOAppConfig(umi.rpc, squadsSigner, {
            oapp: oftStore,
            eid: toEid,
            config: {
                configType: SetConfigType.RECEIVE_ULN,
                value: toPinnedUlnConfig(receiveConfig),
            },
            msgLibProgram,
            msgLibVersion,
        })

        console.log({
            fromEid,
            toEid,
            squadsAuthority: squadsAuthorityStr,
            oftStore: oftStore.toString(),
            sendConfig,
            receiveConfig,
        })

        const combinedTx = await buildAndSerializeTx(umi, squadsSigner, [sendInstruction, receiveInstruction])
        const sendTx = await buildAndSerializeTx(umi, squadsSigner, [sendInstruction])
        const receiveTx = await buildAndSerializeTx(umi, squadsSigner, [receiveInstruction])

        console.log('TX_SIZE_AUDIT', {
            maxPacketBytes: MAX_SOLANA_TX_BYTES,
            combined: combinedTx.byteLength,
            sendOnly: sendTx.byteLength,
            receiveOnly: receiveTx.byteLength,
            combinedWithinLimit: combinedTx.byteLength <= MAX_SOLANA_TX_BYTES,
            sendWithinLimit: sendTx.byteLength <= MAX_SOLANA_TX_BYTES,
            receiveWithinLimit: receiveTx.byteLength <= MAX_SOLANA_TX_BYTES,
        })

        console.log('SEND_ONLY_BASE58: \n')
        console.log(sendTx.base58)
        console.log('\nSEND_ONLY_BASE64: \n')
        console.log(sendTx.base64)

        console.log('\nRECEIVE_ONLY_BASE58: \n')
        console.log(receiveTx.base58)
        console.log('\nRECEIVE_ONLY_BASE64: \n')
        console.log(receiveTx.base64)

        await mkdir(outputPath, { recursive: true })
        const sendPath = path.join(outputPath, `${oftSymbolSlug}-pinoftionaldvn-send-${toEid}.txt`)
        const receivePath = path.join(outputPath, `${oftSymbolSlug}-pinoftionaldvn-rcv-${toEid}.txt`)

        await writeFile(sendPath, `${sendTx.base58}\n`, 'utf8')
        await writeFile(receivePath, `${receiveTx.base58}\n`, 'utf8')

        console.log('BASE58_FILE_OUTPUT', {
            sendPath,
            receivePath,
            oftName: metadata.name,
            oftSymbol: metadata.symbol,
            oftSymbolSlug,
        })
    })