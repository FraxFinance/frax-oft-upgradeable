import dotenv from "dotenv"
import {
    AddressLookupTableProgram,
    Connection,
    Keypair,
    PublicKey,
    Transaction,
    sendAndConfirmTransaction,
} from '@solana/web3.js'
import {default as bs58} from 'bs58'

dotenv.config({ path: '.env' })

const RPC_URL =
    process.env.RPC_URL_SOLANA_MAINNET ||
    process.env.RPC_URL_SOLANA ||
    process.env.SOLANA_RPC_URL ||
    'https://api.mainnet-beta.solana.com'

const SOLANA_PRIVATE_KEY = process.env.SOLANA_PRIVATE_KEY

if (!SOLANA_PRIVATE_KEY) {
    throw new Error('Set SOLANA_PRIVATE_KEY')
}

const payer = Keypair.fromSeed(Uint8Array.from(bs58.decode(SOLANA_PRIVATE_KEY).slice(0, 32)));

const connection = new Connection(RPC_URL, 'confirmed')

const addresses = [
    'E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ',
    '5AbNv2Xbjn6e7nFBgbFLUzFM2XXCqsiWRRjTqGw53SYL',
    '7LS6y37WXXCyBHkBU6zVpiqaqbkXLr4P85ZhQi3eonSp',
    '5VaGz7xPjzESex1QcgGkPH8cmG6jBsUJLZtjdAnoiQ9z',
    '84AFSH3TSzyjbEFJX9z8sjpV7npTWq7f8ZR5zkLG22hX',
    'GzX1ireZDU865FiMaKrdVB1H6AE8LAqWYCg6chrMrfBw',
    'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
    'Dae43X8nYxf7Acy51E4oqTWX5wqJ4yB91MSYg3MPWeEa',
    '76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6',
    '7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH',
    'EK8rh8hQnzCYyWpB4dyHT1T6Jd8EP31ikYctqBrLdH8J',
    '7gJubSh2enfMQkJu8FBqL2QKeZWQrWCyzPeZbQeEyYuh',
    '526PeNZfw8kSnDU4nmzJFVJzJWNhwmZykEyJr5XWz5Fv',
    '2uk9pQh3tB5ErV7LGQJcbWjb4KeJ2UJki5qJZ8QG56G3',
    'DRwMNL6bNT89BGeECV78ZocGjrBCqxo6Kvw6wvgusKXj',
    'F8E8QGhKmHEx2esh5LpVizzcP4cHYhzXdXTwg9w3YYY2',
    '2XgGZG4oP29U3w5h4nTk1V2LFHL23zKDPJjs3psGzLKQ',
    '7fp3u9L4rt5PqT9EvZYee2NL5rjS73ftHTthP47Ym95q',
    'Ag8FRwGc1ZXDozyr3TWcaHSZUoiiDjmGwGZ32zvir3yD',
    '11111111111111111111111111111111',
    '7n1YeBMVEUCJ4DscKAcpVQd6KXU7VpcEcc15ZuMcL4U3',
    '6doghB248px58JSSwG4qejQ46kFMW4AMj7vzJnWZHNZn',
    'AwrbHeCyniXaQhiJZkLhgWdUCteeWSGaSN1sTfLiY7xK',
    '8ahPGPjEbpgGaZx2NV1iG5Shj7TDwvsjkEDcGWjt94TP',
    'CSFsUupvJEQQd1F4SsXGACJaxQX4eropQMkGV2696eeQ',
    'HtEYV4xB4wvsj5fgTkcfuChYpvGYzgzwvNhgDZQNh7wW',
    '4VDjp6XQaxoZf5RGwiPU9NR1EXSZn2TP4ATMmiSzLfhb',
    '3f8coqkajiMZC4dyrSs4JHH5xt8m9ceZJZe7d7VVCC3e',
    '6YB63FDuyYLt5gnJeiVmYRE4c6tFid5SrBZzMLQFfexm',
    '5KAALa8AEEKnW6p6AacdnqNDmGMpfhwR7AEyWs1gUvsT',
    '7jMeX5mzXnSSKYd8DxBDP4xMnkNFZZZm5W28FWUTbwU3',
    '4fs6aL12L18K5giDy9Dgxgrb3aNRYiuRV2a7JPPj3e7F',
    'GPjyWr8vCotGuFubDpTxDxy9Vj1ZeEN4F2dwRmFiaGab',
    '4Z436PCb83Ft9dMRtwZ2mK7ZQtqVhbFEC3BYna9qB7B9',
    'HR9NQKK1ynW9NzgdM37dU5CBtqRHTukmbMKS7qkwSkHX',
].map((x) => new PublicKey(x))

function chunks<T>(arr: T[], size: number): T[][] {
    const out: T[][] = []
    for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size))
    return out
}

async function main() {
    console.log('RPC:', RPC_URL)
    console.log('Payer:', payer.publicKey.toBase58())

    const slot = await connection.getSlot('finalized')

    const [createIx, lookupTableAddress] = AddressLookupTableProgram.createLookupTable({
        authority: payer.publicKey,
        payer: payer.publicKey,
        recentSlot: slot,
    })

    console.log('Creating ALT:', lookupTableAddress.toBase58())

    await sendAndConfirmTransaction(
        connection,
        new Transaction().add(createIx),
        [payer],
        { commitment: 'confirmed' }
    )

    for (const group of chunks(addresses, 20)) {
        const extendIx = AddressLookupTableProgram.extendLookupTable({
            payer: payer.publicKey,
            authority: payer.publicKey,
            lookupTable: lookupTableAddress,
            addresses: group,
        })

        const sig = await sendAndConfirmTransaction(
            connection,
            new Transaction().add(extendIx),
            [payer],
            { commitment: 'confirmed' }
        )

        console.log(`Extended ${group.length} addresses:`, sig)
    }

    console.log('\nCUSTOM_ALT=' + lookupTableAddress.toBase58())
    console.log('Wait a few slots before using it.')
}

main().catch((err) => {
    console.error(err)
    process.exit(1)
})