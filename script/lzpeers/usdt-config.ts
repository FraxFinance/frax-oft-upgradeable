import { bytesToHex, createPublicClient, decodeAbiParameters, getAddress, Hex, hexToBytes, http, padHex, toHex } from "viem";
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
import { createUmi } from "@metaplex-foundation/umi-bundle-defaults";
import { publicKey } from "@metaplex-foundation/umi";
import { oft302 } from "@layerzerolabs/oft-v2-solana-sdk";
import { default as ENDPOINT_ABI } from "./abis/ENDPOINT_ABI.json"
import { default as OFT_ADAPTER_ABI } from "./abis/OFT_ADAPTER_ABI.json"
import { default as RECEIVE_ULN302_ABI } from "./abis/RECEIVE_ULN302_ABI.json"
import { default as SEND_ULN302_ABI } from "./abis/SEND_ULN302_ABI.json"
import fs from "fs"
import * as dotenv from "dotenv";

dotenv.config();

const bytes32Zero =
    "0x0000000000000000000000000000000000000000000000000000000000000000";

function decodeLzReceiveOption(encodedOption: Hex) {
    const optionBytes = hexToBytes(encodedOption);
    const length = optionBytes.length;

    if (length < 16) throw new Error(`Invalid data length: ${length} bytes`);

    const extractedData = optionBytes.slice(-16); // Always extract last 16 bytes
    const isValuePresent = length >= 32;

    if (!isValuePresent) {
        const [gas] = decodeAbiParameters([{ type: "uint128" }], padHex(bytesToHex(extractedData), { size: 32 }));
        return { gas, value: 0n }; // If value is absent, return 0n
    } else {
        const extractedData32 = optionBytes.slice(-32); // Extract last 32 bytes
        console.log(bytesToHex(extractedData32))
        const [gas, value] = decodeAbiParameters([{ type: "uint128" }, { type: "uint128" }], bytesToHex(extractedData32));
        return { gas, value };
    }
}

// Define the UlnConfig type
interface UlnConfig {
    confirmations: number;
    requiredDVNCount: number;
    optionalDVNCount: number;
    optionalDVNThreshold: number;
    requiredDVNs: string[];
    optionalDVNs: string[];
}

type assetListType = {
    USDT: string;
    // frxUSD: string;
    // sfrxUSD: string;
    // frxETH: string;
    // sfrxETH: string;
    // FXS: string;
    // FPI: string;
    // PYUSDADAPTER: string
    // PYUSDLOCKER:string
    // USDG:string
    // USDP:string
    // USDL:string
}

const solanaOFTs: Record<string, Record<string, string>> = {
    frxUSD: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "GzX1ireZDU865FiMaKrdVB1H6AE8LAqWYCg6chrMrfBw",
        "mintAuthority": "52e8UiVqx28VEqyiEqMbMVehFC3LheNGqnA9m82XF6GK",
        "escrow": "84AFSH3TSzyjbEFJX9z8sjpV7npTWq7f8ZR5zkLG22hX",
        "oftStore": "7LS6y37WXXCyBHkBU6zVpiqaqbkXLr4P85ZhQi3eonSp"
    },
    sfrxUSD: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "DUvWQMyASSkLNJFwsMDA4kwxEvmfaqpPGrvUVKtitX45",
        "mintAuthority": "EK2qrg4ggSVmxNDU3qSvVcKx7HYpmNT3kWbLHMtL5vaV",
        "escrow": "8vRGMiktFX3VhQRfwkaWsAG3KHHzVnRYEKkDKEYzgmCa",
        "oftStore": "A28EK6j1euK4e6taP1KLFpGEoR1mDpXR4vtfiyCE1Nxv"
    },
    frxETH: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "5sDrwVNiHMM2jC78hRBH1CtysDQYiNKihubgW2zNu8tf",
        "mintAuthority": "Ea6GvxUc4xh4LoPgJXePhKFsUcuW8G2RASdNYyuoohxr",
        "escrow": "H17Anco2cnEtSyfSwt4XKhsU7nbFyP57qqXhsff39UW3",
        "oftStore": "4pyqBQFhzsuL7ED76x3AyzT4bCVpMpQWXhS1LqEsfQtz"
    },
    sfrxETH: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "58zpC9acE6F4FBtd88L64NoWHJcmzLsQSy5bjz35Ydgv",
        "mintAuthority": "BVQcQygw2f6nrDu6HNTfQ1ECjRRx8nm2CnBANt4yqqvp",
        "escrow": "AmjMhAYdCz2crdKYG4U9WMPT7ccHsXSx12qJ5TTjoHYq",
        "oftStore": "DsJYjDF5yVSopMC15q9W42v833MhWGhCxcU2J39oS3wN"
    },
    FXS: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "zZbQjiRg8uSxZaPu996XuviuZeSY6nsaMuutKZQBJga",
        "mintAuthority": "CMCA6bzoCH4KcDZtwCviFYF2c5tasLHjEhX8ThMeCpqk",
        "escrow": "FwmRDpyFBLkdk7BLRkWF5p5DqwBX2LzVTARGkG5haHbV",
        "oftStore": "5vqBiG7nxNnoCst8mEVVS6ax7C1ypEEenPfcZ4kLgj9B"
    },
    FPI: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "8xKX8CRH9LxriRUNCPittu1jiovyQQr4EonWQjHZjWyH",
        "mintAuthority": "F3YLUzqvJndUpypxUgxsFZQFHD3KUNC5QrkpNJKLBGje",
        "escrow": "EPmy89v6at8rxrV2n1E3xZP74MzaGi7BWdFNiA2xW64Z",
        "oftStore": "FFozEKoFQ1CZD6Kn7bpwAxaWhK1jEA76pjucvBBHf9ZH"
    }
}

