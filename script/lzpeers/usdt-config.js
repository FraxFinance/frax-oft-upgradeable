"use strict";
var __assign = (this && this.__assign) || function () {
    __assign = Object.assign || function(t) {
        for (var s, i = 1, n = arguments.length; i < n; i++) {
            s = arguments[i];
            for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p))
                t[p] = s[p];
        }
        return t;
    };
    return __assign.apply(this, arguments);
};
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
Object.defineProperty(exports, "__esModule", { value: true });
var viem_1 = require("viem");
var chains_1 = require("viem/chains");
var dotenv = require("dotenv");
dotenv.config();
var OFT_ADAPTER_ABI = [
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
    {
        inputs: [],
        name: "endpoint",
        outputs: [
            {
                internalType: "contract ILayerZeroEndpointV2",
                name: "",
                type: "address",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
];
function main() {
    return __awaiter(this, void 0, void 0, function () {
        var chains, USDT_lockbox, endpointAddress, contractCalls, oftContract, peers;
        var _this = this;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    chains = {
                        ethereum: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.mainnet,
                                transport: (0, viem_1.http)("https://eth-mainnet.alchemyapi.io/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30101,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0xc02Ab410f0734EFa3F14628780e6e695156024C2",
                            sendLib302: "0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1",
                        },
                        fraxtal: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.fraxtal,
                                transport: (0, viem_1.http)(),
                            }),
                            peerId: 30255,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0x8bC1e36F015b9902B54b1387A4d733cebc2f5A4e",
                            sendLib302: "0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6",
                        },
                        base: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.base,
                                transport: (0, viem_1.http)("https://base-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30184,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf",
                            sendLib302: "0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2",
                        },
                        metis: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.metis,
                                transport: (0, viem_1.http)("https://metis-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30151,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0x5539Eb17a84E1D59d37C222Eb2CC4C81b502D1Ac",
                            sendLib302: "0x63e39ccB510926d05a0ae7817c8f1CC61C5BdD6c",
                        },
                        blast: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.blast,
                                transport: (0, viem_1.http)("https://blast-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30243,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6",
                            sendLib302: "0xc1B621b18187F74c8F6D52a6F709Dd2780C09821",
                        },
                        mode: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.mode,
                                transport: (0, viem_1.http)("https://mainnet.mode.network/"),
                            }),
                            peerId: 30260,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0xc1B621b18187F74c8F6D52a6F709Dd2780C09821",
                            sendLib302: "0x2367325334447C5E1E0f1b3a6fB947b262F58312",
                        },
                        sei: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.sei,
                                transport: (0, viem_1.http)("https://sei.drpc.org"),
                            }),
                            peerId: 30280,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
                            sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
                        },
                        xlayer: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.xLayer,
                                transport: (0, viem_1.http)("https://rpc.xlayer.tech"),
                            }),
                            peerId: 30274,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0x2367325334447C5E1E0f1b3a6fB947b262F58312",
                            sendLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
                        },
                        sonic: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.sonic,
                                transport: (0, viem_1.http)("https://sonic-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30332,
                            endpoint: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
                            receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
                            sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
                        },
                        ink: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.ink,
                                transport: (0, viem_1.http)("https://ink-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30339,
                            endpoint: "0xca29f3A6f966Cb2fc0dE625F8f325c0C46dbE958",
                            receiveLib302: "0x473132bb594caEF281c68718F4541f73FE14Dc89",
                            sendLib302: "0x76111DE813F83AAAdBD62773Bf41247634e2319a",
                        },
                        arbitrum: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.arbitrum,
                                transport: (0, viem_1.http)("https://arb-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30110,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6",
                            sendLib302: "0x975bcD720be66659e3EB3C0e4F1866a3020E493A",
                        },
                        optimism: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.optimism,
                                transport: (0, viem_1.http)("https://opt-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30111,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063",
                            sendLib302: "0x1322871e4ab09Bc7f5717189434f97bBD9546e95",
                        },
                        polygon: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.polygon,
                                transport: (0, viem_1.http)("https://polygon-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30109,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0x1322871e4ab09Bc7f5717189434f97bBD9546e95",
                            sendLib302: "0x6c26c61a97006888ea9E4FA36584c7df57Cd9dA3",
                        },
                        avalanche: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.avalanche,
                                transport: (0, viem_1.http)("https://avax-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30106,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0xbf3521d309642FA9B1c91A08609505BA09752c61",
                            sendLib302: "0x197D1333DEA5Fe0D6600E9b396c7f1B1cFCc558a",
                        },
                        bnb: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.bsc,
                                transport: (0, viem_1.http)("https://bsc-dataseed.binance.org"),
                            }),
                            peerId: 30102,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0xB217266c3A98C8B2709Ee26836C98cf12f6cCEC1",
                            sendLib302: "0x9F8C645f2D0b2159767Bd6E0839DE4BE49e823DE",
                        },
                        zkevm: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.polygonZkEvm,
                                transport: (0, viem_1.http)("https://polygonzkevm-mainnet.g.alchemy.com/v2/-qUruptd488TJA0HpIHhSmKny7kZ75FZ"),
                            }),
                            peerId: 30158,
                            endpoint: "0x1a44076050125825900e736c501f859c50fE728c",
                            receiveLib302: "0x581b26F362AD383f7B51eF8A165Efa13DDe398a4",
                            sendLib302: "0x28B6140ead70cb2Fb669705b3598ffB4BEaA060b",
                        },
                        zksync: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.zksync,
                                transport: (0, viem_1.http)(),
                            }),
                            peerId: 30165,
                            endpoint: "0xd07C30aF3Ff30D96BDc9c6044958230Eb797DDBF",
                            receiveLib302: "0x04830f6deCF08Dec9eD6C3fCAD215245B78A59e1",
                            sendLib302: "0x07fD0e370B49919cA8dA0CE842B8177263c0E12c",
                        },
                        abstract: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.abstract,
                                transport: (0, viem_1.http)(),
                            }),
                            peerId: 30324,
                            endpoint: "0x5c6cfF4b7C49805F8295Ff73C204ac83f3bC4AE7",
                            receiveLib302: "0x9d799c1935c51CA399e6465Ed9841DEbCcEc413E",
                            sendLib302: "0x166CAb679EBDB0853055522D3B523621b94029a1",
                        },
                        berachain: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.berachain,
                                transport: (0, viem_1.http)(),
                            }),
                            peerId: 30362,
                            endpoint: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
                            receiveLib302: "0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043",
                            sendLib302: "0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7",
                        },
                        linea: {
                            client: (0, viem_1.createPublicClient)({
                                chain: chains_1.linea,
                                transport: (0, viem_1.http)(),
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
                    USDT_lockbox = "0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee";
                    return [4 /*yield*/, chains.ethereum.client.readContract({
                            address: USDT_lockbox,
                            abi: OFT_ADAPTER_ABI,
                            functionName: "endpoint",
                        })];
                case 1:
                    endpointAddress = _a.sent();
                    console.log(endpointAddress);
                    contractCalls = [];
                    oftContract = {
                        address: USDT_lockbox,
                        abi: OFT_ADAPTER_ABI,
                    };
                    // get peers
                    Object.keys(chains).forEach(function (chainName) { return __awaiter(_this, void 0, void 0, function () {
                        return __generator(this, function (_a) {
                            if (chainName === "ethereum") {
                                return [2 /*return*/];
                            }
                            contractCalls.push(__assign(__assign({}, oftContract), { functionName: "peers", args: [chains[chainName].peerId] }));
                            return [2 /*return*/];
                        });
                    }); });
                    return [4 /*yield*/, chains.ethereum.client.multicall({
                            contracts: contractCalls,
                        })];
                case 2:
                    peers = _a.sent();
                    console.log(peers);
                    return [2 /*return*/];
            }
        });
    });
}
main();
