import { chains } from '../chains'
import REMOTE_HOP_ABI from '../abis/REMOTE_HOP_ABI.json'

interface HopConfig {
    chain: string
    blockNumber: string
    hop:string
    fraxtalHop: string
    numDVNs: string
    hopFee: string
    executorOptions: string
    executor: string
    dvn: string
    treasury: string
    version: string
    owner: string
    signers: string[]
    threshold: string
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
                address: chains[chainName].hop,
                abi: REMOTE_HOP_ABI,
                functionName: 'fraxtalHop',
                blockNumber,
            })

            const numDVNS = await chains[chainName].client.readContract({
                address: chains[chainName].hop,
                abi: REMOTE_HOP_ABI,
                functionName: 'numDVNs',
                blockNumber,
            })

            const hopFee = await chains[chainName].client.readContract({
                address: chains[chainName].hop,
                abi: REMOTE_HOP_ABI,
                functionName: 'hopFee',
                blockNumber,
            })

            const executorOptions = await chains[chainName].client.readContract({
                address: chains[chainName].hop,
                abi: REMOTE_HOP_ABI,
                functionName: 'executorOptions',
                args: [30168],
                blockNumber,
            })

            const executor = await chains[chainName].client.readContract({
                address: chains[chainName].hop,
                abi: REMOTE_HOP_ABI,
                functionName: 'EXECUTOR',
                blockNumber,
            })

            const dvn = await chains[chainName].client.readContract({
                address: chains[chainName].hop,
                abi: REMOTE_HOP_ABI,
                functionName: 'DVN',
                blockNumber,
            })

            const treasury = await chains[chainName].client.readContract({
                address: chains[chainName].hop,
                abi: REMOTE_HOP_ABI,
                functionName: 'TREASURY',
                blockNumber,
            })

            let version = ''
            try {
                const _version = await chains[chainName].client.readContract({
                    address: chains[chainName].hop,
                    abi: REMOTE_HOP_ABI,
                    functionName: 'version',
                    blockNumber,
                })
                version = _version
            } catch (error) {
                console.error(`error fetching version for ${chainName}`)
            }

            const owner = await chains[chainName].client.readContract({
                address: chains[chainName].hop,
                abi: REMOTE_HOP_ABI,
                functionName: 'owner',
                blockNumber,
            })

            const signers = await chains[chainName].client.readContract({
                address: owner,
                abi: MSIG_ABI,
                functionName: 'getOwners',
                blockNumber,
            })

            const threshold = await chains[chainName].client.readContract({
                address: owner,
                abi: MSIG_ABI,
                functionName: 'getThreshold',
                blockNumber,
            })

            hopConfigs.push({
                chain: chainName,
                blockNumber: blockNumber.toString(),
                hop:chains[chainName].hop || '',
                fraxtalHop: fraxtalHop,
                numDVNs: numDVNS.toString(),
                hopFee: hopFee.toString(),
                executorOptions: executorOptions,
                executor: executor,
                dvn: dvn,
                treasury: treasury,
                version: version,
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

    console.log("Chain,Blocknumber,RemoteHop,FraxtalHop,NumOfDVNs,SolanaExecutorOptions,Executor,Dvn,Treasury,Version,Owner,Threshold,Signers")
    hopConfigs.forEach((hopConfig) => {
        console.log(`${hopConfig.chain},${hopConfig.blockNumber},${hopConfig.hop},${hopConfig.fraxtalHop},${hopConfig.numDVNs},${hopConfig.executorOptions},${hopConfig.executor},${hopConfig.dvn},${hopConfig.treasury},${hopConfig.version},${hopConfig.owner},${hopConfig.threshold},${hopConfig.signers}`)
    })
}

main().catch(console.error)
