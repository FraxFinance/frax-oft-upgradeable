import { createPublicClient, defineChain, http } from "viem";
import { abstract, arbitrum, aurora, avalanche, base, berachain, blast, bsc, fraxtal, ink, katana, linea, mainnet, mode, optimism, plumeMainnet, polygon, polygonZkEvm, scroll, sei, sonic, unichain, worldchain, xLayer, zksync } from "viem/chains";
import { ChainInfo } from "./types";
// import { createUmi } from "@metaplex-foundation/umi-bundle-defaults";
import { Connection } from "@solana/web3.js";

export const hyperliquid = defineChain({
    id: 999,
    name: 'Hyperliquid',
    nativeCurrency: {
        decimals: 18,
        name: 'Hyper',
        symbol: 'HYPE',
    },
    rpcUrls: {
        default: {
            http: ['https://rpc.hyperliquid.xyz/evm'],
            webSocket: ['wss://hyperliquid.drpc.org'],
        },
    },
    blockExplorers: {
        default: { name: 'Explorer', url: 'https://hyperevmscan.io/' },
    },
    contracts: {
        multicall3: {
            address: '0xcA11bde05977b3631167028862bE2a173976CA11',
            blockCreated: 13052,
        },
    },
})

export const chains: Record<string, ChainInfo> = {
    ethereum: {
        client: createPublicClient({
            chain: mainnet,
            transport: http(),
        }),
        peerId: 30101,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xc02Ab410f0734EFa3F14628780e6e695156024C2",
        sendLib302: "0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1",
    },
    fraxtal: {
        client: createPublicClient({
            chain: fraxtal,
            transport: http(),
        }),
        peerId: 30255,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x8bC1e36F015b9902B54b1387A4d733cebc2f5A4e",
        sendLib302: "0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6",
    },
    base: {
        client: createPublicClient({
            chain: base,
            transport: http(
                "https://base-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
            ),
        }),
        peerId: 30184,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf",
        sendLib302: "0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2",
    },
    blast: {
        client: createPublicClient({
            chain: blast,
            transport: http(
                "https://blast-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
            ),
        }),
        peerId: 30243,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6",
        sendLib302: "0xc1B621b18187F74c8F6D52a6F709Dd2780C09821",
    },
    mode: {
        client: createPublicClient({
            chain: mode,
            transport: http("https://mainnet.mode.network/"),
        }),
        peerId: 30260,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xc1B621b18187F74c8F6D52a6F709Dd2780C09821",
        sendLib302: "0x2367325334447C5E1E0f1b3a6fB947b262F58312",
    },
    sei: {
        client: createPublicClient({
            chain: sei,
            transport: http("https://sei-mainnet.g.alchemy.com/v2/ISqt4ylM2QDVoqg8av78v4Jz6Gb426JT"),
        }),
        peerId: 30280,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
        sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
    },
    xlayer: {
        client: createPublicClient({
            chain: xLayer,
            transport: http("https://xlayerrpc.okx.com"),
        }),
        peerId: 30274,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x2367325334447C5E1E0f1b3a6fB947b262F58312",
        sendLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
    },
    sonic: {
        client: createPublicClient({
            chain: sonic,
            transport: http(
                "https://sonic-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
            ),
        }),
        peerId: 30332,
        endpoint: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
        receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
        sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
    },
    ink: {
        client: createPublicClient({
            chain: ink,
            transport: http(
                "https://ink-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
            ),
        }),
        peerId: 30339,
        endpoint: "0xca29f3A6f966Cb2fc0dE625F8f325c0C46dbE958",
        receiveLib302: "0x473132bb594caEF281c68718F4541f73FE14Dc89",
        sendLib302: "0x76111DE813F83AAAdBD62773Bf41247634e2319a",
    },
    arbitrum: {
        client: createPublicClient({
            chain: arbitrum,
            transport: http(
                "https://arb-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
            ),
        }),
        peerId: 30110,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6",
        sendLib302: "0x975bcD720be66659e3EB3C0e4F1866a3020E493A",
    },
    optimism: {
        client: createPublicClient({
            chain: optimism,
            transport: http(
                "https://opt-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
            ),
        }),
        peerId: 30111,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063",
        sendLib302: "0x1322871e4ab09Bc7f5717189434f97bBD9546e95",
    },
    polygon: {
        client: createPublicClient({
            chain: polygon,
            transport: http(
                "https://polygon-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
            ),
        }),
        peerId: 30109,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x1322871e4ab09Bc7f5717189434f97bBD9546e95",
        sendLib302: "0x6c26c61a97006888ea9E4FA36584c7df57Cd9dA3",
    },
    avalanche: {
        client: createPublicClient({
            chain: avalanche,
            transport: http(
                "https://avax-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
            ),
        }),
        peerId: 30106,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xbf3521d309642FA9B1c91A08609505BA09752c61",
        sendLib302: "0x197D1333DEA5Fe0D6600E9b396c7f1B1cFCc558a",
    },
    bnb: {
        client: createPublicClient({
            chain: bsc,
            transport: http("https://bsc-dataseed.binance.org"),
        }),
        peerId: 30102,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xB217266c3A98C8B2709Ee26836C98cf12f6cCEC1",
        sendLib302: "0x9F8C645f2D0b2159767Bd6E0839DE4BE49e823DE",
    },
    zkevm: {
        client: createPublicClient({
            chain: polygonZkEvm,
            transport: http(
                "https://polygonzkevm-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
            ),
        }),
        peerId: 30158,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x581b26F362AD383f7B51eF8A165Efa13DDe398a4",
        sendLib302: "0x28B6140ead70cb2Fb669705b3598ffB4BEaA060b",
    },
    zksync: {
        client: createPublicClient({
            chain: zksync,
            transport: http(),
        }),
        peerId: 30165,
        endpoint: "0xd07C30aF3Ff30D96BDc9c6044958230Eb797DDBF",
        receiveLib302: "0x04830f6deCF08Dec9eD6C3fCAD215245B78A59e1",
        sendLib302: "0x07fD0e370B49919cA8dA0CE842B8177263c0E12c",
    },
    abstract: {
        client: createPublicClient({
            chain: abstract,
            transport: http(),
        }),
        peerId: 30324,
        endpoint: "0x5c6cfF4b7C49805F8295Ff73C204ac83f3bC4AE7",
        receiveLib302: "0x9d799c1935c51CA399e6465Ed9841DEbCcEc413E",
        sendLib302: "0x166CAb679EBDB0853055522D3B523621b94029a1",
    },
    berachain: {
        client: createPublicClient({
            chain: berachain,
            transport: http(),
        }),
        peerId: 30362,
        endpoint: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
        receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
        sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
    },
    linea: {
        client: createPublicClient({
            chain: linea,
            transport: http(),
        }),
        peerId: 30183,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xE22ED54177CE1148C557de74E4873619e6c6b205",
        sendLib302: "0x32042142DD551b4EbE17B6FEd53131dd4b4eEa06",
    },
    aurora: {
        client: createPublicClient({
            chain: aurora,
            transport: http(),
        }),
        peerId: 30211,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x000CC1A759bC3A15e664Ed5379E321Be5de1c9B6",
        sendLib302: "0x1aCe9DD1BC743aD036eF2D92Af42Ca70A1159df5",
    },
    hyperliquid: {
        client: createPublicClient({
            chain: hyperliquid,
            transport: http(),
        }),
        peerId: 30367,
        endpoint: "0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9",
        receiveLib302: "0x7cacBe439EaD55fa1c22790330b12835c6884a91",
        sendLib302: "0xfd76d9CB0Bac839725aB79127E7411fe71b1e3CA",
    },
    katana: {
        client: createPublicClient({
            chain: katana,
            transport: http(),
        }),
        peerId: 30375,
        endpoint: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
        receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
        sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
    },
    plumephoenix: {
        client: createPublicClient({
            chain: plumeMainnet,
            transport: http(),
        }),
        peerId: 30370,
        endpoint: "0xC1b15d3B262bEeC0e3565C11C9e0F6134BdaCB36",
        receiveLib302: "0x5B19bd330A84c049b62D5B0FC2bA120217a18C1C",
        sendLib302: "0xFe7C30860D01e28371D40434806F4A8fcDD3A098",
    },
    scroll: {
        client: createPublicClient({
            chain: scroll,
            transport: http(),
        }),
        peerId: 30214,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x8363302080e711E0CAb978C081b9e69308d49808",
        sendLib302: "0x9BbEb2B2184B9313Cf5ed4a4DDFEa2ef62a2a03B",
    },
    unichain: {
        client: createPublicClient({
            chain: unichain,
            transport: http(),
        }),
        peerId: 30320,
        endpoint: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
        receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
        sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
    },
    worldchain: {
        client: createPublicClient({
            chain: worldchain,
            transport: http(),
        }),
        peerId: 30319,
        endpoint: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
        receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
        sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
    },
    solana: {
        // client: createUmi("https://api.mainnet-beta.solana.com"),
        client: new Connection("https://api.mainnet-beta.solana.com"),
        peerId: 30168,
        endpoint: "76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6",
        receiveLib302: "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH",
        sendLib302: "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH",
    }
    // TODO:
    // Movement
    // Aptos
};