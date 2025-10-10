import { ERC20ABI } from "./abis/ERC20";
import { chains } from "./chains";
import { ofts, solanaOFTs } from "./oft";
import { PublicKey } from "@solana/web3.js";

const EthereumPortal = "0x36cb65c1967A0Fb0EEE11569C51C2f2aA1Ca6f6D";
const EthereumL1Bridge = "0x34C0bD5877A5Ee7099D0f5688D65F4bB9158BDE2";
const EthereumMultisig = "0xe0d7755252873c4eF5788f7f45764E0e17610508";
const fxsToken = "0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0";

interface TokenSupplyData {
    chain: string;
    blockNumber?: string;
    token: string;
    supply: string;
}

// Convert wei (raw token amount) to decimal format by dividing by 10^18
function formatTokenAmount(amount: bigint | string | number): string {
    if (typeof amount === 'string' || typeof amount === 'number') {
        // Handle already decimal values (like from Solana)
        return amount.toString();
    }
    
    // Convert BigInt wei to decimal by dividing by 10^18
    const divisor = 10n ** 18n;
    const wholePart = amount / divisor;
    const fractionalPart = amount % divisor;
    
    // Convert to decimal string with up to 18 decimal places
    const fractionalStr = fractionalPart.toString().padStart(18, '0');
    const trimmedFractional = fractionalStr.replace(/0+$/, ''); // Remove trailing zeros
    
    if (trimmedFractional === '') {
        return wholePart.toString();
    } else {
        return `${wholePart}.${trimmedFractional}`;
    }
}

