import { ethers, BigNumberish } from "ethers";
import * as dotenv from "dotenv";

interface OFTs {
    [key: string]: string;
}

interface Lockbox {
    RPC: string;
    OFTs: OFTs;
}

interface Lockboxes {
    [key: string]: Lockbox[];
}

const lockboxes: Lockboxes = {
    "Legacy": [
        {
            "RPC": "https://ethereum-rpc.publicnode.com",
            "OFTs": {
                "frxUSD": "0x909DBdE1eBE906Af95660033e478D59EFe831fED",
                "sfrxUSD": "0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E",
                "frxETH": "0xF010a7c8877043681D59AD125EbF575633505942",
                "sfrxETH": "0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A",
                "fxs": "0x23432452B720C80553458496D4D9d7C5003280d0",
                "fpi": "0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d"
            }
        }
    ],
    "Proxy": [
        {
            "RPC": "https://ethereum-rpc.publicnode.com",
            "OFTs": {
                "frxUSD": "0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0",
                "sfrxUSD": "0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126",
                "frxETH": "0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6",
                "sfrxETH": "0xbBc424e58ED38dd911309611ae2d7A23014Bd960",
                "fxs": "0xC6F59a4fD50cAc677B51558489E03138Ac1784EC",
                "fpi": "0x9033BAD7aA130a2466060A2dA71fAe2219781B4b"
            }
        },
        {
            "RPC": "https://rpc.frax.com",
            "OFTs": {
                "frxUSD": "0x96A394058E2b84A89bac9667B19661Ed003cF5D4",
                "sfrxUSD": "0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361",
                "frxETH": "0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604",
                "sfrxETH": "0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168",
                "fxs": "0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A",
                "fpi": "0x75c38D46001b0F8108c4136216bd2694982C20FC"
            }
        }
    ]
}

interface Balances {
    [key: string]: number;
}

let lockboxBalances: Balances = {
    "frxUSD": 0,
    "sfrxUSD": 0,
    "frxETH": 0,
    "sfrxETH": 0,
    "fxs": 0,
    "fpi": 0
}

let oftBalances: Balances = {
    "frxUSD": 0,
    "sfrxUSD": 0,
    "frxETH": 0,
    "sfrxETH": 0,
    "fxs": 0,
    "fpi": 0
}

interface Destinations {
    [key: string]: Destination[];
}

interface Destination {
    RPC: string;
    chainid: number;
    frxUSD: string;
    sfrxUSD: string;
    frxETH: string;
    sfrxETH: string;
    fxs: string;
    fpi: string;
}

import _destinations from "./assets/ofts.json";
const destinations: Destinations = _destinations;

main();

export async function main() {

    // for each lockbox
    for (let lockbox in lockboxes) {
        // for each lockbox instance
        for (let instance of lockboxes[lockbox]) {
            const provider = new ethers.providers.JsonRpcProvider(instance.RPC);
            // for each Adapter
            for (const [symbol, adapterAddress] of Object.entries(instance.OFTs)) {
                const adapterContract = new ethers.Contract(adapterAddress, [
                    "function token() view returns (address)"
                ], provider);
                const tokenAddress = await adapterContract.token();
                const tokenContract = new ethers.Contract(tokenAddress, [               
                    "function balanceOf(address) view returns (uint256)",
                ], provider);
                const balance = await tokenContract.balanceOf(adapterAddress);
                const balanceAsNumber = ethers.utils.formatEther(balance);
                lockboxBalances[symbol] += parseFloat(balanceAsNumber);
            }
        }
    }
    console.log("Lockbox Balances");
    console.log(lockboxBalances);
    console.log('\n');

    // for each destination
    for (let destination in destinations) {
        for (let instance of destinations[destination]) {
            const provider = new ethers.providers.JsonRpcProvider(instance.RPC);
            for (const [symbol, oftAddress] of Object.entries(instance)) {
                if (symbol === "RPC" || symbol === "chainid") continue;
                const oftContract = new ethers.Contract(oftAddress, [
                    "function totalSupply() view returns (address)"
                ], provider);
                const totalSupply = await oftContract.totalSupply();
                const totalSupplyAsNumber = ethers.utils.formatEther(totalSupply);
                oftBalances[symbol] += parseFloat(totalSupplyAsNumber);
            }
        }
    }

    console.log("OFT Balances");
    console.log(oftBalances);
}