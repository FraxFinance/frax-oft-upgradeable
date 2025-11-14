import {
    abstract,
    arbitrum,
    avalanche,
    base,
    berachain,
    blast,
    bsc,
    fraxtal,
    ink,
    linea,
    mainnet,
    mode,
    optimism,
    polygon,
    polygonZkEvm,
    sei,
    sonic,
    unichain,
    worldchain,
    xLayer,
    zksync,
} from "viem/chains";
import { createPublicClient, http } from "viem";
import { default as DVN_ABI } from "./abis/DVN_ABI.json"

// const expectedSigners = [
//     '0x23c022223d543ADAdDA3c1c05553b63f1D15aA42',
//     '0x2f99B4A409AF38F926e4CC68e5b932B7EFaB5A15',
//     '0x9398Fbf6dFfF6A92D5e41F1A997BF84F0203B92B'
//   ]
type ChainInfo = {
    client: any; // Replace `any` with the actual type from `createPublicClient`
    peerId: number;
    dvn: string;
};

async function main() {
    const chains: Record<string, ChainInfo> = {
        ethereum: {
            client: createPublicClient({
                chain: mainnet,
                transport: http(
                    "https://eth-mainnet.alchemyapi.io/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30101,
            dvn: "0x38654142f5e672ae86a1b21523aafc765e6a1e08"
        },
        fraxtal: {
            client: createPublicClient({
                chain: fraxtal,
                transport: http(),
            }),
            peerId: 30255,
            dvn: "0x26cd5abadf7ec3f0f02b48314bfca6b2342cddd4"
        },
        base: {
            client: createPublicClient({
                chain: base,
                transport: http(
                    "https://base-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30184,
            dvn: "0x187cf227f81c287303ee765ee001e151347faaa2"
        },
        blast: {
            client: createPublicClient({
                chain: blast,
                transport: http(
                    "https://blast-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30243,
            dvn: "0xfa06f93ad99825114c8f8738943734b07fdd162f"
        },
        mode: {
            client: createPublicClient({
                chain: mode,
                transport: http("https://mainnet.mode.network/"),
            }),
            peerId: 30260,
            dvn: "0x315b0e76a510607bb0f706b17716f426d5b385b8"
        },
        sei: {
            client: createPublicClient({
                chain: sei,
                transport: http("https://evm-rpc.sei-apis.com"),
            }),
            peerId: 30280,
            dvn: "0xe016f0f39fb7dcf14e9412d92f2049668d4d2612"
        },
        xlayer: {
            client: createPublicClient({
                chain: xLayer,
                transport: http("https://xlayerrpc.okx.com"),
            }),
            peerId: 30274,
            dvn: "0x2ae36a544b904f2f2960f6fd1a6084b4b11ba334"
        },
        sonic: {
            client: createPublicClient({
                chain: sonic,
                transport: http(
                    "https://sonic-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30332,
            dvn: "0x805ed883fa3453e7ac588667785a4495c573cd13"
        },
        ink: {
            client: createPublicClient({
                chain: ink,
                transport: http(
                    "https://ink-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30339,
            dvn: "0xf007f1fef50c0acaf4418741454bcaeaecb96b87"
        },
        arbitrum: {
            client: createPublicClient({
                chain: arbitrum,
                transport: http(
                    "https://arb-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30110,
            dvn: "0xb42726e41dbe96fc4ea6d73cd792167608353698"
        },
        optimism: {
            client: createPublicClient({
                chain: optimism,
                transport: http(
                    "https://opt-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30111,
            dvn: "0x7240264781aa2f97cb994c6231297a8606483242"
        },
        polygon: {
            client: createPublicClient({
                chain: polygon,
                transport: http(
                    "https://polygon-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30109,
            dvn: "0xdab6e6ecb3513a8d2614ad75199b4b264a731050"
        },
        avalanche: {
            client: createPublicClient({
                chain: avalanche,
                transport: http(
                    "https://avax-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30106,
            dvn: "0xfe4c37cd401f58ee0bf4d214447bf306c2bbd41b"
        },
        bnb: {
            client: createPublicClient({
                chain: bsc,
                transport: http("https://bsc-dataseed.binance.org"),
            }),
            peerId: 30102,
            dvn: "0xd4bf35ce3bfc7f7d7dfc0694a7d4aa8b8c60a38c"
        },
        zkevm: {
            client: createPublicClient({
                chain: polygonZkEvm,
                transport: http(
                    "https://polygonzkevm-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30158,
            dvn: "0x651b1cf59014420112f8b7fcfda840a16ad763e0"
        },
        zksync: {
            client: createPublicClient({
                chain: zksync,
                transport: http(),
            }),
            peerId: 30165,
            dvn: "0x2eb85384cad49a67ebd8e2afb0f72b3f586baf03"
        },
        abstract: {
            client: createPublicClient({
                chain: abstract,
                transport: http(),
            }),
            peerId: 30324,
            dvn: "0xa8c83febab692d6f08cfa303e5d53b3b34f9046d"
        },
        berachain: {
            client: createPublicClient({
                chain: berachain,
                transport: http(),
            }),
            peerId: 30362,
            dvn: "0x559a194dae0508342e7ce1ad96e7e90a77f8bc4c"
        },
        linea: {
            client: createPublicClient({
                chain: linea,
                transport: http(),
            }),
            peerId: 30183,
            dvn: "0xf4064220871e3b94ca6ab3b0cee8e29178bf47de"
        },
        worldchain: {
            client: createPublicClient({
                chain: worldchain,
                transport: http(),
            }),
            peerId: 30319,
            dvn: "0xe16561b56bdf003b785347d237905bae24f5f973"
        },
        unichain: {
            client: createPublicClient({
                chain: unichain,
                transport: http(),
            }),
            peerId: 30320,
            dvn: "0x97faa2a9c9bf8B4082B175A5B894Ce6bac6697a8"
        },
        // TODO:
        // Solana
        // Movement
        // Aptos
        // Stretch Goal : Initia
    };

    Object.keys(chains).forEach(async (chainName) => {
        // const signers = await chains[chainName].client.readContract({
        //     address: chains[chainName].dvn,
        //     abi: DVN_ABI,
        //     functionName: "getSigners",
        // });
        // if (!(JSON.stringify(expectedSigners) === JSON.stringify(signers))) {
        //     console.log("Mismatch Signers ", chainName)
        // }
        // const signerSize = await chains[chainName].client.readContract({
        //     address: chains[chainName].dvn,
        //     abi: DVN_ABI,
        //     functionName: "signerSize",
        // });
        // console.log(`signer size of ${chainName} : ${signerSize}`)
        const quorum = await chains[chainName].client.readContract({
            address: chains[chainName].dvn,
            abi: DVN_ABI,
            functionName: "quorum",
        });
        console.log(`Quorum of ${chainName} : ${quorum}`)
        // Object.keys(chains).forEach(async (chainNameInternal) => {
        //     if (chainName != chainNameInternal) {
        //         const dstConfig = await chains[chainName].client.readContract({
        //             address: chains[chainName].dvn,
        //             abi: DVN_ABI,
        //             functionName: "dstConfig",
        //             args:[chains[chainNameInternal].peerId]
        //         });
        //         console.log(`${chains[chainName].peerId} => ${chains[chainNameInternal].peerId}`, dstConfig)
        //     } 
        // })
    });
}

main()