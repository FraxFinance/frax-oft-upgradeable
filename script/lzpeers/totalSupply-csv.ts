import { encodeFunctionData, parseUnits } from 'viem'
import { ERC20ABI } from './abis/ERC20'
import { chains } from './chains'
import { aptosMovementOFTs, ofts, solanaOFTs } from './oft'
import { PublicKey } from '@solana/web3.js'
import * as fs from 'fs'

const EthereumPortal = '0x36cb65c1967A0Fb0EEE11569C51C2f2aA1Ca6f6D'
const EthereumL1Bridge = '0x34C0bD5877A5Ee7099D0f5688D65F4bB9158BDE2'
const EthereumMultisig = '0xe0d7755252873c4eF5788f7f45764E0e17610508'
const fxsToken = '0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0'

interface TokenSupplyData {
    chain: string
    blockNumber?: string
    token: string
    rawSupply: string
    totalTransferFromFraxtal?: string
    totalTransferToFraxtal?: string
    totalTransferFromEthereum?: string
    totalTransferToEthereum?: string
    supply: string
}

interface Meta {
    description: string
    name: string
}

interface Transaction {
    data: string
    operation: string
    to: string
    value: string
}

interface TransactionBatch {
    chainId: number
    createdAt: number
    meta: Meta
    transactions: Transaction[]
    version: string
}

const setInitialTotalSupplyAbi = [
    {
        type: 'function',
        name: 'setInitialTotalSupply',
        inputs: [
            {
                name: '_eid',
                type: 'uint32',
                internalType: 'uint32',
            },
            {
                name: '_amount',
                type: 'uint256',
                internalType: 'uint256',
            },
        ],
        outputs: [],
        stateMutability: 'nonpayable',
    },
]

// Convert wei (raw token amount) to decimal format by dividing by 10^18
function formatTokenAmount(amount: bigint | string | number): string {
    if (typeof amount === 'string' || typeof amount === 'number') {
        // Handle already decimal values (like from Solana)
        return amount.toString()
    }

    // Convert BigInt wei to decimal by dividing by 10^18
    const divisor = 10n ** 18n
    const wholePart = amount / divisor
    const fractionalPart = amount % divisor

    // Convert to decimal string with up to 18 decimal places
    const fractionalStr = fractionalPart.toString().padStart(18, '0')
    const trimmedFractional = fractionalStr.replace(/0+$/, '') // Remove trailing zeros

    if (trimmedFractional === '') {
        return wholePart.toString()
    } else {
        return `${wholePart}.${trimmedFractional}`
    }
}

