import { createPublicClient, defineChain, http } from "viem";
import { abstract, arbitrum, aurora, avalanche, base, berachain, blast, bsc, fraxtal, ink, katana, linea, mainnet, mode, optimism, plasma, plumeMainnet, polygon, polygonZkEvm, scroll, sei, sonic, unichain, worldchain, xLayer, zksync } from "viem/chains";
import { ChainInfo } from "./types";
// import { Connection } from "@solana/web3.js";
import { createUmi } from "@metaplex-foundation/umi-bundle-defaults";
import { configDotenv } from "dotenv"
import { Aptos, AptosConfig, Network } from "@aptos-labs/ts-sdk";

configDotenv({ path: "./.env" });

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
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x3ad4dC2319394bB4BE99A0e4aE2AbF7bCEbD648E",
        mintRedeemHop: "0x99B5587ab54A49e3F827D10175Caf69C0187bfA8"
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
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x2A2019b30C157dB6c1C01306b8025167dBe1803B",
        mintRedeemHop: "0x3e6a2cBaFD864e09e6DAb9Cf035a0AbEa32bc0BC"
    },
    base: {
        client: createPublicClient({
            chain: base,
            transport: http(
                process.env.BASE_RPC_URL
            ),
        }),
        peerId: 30184,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf",
        sendLib302: "0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2",
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45",
        mintRedeemHop: "0x73382eb28F35d80Df8C3fe04A3EED71b1aFce5dE"
    },
    blast: {
        client: createPublicClient({
            chain: blast,
            transport: http(
                process.env.BLAST_RPC_URL
            ),
        }),
        peerId: 30243,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6",
        sendLib302: "0xc1B621b18187F74c8F6D52a6F709Dd2780C09821",
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0xe93Cb38f97469eac2f284a87813D0d701b28E58e",
        mintRedeemHop: "0x85b1714b25f40FD5025423124c076476073180b3"
    },
    mode: {
        client: createPublicClient({
            chain: mode,
            transport: http(process.env.MODE_RPC_URL),
        }),
        peerId: 30260,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xc1B621b18187F74c8F6D52a6F709Dd2780C09821",
        sendLib302: "0x2367325334447C5E1E0f1b3a6fB947b262F58312",
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x486CB4788F1bE7cdEf9301a7a637B451df3Cf262",
        mintRedeemHop: "0x7360575f6f8F91b38dD078241b0Df508f5fBfDf9"
    },
    sei: {
        client: createPublicClient({
            chain: sei,
            transport: http(process.env.SEI_RPC_URL),
        }),
        peerId: 30280,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
        sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x3a6F28e8DDD232B02C72C491Bd1626F69D2fb329",
        mintRedeemHop: "0x0255a172d0a060F2bEab3e7c12334dD73cCC26ba"
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
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x79152c303AD5aE429eDefa4553CB1Ad2c6EE1396",
        mintRedeemHop: "0x45c6852A5188Ce1905567EA83454329bd4982007"
    },
    sonic: {
        client: createPublicClient({
            chain: sonic,
            transport: http(
                process.env.SONIC_RPC_URL
            ),
        }),
        peerId: 30332,
        endpoint: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
        receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
        sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
        blockSendLib:"0xc1ce56b2099ca68720592583c7984cab4b6d7e7a",
        hop: "0x3A5cDA3Ac66Aa80573402610c94B74eD6cdb2F23",
        mintRedeemHop: "0xf6115Bb9b6A4b3660dA409cB7afF1fb773efaD0b"
    },
    ink: {
        client: createPublicClient({
            chain: ink,
            transport: http(
                process.env.INK_RPC_URL
            ),
        }),
        peerId: 30339,
        endpoint: "0xca29f3A6f966Cb2fc0dE625F8f325c0C46dbE958",
        receiveLib302: "0x473132bb594caEF281c68718F4541f73FE14Dc89",
        sendLib302: "0x76111DE813F83AAAdBD62773Bf41247634e2319a",
        blockSendLib:"0x796862c4849662bfc30fe7559780923d519d3192",
        hop: "0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A",
        mintRedeemHop: "0x452420df4AC1e3db5429b5FD629f3047482C543C"
    },
    arbitrum: {
        client: createPublicClient({
            chain: arbitrum,
            transport: http(
                process.env.ARBITRUM_RPC_URL
            ),
        }),
        peerId: 30110,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6",
        sendLib302: "0x975bcD720be66659e3EB3C0e4F1866a3020E493A",
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x29F5DBD0FE72d8f11271FCBE79Cb87E18a83C70A",
        mintRedeemHop: "0xa46A266dCBf199a71532c76967e200994C5A0D6d"
    },
    optimism: {
        client: createPublicClient({
            chain: optimism,
            transport: http(
                process.env.OPTIMISM_RPC_URL
            ),
        }),
        peerId: 30111,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063",
        sendLib302: "0x1322871e4ab09Bc7f5717189434f97bBD9546e95",
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x31D982ebd82Ad900358984bd049207A4c2468640",
        mintRedeemHop: "0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A"
    },
    polygon: {
        client: createPublicClient({
            chain: polygon,
            transport: http(
                process.env.POLYGON_RPC_URL
            ),
        }),
        peerId: 30109,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x1322871e4ab09Bc7f5717189434f97bBD9546e95",
        sendLib302: "0x6c26c61a97006888ea9E4FA36584c7df57Cd9dA3",
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0xf74D38A26948E9DDa53eD85cF03C6b1188FbB30C",
        mintRedeemHop: "0x5658e82E330e094627D9b362ed0E137eA06673C4"
    },
    avalanche: {
        client: createPublicClient({
            chain: avalanche,
            transport: http(
                process.env.AVALANCHE_RPC_URL
            ),
        }),
        peerId: 30106,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0xbf3521d309642FA9B1c91A08609505BA09752c61",
        sendLib302: "0x197D1333DEA5Fe0D6600E9b396c7f1B1cFCc558a",
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A",
        mintRedeemHop: "0x452420df4AC1e3db5429b5FD629f3047482C543C"
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
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x452420df4AC1e3db5429b5FD629f3047482C543C",
        mintRedeemHop: "0xdee45510b42Cb0678C8A61D043C698aF66b0d852"
    },
    zkevm: {
        client: createPublicClient({
            chain: polygonZkEvm,
            transport: http(
                process.env.ZKEVM_RPC_URL
            ),
        }),
        peerId: 30158,
        endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
        receiveLib302: "0x581b26F362AD383f7B51eF8A165Efa13DDe398a4",
        sendLib302: "0x28B6140ead70cb2Fb669705b3598ffB4BEaA060b",
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x111ddab65Af5fF96b674400246699ED40F550De1",
        mintRedeemHop: "0xc71BF5Ee4740405030eF521F18A96eA14fec802D"
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
        blockSendLib:"0x0fddfc529b5912e1cbe38ccedf8e226566e596d3",
        hop: "0xc5e4a0cfef8d801278927c25fb51c1db7b69ddfb",
        mintRedeemHop: "0xa05e9f9b97c963b5651ed6a50fae46625a8c400b"
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
        blockSendLib:"0x3258287147fb7887d8a643006e26e19368057377",
        hop: "0xc5e4a0cfef8d801278927c25fb51c1db7b69ddfb",
        mintRedeemHop: "0xa05e9f9b97c963b5651ed6a50fae46625a8c400b"
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
        blockSendLib:"0xc1ce56b2099ca68720592583c7984cab4b6d7e7a",
        hop: "0xc71BF5Ee4740405030eF521F18A96eA14fec802D",
        mintRedeemHop: "0x983aF86c94Fe3963989c22CeeEb6eA8Eac32D263"
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
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x6cA98f43719231d38F6426DB64C7F3D5C7CE7876",
        mintRedeemHop: "0xa71f2204EDDB8d84F411A0C712687FAe5002e7Fb"
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
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0x53e36c8380ff62d7964bfa4868a0045e58a52344",
        mintRedeemHop: "0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2"
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
        blockSendLib:"0xf540d892bc671f08e0b1c5b61185c53c2211e8f7",
        hop: "0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2",
        mintRedeemHop: "0xb85A8FDa7F5e52E32fa5582847CFfFee9456a5Dc"
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
        blockSendLib:"0xc1ce56b2099ca68720592583c7984cab4b6d7e7a",
        hop: "0x5d8EB59A12Bc98708702305A7b032f4b69Dd5b5c",
        mintRedeemHop: "0xF6f45CCB5E85D1400067ee66F9e168f83e86124E"
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
        blockSendLib:"0x9e611db91ade3312534064ae6ae700f5b531844c",
        hop: "0x6cA98f43719231d38F6426DB64C7F3D5C7CE7876",
        mintRedeemHop: "0xa71f2204EDDB8d84F411A0C712687FAe5002e7Fb"
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
        blockSendLib:"0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862",
        hop: "0xF6f45CCB5E85D1400067ee66F9e168f83e86124E",
        mintRedeemHop: "0x91DDB0E0C36B901C6BF53B9Eb5ACa0Eb1465F558"
    },
    unichain: {
        client: createPublicClient({
            chain: unichain,
            transport: http(process.env.UNICHAIN_RPC_URL),
        }),
        peerId: 30320,
        endpoint: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
        receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
        sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
        blockSendLib:"0xc1ce56b2099ca68720592583c7984cab4b6d7e7a",
        hop: "0xc71BF5Ee4740405030eF521F18A96eA14fec802D",
        mintRedeemHop: "0x983aF86c94Fe3963989c22CeeEb6eA8Eac32D263"
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
        blockSendLib:"0xc1ce56b2099ca68720592583c7984cab4b6d7e7a",
        hop: "0x938d99A81814f66b01010d19DDce92A633441699",
        mintRedeemHop: "0x111ddab65Af5fF96b674400246699ED40F550De1"
    },
    plasma: {
        client: createPublicClient({
            chain: plasma,
            transport: http(),
        }),
        peerId: 30383,
        endpoint: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
        receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
        sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
        blockSendLib:"0xc1ce56b2099ca68720592583c7984cab4b6d7e7a",
        hop:"0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2",
        mintRedeemHop:"0xb85A8FDa7F5e52E32fa5582847CFfFee9456a5Dc"
    },
    solana: {
        // client: new Connection("https://api.mainnet-beta.solana.com"),
        client: createUmi("https://api.mainnet-beta.solana.com"),
        peerId: 30168,
        endpoint: "76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6",
        receiveLib302: "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH",
        sendLib302: "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH",
        blockSendLib:"2XrYqmhBMPJgDsb4SVbjV1PnJBprurd5bzRCkHwiFCJB"
    },
    movement: {
        client: new Aptos(new AptosConfig({
            network: Network.CUSTOM,
            fullnode: 'https://full.mainnet.movementinfra.xyz/v1',
        })),
        peerId: 30325,
        endpoint: "0xe60045e20fc2c99e869c1c34a65b9291c020cd12a0d37a00a53ac1348af4f43c",
        receiveLib302: "0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9",
        sendLib302: "0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9",
        blockSendLib:"0x3ca0d187f1938cf9776a0aa821487a650fc7bb2ab1c1d241ba319192aae4afc6"
    },
    aptos: {
        client: new Aptos(new AptosConfig({
            network: Network.MAINNET,
            fullnode: 'https://fullnode.mainnet.aptoslabs.com/v1',
        })),
        peerId: 30108,
        endpoint: "0xe60045e20fc2c99e869c1c34a65b9291c020cd12a0d37a00a53ac1348af4f43c",
        receiveLib302: "0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9",
        sendLib302: "0xc33752e0220faf79e45385dd73fb28d681dcd9f1569a1480725507c1f3c3aba9",
        blockSendLib:"0x3ca0d187f1938cf9776a0aa821487a650fc7bb2ab1c1d241ba319192aae4afc6"
    },
};