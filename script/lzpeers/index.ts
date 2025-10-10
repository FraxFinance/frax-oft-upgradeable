import {
    createPublicClient,
    getAddress,
    http,
} from "viem";

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
    metis,
    mode,
    optimism,
    polygon,
    polygonZkEvm,
    sei,
    sonic,
    xLayer,
    zksync,
} from "viem/chains";

import * as dotenv from "dotenv";

dotenv.config();

const bytes32Zero =
    "0x0000000000000000000000000000000000000000000000000000000000000000";

const OFT_ADAPTER_ABI = [
    {
        inputs: [],
        name: "token",
        outputs: [{ internalType: "address", name: "", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [{ internalType: "uint32", name: "_eid", type: "uint32" }],
        name: "peers",
        outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
        stateMutability: "view",
        type: "function",
    },
];

const ENDPOINT_ABI = [
    {
        inputs: [
            { internalType: "address", name: "_sender", type: "address" },
            { internalType: "uint32", name: "_dstEid", type: "uint32" },
        ],
        name: "getSendLibrary",
        outputs: [{ internalType: "address", name: "lib", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "_receiver", type: "address" },
            { internalType: "uint32", name: "_srcEid", type: "uint32" },
        ],
        name: "getReceiveLibrary",
        outputs: [
            { internalType: "address", name: "lib", type: "address" },
            { internalType: "bool", name: "isDefault", type: "bool" },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "_sender", type: "address" },
            { internalType: "uint32", name: "_dstEid", type: "uint32" },
        ],
        name: "isDefaultSendLibrary",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
];

const frxUSD_lockbox = "0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0";
const sfrxUSD_lockbox = "0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126";
const frxETH_lockbox = "0xF010a7c8877043681D59AD125EbF575633505942";
const sfrxETH_lockbox = "0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A";
const FXS_lockbox = "0x23432452B720C80553458496D4D9d7C5003280d0";
const FPI_lockbox = "0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d";
const FRAX_legacy_lockbox = "0x909DBdE1eBE906Af95660033e478D59EFe831fED";
const sFRAX_legacy_lockbox = "0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E";

type TokenInfo = {
    [key: string]: string | undefined; // Allow dynamic string keys
}

const tokens: TokenInfo = {
    frxUSD: "0x80Eede496655FB9047dd39d9f418d5483ED600df",
    sfrxUSD: "0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0",
    frxETH: "0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050",
    sfrxETH: "0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45",
    FXS: "0x64445f0aecC51E94aD52d8AC56b7190e764E561a",
    FPI: "0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927",
};

const legacyTokens: TokenInfo = {
    FRAX: "0x909DBdE1eBE906Af95660033e478D59EFe831fED",
    sFRAX: "0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E",
    frxETH: "0xF010a7c8877043681D59AD125EbF575633505942",
    sfrxETH: "0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A",
    FXS: "0x23432452B720C80553458496D4D9d7C5003280d0",
    FPI: "0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d",
};

async function main() {
    type ChainInfo = {
        client: any; // Replace `any` with the actual type from `createPublicClient`
        peerId: number;
        endpoint: string;
        receiveLib302: string;
        sendLib302: string;
        peerAddress?: string;
    };
    type LockBoxInfo = {
        [key: string]: string | undefined; // Allow dynamic string keys
    }

    const chains: Record<string, ChainInfo> = {
        ethereum: {
            client: createPublicClient({
                chain: mainnet,
                transport: http(
                    "https://eth-mainnet.alchemyapi.io/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
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
        metis: {
            client: createPublicClient({
                chain: metis,
                transport: http(
                    "https://metis-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"
                ),
            }),
            peerId: 30151,
            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
            receiveLib302: "0x5539Eb17a84E1D59d37C222Eb2CC4C81b502D1Ac",
            sendLib302: "0x63e39ccB510926d05a0ae7817c8f1CC61C5BdD6c",
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
                transport: http("https://sei.drpc.org"),
            }),
            peerId: 30280,
            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
            receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
            sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
        },
        xlayer: {
            client: createPublicClient({
                chain: xLayer,
                transport: http("https://rpc.xlayer.tech"),
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
        // TODO:
        // Solana
        // Movement
        // Aptos
        // Stretch Goal : Initia
    };
    const lockboxes: Record<string, LockBoxInfo> = {
        ethereum: {
            fraxLegacy: FRAX_legacy_lockbox,
            frxUSD: frxUSD_lockbox,
            sfraxLegacy: sFRAX_legacy_lockbox,
            sfrxUSD: sfrxUSD_lockbox,
            frxEthLockbox: frxETH_lockbox,
            sfrxETHLockbox: sfrxETH_lockbox,
            fxsLockbox: FXS_lockbox,
            fpiLockbox: FPI_lockbox,
        },
        fraxtal: {
            frxUSD: "0x96A394058E2b84A89bac9667B19661Ed003cF5D4",
            sfrxUSD: "0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361",
            fxs: "0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A",
            fpi: "0x75c38D46001b0F8108c4136216bd2694982C20FC",
            frxETH: "0x9abfe1f8a999b0011ecd6116649aee8d575f5604",
            sfrxETH: "0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168",
        },
    };
    const lockboxChains = ["ethereum", "fraxtal"];
    const oftChains = getFilteredChainNames(Object.keys(chains), lockboxChains);

    lockboxChains.forEach((lockboxChain: string) => {
        Object.keys(lockboxes[lockboxChain]).forEach((lockbox: string) => {
            oftChains.forEach(async (oftChain: string) => {
                try {
                    const peer = await chains[lockboxChain].client.readContract({
                        address: lockboxes[lockboxChain][lockbox],
                        abi: OFT_ADAPTER_ABI,
                        functionName: "peers",
                        args: [chains[oftChain].peerId],
                    });
                    const peerString =
                        typeof peer == "string" ? peer.toString() : bytes32Zero;
                    const isPeerZeroBytes32 =
                        peerString.toLowerCase() === bytes32Zero.toLowerCase();
                    const peerAddress = getAddress("0x" + peerString.slice(-40));
                    // check if there is a code at peer address
                    if (!isPeerZeroBytes32) {
                        try {
                            const code = await chains[oftChain].client.getCode({
                                address: peerAddress,
                            });
                            if (code.length == 0) {
                                console.log("No OFT on ", oftChain);
                            } else {
                                const originPeer = await chains[oftChain].client.readContract({
                                    address: peerAddress,
                                    abi: OFT_ADAPTER_ABI,
                                    functionName: "peers",
                                    args: [chains[lockboxChain].peerId],
                                });
                                const peerStr =
                                    typeof originPeer == "string"
                                        ? originPeer.toString()
                                        : bytes32Zero;
                                const isPeerZeroBytes32 =
                                    peerStr.toLowerCase() === bytes32Zero.toLowerCase();
                                const peerAddr = getAddress("0x" + peerStr.slice(-40));
                                // console.log(`${fraxLegacyChain} : ${peerAddr}`);
                                if (
                                    getAddress(peerAddr) !=
                                    getAddress(lockboxes[lockboxChain][lockbox] as string)
                                ) {
                                    console.log(
                                        `${lockbox} Peer : ${lockboxChain} <=> ${oftChain} : ${getAddress(peerAddr) ==
                                        getAddress(lockboxes[lockboxChain][lockbox] as string)
                                        }`
                                    );
                                } else {
                                    try {
                                        const sendLibSrc = await chains[
                                            lockboxChain
                                        ].client.readContract({
                                            address: chains[lockboxChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "getSendLibrary",
                                            args: [
                                                lockboxes[lockboxChain][lockbox],
                                                chains[oftChain].peerId,
                                            ],
                                        });
                                        const isDefaultSendLibSrc = await chains[
                                            lockboxChain
                                        ].client.readContract({
                                            address: chains[lockboxChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "isDefaultSendLibrary",
                                            args: [
                                                lockboxes[lockboxChain][lockbox],
                                                chains[oftChain].peerId,
                                            ],
                                        });

                                        if (
                                            getAddress(sendLibSrc) !=
                                            getAddress(chains[lockboxChain].sendLib302)
                                        ) {
                                            console.log(
                                                `${lockbox} SendLibSrc : ${lockboxChain} => ${oftChain} : ${getAddress(sendLibSrc) ==
                                                getAddress(chains[lockboxChain].sendLib302)
                                                }`
                                            );
                                        } else if (isDefaultSendLibSrc) {
                                            console.log(
                                                `${lockbox} SendLibSrc : ${lockboxChain} => ${oftChain} : default`
                                            );
                                        }
                                    } catch (error) {
                                        console.log(
                                            `Error calling getSendLibrary Src : ${lockboxChain} => ${oftChain}`
                                        );
                                    }
                                    try {
                                        const sendLibDest = await chains[
                                            oftChain
                                        ].client.readContract({
                                            address: chains[oftChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "getSendLibrary",
                                            args: [peerAddr, chains[lockboxChain].peerId],
                                        });
                                        const isDefaultSendLibDest = await chains[
                                            oftChain
                                        ].client.readContract({
                                            address: chains[oftChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "isDefaultSendLibrary",
                                            args: [peerAddr, chains[lockboxChain].peerId],
                                        });
                                        if (
                                            getAddress(sendLibDest) !=
                                            getAddress(chains[oftChain].sendLib302)
                                        ) {
                                            console.log(
                                                `${lockbox} SendLibDest : ${oftChain} => ${lockboxChain} : ${getAddress(sendLibDest) ==
                                                getAddress(chains[oftChain].sendLib302)
                                                }`
                                            );
                                        } else if (isDefaultSendLibDest) {
                                            console.log(
                                                `${lockbox} SendLibDest : ${lockboxChain} => ${oftChain} : default`
                                            );
                                        }
                                    } catch (error) {
                                        console.log(
                                            `Error calling getSendLibrary Dest : ${oftChain} => ${lockboxChain}`
                                        );
                                    }
                                    try {
                                        const receiveLibSrc = await chains[
                                            lockboxChain
                                        ].client.readContract({
                                            address: chains[lockboxChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "getReceiveLibrary",
                                            args: [peerAddr, chains[lockboxChain].peerId],
                                        });
                                        if (
                                            getAddress(receiveLibSrc[0]) !=
                                            getAddress(chains[lockboxChain].receiveLib302)
                                        ) {
                                            console.log(
                                                `${lockbox} ReceiveLibSrc : ${lockboxChain} => ${oftChain} : ${getAddress(receiveLibSrc[0]) ==
                                                getAddress(chains[lockboxChain].receiveLib302)
                                                }`
                                            );
                                        } else if (receiveLibSrc[1]) {
                                            console.log(
                                                `${lockbox} ReceiveLibSrc : ${lockboxChain} => ${oftChain} : default`
                                            );
                                        }
                                    } catch (error) {
                                        console.log(
                                            `Error calling getReceiveLibrary Src : ${lockboxChain} => ${oftChain}`
                                        );
                                    }
                                    try {
                                        const receiveLibDest = await chains[
                                            oftChain
                                        ].client.readContract({
                                            address: chains[oftChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "getReceiveLibrary",
                                            args: [
                                                lockboxes[lockboxChain][lockbox],
                                                chains[oftChain].peerId,
                                            ],
                                        });
                                        if (
                                            getAddress(receiveLibDest[0]) !=
                                            getAddress(chains[oftChain].receiveLib302)
                                        ) {
                                            console.log(
                                                `${lockbox} ReceiveLibDest : ${oftChain} => ${lockboxChain} : ${getAddress(receiveLibDest[0]) ==
                                                getAddress(chains[oftChain].receiveLib302)
                                                }`
                                            );
                                        } else if (receiveLibDest[1]) {
                                            console.log(
                                                `${lockbox} ReceiveLibDest : ${oftChain} => ${lockboxChain} : default`
                                            );
                                        }
                                    } catch (error) {
                                        console.log(
                                            `Error calling getReceiveLibrary Dest : ${oftChain} => ${lockboxChain}`
                                        );
                                    }
                                }
                            }
                        } catch (error) {
                            try {
                                const originPeer = await chains[oftChain].client.readContract({
                                    address: peerAddress,
                                    abi: OFT_ADAPTER_ABI,
                                    functionName: "peers",
                                    args: [chains[lockboxChain].peerId],
                                });
                                const peerStr =
                                    typeof originPeer == "string"
                                        ? originPeer.toString()
                                        : bytes32Zero;
                                const isPeerZeroBytes32 =
                                    peerStr.toLowerCase() === bytes32Zero.toLowerCase();
                                const peerAddr = getAddress("0x" + peerStr.slice(-40));
                                // console.log(`${fraxLegacyChain} : ${peerAddr}`);
                                if (getAddress(peerAddr) != getAddress(lockboxes[lockbox][lockbox] as string)) {
                                    console.log(
                                        `${lockbox} : ${lockboxChain} <=> ${oftChain} : ${getAddress(peerAddr) ==
                                        getAddress(lockboxes[lockboxChain][lockbox] as string)
                                        }`
                                    );
                                } else {
                                    try {
                                        const sendLibSrc = await chains[
                                            lockboxChain
                                        ].client.readContract({
                                            address: chains[lockboxChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "getSendLibrary",
                                            args: [
                                                lockboxes[lockboxChain][lockbox],
                                                chains[oftChain].peerId,
                                            ],
                                        });
                                        const isDefaultSendLibSrc = await chains[
                                            lockboxChain
                                        ].client.readContract({
                                            address: chains[lockboxChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "isDefaultSendLibrary",
                                            args: [
                                                lockboxes[lockboxChain][lockbox],
                                                chains[oftChain].peerId,
                                            ],
                                        });

                                        if (
                                            getAddress(sendLibSrc) !=
                                            getAddress(chains[lockboxChain].sendLib302)
                                        ) {
                                            console.log(
                                                `${lockbox} SendLibSrc : ${lockboxChain} => ${oftChain} : ${getAddress(sendLibSrc) ==
                                                getAddress(chains[lockboxChain].sendLib302)
                                                }`
                                            );
                                        } else if (isDefaultSendLibSrc) {
                                            console.log(
                                                `${lockbox} SendLibSrc : ${lockboxChain} => ${oftChain} : default`
                                            );
                                        }
                                    } catch (error) {
                                        console.log(
                                            `Error calling getSendLibrary Src : ${lockboxChain} => ${oftChain}`
                                        );
                                    }
                                    try {
                                        const sendLibDest = await chains[
                                            oftChain
                                        ].client.readContract({
                                            address: chains[oftChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "getSendLibrary",
                                            args: [peerAddr, chains[lockboxChain].peerId],
                                        });
                                        const isDefaultSendLibDest = await chains[
                                            oftChain
                                        ].client.readContract({
                                            address: chains[oftChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "isDefaultSendLibrary",
                                            args: [peerAddr, chains[lockboxChain].peerId],
                                        });
                                        if (
                                            getAddress(sendLibDest) !=
                                            getAddress(chains[oftChain].sendLib302)
                                        ) {
                                            console.log(
                                                `${lockbox} SendLibDest : ${oftChain} => ${lockboxChain} : ${getAddress(sendLibDest) ==
                                                getAddress(chains[oftChain].sendLib302)
                                                }`
                                            );
                                        } else if (isDefaultSendLibDest) {
                                            console.log(
                                                `${lockbox} SendLibDest : ${lockboxChain} => ${oftChain} : default`
                                            );
                                        }
                                    } catch (error) {
                                        console.log(
                                            `Error calling getSendLibrary Dest : ${oftChain} => ${lockboxChain}`
                                        );
                                    }
                                    try {
                                        const receiveLibSrc = await chains[
                                            lockboxChain
                                        ].client.readContract({
                                            address: chains[lockboxChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "getReceiveLibrary",
                                            args: [peerAddr, chains[lockboxChain].peerId],
                                        });
                                        if (
                                            getAddress(receiveLibSrc[0]) !=
                                            getAddress(chains[lockboxChain].receiveLib302)
                                        ) {
                                            console.log(
                                                `${lockbox} ReceiveLibSrc : ${lockboxChain} => ${oftChain} : ${getAddress(receiveLibSrc[0]) ==
                                                getAddress(chains[lockboxChain].receiveLib302)
                                                }`
                                            );
                                        } else if (receiveLibSrc[1]) {
                                            console.log(
                                                `${lockbox} ReceiveLibSrc : ${lockboxChain} => ${oftChain} : default`
                                            );
                                        }
                                    } catch (error) {
                                        console.log(
                                            `Error calling getReceiveLibrary Src : ${lockboxChain} => ${oftChain}`
                                        );
                                    }
                                    try {
                                        const receiveLibDest = await chains[
                                            oftChain
                                        ].client.readContract({
                                            address: chains[oftChain].endpoint,
                                            abi: ENDPOINT_ABI,
                                            functionName: "getReceiveLibrary",
                                            args: [
                                                lockboxes[lockboxChain][lockbox],
                                                chains[oftChain].peerId,
                                            ],
                                        });
                                        if (
                                            getAddress(receiveLibDest[0]) !=
                                            getAddress(chains[oftChain].receiveLib302)
                                        ) {
                                            console.log(
                                                `${lockbox} ReceiveLibDest : ${oftChain} => ${lockboxChain} : ${getAddress(receiveLibDest[0]) ==
                                                getAddress(chains[oftChain].receiveLib302)
                                                }`
                                            );
                                        } else if (receiveLibDest[1]) {
                                            console.log(
                                                `${lockbox} ReceiveLibDest : ${oftChain} => ${lockboxChain} : default`
                                            );
                                        }
                                    } catch (error) {
                                        console.log(
                                            `Error calling getReceiveLibrary Dest : ${oftChain} => ${lockboxChain}`
                                        );
                                    }
                                }
                            } catch (error) {
                                console.log("No OFT on ", oftChain, peerAddress);
                            }
                        }
                    } else {
                        console.log(`${lockbox} : ${lockboxChain} != ${oftChain}`);
                    }
                } catch (error) {
                    console.log("Error ", oftChain);
                }
            });
        });
    });

    const srcChains: any[] = [];
    oftChains.forEach((oftChain: string) => {
        srcChains.push(oftChain);
        const remainingOftChains = getFilteredChainNames(oftChains, srcChains);
        Object.keys(tokens).forEach((tokenName) => {
            remainingOftChains.forEach(async (remainingOftChain: string) => {
                let originAddr = tokens[tokenName] as string;
                let tnName = tokenName;
                if (oftChain == "base" || oftChain == "metis" || oftChain == "blast") {
                    if (tokenName == "frxUSD") {
                        tnName = "FRAX";
                    }
                    if (tokenName == "sfrxUSD") {
                        tnName = "sFRAX";
                    }
                    originAddr = legacyTokens[tnName] as string;
                }
                try {
                    const code = await chains[oftChain].client.getCode({
                        address: originAddr,
                    });
                    if (code.length == 0) {
                        console.log("No origin OFT ", oftChain, tnName);
                    } else {
                        const peer = await chains[oftChain].client.readContract({
                            address: originAddr,
                            abi: OFT_ADAPTER_ABI,
                            functionName: "peers",
                            args: [chains[remainingOftChain].peerId],
                        });
                        const peerString =
                            typeof peer == "string" ? peer.toString() : bytes32Zero;
                        const isPeerZeroBytes32 =
                            peerString.toLowerCase() === bytes32Zero.toLowerCase();
                        const peerAddress = getAddress("0x" + peerString.slice(-40));
                        if (!isPeerZeroBytes32) {
                            try {
                                const code = await chains[remainingOftChain].client.getCode({
                                    address: peerAddress,
                                });
                                if (code.length == 0) {
                                    console.log("No OFT on ", remainingOftChain);
                                } else {
                                    const originPeer = await chains[
                                        remainingOftChain
                                    ].client.readContract({
                                        address: peerAddress,
                                        abi: OFT_ADAPTER_ABI,
                                        functionName: "peers",
                                        args: [chains[oftChain].peerId],
                                    });
                                    const peerStr =
                                        typeof originPeer == "string"
                                            ? originPeer.toString()
                                            : bytes32Zero;
                                    const isPeerZeroBytes32 =
                                        peerStr.toLowerCase() === bytes32Zero.toLowerCase();
                                    const peerAddr = getAddress("0x" + peerStr.slice(-40));
                                    // console.log(`${fraxLegacyChain} : ${peerAddr}`);
                                    if (getAddress(peerAddr) != getAddress(originAddr as string)) {
                                        console.log(
                                            `${tnName} : ${oftChain} <=> ${remainingOftChain} : ${getAddress(peerAddr) == getAddress(originAddr as string)
                                            }`
                                        );
                                    } else {
                                        try {
                                            const sendLibSrc = await chains[
                                                oftChain
                                            ].client.readContract({
                                                address: chains[oftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "getSendLibrary",
                                                args: [originAddr, chains[remainingOftChain].peerId],
                                            });
                                            const isDefaultSendLibSrc = await chains[
                                                oftChain
                                            ].client.readContract({
                                                address: chains[oftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "isDefaultSendLibrary",
                                                args: [originAddr, chains[remainingOftChain].peerId],
                                            });

                                            if (
                                                getAddress(sendLibSrc) !=
                                                getAddress(chains[oftChain].sendLib302)
                                            ) {
                                                console.log(
                                                    `${tnName} SendLibSrc : ${oftChain} => ${remainingOftChain} : ${getAddress(sendLibSrc) ==
                                                    getAddress(chains[oftChain].sendLib302)
                                                    }`
                                                );
                                            } else if (isDefaultSendLibSrc) {
                                                console.log(
                                                    `${tnName} SendLibSrc : ${oftChain} => ${remainingOftChain} : default`
                                                );
                                            }
                                        } catch (error) {
                                            console.log(
                                                `Error calling getSendLibrary Src : ${oftChain} => ${remainingOftChain}`
                                            );
                                        }
                                        try {
                                            const sendLibDest = await chains[
                                                remainingOftChain
                                            ].client.readContract({
                                                address: chains[remainingOftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "getSendLibrary",
                                                args: [peerAddr, chains[oftChain].peerId],
                                            });
                                            const isDefaultSendLibDest = await chains[
                                                remainingOftChain
                                            ].client.readContract({
                                                address: chains[remainingOftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "isDefaultSendLibrary",
                                                args: [peerAddr, chains[oftChain].peerId],
                                            });
                                            if (
                                                getAddress(sendLibDest) !=
                                                getAddress(chains[remainingOftChain].sendLib302)
                                            ) {
                                                console.log(
                                                    `${tnName} SendLibDest : ${remainingOftChain} => ${oftChain} : ${getAddress(sendLibDest) ==
                                                    getAddress(chains[remainingOftChain].sendLib302)
                                                    }`
                                                );
                                            } else if (isDefaultSendLibDest) {
                                                console.log(
                                                    `${tnName} SendLibDest : ${remainingOftChain} => ${oftChain} : default`
                                                );
                                            }
                                        } catch (error) {
                                            console.log(
                                                `Error calling getSendLibrary Dest : ${remainingOftChain} => ${oftChain}`
                                            );
                                        }
                                        try {
                                            const receiveLibSrc = await chains[
                                                oftChain
                                            ].client.readContract({
                                                address: chains[oftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "getReceiveLibrary",
                                                args: [peerAddr, chains[oftChain].peerId],
                                            });
                                            if (
                                                getAddress(receiveLibSrc[0]) !=
                                                getAddress(chains[oftChain].receiveLib302)
                                            ) {
                                                console.log(
                                                    `${tnName} ReceiveLibSrc : ${oftChain} => ${remainingOftChain} : ${getAddress(receiveLibSrc[0]) ==
                                                    getAddress(chains[oftChain].receiveLib302)
                                                    }`
                                                );
                                            } else if (receiveLibSrc[1]) {
                                                console.log(
                                                    `${tnName} ReceiveLibSrc : ${oftChain} => ${remainingOftChain} : default`
                                                );
                                            }
                                        } catch (error) {
                                            console.log(
                                                `Error calling getReceiveLibrary Src : ${oftChain} => ${remainingOftChain}`
                                            );
                                        }
                                        try {
                                            const receiveLibDest = await chains[
                                                remainingOftChain
                                            ].client.readContract({
                                                address: chains[remainingOftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "getReceiveLibrary",
                                                args: [originAddr, chains[remainingOftChain].peerId],
                                            });
                                            if (
                                                getAddress(receiveLibDest[0]) !=
                                                getAddress(chains[remainingOftChain].receiveLib302)
                                            ) {
                                                console.log(
                                                    `${tnName} ReceiveLibDest : ${remainingOftChain} => ${oftChain} : ${getAddress(receiveLibDest[0]) ==
                                                    getAddress(chains[remainingOftChain].receiveLib302)
                                                    }`
                                                );
                                            } else if (receiveLibDest[1]) {
                                                console.log(
                                                    `${tnName} ReceiveLibDest : ${remainingOftChain} => ${oftChain} : default`
                                                );
                                            }
                                        } catch (error) {
                                            console.log(
                                                `Error calling getReceiveLibrary Dest : ${remainingOftChain} => ${oftChain}`
                                            );
                                        }
                                    }
                                }
                            } catch (error) {
                                try {
                                    const originPeer = await chains[
                                        remainingOftChain
                                    ].client.readContract({
                                        address: peerAddress,
                                        abi: OFT_ADAPTER_ABI,
                                        functionName: "peers",
                                        args: [chains[oftChain].peerId],
                                    });
                                    const peerStr =
                                        typeof originPeer == "string"
                                            ? originPeer.toString()
                                            : bytes32Zero;
                                    const isPeerZeroBytes32 =
                                        peerStr.toLowerCase() === bytes32Zero.toLowerCase();
                                    const peerAddr = getAddress("0x" + peerStr.slice(-40));
                                    // console.log(`${fraxLegacyChain} : ${peerAddr}`);
                                    if (getAddress(peerAddr) != getAddress(originAddr as string)) {
                                        console.log(
                                            `${tnName} : ${oftChain} <=> ${remainingOftChain} : ${getAddress(peerAddr) == getAddress(originAddr)
                                            }`
                                        );
                                    } else {
                                        try {
                                            const sendLibSrc = await chains[
                                                oftChain
                                            ].client.readContract({
                                                address: chains[oftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "getSendLibrary",
                                                args: [originAddr, chains[remainingOftChain].peerId],
                                            });
                                            const isDefaultSendLibSrc = await chains[
                                                oftChain
                                            ].client.readContract({
                                                address: chains[oftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "isDefaultSendLibrary",
                                                args: [originAddr, chains[remainingOftChain].peerId],
                                            });

                                            if (
                                                getAddress(sendLibSrc) !=
                                                getAddress(chains[oftChain].sendLib302)
                                            ) {
                                                console.log(
                                                    `${tnName} SendLibSrc : ${oftChain} => ${remainingOftChain} : ${getAddress(sendLibSrc) ==
                                                    getAddress(chains[oftChain].sendLib302)
                                                    }`
                                                );
                                            } else if (isDefaultSendLibSrc) {
                                                console.log(
                                                    `${tnName} SendLibSrc : ${oftChain} => ${remainingOftChain} : default`
                                                );
                                            }
                                        } catch (error) {
                                            console.log(
                                                `Error calling getSendLibrary Src : ${oftChain} => ${remainingOftChain}`
                                            );
                                        }
                                        try {
                                            const sendLibDest = await chains[
                                                remainingOftChain
                                            ].client.readContract({
                                                address: chains[remainingOftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "getSendLibrary",
                                                args: [peerAddr, chains[oftChain].peerId],
                                            });
                                            const isDefaultSendLibDest = await chains[
                                                remainingOftChain
                                            ].client.readContract({
                                                address: chains[remainingOftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "isDefaultSendLibrary",
                                                args: [peerAddr, chains[oftChain].peerId],
                                            });
                                            if (
                                                getAddress(sendLibDest) !=
                                                getAddress(chains[remainingOftChain].sendLib302)
                                            ) {
                                                console.log(
                                                    `${tnName} SendLibDest : ${remainingOftChain} => ${oftChain} : ${getAddress(sendLibDest) ==
                                                    getAddress(chains[remainingOftChain].sendLib302)
                                                    }`
                                                );
                                            } else if (isDefaultSendLibDest) {
                                                console.log(
                                                    `${tnName} SendLibDest : ${remainingOftChain} => ${oftChain} : default`
                                                );
                                            }
                                        } catch (error) {
                                            console.log(
                                                `Error calling getSendLibrary Dest : ${remainingOftChain} => ${oftChain}`
                                            );
                                        }
                                        try {
                                            const receiveLibSrc = await chains[
                                                oftChain
                                            ].client.readContract({
                                                address: chains[oftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "getReceiveLibrary",
                                                args: [peerAddr, chains[oftChain].peerId],
                                            });
                                            if (
                                                getAddress(receiveLibSrc[0]) !=
                                                getAddress(chains[oftChain].receiveLib302)
                                            ) {
                                                console.log(
                                                    `${tnName} ReceiveLibSrc : ${oftChain} => ${remainingOftChain} : ${getAddress(receiveLibSrc[0]) ==
                                                    getAddress(chains[oftChain].receiveLib302)
                                                    }`
                                                );
                                            } else if (receiveLibSrc[1]) {
                                                console.log(
                                                    `${tnName} ReceiveLibSrc : ${oftChain} => ${remainingOftChain} : default`
                                                );
                                            }
                                        } catch (error) {
                                            console.log(
                                                `Error calling getReceiveLibrary Src : ${oftChain} => ${remainingOftChain}`
                                            );
                                        }
                                        try {
                                            const receiveLibDest = await chains[
                                                remainingOftChain
                                            ].client.readContract({
                                                address: chains[remainingOftChain].endpoint,
                                                abi: ENDPOINT_ABI,
                                                functionName: "getReceiveLibrary",
                                                args: [originAddr, chains[remainingOftChain].peerId],
                                            });
                                            if (
                                                getAddress(receiveLibDest[0]) !=
                                                getAddress(chains[remainingOftChain].receiveLib302)
                                            ) {
                                                console.log(
                                                    `${tnName} ReceiveLibDest : ${remainingOftChain} => ${oftChain} : ${getAddress(receiveLibDest[0]) ==
                                                    getAddress(chains[remainingOftChain].receiveLib302)
                                                    }`
                                                );
                                            } else if (receiveLibDest[1]) {
                                                console.log(
                                                    `${tnName} ReceiveLibDest : ${remainingOftChain} => ${oftChain} : default`
                                                );
                                            }
                                        } catch (error) {
                                            console.log(
                                                `Error calling getReceiveLibrary Dest : ${remainingOftChain} => ${oftChain}`
                                            );
                                        }
                                    }
                                } catch (error) {
                                    console.log(
                                        "No OFT on ",
                                        remainingOftChain,
                                        peerAddress
                                    );
                                }
                            }
                        } else {
                            console.log(`${tnName} : ${oftChain} != ${remainingOftChain}`);
                        }
                    }
                } catch (error) {
                    console.log("Error ", oftChain, tnName, originAddr);
                }
            });
        });
    });
}

function getFilteredChainNames(chains: string[], excludedChains: string[]) {
    return chains.filter((chain: string) => !excludedChains.includes(chain));
}

main();