async function main() {
    type ChainInfo = {
        client: any; // Replace `any` with the actual type from `createPublicClient`
        peerId: number;
        endpoint: string;
        receiveLib302: string;
        sendLib302: string;
        oApps?: assetListType;
    };

    type OFTEnforcedOptions = {
        gas: string;
        value: string;
    }

    type ReceiveLibraryTimeOutInfo = {
        libAddress: string;
        expiry: string;
    }

    type EndpointConfig = {
        send: UlnConfig;
        receive: UlnConfig;
    }

    type ReceiveLibraryType = {
        receiveLibraryAddress: string
        isDefault: boolean
    }

    type ExecutorConfigType = {
        maxMessageSize: number
        executorAddress: string
    }

    type OFTInfo = {
        peerAddress: string;
        peerAddressBytes32: string;
        combinedOptionsSend: OFTEnforcedOptions
        combinedOptionsSendAndCall: OFTEnforcedOptions
        enforcedOptions: OFTEnforcedOptions
        defaultReceiveLibrary: string;
        defaultReceiveLibraryTimeOut: ReceiveLibraryTimeOutInfo;
        defaultSendLibrary: string;
        appUlnConfig: EndpointConfig;
        appUlnDefaultConfig: EndpointConfig;
        ulnConfig: EndpointConfig;
        ulnDefaultConfig: EndpointConfig;
        receiveLibSupportEid: boolean;
        defaultReceiveLibSupportEid: boolean;
        sendLibSupportEid: boolean;
        defaultSendLibSupportEid: boolean;
        receiveLibrary: ReceiveLibraryType;
        sendLibrary: string;
        isDefaultSendLibrary: boolean;
        receiveLibraryTimeOut: ReceiveLibraryTimeOutInfo;
        executorConfig: ExecutorConfigType;
        defaultExecutorConfig: ExecutorConfigType;
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
            oApps: {
                USDT: "0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee",
                // frxUSD: "0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0",
                // sfrxUSD: "0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126",
                // frxETH: "0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6",
                // sfrxETH: "0xbBc424e58ED38dd911309611ae2d7A23014Bd960",
                // FXS: "0xC6F59a4fD50cAc677B51558489E03138Ac1784EC",
                // FPI: "0x9033BAD7aA130a2466060A2dA71fAe2219781B4b",
                // PYUSDADAPTER: "0x688e72142674041f8f6Af4c808a4045cA1D6aC82"
                // PYUSDLOCKER:"0xFA0e06B54986ad96DE87a8c56Fea76FBD8d493F8"
            }
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
                transport: http("https://evm-rpc.sei-apis.com"),
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
        solana: {
            client: createUmi("https://api.mainnet-beta.solana.com"),
            peerId: 30168,
            endpoint: "76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6",
            receiveLib302: "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH",
            sendLib302: "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH",
        }
        // TODO:
        // Movement
        // Aptos
        // Stretch Goal : Initia
    };

    const ofts: Record<string, Record<string, Record<string, OFTInfo>>> = {}
    const chainArr = Object.keys(chains)


    for (let chainArrIndex = 0; chainArrIndex < chainArr.length; chainArrIndex++) {
        const srcChain = chainArr[chainArrIndex];
        if (chains[srcChain].oApps === undefined) { continue }

        for (const oAppName of Object.keys(chains[srcChain].oApps as assetListType)) {
            let contractCalls: any[] = [];
            const oApp = chains[srcChain].oApps?.[oAppName as keyof assetListType]
            const oftContract = {
                address: oApp,
                abi: OFT_ADAPTER_ABI,
            } as const;

            if (ofts[oAppName] === undefined) {
                ofts[oAppName] = {} as Record<string, Record<string, OFTInfo>>
            }
            if (ofts[oAppName][srcChain] === undefined) {
                ofts[oAppName][srcChain] = {} as Record<string, OFTInfo>
            }

            if (srcChain === "solana") {
                // add to ofts
                for (const destChainName of Object.keys(chains)) {
                    const peerInfo = await oft302.getPeerAddress(
                        chains[srcChain].client.rpc,
                        publicKey(solanaOFTs[oAppName].oftStore), //oftStore
                        chains[destChainName].peerId,
                        publicKey(solanaOFTs[oAppName].programId), //programId
                    )

                    if (peerInfo && peerInfo !== bytes32Zero) {
                        ofts[oAppName][srcChain][destChainName] = {} as OFTInfo
                        ofts[oAppName][srcChain][destChainName].peerAddressBytes32 = peerInfo
                        ofts[oAppName][srcChain][destChainName].peerAddress = getAddress(
                            "0x" + peerInfo.slice(-40)
                        );
                        if (chains[destChainName].oApps === undefined) {
                            chains[destChainName].oApps = {} as assetListType
                        }
                        chains[destChainName].oApps[oAppName as keyof assetListType] = ofts[oAppName][srcChain][destChainName].peerAddress
                    }
                }
            }
            else if (srcChain === "ink") {
                // add to ofts
                for (const destChainName of Object.keys(chains)) {
                    const peerInfo = await chains[srcChain].client.readContract({
                        ...oftContract,
                        functionName: "peers",
                        args: [chains[destChainName].peerId]
                    })

                    if (peerInfo && peerInfo !== bytes32Zero) {
                        ofts[oAppName][srcChain][destChainName] = {} as OFTInfo
                        ofts[oAppName][srcChain][destChainName].peerAddressBytes32 = peerInfo
                        ofts[oAppName][srcChain][destChainName].peerAddress = getAddress(
                            "0x" + peerInfo.slice(-40)
                        );
                        if (chains[destChainName].oApps === undefined) {
                            chains[destChainName].oApps = {} as assetListType
                        }
                        chains[destChainName].oApps[oAppName as keyof assetListType] = ofts[oAppName][srcChain][destChainName].peerAddress
                    }
                }
            }
            else {// get peers
                Object.keys(chains).forEach(async (destChainName) => {
                    contractCalls.push({
                        ...oftContract,
                        functionName: "peers",
                        args: [chains[destChainName].peerId],
                    });
                });

                const peers = await chains[srcChain].client.multicall({
                    contracts: contractCalls,
                });

                // add to ofts
                Object.keys(chains).forEach((destChainName, index) => {
                    if (peers[index].result) {
                        if (peers[index].result != bytes32Zero) {
                            ofts[oAppName][srcChain][destChainName] = {} as OFTInfo
                            ofts[oAppName][srcChain][destChainName].peerAddressBytes32 = peers[index].result
                            ofts[oAppName][srcChain][destChainName].peerAddress = getAddress(
                                "0x" + peers[index].result.slice(-40)
                            );
                            if (chains[destChainName].oApps === undefined) {
                                chains[destChainName].oApps = {} as assetListType
                            }
                            chains[destChainName].oApps[oAppName as keyof assetListType] = ofts[oAppName][srcChain][destChainName].peerAddress
                        }
                    }
                });
            }

            if (srcChain === "solana") {
                for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
                    let oftres = await oft302.getEnforcedOptions(chains[srcChain].client.rpc,
                        publicKey(solanaOFTs[oAppName].oftStore), //oftStore,
                        chains[destChainName].peerId,
                        publicKey(solanaOFTs[oAppName].programId), //programId
                    )

                    let opt
                    if (oftres.send.length > 0) {
                        opt = decodeLzReceiveOption(toHex(oftres.send))
                        ofts[oAppName][srcChain][destChainName].combinedOptionsSend = {} as OFTEnforcedOptions
                        ofts[oAppName][srcChain][destChainName].combinedOptionsSend.gas = opt.gas.toString()
                        ofts[oAppName][srcChain][destChainName].combinedOptionsSend.value = opt.value.toString()
                    }

                    if (oftres.sendAndCall.length > 0) {
                        opt = decodeLzReceiveOption(toHex(oftres.sendAndCall))
                        ofts[oAppName][srcChain][destChainName].enforcedOptions = {} as OFTEnforcedOptions
                        ofts[oAppName][srcChain][destChainName].enforcedOptions.gas = opt.gas.toString()
                        ofts[oAppName][srcChain][destChainName].enforcedOptions.value = opt.value.toString()
                    }
                }
            }
            else if (srcChain === "ink") {
                for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
                    let oftres = await chains[srcChain].client.readContract({
                        ...oftContract,
                        functionName: "combineOptions",
                        args: [chains[destChainName].peerId, 1, "0x"],
                    })
                    let opt
                    if (oftres !== "0x") {
                        opt = decodeLzReceiveOption(oftres)
                        ofts[oAppName][srcChain][destChainName].combinedOptionsSend = {} as OFTEnforcedOptions
                        ofts[oAppName][srcChain][destChainName].combinedOptionsSend.gas = opt.gas.toString()
                        ofts[oAppName][srcChain][destChainName].combinedOptionsSend.value = opt.value.toString()
                    }

                    // TODO
                    // oftres = oftOptions[(index * 4) + 1]
                    // opt = decodeLzReceiveOption(oftres.result)
                    // ofts[destChainName].combinedOptionsSendAndCall = {} as OFTEnforceedOptions
                    // ofts[destChainName].combinedOptionsSendAndCall.gas = opt.gas.toString()
                    // ofts[destChainName].combinedOptionsSendAndCall.value = opt.value.toString()
                    oftres = await chains[srcChain].client.readContract({
                        ...oftContract,
                        functionName: "enforcedOptions",
                        args: [chains[destChainName].peerId, 3],
                    })
                    if (oftres !== "0x") {
                        opt = decodeLzReceiveOption(oftres)
                        ofts[oAppName][srcChain][destChainName].enforcedOptions = {} as OFTEnforcedOptions
                        ofts[oAppName][srcChain][destChainName].enforcedOptions.gas = opt.gas.toString()
                        ofts[oAppName][srcChain][destChainName].enforcedOptions.value = opt.value.toString()
                    }
                }
            }
            else {
                contractCalls = [];
                Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName) => {
                    // oft.combineOptions (_eid (uint32), _msgType (uint16), _extraOptions (bytes)) : bytes
                    contractCalls.push({
                        ...oftContract,
                        functionName: "combineOptions",
                        args: [chains[destChainName].peerId, 1, "0x"],
                    });
                    contractCalls.push({
                        ...oftContract,
                        functionName: "combineOptions",
                        args: [chains[destChainName].peerId, 2, "0x"],
                    });
                    // oft.enforcedOptions (_eid (uint32), _msgType (uint16)) : bytes
                    contractCalls.push({
                        ...oftContract,
                        functionName: "enforcedOptions",
                        args: [chains[destChainName].peerId, 3],
                    });
                    // oft.isPeer (_eid (uint32), _peer (bytes32)) : bool
                    contractCalls.push({
                        ...oftContract,
                        functionName: "isPeer",
                        args: [chains[destChainName].peerId, ofts[oAppName][srcChain][destChainName].peerAddressBytes32],
                    });
                });

                const oftOptions = await chains[srcChain].client.multicall({
                    contracts: contractCalls,
                });

                // add to ofts
                Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName, index) => {
                    let oftres = oftOptions[index * 4]
                    let opt
                    if (oftres.result) {
                        opt = decodeLzReceiveOption(oftres.result)
                        ofts[oAppName][srcChain][destChainName].combinedOptionsSend = {} as OFTEnforcedOptions
                        if (oftres.result !== "0x") {
                            ofts[oAppName][srcChain][destChainName].combinedOptionsSend.gas = opt.gas.toString()
                            ofts[oAppName][srcChain][destChainName].combinedOptionsSend.value = opt.value.toString()
                        }
                    }
                    // TODO
                    // oftres = oftOptions[(index * 4) + 1]
                    // opt = decodeLzReceiveOption(oftres.result)
                    // ofts[destChainName].combinedOptionsSendAndCall = {} as OFTEnforceedOptions
                    // ofts[destChainName].combinedOptionsSendAndCall.gas = opt.gas.toString()
                    // ofts[destChainName].combinedOptionsSendAndCall.value = opt.value.toString()
                    oftres = oftOptions[(index * 4) + 2]
                    if (oftres.result) {
                        ofts[oAppName][srcChain][destChainName].enforcedOptions = {} as OFTEnforcedOptions
                        if (oftres.result !== "0x") {
                            opt = decodeLzReceiveOption(oftres.result)
                            ofts[oAppName][srcChain][destChainName].enforcedOptions.gas = opt.gas.toString()
                            ofts[oAppName][srcChain][destChainName].enforcedOptions.value = opt.value.toString()
                        }
                    }
                })
            }

            // OFT
            // TODO oft.sharedDecimals : uint8
            // TODO oft.token : address

            // // endpoint.delegates (oapp (address)) : delegate address
            // contractCalls.push({
            //     ...endpointContract,
            //     functionName: "delegates",
            //     args: [USDT_lockbox],
            // });

            // endpoint
            let endpointContract:any
            if (srcChain !== "solana") {
                // oft.endpoint : address
                const endpointAddress = await chains[srcChain].client.readContract({
                    address: oApp,
                    abi: OFT_ADAPTER_ABI,
                    functionName: "endpoint",
                });
                endpointContract = {
                    address: endpointAddress,
                    abi: ENDPOINT_ABI,
                } as const;
                if (srcChain !== "ink") {
                    contractCalls = [];
                    Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName) => {

                        // endpoint.defaultReceiveLibrary (srcEid (uint32)) : lib address
                        contractCalls.push({
                            ...endpointContract,
                            functionName: "defaultReceiveLibrary",
                            args: [chains[destChainName].peerId],
                        });
                        // endpoint.defaultReceiveLibraryTimeout (srcEid (uint32)) : lib address, expiry uint256
                        contractCalls.push({
                            ...endpointContract,
                            functionName: "defaultReceiveLibraryTimeout",
                            args: [chains[destChainName].peerId],
                        });
                        // endpoint.defaultSendLibrary (dstEid (uint32)) : lib address
                        contractCalls.push({
                            ...endpointContract,
                            functionName: "defaultSendLibrary",
                            args: [chains[destChainName].peerId],
                        });
                    });

                    const endpointInfo = await chains[srcChain].client.multicall({
                        contracts: contractCalls,
                    });

                    // add to ofts
                    Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName, index) => {
                        let oftres = endpointInfo[index * 3]
                        ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary = oftres.result
                        oftres = endpointInfo[(index * 3) + 1]
                        ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut = {} as ReceiveLibraryTimeOutInfo
                        ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.libAddress = oftres.result[0]
                        ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.expiry = oftres.result[1].toString()
                        oftres = endpointInfo[(index * 3) + 2]
                        ofts[oAppName][srcChain][destChainName].defaultSendLibrary = oftres.result
                    })
                } else {
                    // add to ofts
                    for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
                        let oftres = await chains[srcChain].client.readContract({
                            ...endpointContract,
                            functionName: "defaultReceiveLibrary",
                            args: [chains[destChainName].peerId],
                        })
                        ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary = oftres
                        oftres = await chains[srcChain].client.readContract({
                            ...endpointContract,
                            functionName: "defaultReceiveLibraryTimeout",
                            args: [chains[destChainName].peerId],
                        })
                        ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut = {} as ReceiveLibraryTimeOutInfo
                        ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.libAddress = oftres[0]
                        ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.expiry = oftres[1].toString()
                        oftres = await chains[srcChain].client.readContract({
                            ...endpointContract,
                            functionName: "defaultSendLibrary",
                            args: [chains[destChainName].peerId],
                        })
                        ofts[oAppName][srcChain][destChainName].defaultSendLibrary = oftres
                    }
                }
            } else if (srcChain === "solana") {
                // add to ofts
                // for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
                // let oftres = await oft302.li.getEndpointConfig(
                //     chains[srcChain].client.rpc,
                //     publicKey(solanaOFTs[oAppName].oftStore), //oftStore
                // chains[destChainName].peerId,
                // publicKey(solanaOFTs[oAppName].programId), //programId
                // )
                // let oftres = await chains[srcChain].client.readContract({
                //     ...endpointContract,
                //     functionName: "defaultReceiveLibrary",
                //     args: [chains[destChainName].peerId],
                // })
                // ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary = oftres
                // oftres = await chains[srcChain].client.readContract({
                //     ...endpointContract,
                //     functionName: "defaultReceiveLibraryTimeout",
                //     args: [chains[destChainName].peerId],
                // })
                // ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut = {} as ReceiveLibraryTimeOutInfo
                // ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.libAddress = oftres[0]
                // ofts[oAppName][srcChain][destChainName].defaultReceiveLibraryTimeOut.expiry = oftres[1].toString()
                // oftres = await chains[srcChain].client.readContract({
                //     ...endpointContract,
                //     functionName: "defaultSendLibrary",
                //     args: [chains[destChainName].peerId],
                // })
                // ofts[oAppName][srcChain][destChainName].defaultSendLibrary = oftres
                // }

            }

            // TODO endpoint.eid : 30101 uint32
            // TODO endpoint.getRegisteredLibraries : address[]

            if (srcChain !== "ink") {
                contractCalls = [];
                Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName) => {
                    // endpoint.getReceiveLibrary (_receiver (address), _srcEid (uint32)) : lib address, isDefault bool
                    contractCalls.push({
                        ...endpointContract,
                        functionName: "getReceiveLibrary",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    // endpoint.getSendLibrary (_sender (address),_dstEid (uint32)) : lib address
                    contractCalls.push({
                        ...endpointContract,
                        functionName: "getSendLibrary",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    // endpoint.isDefaultSendLibrary (_sender (address),_dstEid (uint32)) : bool
                    contractCalls.push({
                        ...endpointContract,
                        functionName: "isDefaultSendLibrary",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    // endpoint.receiveLibraryTimeout (receiver (address), srcEid (uint32)) : lib address, expiry uint256
                    contractCalls.push({
                        ...endpointContract,
                        functionName: "receiveLibraryTimeout",
                        args: [oApp, chains[destChainName].peerId],
                    });
                });

                // TODO endpoint.getSendContext : eid uint32, sender address

                const endpointInfo2 = await chains[srcChain].client.multicall({
                    contracts: contractCalls,
                });

                // add to ofts
                Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName, index) => {
                    ofts[oAppName][srcChain][destChainName].receiveLibrary = {} as ReceiveLibraryType
                    ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut = {} as ReceiveLibraryTimeOutInfo
                    // let oftres = endpointInfo2[index * 6]
                    // let decoded = decodeUlnConfig(oftres.result)
                    // ofts[oAppName][srcChain][destChainName].config.receive.confirmations = Number(decoded.confirmations)
                    // ofts[oAppName][srcChain][destChainName].config.receive.requiredDVNCount = decoded.requiredDVNCount
                    // ofts[oAppName][srcChain][destChainName].config.receive.optionalDVNCount = decoded.optionalDVNCount
                    // ofts[oAppName][srcChain][destChainName].config.receive.optionalDVNThreshold = decoded.optionalDVNThreshold
                    // oftres = endpointInfo2[(index * 6) + 1]
                    // decoded = decodeUlnConfig(oftres.result)
                    // ofts[oAppName][srcChain][destChainName].config.send.confirmations = Number(decoded.confirmations)
                    // ofts[oAppName][srcChain][destChainName].config.send.requiredDVNCount = decoded.requiredDVNCount
                    // ofts[oAppName][srcChain][destChainName].config.send.optionalDVNCount = decoded.optionalDVNCount
                    // ofts[oAppName][srcChain][destChainName].config.send.optionalDVNThreshold = decoded.optionalDVNThreshold
                    let oftres = endpointInfo2[(index * 4)]
                    ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress = oftres.result[0]
                    ofts[oAppName][srcChain][destChainName].receiveLibrary.isDefault = oftres.result[1]
                    oftres = endpointInfo2[(index * 4) + 1]
                    ofts[oAppName][srcChain][destChainName].sendLibrary = oftres.result
                    oftres = endpointInfo2[(index * 4) + 2]
                    ofts[oAppName][srcChain][destChainName].isDefaultSendLibrary = oftres.result
                    oftres = endpointInfo2[(index * 4) + 3]
                    ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut.libAddress = oftres.result[0]
                    ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut.expiry = oftres.result[1].toString()
                })
            } else {
                // add to ofts
                for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {
                    // endpoint.getReceiveLibrary (_receiver (address), _srcEid (uint32)) : lib address, isDefault bool
                    contractCalls.push();
                    // endpoint.getSendLibrary (_sender (address),_dstEid (uint32)) : lib address
                    contractCalls.push();
                    // endpoint.isDefaultSendLibrary (_sender (address),_dstEid (uint32)) : bool
                    contractCalls.push();
                    // endpoint.receiveLibraryTimeout (receiver (address), srcEid (uint32)) : lib address, expiry uint256
                    contractCalls.push();
                    ofts[oAppName][srcChain][destChainName].receiveLibrary = {} as ReceiveLibraryType
                    ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut = {} as ReceiveLibraryTimeOutInfo

                    let oftres = await chains[srcChain].client.readContract({
                        ...endpointContract,
                        functionName: "getReceiveLibrary",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress = oftres[0]
                    ofts[oAppName][srcChain][destChainName].receiveLibrary.isDefault = oftres[1]
                    oftres = await chains[srcChain].client.readContract({
                        ...endpointContract,
                        functionName: "getSendLibrary",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].sendLibrary = oftres
                    oftres = await chains[srcChain].client.readContract({
                        ...endpointContract,
                        functionName: "isDefaultSendLibrary",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].isDefaultSendLibrary = oftres
                    oftres = await chains[srcChain].client.readContract({
                        ...endpointContract,
                        functionName: "receiveLibraryTimeout",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut.libAddress = oftres[0]
                    ofts[oAppName][srcChain][destChainName].receiveLibraryTimeOut.expiry = oftres[1].toString()
                }
            }



            // ReceiveUln302
            if (srcChain !== "ink") {
                contractCalls = [];
                Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName) => {
                    // receiveUln302.getAppUlnConfig (_oapp (address), _remoteEid (uint32)) : tuple
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "getAppUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "getAppUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    // receiveUln302.getUlnConfig (_oapp (address), _remoteEid (uint32)) : rtnConfig tuple
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "getUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "getUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    // receiveUln302.isSupportedEid (_eid (uint32)) : bool
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "isSupportedEid",
                        args: [chains[destChainName].peerId],
                    });
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "isSupportedEid",
                        args: [chains[destChainName].peerId],
                    });
                });

                const receiveULN302Info = await chains[srcChain].client.multicall({
                    contracts: contractCalls,
                });

                // add to ofts
                Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName, index) => {
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig = {} as EndpointConfig
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive = {} as UlnConfig
                    ofts[oAppName][srcChain][destChainName].appUlnConfig = {} as EndpointConfig
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive = {} as UlnConfig

                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig = {} as EndpointConfig
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive = {} as UlnConfig
                    ofts[oAppName][srcChain][destChainName].ulnConfig = {} as EndpointConfig
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive = {} as UlnConfig

                    let oftres = receiveULN302Info[index * 6]
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.confirmations = Number(oftres.result.confirmations)
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.requiredDVNCount = oftres.result.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNCount = oftres.result.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNThreshold = oftres.result.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.requiredDVNs = [...oftres.result.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNs = [...oftres.result.optionalDVNs]
                    oftres = receiveULN302Info[(index * 6) + 1]
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.confirmations = Number(oftres.result.confirmations)
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.requiredDVNCount = oftres.result.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNCount = oftres.result.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNThreshold = oftres.result.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.requiredDVNs = [...oftres.result.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNs = [...oftres.result.optionalDVNs]
                    oftres = receiveULN302Info[(index * 6) + 2]
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.confirmations = Number(oftres.result.confirmations)
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.requiredDVNCount = oftres.result.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNCount = oftres.result.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNThreshold = oftres.result.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.requiredDVNs = [...oftres.result.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNs = [...oftres.result.optionalDVNs]
                    oftres = receiveULN302Info[(index * 6) + 3]
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.confirmations = Number(oftres.result.confirmations)
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.requiredDVNCount = oftres.result.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNCount = oftres.result.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNThreshold = oftres.result.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.requiredDVNs = [...oftres.result.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNs = [...oftres.result.optionalDVNs]
                    oftres = receiveULN302Info[(index * 6) + 4]
                    ofts[oAppName][srcChain][destChainName].defaultReceiveLibSupportEid = oftres.result
                    oftres = receiveULN302Info[(index * 6) + 5]
                    ofts[oAppName][srcChain][destChainName].receiveLibSupportEid = oftres.result
                })
            } else {
                for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {

                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig = {} as EndpointConfig
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive = {} as UlnConfig
                    ofts[oAppName][srcChain][destChainName].appUlnConfig = {} as EndpointConfig
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive = {} as UlnConfig

                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig = {} as EndpointConfig
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive = {} as UlnConfig
                    ofts[oAppName][srcChain][destChainName].ulnConfig = {} as EndpointConfig
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive = {} as UlnConfig

                    let oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "getAppUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.confirmations = Number(oftres.confirmations)
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.requiredDVNCount = oftres.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNCount = oftres.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNThreshold = oftres.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.requiredDVNs = [...oftres.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.receive.optionalDVNs = [...oftres.optionalDVNs]

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "getAppUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.confirmations = Number(oftres.confirmations)
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.requiredDVNCount = oftres.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNCount = oftres.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNThreshold = oftres.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.requiredDVNs = [...oftres.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.receive.optionalDVNs = [...oftres.optionalDVNs]

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "getUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.confirmations = Number(oftres.confirmations)
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.requiredDVNCount = oftres.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNCount = oftres.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNThreshold = oftres.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.requiredDVNs = [...oftres.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].ulnConfig.receive.optionalDVNs = [...oftres.optionalDVNs]

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "getUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.confirmations = Number(oftres.confirmations)
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.requiredDVNCount = oftres.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNCount = oftres.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNThreshold = oftres.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.requiredDVNs = [...oftres.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.receive.optionalDVNs = [...oftres.optionalDVNs]

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].defaultReceiveLibrary,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "isSupportedEid",
                        args: [chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].defaultReceiveLibSupportEid = oftres

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].receiveLibrary.receiveLibraryAddress,
                        abi: RECEIVE_ULN302_ABI,
                        functionName: "isSupportedEid",
                        args: [chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].receiveLibSupportEid = oftres

                }
            }

            // SendUln302
            if (srcChain !== "ink") {
                contractCalls = [];
                Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName) => {
                    // senduln302.getAppUlnConfig (_oapp (address), _remoteEid (uint32)) : tuple
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getAppUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getAppUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    // senduln302.getExecutorConfig (_oapp (address) , _remoteEid (uint32)) :  rtnConfig tuple
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getExecutorConfig",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getExecutorConfig",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    // senduln302.getUlnConfig (_oapp (address), _remoteEid (uint32)) : rtnConfig tuple
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    });
                    // senduln302.isSupportedEid (_eid (uint32)) : bool
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "isSupportedEid",
                        args: [chains[destChainName].peerId],
                    });
                    contractCalls.push({
                        address: ofts[oAppName][srcChain][destChainName].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "isSupportedEid",
                        args: [chains[destChainName].peerId],
                    });
                });

                const sendULN302Info = await chains[srcChain].client.multicall({
                    contracts: contractCalls,
                });

                // add to ofts
                Object.keys(ofts[oAppName][srcChain]).forEach(async (destChainName, index) => {
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send = {} as UlnConfig
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send = {} as UlnConfig

                    ofts[oAppName][srcChain][destChainName].defaultExecutorConfig = {} as ExecutorConfigType
                    ofts[oAppName][srcChain][destChainName].executorConfig = {} as ExecutorConfigType

                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send = {} as UlnConfig
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send = {} as UlnConfig

                    let oftres = sendULN302Info[index * 8]
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.confirmations = Number(oftres.result.confirmations)
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.requiredDVNCount = oftres.result.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNCount = oftres.result.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNThreshold = oftres.result.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.requiredDVNs = [...oftres.result.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNs = [...oftres.result.optionalDVNs]

                    oftres = sendULN302Info[(index * 8) + 1]
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.confirmations = Number(oftres.result.confirmations)
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.requiredDVNCount = oftres.result.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNCount = oftres.result.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNThreshold = oftres.result.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.requiredDVNs = [...oftres.result.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNs = [...oftres.result.optionalDVNs]

                    oftres = sendULN302Info[(index * 8) + 2]
                    ofts[oAppName][srcChain][destChainName].defaultExecutorConfig.maxMessageSize = oftres.result.maxMessageSize
                    ofts[oAppName][srcChain][destChainName].defaultExecutorConfig.executorAddress = oftres.result.executor

                    oftres = sendULN302Info[(index * 8) + 3]
                    ofts[oAppName][srcChain][destChainName].executorConfig.maxMessageSize = oftres.result.maxMessageSize
                    ofts[oAppName][srcChain][destChainName].executorConfig.executorAddress = oftres.result.executor

                    oftres = sendULN302Info[(index * 8) + 4]
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.confirmations = Number(oftres.result.confirmations)
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.requiredDVNCount = oftres.result.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNCount = oftres.result.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNThreshold = oftres.result.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.requiredDVNs = [...oftres.result.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNs = [...oftres.result.optionalDVNs]

                    oftres = sendULN302Info[(index * 8) + 5]
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.confirmations = Number(oftres.result.confirmations)
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.requiredDVNCount = oftres.result.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNCount = oftres.result.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNThreshold = oftres.result.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.requiredDVNs = [...oftres.result.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNs = [...oftres.result.optionalDVNs]

                    oftres = sendULN302Info[(index * 8) + 6]
                    ofts[oAppName][srcChain][destChainName].defaultSendLibSupportEid = oftres.result

                    oftres = sendULN302Info[(index * 8) + 7]
                    ofts[oAppName][srcChain][destChainName].sendLibSupportEid = oftres.result
                })
            } else {
                // add to ofts
                for (const destChainName of Object.keys(ofts[oAppName][srcChain])) {

                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send = {} as UlnConfig
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send = {} as UlnConfig

                    ofts[oAppName][srcChain][destChainName].defaultExecutorConfig = {} as ExecutorConfigType
                    ofts[oAppName][srcChain][destChainName].executorConfig = {} as ExecutorConfigType

                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send = {} as UlnConfig
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send = {} as UlnConfig

                    let oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getAppUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.confirmations = Number(oftres.confirmations)
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.requiredDVNCount = oftres.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNCount = oftres.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNThreshold = oftres.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.requiredDVNs = [...oftres.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].appUlnDefaultConfig.send.optionalDVNs = [...oftres.optionalDVNs]

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getAppUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.confirmations = Number(oftres.confirmations)
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.requiredDVNCount = oftres.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNCount = oftres.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNThreshold = oftres.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.requiredDVNs = [...oftres.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].appUlnConfig.send.optionalDVNs = [...oftres.optionalDVNs]

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getExecutorConfig",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].defaultExecutorConfig.maxMessageSize = oftres.maxMessageSize
                    ofts[oAppName][srcChain][destChainName].defaultExecutorConfig.executorAddress = oftres.executor

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getExecutorConfig",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].executorConfig.maxMessageSize = oftres.maxMessageSize
                    ofts[oAppName][srcChain][destChainName].executorConfig.executorAddress = oftres.executor

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.confirmations = Number(oftres.confirmations)
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.requiredDVNCount = oftres.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNCount = oftres.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNThreshold = oftres.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.requiredDVNs = [...oftres.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].ulnDefaultConfig.send.optionalDVNs = [...oftres.optionalDVNs]

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "getUlnConfig",
                        args: [oApp, chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.confirmations = Number(oftres.confirmations)
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.requiredDVNCount = oftres.requiredDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNCount = oftres.optionalDVNCount
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNThreshold = oftres.optionalDVNThreshold
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.requiredDVNs = [...oftres.requiredDVNs]
                    ofts[oAppName][srcChain][destChainName].ulnConfig.send.optionalDVNs = [...oftres.optionalDVNs]

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].defaultSendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "isSupportedEid",
                        args: [chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].defaultSendLibSupportEid = oftres.result

                    oftres = await chains[srcChain].client.readContract({
                        address: ofts[oAppName][srcChain][destChainName].sendLibrary,
                        abi: SEND_ULN302_ABI,
                        functionName: "isSupportedEid",
                        args: [chains[destChainName].peerId],
                    })
                    ofts[oAppName][srcChain][destChainName].sendLibSupportEid = oftres.result
                }
            }
        };
    }
    // Assuming `ofts` is already defined
    fs.writeFileSync('config-all.json', JSON.stringify(ofts, null, 2), 'utf-8');

    console.log('Data written to output.json');
}

main();
