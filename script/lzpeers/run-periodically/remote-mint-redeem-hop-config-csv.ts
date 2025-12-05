import fs from 'fs'
import { chains } from '../chains'
import REMOTE_MINT_REDEEM_HOP_ABI from '../abis/REMOTE_MINT_REDEEM_HOP.json'

interface HopConfig {
    chain: string
    blockNumber: string
    remoteMintRedeemHop: string
    fraxtalHop: string
    numDVNs: string
    hopFee: string
    executor: string
    dvn: string
    treasury: string
    eid: string
    owner: string
    signers: string[]
    threshold: string
    frxUsdOft: string
    sfrxUsdOft: string
}

const MSIG_ABI = [
    {
        inputs: [],
        name: 'getOwners',
        outputs: [
            {
                internalType: 'address[]',
                name: '',
                type: 'address[]',
            },
        ],
        stateMutability: 'view',
        type: 'function',
    },
    {
        inputs: [],
        name: 'getThreshold',
        outputs: [
            {
                internalType: 'uint256',
                name: '',
                type: 'uint256',
            },
        ],
        stateMutability: 'view',
        type: 'function',
    },
]

async function main() {
    const hopConfigs: HopConfig[] = []
    const chainProcessingPromises = Object.keys(chains).map(async (chainName) => {
        const chainResults: HopConfig[] = []
        if (
            chainName !== 'fraxtal' &&
            chainName !== 'solana' &&
            chainName !== 'aptos' &&
            chainName !== 'movement' &&
            chainName !== 'xlayer'
        ) {
            const blockNumber = await chains[chainName].client.getBlockNumber()

            const fraxtalHop = await chains[chainName].client.readContract({
                address: chains[chainName].mintRedeemHop,
                abi: REMOTE_MINT_REDEEM_HOP_ABI,
                functionName: 'fraxtalHop',
                blockNumber,
            })

            const numDVNS = await chains[chainName].client.readContract({
                address: chains[chainName].mintRedeemHop,
                abi: REMOTE_MINT_REDEEM_HOP_ABI,
                functionName: 'numDVNs',
                blockNumber,
            })

            const hopFee = await chains[chainName].client.readContract({
                address: chains[chainName].mintRedeemHop,
                abi: REMOTE_MINT_REDEEM_HOP_ABI,
                functionName: 'hopFee',
                blockNumber,
            })

            let executor = ''
            try {
                executor = await chains[chainName].client.readContract({
                    address: chains[chainName].mintRedeemHop,
                    abi: REMOTE_MINT_REDEEM_HOP_ABI,
                    functionName: 'EXECUTOR',
                    blockNumber,
                })
            } catch (error) {
                console.log(`EXECUTOR : ${chainName}: ${chains[chainName].mintRedeemHop}`)
            }

            const dvn = await chains[chainName].client.readContract({
                address: chains[chainName].mintRedeemHop,
                abi: REMOTE_MINT_REDEEM_HOP_ABI,
                functionName: 'DVN',
                blockNumber,
            })

            const treasury = await chains[chainName].client.readContract({
                address: chains[chainName].mintRedeemHop,
                abi: REMOTE_MINT_REDEEM_HOP_ABI,
                functionName: 'TREASURY',
                blockNumber,
            })

            const eid = await chains[chainName].client.readContract({
                address: chains[chainName].mintRedeemHop,
                abi: REMOTE_MINT_REDEEM_HOP_ABI,
                functionName: 'EID',
                blockNumber,
            })

            const frxUsdOft = await chains[chainName].client.readContract({
                address: chains[chainName].mintRedeemHop,
                abi: REMOTE_MINT_REDEEM_HOP_ABI,
                functionName: 'frxUsdOft',
                blockNumber,
            })

            const sfrxUsdOft = await chains[chainName].client.readContract({
                address: chains[chainName].mintRedeemHop,
                abi: REMOTE_MINT_REDEEM_HOP_ABI,
                functionName: 'sfrxUsdOft',
                blockNumber,
            })

            const owner = await chains[chainName].client.readContract({
                address: chains[chainName].mintRedeemHop,
                abi: REMOTE_MINT_REDEEM_HOP_ABI,
                functionName: 'owner',
                blockNumber,
            })

            let signers = []
            try {
                signers = await chains[chainName].client.readContract({
                    address: owner,
                    abi: MSIG_ABI,
                    functionName: 'getOwners',
                    blockNumber,
                })
            } catch (error) {
                console.log(`getOwners : ${chainName}: ${chains[chainName].mintRedeemHop} : ${owner}`)
            }

            let threshold = ''
            try {
                threshold = await chains[chainName].client.readContract({
                    address: owner,
                    abi: MSIG_ABI,
                    functionName: 'getThreshold',
                    blockNumber,
                })
            } catch (error) {
                console.log(`getThreshold : ${chainName}: ${chains[chainName].mintRedeemHop} : ${owner}`)
            }

            hopConfigs.push({
                chain: chainName,
                blockNumber: blockNumber.toString(),
                remoteMintRedeemHop: chains[chainName].mintRedeemHop || '',
                fraxtalHop: fraxtalHop,
                numDVNs: numDVNS.toString(),
                hopFee: hopFee.toString(),
                executor: executor,
                dvn: dvn,
                treasury: treasury,
                eid: eid,
                frxUsdOft: frxUsdOft,
                sfrxUsdOft: sfrxUsdOft,
                owner: owner,
                signers: signers,
                threshold: threshold.toString(),
            })
        }
        return chainResults
    })
    const hopConfigResults = await Promise.all(chainProcessingPromises)

    for (const hopConfigResult of hopConfigResults) {
        hopConfigs.push(...hopConfigResult)
    }

    let rows: string[][] = []
    rows.push([
        'Chain,Blocknumber,RemoteMintRedeemHop,FraxtalHop,NumOfDVNs,Executor,Dvn,Treasury,Eid,frxUsdOFT,sfrxUsdOft,Owner,Threshold,Signers',
    ])
    hopConfigs.forEach((hopConfig) => {
        rows.push([
            hopConfig.chain,
            hopConfig.blockNumber,
            hopConfig.remoteMintRedeemHop,
            hopConfig.fraxtalHop,
            hopConfig.numDVNs,
            hopConfig.executor,
            hopConfig.dvn,
            hopConfig.treasury,
            hopConfig.eid,
            hopConfig.frxUsdOft,
            hopConfig.sfrxUsdOft,
            hopConfig.owner,
            hopConfig.threshold,
            hopConfig.signers.join(';'),
        ])
    })

    fs.writeFileSync(
        `./run-periodically/remote-mint-redeem-hop-config-csv/remote-mint-redeem-hop-config.csv`,
        rows.map((r) => r.join(',')).join('\n')
    )
}

main().catch(console.error)