async function main() {
    const results: TokenSupplyData[] = []

    const chainProcessingPromises = Object.keys(chains).map(async (chainName) => {
        const chainResults: TokenSupplyData[] = []

        if (
            chainName !== 'fraxtal' &&
            chainName !== 'ethereum' &&
            chainName !== 'solana' &&
            chainName !== 'movement' &&
            chainName !== 'aptos'
        ) {
            try {
                const blockNumber = await chains[chainName].client.getBlockNumber()

                const totalSupplyfpi = await chains[chainName].client.readContract({
                    address: ofts[chainName]['fpi'].address,
                    abi: ofts[chainName]['fpi'].abi,
                    functionName: 'totalSupply',
                    blockNumber,
                })

                const totalTransferToFraxtalfpi = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['fpi'].address,
                    abi: ofts.fraxtal['fpi'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })

                const totalTransferFromFraxtalfpi = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['fpi'].address,
                    abi: ofts.fraxtal['fpi'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })

                const totalTransferToEthereumfpi = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['fpi'].address,
                    abi: ofts.ethereum['fpi'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })

                const totalTransferFromEthereumfpi = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['fpi'].address,
                    abi: ofts.ethereum['fpi'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })

                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'fpi',
                    rawSupply: totalSupplyfpi,
                    totalTransferToFraxtal: totalTransferToFraxtalfpi,
                    totalTransferFromFraxtal: totalTransferFromFraxtalfpi,
                    totalTransferToEthereum: totalTransferToEthereumfpi,
                    totalTransferFromEthereum: totalTransferFromEthereumfpi,
                    supply: formatTokenAmount(totalSupplyfpi),
                })

                const totalSupplyfrxeth = await chains[chainName].client.readContract({
                    address: ofts[chainName]['frxETH'].address,
                    abi: ofts[chainName]['frxETH'].abi,
                    functionName: 'totalSupply',
                    blockNumber,
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'frxETH',
                    rawSupply: totalSupplyfrxeth,
                    supply: formatTokenAmount(totalSupplyfrxeth),
                })

                const totalSupplyfrxusd = await chains[chainName].client.readContract({
                    address: ofts[chainName]['frxUSD'].address,
                    abi: ofts[chainName]['frxUSD'].abi,
                    functionName: 'totalSupply',
                    blockNumber,
                })
                const totalTransferToFraxtalfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['frxUSD'].address,
                    abi: ofts.fraxtal['frxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })

                const totalTransferFromFraxtalfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['frxUSD'].address,
                    abi: ofts.fraxtal['frxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })

                const totalTransferToEthereumfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['frxUSD'].address,
                    abi: ofts.ethereum['frxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })

                const totalTransferFromEthereumfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['frxUSD'].address,
                    abi: ofts.ethereum['frxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'frxUSD',
                    totalTransferToFraxtal: totalTransferToFraxtalfrxusd,
                    totalTransferFromFraxtal: totalTransferFromFraxtalfrxusd,
                    totalTransferToEthereum: totalTransferToEthereumfrxusd,
                    totalTransferFromEthereum: totalTransferFromEthereumfrxusd,
                    rawSupply: totalSupplyfrxusd,
                    supply: formatTokenAmount(totalSupplyfrxusd),
                })

                const totalSupplysfrxeth = await chains[chainName].client.readContract({
                    address: ofts[chainName]['sfrxETH'].address,
                    abi: ofts[chainName]['sfrxETH'].abi,
                    functionName: 'totalSupply',
                    blockNumber,
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'sfrxETH',
                    rawSupply: totalSupplysfrxeth,
                    supply: formatTokenAmount(totalSupplysfrxeth),
                })

                const totalSupplysfrxusd = await chains[chainName].client.readContract({
                    address: ofts[chainName]['sfrxUSD'].address,
                    abi: ofts[chainName]['sfrxUSD'].abi,
                    functionName: 'totalSupply',
                    blockNumber,
                })
                const totalTransferToFraxtalsfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['sfrxUSD'].address,
                    abi: ofts.fraxtal['sfrxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })

                const totalTransferFromFraxtalsfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['sfrxUSD'].address,
                    abi: ofts.fraxtal['sfrxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })

                const totalTransferToEthereumsfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['sfrxUSD'].address,
                    abi: ofts.ethereum['sfrxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })

                const totalTransferFromEthereumsfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['sfrxUSD'].address,
                    abi: ofts.ethereum['sfrxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'sfrxUSD',
                    totalTransferToFraxtal: totalTransferToFraxtalsfrxusd,
                    totalTransferFromFraxtal: totalTransferFromFraxtalsfrxusd,
                    totalTransferToEthereum: totalTransferToEthereumsfrxusd,
                    totalTransferFromEthereum: totalTransferFromEthereumsfrxusd,
                    rawSupply: totalSupplysfrxusd,
                    supply: formatTokenAmount(totalSupplysfrxusd),
                })

                const totalSupplywfrax = await chains[chainName].client.readContract({
                    address: ofts[chainName]['wfrax'].address,
                    abi: ofts[chainName]['wfrax'].abi,
                    functionName: 'totalSupply',
                    blockNumber,
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'wfrax',
                    rawSupply: totalSupplywfrax,
                    supply: formatTokenAmount(totalSupplywfrax),
                })
            } catch (error) {
                console.error(`Error processing ${chainName}:`, error)
            }
        } else if (chainName === 'ethereum' || chainName === 'fraxtal') {
            // except wfrax, all are lockbox
            try {
                const blockNumber = await chains[chainName].client.getBlockNumber()

                const tokenfpi = await chains[chainName].client.readContract({
                    address: ofts[chainName]['fpi'].address,
                    abi: ofts[chainName]['fpi'].abi,
                    functionName: 'token',
                })
                const fpiBal = await chains[chainName].client.readContract({
                    address: tokenfpi,
                    abi: ERC20ABI,
                    functionName: 'balanceOf',
                    args: [ofts[chainName]['fpi'].address],
                    blockNumber,
                })
                chainResults.push({
                    chain: chainName + '-lockbox',
                    blockNumber: blockNumber.toString(),
                    token: 'fpi',
                    rawSupply: fpiBal,
                    supply: formatTokenAmount(fpiBal),
                })
                const totalSupplyfpi = await chains[chainName].client.readContract({
                    address: tokenfpi,
                    abi: ERC20ABI,
                    functionName: 'totalSupply',
                    blockNumber,
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'fpi',
                    rawSupply: totalSupplyfpi,
                    supply: formatTokenAmount(totalSupplyfpi),
                })

                const tokenfrxeth = await chains[chainName].client.readContract({
                    address: ofts[chainName]['frxETH'].address,
                    abi: ofts[chainName]['frxETH'].abi,
                    functionName: 'token',
                })
                const frxETHBal = await chains[chainName].client.readContract({
                    address: tokenfrxeth,
                    abi: ERC20ABI,
                    functionName: 'balanceOf',
                    args: [ofts[chainName]['frxETH'].address],
                    blockNumber,
                })

                const totalSupplyfrxETH = await chains[chainName].client.readContract({
                    address: tokenfrxeth,
                    abi: ERC20ABI,
                    functionName: 'totalSupply',
                    blockNumber,
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'frxETH',
                    rawSupply: totalSupplyfrxETH,
                    supply: formatTokenAmount(totalSupplyfrxETH),
                })

                chainResults.push({
                    chain: chainName + '-lockbox',
                    blockNumber: blockNumber.toString(),
                    token: 'frxETH',
                    rawSupply: frxETHBal,
                    supply: formatTokenAmount(frxETHBal),
                })

                const tokenfrxusd = await chains[chainName].client.readContract({
                    address: ofts[chainName]['frxUSD'].address,
                    abi: ofts[chainName]['frxUSD'].abi,
                    functionName: 'token',
                })
                const frxUSDBal = await chains[chainName].client.readContract({
                    address: tokenfrxusd,
                    abi: ERC20ABI,
                    functionName: 'balanceOf',
                    args: [ofts[chainName]['frxUSD'].address],
                    blockNumber,
                })

                const totalSupplyfrxUSD = await chains[chainName].client.readContract({
                    address: tokenfrxusd,
                    abi: ERC20ABI,
                    functionName: 'totalSupply',
                    blockNumber,
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'frxUSD',
                    rawSupply: totalSupplyfrxUSD,
                    supply: formatTokenAmount(totalSupplyfrxUSD),
                })

                chainResults.push({
                    chain: chainName + '-lockbox',
                    blockNumber: blockNumber.toString(),
                    token: 'frxUSD',
                    rawSupply: frxUSDBal,
                    supply: formatTokenAmount(frxUSDBal),
                })

                const tokensfrxeth = await chains[chainName].client.readContract({
                    address: ofts[chainName]['sfrxETH'].address,
                    abi: ofts[chainName]['sfrxETH'].abi,
                    functionName: 'token',
                })
                const sfrxethBal = await chains[chainName].client.readContract({
                    address: tokensfrxeth,
                    abi: ERC20ABI,
                    functionName: 'balanceOf',
                    args: [ofts[chainName]['sfrxETH'].address],
                    blockNumber,
                })

                const totalSupplysfrxeth = await chains[chainName].client.readContract({
                    address: tokensfrxeth,
                    abi: ERC20ABI,
                    functionName: 'totalSupply',
                    blockNumber,
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'sfrxETH',
                    rawSupply: totalSupplysfrxeth,
                    supply: formatTokenAmount(totalSupplysfrxeth),
                })

                chainResults.push({
                    chain: chainName + '-lockbox',
                    blockNumber: blockNumber.toString(),
                    token: 'sfrxETH',
                    rawSupply: sfrxethBal,
                    supply: formatTokenAmount(sfrxethBal),
                })

                const tokensfrxusd = await chains[chainName].client.readContract({
                    address: ofts[chainName]['sfrxUSD'].address,
                    abi: ofts[chainName]['sfrxUSD'].abi,
                    functionName: 'token',
                })
                const sfrxusdBal = await chains[chainName].client.readContract({
                    address: tokensfrxusd,
                    abi: ERC20ABI,
                    functionName: 'balanceOf',
                    args: [ofts[chainName]['sfrxUSD'].address],
                    blockNumber,
                })
                const totalSupplysfrxusd = await chains[chainName].client.readContract({
                    address: tokensfrxusd,
                    abi: ERC20ABI,
                    functionName: 'totalSupply',
                    blockNumber,
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: 'sfrxUSD',
                    rawSupply: totalSupplysfrxusd,
                    supply: formatTokenAmount(totalSupplysfrxusd),
                })
                chainResults.push({
                    chain: chainName + '-lockbox',
                    blockNumber: blockNumber.toString(),
                    token: 'sfrxUSD',
                    rawSupply: sfrxusdBal,
                    supply: formatTokenAmount(sfrxusdBal),
                })

                if (chainName === 'ethereum') {
                    const totalSupplywfrax = await chains[chainName].client.readContract({
                        address: ofts[chainName]['wfrax'].address,
                        abi: ofts[chainName]['wfrax'].abi,
                        functionName: 'totalSupply',
                        blockNumber,
                    })
                    const portalBalancefxs = await chains[chainName].client.readContract({
                        address: fxsToken,
                        abi: ERC20ABI,
                        functionName: 'balanceOf',
                        args: [EthereumPortal],
                        blockNumber,
                    })
                    chainResults.push({
                        chain: chainName,
                        blockNumber: blockNumber.toString(),
                        token: 'wfrax',
                        rawSupply: totalSupplywfrax,
                        supply: formatTokenAmount(totalSupplywfrax),
                    })
                    chainResults.push({
                        chain: chainName + '-portal',
                        blockNumber: blockNumber.toString(),
                        token: 'fxs',
                        rawSupply: portalBalancefxs,
                        supply: formatTokenAmount(portalBalancefxs),
                    })

                    const l1BridgeBalancefpi = await chains[chainName].client.readContract({
                        address: tokenfpi,
                        abi: ERC20ABI,
                        functionName: 'balanceOf',
                        args: [EthereumL1Bridge],
                        blockNumber,
                    })
                    chainResults.push({
                        chain: chainName + '-l1bridge',
                        blockNumber: blockNumber.toString(),
                        token: 'fpi',
                        rawSupply: l1BridgeBalancefpi,
                        supply: formatTokenAmount(l1BridgeBalancefpi),
                    })
                    const l1BridgeBalancefrxETH = await chains[chainName].client.readContract({
                        address: tokenfrxeth,
                        abi: ERC20ABI,
                        functionName: 'balanceOf',
                        args: [EthereumL1Bridge],
                        blockNumber,
                    })
                    const multisigBalancefrxETH = await chains[chainName].client.readContract({
                        address: tokenfrxeth,
                        abi: ERC20ABI,
                        functionName: 'balanceOf',
                        args: [EthereumMultisig],
                        blockNumber,
                    })

                    chainResults.push({
                        chain: chainName + '-l1bridge',
                        blockNumber: blockNumber.toString(),
                        token: 'frxETH',
                        rawSupply: l1BridgeBalancefrxETH,
                        supply: formatTokenAmount(l1BridgeBalancefrxETH),
                    })
                    chainResults.push({
                        chain: chainName + '-multisig',
                        blockNumber: blockNumber.toString(),
                        token: 'frxETH',
                        rawSupply: multisigBalancefrxETH,
                        supply: formatTokenAmount(multisigBalancefrxETH),
                    })
                    const l1BridgeBalancesfrxETH = await chains[chainName].client.readContract({
                        address: tokensfrxeth,
                        abi: ERC20ABI,
                        functionName: 'balanceOf',
                        args: [EthereumL1Bridge],
                        blockNumber,
                    })
                    chainResults.push({
                        chain: chainName + '-l1bridge',
                        blockNumber: blockNumber.toString(),
                        token: 'sfrxETH',
                        rawSupply: l1BridgeBalancesfrxETH,
                        supply: formatTokenAmount(l1BridgeBalancesfrxETH),
                    })
                    const l1BridgeBalancefrxUSD = await chains[chainName].client.readContract({
                        address: tokenfrxusd,
                        abi: ERC20ABI,
                        functionName: 'balanceOf',
                        args: [EthereumL1Bridge],
                        blockNumber,
                    })
                    chainResults.push({
                        chain: chainName + '-l1bridge',
                        blockNumber: blockNumber.toString(),
                        token: 'frxUSD',
                        rawSupply: l1BridgeBalancefrxUSD,
                        supply: formatTokenAmount(l1BridgeBalancefrxUSD),
                    })
                    const l1BridgeBalancesfrxUSD = await chains[chainName].client.readContract({
                        address: tokenfrxusd,
                        abi: ERC20ABI,
                        functionName: 'balanceOf',
                        args: [EthereumL1Bridge],
                        blockNumber,
                    })
                    chainResults.push({
                        chain: chainName + '-l1bridge',
                        blockNumber: blockNumber.toString(),
                        token: 'sfrxUSD',
                        rawSupply: l1BridgeBalancesfrxUSD,
                        supply: formatTokenAmount(l1BridgeBalancesfrxUSD),
                    })
                } else {
                    const tokenwfrax = await chains[chainName].client.readContract({
                        address: ofts[chainName]['wfrax'].address,
                        abi: ofts[chainName]['wfrax'].abi,
                        functionName: 'token',
                    })
                    const wfraxBal = await chains[chainName].client.readContract({
                        address: tokenwfrax,
                        abi: ERC20ABI,
                        functionName: 'balanceOf',
                        args: [ofts[chainName]['wfrax'].address],
                        blockNumber,
                    })
                    const totalSupplywfrax = await chains[chainName].client.readContract({
                        address: tokenwfrax,
                        abi: ERC20ABI,
                        functionName: 'totalSupply',
                        blockNumber,
                    })

                    chainResults.push({
                        chain: chainName,
                        blockNumber: blockNumber.toString(),
                        token: 'wfrax',
                        rawSupply: totalSupplywfrax,
                        supply: formatTokenAmount(totalSupplywfrax),
                    })
                    chainResults.push({
                        chain: chainName + '-lockbox',
                        blockNumber: blockNumber.toString(),
                        token: 'wfrax',
                        rawSupply: wfraxBal,
                        supply: formatTokenAmount(wfraxBal),
                    })
                }
            } catch (error) {
                console.error(`Error processing ${chainName}:`, error)
            }
        } else if (chainName === 'solana') {
            try {
                const frxusdmintAddress = new PublicKey(solanaOFTs.frxUSD.mint)
                let frxusdsupply = await chains[chainName].client.getTokenSupply(frxusdmintAddress)
                const totalTransferToFraxtalfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['frxUSD'].address,
                    abi: ofts.fraxtal['frxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromFraxtalfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['frxUSD'].address,
                    abi: ofts.fraxtal['frxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromEthereumfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['frxUSD'].address,
                    abi: ofts.ethereum['frxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferToEthereumfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['frxUSD'].address,
                    abi: ofts.ethereum['frxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })
                chainResults.push({
                    chain: chainName,
                    token: 'frxUSD',
                    rawSupply: parseUnits(frxusdsupply.value.amount, 9).toString(),
                    totalTransferToFraxtal: totalTransferToFraxtalfrxusd,
                    totalTransferFromFraxtal: totalTransferFromFraxtalfrxusd,
                    totalTransferToEthereum: totalTransferToEthereumfrxusd,
                    totalTransferFromEthereum: totalTransferFromEthereumfrxusd,
                    supply: frxusdsupply.value.uiAmount?.toString() || '0',
                })
                const sfrxusdmintAddress = new PublicKey(solanaOFTs.sfrxUSD.mint)
                let sfrxusdsupply = await chains[chainName].client.getTokenSupply(sfrxusdmintAddress)
                const totalTransferToFraxtalsfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['sfrxUSD'].address,
                    abi: ofts.fraxtal['sfrxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromFraxtalsfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['sfrxUSD'].address,
                    abi: ofts.fraxtal['sfrxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromEthereumsfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['sfrxUSD'].address,
                    abi: ofts.ethereum['sfrxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferToEthereumsfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['sfrxUSD'].address,
                    abi: ofts.ethereum['sfrxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })
                chainResults.push({
                    chain: chainName,
                    token: 'sfrxUSD',
                    totalTransferToFraxtal: totalTransferToFraxtalsfrxusd,
                    totalTransferFromFraxtal: totalTransferFromFraxtalsfrxusd,
                    totalTransferToEthereum: totalTransferToEthereumsfrxusd,
                    totalTransferFromEthereum: totalTransferFromEthereumsfrxusd,
                    rawSupply: parseUnits(sfrxusdsupply.value.amount, 9).toString(),
                    supply: sfrxusdsupply.value.uiAmount?.toString() || '0',
                })

                const frxethmintAddress = new PublicKey(solanaOFTs.frxETH.mint)
                let frxethsupply = await chains[chainName].client.getTokenSupply(frxethmintAddress)
                chainResults.push({
                    chain: chainName,
                    token: 'frxETH',
                    rawSupply: parseUnits(frxethsupply.value.amount, 9).toString(),
                    supply: frxethsupply.value.uiAmount?.toString() || '0',
                })

                const sfrxethmintAddress = new PublicKey(solanaOFTs.sfrxETH.mint)
                let sfrxethsupply = await chains[chainName].client.getTokenSupply(sfrxethmintAddress)
                chainResults.push({
                    chain: chainName,
                    token: 'sfrxETH',
                    rawSupply: parseUnits(sfrxethsupply.value.amount, 9).toString(),
                    supply: sfrxethsupply.value.uiAmount?.toString() || '0',
                })

                const wfraxmintAddress = new PublicKey(solanaOFTs.wfrax.mint)
                let wfraxsupply = await chains[chainName].client.getTokenSupply(wfraxmintAddress)
                chainResults.push({
                    chain: chainName,
                    token: 'wfrax',
                    rawSupply: parseUnits(wfraxsupply.value.amount, 9).toString(),
                    supply: wfraxsupply.value.uiAmount?.toString() || '0',
                })

                const fpimintAddress = new PublicKey(solanaOFTs.fpi.mint)
                let fpisupply = await chains[chainName].client.getTokenSupply(fpimintAddress)
                const totalTransferToFraxtalfpi = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['fpi'].address,
                    abi: ofts.fraxtal['fpi'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromFraxtalfpi = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['fpi'].address,
                    abi: ofts.fraxtal['fpi'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromEthereumfpi = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['fpi'].address,
                    abi: ofts.ethereum['fpi'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferToEthereumfpi = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['fpi'].address,
                    abi: ofts.ethereum['fpi'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })
                chainResults.push({
                    chain: chainName,
                    token: 'fpi',
                    rawSupply: parseUnits(fpisupply.value.amount, 9).toString(),
                    totalTransferToFraxtal: totalTransferToFraxtalfpi,
                    totalTransferFromFraxtal: totalTransferFromFraxtalfpi,
                    totalTransferToEthereum: totalTransferToEthereumfpi,
                    totalTransferFromEthereum: totalTransferFromEthereumfpi,
                    supply: fpisupply.value.uiAmount?.toString() || '0',
                })
            } catch (error) {
                console.error(`Error processing ${chainName}:`, error)
            }
        } else if (chainName === 'aptos' || chainName === 'movement') {
            try {
                const totalSupplyfpi = await chains[chainName].client.view({
                    payload: {
                        function: `${aptosMovementOFTs.fpi.oft}::oft_fa::supply`,
                    },
                })

                const totalTransferToFraxtalfpi = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['fpi'].address,
                    abi: ofts.fraxtal['fpi'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromFraxtalfpi = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['fpi'].address,
                    abi: ofts.fraxtal['fpi'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromEthereumfpi = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['fpi'].address,
                    abi: ofts.ethereum['fpi'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferToEthereumfpi = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['fpi'].address,
                    abi: ofts.ethereum['fpi'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })

                chainResults.push({
                    chain: chainName,
                    token: 'fpi',
                    rawSupply: parseUnits(totalSupplyfpi[0] as string, 12).toString(),
                    totalTransferToFraxtal: totalTransferToFraxtalfpi,
                    totalTransferFromFraxtal: totalTransferFromFraxtalfpi,
                    totalTransferToEthereum: totalTransferToEthereumfpi,
                    totalTransferFromEthereum: totalTransferFromEthereumfpi,
                    supply: formatTokenAmount(BigInt(parseUnits(totalSupplyfpi[0] as string, 12).toString())),
                })

                const totalSupplyfrxusd = await chains[chainName].client.view({
                    payload: {
                        function: `${aptosMovementOFTs.frxUSD.oft}::oft_fa::supply`,
                    },
                })
                const totalTransferToFraxtalfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['frxUSD'].address,
                    abi: ofts.fraxtal['frxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromFraxtalfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['frxUSD'].address,
                    abi: ofts.fraxtal['frxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromEthereumfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['frxUSD'].address,
                    abi: ofts.ethereum['frxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferToEthereumfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['frxUSD'].address,
                    abi: ofts.ethereum['frxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })

                chainResults.push({
                    chain: chainName,
                    token: 'frxUSD',
                    rawSupply: parseUnits(totalSupplyfrxusd[0] as string, 12).toString(),
                    totalTransferToFraxtal: totalTransferToFraxtalfrxusd,
                    totalTransferFromFraxtal: totalTransferFromFraxtalfrxusd,
                    totalTransferToEthereum: totalTransferToEthereumfrxusd,
                    totalTransferFromEthereum: totalTransferFromEthereumfrxusd,
                    supply: formatTokenAmount(BigInt(parseUnits(totalSupplyfrxusd[0] as string, 12).toString())),
                })
                console.log("totalSupplyfrxusd[0] ", totalSupplyfrxusd[0])
                const totalSupplysfrxusd = await chains[chainName].client.view({
                    payload: {
                        function: `${aptosMovementOFTs.sfrxUSD.oft}::oft_fa::supply`,
                    },
                })

                const totalTransferToFraxtalsfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['sfrxUSD'].address,
                    abi: ofts.fraxtal['sfrxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromFraxtalsfrxusd = await chains.fraxtal.client.readContract({
                    address: ofts.fraxtal['sfrxUSD'].address,
                    abi: ofts.fraxtal['sfrxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferFromEthereumsfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['sfrxUSD'].address,
                    abi: ofts.ethereum['sfrxUSD'].abi,
                    functionName: 'totalTransferFrom',
                    args: [chains[chainName].peerId],
                })
                const totalTransferToEthereumsfrxusd = await chains.ethereum.client.readContract({
                    address: ofts.ethereum['sfrxUSD'].address,
                    abi: ofts.ethereum['sfrxUSD'].abi,
                    functionName: 'totalTransferTo',
                    args: [chains[chainName].peerId],
                })

                chainResults.push({
                    chain: chainName,
                    token: 'sfrxUSD',
                    rawSupply: parseUnits(totalSupplysfrxusd[0] as string, 12).toString(),
                    totalTransferToFraxtal: totalTransferToFraxtalsfrxusd,
                    totalTransferFromFraxtal: totalTransferFromFraxtalsfrxusd,
                    totalTransferToEthereum: totalTransferToEthereumsfrxusd,
                    totalTransferFromEthereum: totalTransferFromEthereumsfrxusd,
                    supply: formatTokenAmount(BigInt(parseUnits(totalSupplysfrxusd[0] as string, 12))),
                })

                const totalSupplyfrxeth = await chains[chainName].client.view({
                    payload: {
                        function: `${aptosMovementOFTs.frxETH.oft}::oft_fa::supply`,
                    },
                })

                chainResults.push({
                    chain: chainName,
                    token: 'frxETH',
                    rawSupply: parseUnits(totalSupplyfrxeth[0] as string, 12).toString(),
                    supply: totalSupplyfrxeth[0],
                })

                const totalSupplysfrxeth = await chains[chainName].client.view({
                    payload: {
                        function: `${aptosMovementOFTs.sfrxETH.oft}::oft_fa::supply`,
                    },
                })

                chainResults.push({
                    chain: chainName,
                    token: 'sfrxETH',
                    rawSupply: parseUnits(totalSupplysfrxeth[0] as string, 12).toString(),
                    supply: totalSupplysfrxeth[0],
                })

                const totalSupplywfrax = await chains[chainName].client.view({
                    payload: {
                        function: `${aptosMovementOFTs.wfrax.oft}::oft_fa::supply`,
                    },
                })

                chainResults.push({
                    chain: chainName,
                    token: 'wfrax',
                    rawSupply: parseUnits(totalSupplywfrax[0] as string, 12).toString(),
                    supply: totalSupplywfrax[0],
                })
            } catch (error) {
                console.error(`Error processing ${chainName}:`, error)
            }
        } else {
            console.error(`Unknown chain: ${chainName}`)
        }

        return chainResults
    })

    // Wait for all chains to complete
    const allChainResults = await Promise.all(chainProcessingPromises)

    // Flatten the results
    for (const chainResults of allChainResults) {
        results.push(...chainResults)
    }

    // Sort results by chain name and then by token for consistency
    results.sort((a, b) => {
        if (a.chain !== b.chain) {
            return a.chain.localeCompare(b.chain)
        }
        return a.token.localeCompare(b.token)
    })

    // Generate CSV output
    console.log('Chain,Block Number,Token,Supply,fraxtal.totalTransferTo,fraxtal.totalTransferFrom,ethereum.totalTransferTo,ethereum.totalTransferFrom')
    for (const result of results) {
        if (result.token === 'frxUSD') {
            const blockNumber = result.blockNumber || ''
            const totalTransferToFraxtal = result.totalTransferToFraxtal || ''
            const totalTransferFromFraxtal = result.totalTransferFromFraxtal || ''
            const totalTransferToEthereum = result.totalTransferToEthereum || ''
            const totalTransferFromEthereum = result.totalTransferFromEthereum || ''
            console.log(`${result.chain},${blockNumber},${result.token},${result.supply},${totalTransferToFraxtal},${totalTransferFromFraxtal},${totalTransferToEthereum},${totalTransferFromEthereum}`)
        }
    }

    // Generate CSV output
    console.log('Chain,Block Number,Token,Supply,fraxtal.totalTransferTo,fraxtal.totalTransferFrom,ethereum.totalTransferTo,ethereum.totalTransferFrom')
    for (const result of results) {
        if (result.token === 'sfrxUSD') {
            const blockNumber = result.blockNumber || ''
            const totalTransferToFraxtal = result.totalTransferToFraxtal || ''
            const totalTransferFromFraxtal = result.totalTransferFromFraxtal || ''
            const totalTransferToEthereum = result.totalTransferToEthereum || ''
            const totalTransferFromEthereum = result.totalTransferFromEthereum || ''
            console.log(`${result.chain},${blockNumber},${result.token},${result.supply},${totalTransferToFraxtal},${totalTransferFromFraxtal},${totalTransferToEthereum},${totalTransferFromEthereum}`)
        }
    }

    // Generate CSV output
    console.log('Chain,Block Number,Token,Supply,fraxtal.totalTransferTo,fraxtal.totalTransferFrom,ethereum.totalTransferTo,ethereum.totalTransferFrom')
    for (const result of results) {
        if (result.token === 'fpi') {
            const blockNumber = result.blockNumber || ''
            const totalTransferToFraxtal = result.totalTransferToFraxtal || ''
            const totalTransferFromFraxtal = result.totalTransferFromFraxtal || ''
            const totalTransferToEthereum = result.totalTransferToEthereum || ''
            const totalTransferFromEthereum = result.totalTransferFromEthereum || ''
            console.log(`${result.chain},${blockNumber},${result.token},${result.supply},${totalTransferToFraxtal},${totalTransferFromFraxtal},${totalTransferToEthereum},${totalTransferFromEthereum}`)
        }
    }

    // setInitialTotalSupply msig
    const fraxtalSetInitialSupplyMsigfpi: TransactionBatch = {
        chainId: 252,
        createdAt: Math.floor(new Date().getTime() / 1000),
        meta: {
            description: '',
            name: 'Transactions Batch',
        },
        transactions: [],
        version: '1.0',
    }
    const fraxtalSetInitialSupplyMsigfrxusd: TransactionBatch = {
        chainId: 252,
        createdAt: Math.floor(new Date().getTime() / 1000),
        meta: {
            description: '',
            name: 'Transactions Batch',
        },
        transactions: [],
        version: '1.0',
    }

    const fraxtalSetInitialSupplyMsigsfrxusd: TransactionBatch = {
        chainId: 252,
        createdAt: Math.floor(new Date().getTime() / 1000),
        meta: {
            description: '',
            name: 'Transactions Batch',
        },
        transactions: [],
        version: '1.0',
    }

    // const ethereumSetInitialSupplyMsigfpi: TransactionBatch = {
    //     chainId: 1,
    //     createdAt: Math.floor(new Date().getTime() / 1000),
    //     meta: {
    //         description: '',
    //         name: 'Transactions Batch',
    //     },
    //     transactions: [],
    //     version: '1.0',
    // }
    // const ethereumSetInitialSupplyMsigfrxusd: TransactionBatch = {
    //     chainId: 1,
    //     createdAt: Math.floor(new Date().getTime() / 1000),
    //     meta: {
    //         description: '',
    //         name: 'Transactions Batch',
    //     },
    //     transactions: [],
    //     version: '1.0',
    // }
    // const ethereumSetInitialSupplyMsigsfrxusd: TransactionBatch = {
    //     chainId: 1,
    //     createdAt: Math.floor(new Date().getTime() / 1000),
    //     meta: {
    //         description: '',
    //         name: 'Transactions Batch',
    //     },
    //     transactions: [],
    //     version: '1.0',
    // }

    let frxUSDSupply = BigInt(0)
    results.forEach((result) => {
        if (
            result.chain !== 'ethereum-l1bridge' &&
            result.chain !== 'ethereum-lockbox' &&
            result.chain !== 'fraxtal-lockbox'
        ) {
            if (result.token === 'fpi' || result.token === 'frxUSD' || result.token === 'sfrxUSD') {
                try {
                    if (result.chain !== 'fraxtal' && result.chain !== 'ethereum') {
                        const initialTotalSupply = BigInt(result.rawSupply) + BigInt(result.totalTransferFromFraxtal as string) - BigInt(result.totalTransferToFraxtal as string)
                            + BigInt(result.totalTransferFromEthereum as string) - BigInt(result.totalTransferToEthereum as string)
                        const encodedData = encodeFunctionData({
                            abi: setInitialTotalSupplyAbi,
                            args: [chains[result.chain].peerId, initialTotalSupply],
                        })
                        if (initialTotalSupply > 0) {
                            if (result.token === 'fpi') {
                                fraxtalSetInitialSupplyMsigfpi.transactions.push({
                                    data: encodedData,
                                    operation: '0',
                                    to: ofts['fraxtal'].fpi.address,
                                    value: '0',
                                })
                            }
                            if (result.token === 'frxUSD') {
                                frxUSDSupply += BigInt(result.rawSupply)
                                console.log(result.rawSupply)
                                fraxtalSetInitialSupplyMsigfrxusd.transactions.push({
                                    data: encodedData,
                                    operation: '0',
                                    to: ofts['fraxtal'].frxUSD.address,
                                    value: '0',
                                })
                            }
                            if (result.token === 'sfrxUSD') {
                                fraxtalSetInitialSupplyMsigsfrxusd.transactions.push({
                                    data: encodedData,
                                    operation: '0',
                                    to: ofts['fraxtal'].sfrxUSD.address,
                                    value: '0',
                                })
                            }
                        }
                    }
                    // if (result.chain !== 'ethereum') {
                    //     if (result.token === 'fpi') {
                    //         ethereumSetInitialSupplyMsigfpi.transactions.push({
                    //             data: encodedData,
                    //             operation: '0',
                    //             to: ofts['ethereum'].fpi.address,
                    //             value: '0',
                    //         })
                    //     }
                    //     if (result.token === 'frxUSD') {
                    //         ethereumSetInitialSupplyMsigfrxusd.transactions.push({
                    //             data: encodedData,
                    //             operation: '0',
                    //             to: ofts['ethereum'].frxUSD.address,
                    //             value: '0',
                    //         })
                    //     }
                    //     if (result.token === 'sfrxUSD') {
                    //         ethereumSetInitialSupplyMsigsfrxusd.transactions.push({
                    //             data: encodedData,
                    //             operation: '0',
                    //             to: ofts['ethereum'].sfrxUSD.address,
                    //             value: '0',
                    //         })
                    //     }
                    // }
                } catch (e) {
                    console.error(`${result.chain}: `, e)
                }
            }
        }
    })

    console.log("frxUSDSupply : ", frxUSDSupply)

    fs.writeFileSync('fraxtalSetInitialSupplyMsig-fpi.json', JSON.stringify(fraxtalSetInitialSupplyMsigfpi, null, 2))
    fs.writeFileSync(
        'fraxtalSetInitialSupplyMsig-frxusd.json',
        JSON.stringify(fraxtalSetInitialSupplyMsigfrxusd, null, 2)
    )
    fs.writeFileSync(
        'fraxtalSetInitialSupplyMsig-sfrxusd.json',
        JSON.stringify(fraxtalSetInitialSupplyMsigsfrxusd, null, 2)
    )
    // fs.writeFileSync('ethereumSetInitialSupplyMsig-fpi.json', JSON.stringify(ethereumSetInitialSupplyMsigfpi, null, 2))
    // fs.writeFileSync(
    //     'ethereumSetInitialSupplyMsig-frxusd.json',
    //     JSON.stringify(ethereumSetInitialSupplyMsigfrxusd, null, 2)
    // )
    // fs.writeFileSync(
    //     'ethereumSetInitialSupplyMsig-sfrxusd.json',
    //     JSON.stringify(ethereumSetInitialSupplyMsigsfrxusd, null, 2)
    // )
}

main().catch(console.error)
