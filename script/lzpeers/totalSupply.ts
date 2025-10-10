import { ERC20ABI } from "./abis/ERC20";
import { chains } from "./chains";
import { ofts, solanaOFTs } from "./oft";
import { PublicKey } from "@solana/web3.js";

async function main() {
    Object.keys(chains).forEach(async (chainName) => {
        if (chainName !== "fraxtal" && chainName !== "ethereum" && chainName !== "solana") {
            try {
                const blockNumber = await chains[chainName].client.getBlockNumber()
                const totalSupplyfpi = await chains[chainName].client.readContract({
                    address: ofts[chainName]["fpi"].address,
                    abi: ofts[chainName]["fpi"].abi,
                    functionName: "totalSupply",
                    blockNumber,
                })
                console.log(`${chainName} : ${blockNumber} : fpi `, totalSupplyfpi)

                const totalSupplyfrxeth = await chains[chainName].client.readContract({
                    address: ofts[chainName]["frxETH"].address,
                    abi: ofts[chainName]["frxETH"].abi,
                    functionName: "totalSupply",
                    blockNumber
                })
                console.log(`${chainName} : ${blockNumber} : frxETH `, totalSupplyfrxeth)

                const totalSupplyfrxusd = await chains[chainName].client.readContract({
                    address: ofts[chainName]["frxUSD"].address,
                    abi: ofts[chainName]["frxUSD"].abi,
                    functionName: "totalSupply",
                    blockNumber
                })
                console.log(`${chainName} : ${blockNumber} : frxUSD `, totalSupplyfrxusd)

                const totalSupplysfrxeth = await chains[chainName].client.readContract({
                    address: ofts[chainName]["sfrxETH"].address,
                    abi: ofts[chainName]["sfrxETH"].abi,
                    functionName: "totalSupply",
                    blockNumber
                })
                console.log(`${chainName} : ${blockNumber} : sfrxETH `, totalSupplysfrxeth)

                const totalSupplysfrxusd = await chains[chainName].client.readContract({
                    address: ofts[chainName]["sfrxUSD"].address,
                    abi: ofts[chainName]["sfrxUSD"].abi,
                    functionName: "totalSupply",
                    blockNumber
                })
                console.log(`${chainName} : ${blockNumber} : sfrxUSD `, totalSupplysfrxusd)

                const totalSupplywfrax = await chains[chainName].client.readContract({
                    address: ofts[chainName]["wfrax"].address,
                    abi: ofts[chainName]["wfrax"].abi,
                    functionName: "totalSupply",
                    blockNumber
                })
                console.log(`${chainName} : ${blockNumber} : wfrax `, totalSupplywfrax)

            } catch (error) {
                console.log("Error ", chainName, error);
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
                console.log(`${chainName} : ${blockNumber} : fpiBal `, fpiBal)

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
                console.log(`${chainName} : ${blockNumber} : frxethBal `, frxETHBal)

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
                console.log(`${chainName} : ${blockNumber} : frxUSDBal `, frxUSDBal)

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
                console.log(`${chainName} : ${blockNumber} : sfrxethBal `, sfrxethBal)

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
                console.log(`${chainName} : ${blockNumber} : sfrxusdBal `, sfrxusdBal)

                if (chainName === "ethereum") {
                    const totalSupplywfrax = await chains[chainName].client.readContract({
                        address: ofts[chainName]["wfrax"].address,
                        abi: ofts[chainName]["wfrax"].abi,
                        functionName: "totalSupply",
                        blockNumber
                    })
                    console.log(`${chainName} : ${blockNumber} : wfrax `, totalSupplywfrax)
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
                    console.log(`${chainName} : ${blockNumber} : wfraxBal `, wfraxBal)
                }

            } catch (Error) {
                console.log("Error ", chainName, Error)
            }
        } else if (chainName === "solana") {
            const frxusdmintAddress = new PublicKey(solanaOFTs.frxUSD.mint);

            let frxusdsupply = await chains[chainName].client.getTokenSupply(frxusdmintAddress);

            console.log(`${chainName} : frxusd `, frxusdsupply.value.uiAmount)

            // ========================

            const sfrxusdmintAddress = new PublicKey(solanaOFTs.sfrxUSD.mint);

            let sfrxusdsupply = await chains[chainName].client.getTokenSupply(sfrxusdmintAddress);

            console.log(`${chainName} : sfrxusd `, sfrxusdsupply.value.uiAmount)

            // ========================

            const frxethmintAddress = new PublicKey(solanaOFTs.frxETH.mint);

            let frxethsupply = await chains[chainName].client.getTokenSupply(frxethmintAddress);

            console.log(`${chainName} : frxETH `, frxethsupply.value.uiAmount)

            // =========================
            const sfrxethmintAddress = new PublicKey(solanaOFTs.sfrxETH.mint);

            let sfrxethsupply = await chains[chainName].client.getTokenSupply(sfrxethmintAddress);

            console.log(`${chainName} : sfrxETH `, sfrxethsupply.value.uiAmount)

            // =========================

            const wfraxmintAddress = new PublicKey(solanaOFTs.wfrax.mint);

            let wfraxsupply = await chains[chainName].client.getTokenSupply(wfraxmintAddress);

            console.log(`${chainName} : wfrax `, wfraxsupply.value.uiAmount)

            // ========================

            const fpimintAddress = new PublicKey(solanaOFTs.fpi.mint);

            let fpisupply = await chains[chainName].client.getTokenSupply(fpimintAddress);

            console.log(`${chainName} : fpi `, fpisupply.value.uiAmount)

        } else {
            throw Error("Unknown chain")
        }
    });
}

main()