async function main() {
    const results: TokenSupplyData[] = [];
    
    const chainProcessingPromises = Object.keys(chains).map(async (chainName) => {
        const chainResults: TokenSupplyData[] = [];
        
        if (chainName !== "fraxtal" && chainName !== "ethereum" && chainName !== "solana") {
            try {
                const blockNumber = await chains[chainName].client.getBlockNumber()
                
                const totalSupplyfpi = await chains[chainName].client.readContract({
                    address: ofts[chainName]["fpi"].address,
                    abi: ofts[chainName]["fpi"].abi,
                    functionName: "totalSupply",
                    blockNumber,
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "fpi",
                    supply: formatTokenAmount(totalSupplyfpi)
                });

                const totalSupplyfrxeth = await chains[chainName].client.readContract({
                    address: ofts[chainName]["frxETH"].address,
                    abi: ofts[chainName]["frxETH"].abi,
                    functionName: "totalSupply",
                    blockNumber
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "frxETH",
                    supply: formatTokenAmount(totalSupplyfrxeth)
                });

                const totalSupplyfrxusd = await chains[chainName].client.readContract({
                    address: ofts[chainName]["frxUSD"].address,
                    abi: ofts[chainName]["frxUSD"].abi,
                    functionName: "totalSupply",
                    blockNumber
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "frxUSD",
                                        supply: formatTokenAmount(totalSupplyfrxusd)
                });

                const totalSupplysfrxeth = await chains[chainName].client.readContract({
                    address: ofts[chainName]["sfrxETH"].address,
                    abi: ofts[chainName]["sfrxETH"].abi,
                    functionName: "totalSupply",
                    blockNumber
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "sfrxETH",
                    supply: formatTokenAmount(totalSupplysfrxeth)
                });

                const totalSupplysfrxusd = await chains[chainName].client.readContract({
                    address: ofts[chainName]["sfrxUSD"].address,
                    abi: ofts[chainName]["sfrxUSD"].abi,
                    functionName: "totalSupply",
                    blockNumber
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "sfrxUSD",
                    supply: formatTokenAmount(totalSupplysfrxusd)
                });

                const totalSupplywfrax = await chains[chainName].client.readContract({
                    address: ofts[chainName]["wfrax"].address,
                    abi: ofts[chainName]["wfrax"].abi,
                    functionName: "totalSupply",
                    blockNumber
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "wfrax",
                    supply: formatTokenAmount(totalSupplywfrax)
                });

            } catch (error) {
                console.error(`Error processing ${chainName}:`, error);
            }
        } else if (chainName === "ethereum" || chainName === "fraxtal") {
            // except wfrax, all are lockbox
            try {
                const blockNumber = await chains[chainName].client.getBlockNumber()
                
                const tokenfpi = await chains[chainName].client.readContract({
                    address: ofts[chainName]["fpi"].address,
                    abi: ofts[chainName]["fpi"].abi,
                    functionName: "token"
                })
                const fpiBal = await chains[chainName].client.readContract({
                    address: tokenfpi,
                    abi: ERC20ABI,
                    functionName: "balanceOf",
                    args: [ofts[chainName]["fpi"].address],
                    blockNumber
                })
                chainResults.push({
                    chain: chainName+"-lockbox",
                    blockNumber: blockNumber.toString(),
                    token: "fpi",
                    supply: formatTokenAmount(fpiBal)
                });
                const totalSupplyfpi = await chains[chainName].client.readContract({
                    address: tokenfpi,
                    abi: ERC20ABI,
                    functionName: "totalSupply",
                    blockNumber
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "fpi",
                    supply: formatTokenAmount(totalSupplyfpi)
                });

                const tokenfrxeth = await chains[chainName].client.readContract({
                    address: ofts[chainName]["frxETH"].address,
                    abi: ofts[chainName]["frxETH"].abi,
                    functionName: "token"
                })
                const frxETHBal = await chains[chainName].client.readContract({
                    address: tokenfrxeth,
                    abi: ERC20ABI,
                    functionName: "balanceOf",
                    args: [ofts[chainName]["frxETH"].address],
                    blockNumber
                })

                const totalSupplyfrxETH = await chains[chainName].client.readContract({
                    address: tokenfrxeth,
                    abi: ERC20ABI,
                    functionName: "totalSupply",
                    blockNumber
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "frxETH",
                    supply: formatTokenAmount(totalSupplyfrxETH)
                });

                chainResults.push({
                    chain: chainName+"-lockbox",
                    blockNumber: blockNumber.toString(),
                    token: "frxETH",
                    supply: formatTokenAmount(frxETHBal)
                });

                const tokenfrxusd = await chains[chainName].client.readContract({
                    address: ofts[chainName]["frxUSD"].address,
                    abi: ofts[chainName]["frxUSD"].abi,
                    functionName: "token"
                })
                const frxUSDBal = await chains[chainName].client.readContract({
                    address: tokenfrxusd,
                    abi: ERC20ABI,
                    functionName: "balanceOf",
                    args: [ofts[chainName]["frxUSD"].address],
                    blockNumber
                })

                const totalSupplyfrxUSD = await chains[chainName].client.readContract({
                    address: tokenfrxusd,
                    abi: ERC20ABI,
                    functionName: "totalSupply",
                    blockNumber
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "frxUSD",
                    supply: formatTokenAmount(totalSupplyfrxUSD)
                });

                chainResults.push({
                    chain: chainName+"-lockbox",
                    blockNumber: blockNumber.toString(),
                    token: "frxUSD",
                    supply: formatTokenAmount(frxUSDBal)
                });

                const tokensfrxeth = await chains[chainName].client.readContract({
                    address: ofts[chainName]["sfrxETH"].address,
                    abi: ofts[chainName]["sfrxETH"].abi,
                    functionName: "token"
                })
                const sfrxethBal = await chains[chainName].client.readContract({
                    address: tokensfrxeth,
                    abi: ERC20ABI,
                    functionName: "balanceOf",
                    args: [ofts[chainName]["sfrxETH"].address],
                    blockNumber
                })

                const totalSupplysfrxeth = await chains[chainName].client.readContract({
                    address: tokensfrxeth,
                    abi: ERC20ABI,
                    functionName: "totalSupply",
                    blockNumber
                })
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "sfrxETH",
                    supply: formatTokenAmount(totalSupplysfrxeth)
                });
                
                chainResults.push({
                    chain: chainName+"-lockbox",
                    blockNumber: blockNumber.toString(),
                    token: "sfrxETH",
                    supply: formatTokenAmount(sfrxethBal)
                });

                const tokensfrxusd = await chains[chainName].client.readContract({
                    address: ofts[chainName]["sfrxUSD"].address,
                    abi: ofts[chainName]["sfrxUSD"].abi,
                    functionName: "token"
                })
                const sfrxusdBal = await chains[chainName].client.readContract({
                    address: tokensfrxusd,
                    abi: ERC20ABI,
                    functionName: "balanceOf",
                    args: [ofts[chainName]["sfrxUSD"].address],
                    blockNumber
                })
                const totalSupplysfrxusd = await chains[chainName].client.readContract({
                    address: tokensfrxusd,
                    abi: ERC20ABI,
                    functionName: "totalSupply",
                    blockNumber
                })      
                chainResults.push({
                    chain: chainName,
                    blockNumber: blockNumber.toString(),
                    token: "sfrxUSD",
                    supply: formatTokenAmount(totalSupplysfrxusd)
                });      
                chainResults.push({
                    chain: chainName+"-lockbox",
                    blockNumber: blockNumber.toString(),
                    token: "sfrxUSD",
                    supply: formatTokenAmount(sfrxusdBal)
                });

                if (chainName === "ethereum") {
                    const totalSupplywfrax = await chains[chainName].client.readContract({
                        address: ofts[chainName]["wfrax"].address,
                        abi: ofts[chainName]["wfrax"].abi,
                        functionName: "totalSupply",
                        blockNumber
                    })
                    const portalBalancefxs = await chains[chainName].client.readContract({
                        address: fxsToken,
                        abi: ERC20ABI,
                        functionName: "balanceOf",
                        args: [EthereumPortal],
                        blockNumber
                    })
                    chainResults.push({
                        chain: chainName,
                        blockNumber: blockNumber.toString(),
                        token: "wfrax",
                        supply: formatTokenAmount(totalSupplywfrax)
                    });
                    chainResults.push({
                        chain: chainName+"-portal",
                        blockNumber: blockNumber.toString(),
                        token: "fxs",
                        supply: formatTokenAmount(portalBalancefxs)
                    });

                    const l1BridgeBalancefpi = await chains[chainName].client.readContract({
                        address: tokenfpi,
                        abi: ERC20ABI,
                        functionName: "balanceOf",
                        args: [EthereumL1Bridge],
                        blockNumber
                    });
                    chainResults.push({
                        chain: chainName+"-l1bridge",
                        blockNumber: blockNumber.toString(),
                        token: "fpi",
                        supply: formatTokenAmount(l1BridgeBalancefpi)
                    });
                    const l1BridgeBalancefrxETH = await chains[chainName].client.readContract({
                        address: tokenfrxeth,
                        abi: ERC20ABI,
                        functionName: "balanceOf",
                        args: [EthereumL1Bridge],
                        blockNumber
                    });
                    const multisigBalancefrxETH = await chains[chainName].client.readContract({
                        address: tokenfrxeth,
                        abi: ERC20ABI,
                        functionName: "balanceOf",
                        args: [EthereumMultisig],
                        blockNumber
                    });
                    
                    chainResults.push({
                        chain: chainName+"-l1bridge",
                        blockNumber: blockNumber.toString(),
                        token: "frxETH",
                        supply: formatTokenAmount(l1BridgeBalancefrxETH)
                    });
                    chainResults.push({
                        chain: chainName+"-multisig",
                        blockNumber: blockNumber.toString(),
                        token: "frxETH",
                        supply: formatTokenAmount(multisigBalancefrxETH)
                    });
                    const l1BridgeBalancesfrxETH = await chains[chainName].client.readContract({
                        address: tokensfrxeth,
                        abi: ERC20ABI,
                        functionName: "balanceOf",
                        args: [EthereumL1Bridge],
                        blockNumber
                    });
                    chainResults.push({
                        chain: chainName+"-l1bridge",
                        blockNumber: blockNumber.toString(),
                        token: "sfrxETH",
                        supply: formatTokenAmount(l1BridgeBalancesfrxETH)
                    });
                    const l1BridgeBalancefrxUSD = await chains[chainName].client.readContract({
                        address: tokenfrxusd,
                        abi: ERC20ABI,
                        functionName: "balanceOf",
                        args: [EthereumL1Bridge],
                        blockNumber
                    });
                    chainResults.push({
                        chain: chainName+"-l1bridge",
                        blockNumber: blockNumber.toString(),
                        token: "frxUSD",
                        supply: formatTokenAmount(l1BridgeBalancefrxUSD)
                    });
                    const l1BridgeBalancesfrxUSD = await chains[chainName].client.readContract({
                        address: tokenfrxusd,
                        abi: ERC20ABI,
                        functionName: "balanceOf",
                        args: [EthereumL1Bridge],
                        blockNumber
                    });
                    chainResults.push({
                        chain: chainName+"-l1bridge",
                        blockNumber: blockNumber.toString(),
                        token: "sfrxUSD",
                        supply: formatTokenAmount(l1BridgeBalancesfrxUSD)
                    });


                } else {
                    const tokenwfrax = await chains[chainName].client.readContract({
                        address: ofts[chainName]["wfrax"].address,
                        abi: ofts[chainName]["wfrax"].abi,
                        functionName: "token"
                    })
                    const wfraxBal = await chains[chainName].client.readContract({
                        address: tokenwfrax,
                        abi: ERC20ABI,
                        functionName: "balanceOf",
                        args: [ofts[chainName]["wfrax"].address],
                        blockNumber
                    })
                    const totalSupplywfrax = await chains[chainName].client.readContract({
                        address: tokenwfrax,
                        abi: ERC20ABI,
                        functionName: "totalSupply",
                        blockNumber
                    })
                    
                    chainResults.push({
                        chain: chainName,
                        blockNumber: blockNumber.toString(),
                        token: "wfrax",
                        supply: formatTokenAmount(totalSupplywfrax)
                    });                    
                    chainResults.push({
                        chain: chainName+"-lockbox",
                        blockNumber: blockNumber.toString(),
                        token: "wfrax",
                        supply: formatTokenAmount(wfraxBal)
                    });
                }

            } catch (error) {
                console.error(`Error processing ${chainName}:`, error);
            }
        } else if (chainName === "solana") {
            try {
                const frxusdmintAddress = new PublicKey(solanaOFTs.frxUSD.mint);
                let frxusdsupply = await chains[chainName].client.getTokenSupply(frxusdmintAddress);
                chainResults.push({
                    chain: chainName,
                    token: "frxUSD",
                    supply: frxusdsupply.value.uiAmount?.toString() || "0"
                });

                const sfrxusdmintAddress = new PublicKey(solanaOFTs.sfrxUSD.mint);
                let sfrxusdsupply = await chains[chainName].client.getTokenSupply(sfrxusdmintAddress);
                chainResults.push({
                    chain: chainName,
                    token: "sfrxUSD",
                    supply: sfrxusdsupply.value.uiAmount?.toString() || "0"
                });

                const frxethmintAddress = new PublicKey(solanaOFTs.frxETH.mint);
                let frxethsupply = await chains[chainName].client.getTokenSupply(frxethmintAddress);
                chainResults.push({
                    chain: chainName,
                    token: "frxETH",
                    supply: frxethsupply.value.uiAmount?.toString() || "0"
                });

                const sfrxethmintAddress = new PublicKey(solanaOFTs.sfrxETH.mint);
                let sfrxethsupply = await chains[chainName].client.getTokenSupply(sfrxethmintAddress);
                chainResults.push({
                    chain: chainName,
                    token: "sfrxETH",
                    supply: sfrxethsupply.value.uiAmount?.toString() || "0"
                });

                const wfraxmintAddress = new PublicKey(solanaOFTs.wfrax.mint);
                let wfraxsupply = await chains[chainName].client.getTokenSupply(wfraxmintAddress);
                chainResults.push({
                    chain: chainName,
                    token: "wfrax",
                    supply: wfraxsupply.value.uiAmount?.toString() || "0"
                });

                const fpimintAddress = new PublicKey(solanaOFTs.fpi.mint);
                let fpisupply = await chains[chainName].client.getTokenSupply(fpimintAddress);
                chainResults.push({
                    chain: chainName,
                    token: "fpi",
                    supply: fpisupply.value.uiAmount?.toString() || "0"
                });

            } catch (error) {
                console.error(`Error processing ${chainName}:`, error);
            }
        } else {
            console.error(`Unknown chain: ${chainName}`);
        }
        
        return chainResults;
    });

    // Wait for all chains to complete
    const allChainResults = await Promise.all(chainProcessingPromises);
    
    // Flatten the results
    for (const chainResults of allChainResults) {
        results.push(...chainResults);
    }

    // Generate CSV output
    console.log("Chain,Block Number,Token,Supply");
    
    // Sort results by chain name and then by token for consistency
    results.sort((a, b) => {
        if (a.chain !== b.chain) {
            return a.chain.localeCompare(b.chain);
        }
        return a.token.localeCompare(b.token);
    });
    
    for (const result of results) {
        const blockNumber = result.blockNumber || "";
        console.log(`${result.chain},${blockNumber},${result.token},${result.supply}`);
    }
}

main().catch(console.error);