import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OAppEnforcedOption, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import L0Config from "../L0Config.json"
import { zeroAddress } from 'viem'
import { readFileSync } from 'fs'
import path from 'path'


const dvnConfigPath = "config/dvn"

const chainIds = [
    1, 252
] as const;
const dvnKeys = ['bcwGroup', 'frax', 'horizen', 'lz', 'nethermind', 'stargate'] as const;

const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_MAINNET,
    address: "A28EK6j1euK4e6taP1KLFpGEoR1mDpXR4vtfiyCE1Nxv",
}

enum MsgType {
    SEND = 1,
    SEND_AND_CALL = 2,
}

const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: MsgType.SEND,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 150_000,
        value: 0,
    },
    {
        msgType: MsgType.SEND_AND_CALL,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 150_000,
        value: 0,
    },
]

const SOLANA_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: MsgType.SEND,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 200_000,
        value: 2_500_000,
    },
    {
        msgType: MsgType.SEND_AND_CALL,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 200_000,
        value: 2_500_000,
    },
]

// Learn about Message Execution Options: https://docs.layerzero.network/v2/developers/solana/oft/account#message-execution-options
// Learn more about the Simple Config Generator - https://docs.layerzero.network/v2/developers/evm/technical-reference/simple-config
export default async function () {
    const srcDVNConfig = JSON.parse(readFileSync(path.join(__dirname, `../../${dvnConfigPath}/111111111.json`), "utf8"));
    const contracts: any = []
    const connectionConfigs: any = []
    for (const _chainid of chainIds) {
        let eid = 0
        for (const config of L0Config["Proxy"]) {
            if (config.chainid === _chainid) {
                eid = config.eid;
                break;
            }
        }

        if (eid === 0) throw Error(`EID not found for chainid: ${_chainid}`)
        let OFTAddress = zeroAddress as string
        if (_chainid === 1) {
            OFTAddress = "0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126"
        } else if (_chainid === 252) {
            OFTAddress = "0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361"
        } else {
            throw Error(`OFT not found for chainid: ${_chainid}`)
        }
        if (OFTAddress === zeroAddress) throw Error(`OFT not found for chainid: ${_chainid}`)

        const requiredSrcDVNs: string[] = []
        const dstDVNConfig = JSON.parse(readFileSync(path.join(__dirname, `../../${dvnConfigPath}/${_chainid}.json`), "utf8"));

        dvnKeys.forEach(key => {
            const dst = dstDVNConfig["111111111"]?.[key] ?? zeroAddress;
            const src = srcDVNConfig[_chainid]?.[key] ?? zeroAddress;

            if (dst !== zeroAddress || src !== zeroAddress) {
                if (dst === zeroAddress || src === zeroAddress) {
                    throw new Error(`DVN Stack misconfigured: ${_chainid}<>solana-${key}`);
                }
                let dvnName = ""
                switch (key) {
                    case "bcwGroup":
                        dvnName = "BCW Group"
                        break;
                    case "frax":
                        dvnName = "Frax"
                        break;
                    case "horizen":
                        dvnName = "Horizen"
                        break;
                    case "lz":
                        dvnName = "LayerZero Labs"
                        break;
                    case "nethermind":
                        dvnName = "Nethermind"
                        break;
                    case "stargate":
                        dvnName = "Stargate"
                        break;
                    default:
                        throw new Error(`DVN ${key} not found for ${_chainid}`)
                }
                requiredSrcDVNs.push(dvnName);
            }
        });

        const evmContract = {
            eid: eid,
            contractName: _chainid === 252 ? "MockFraxMintableOFT" : "MockFrax",
            address: OFTAddress
        }
        contracts.push({ contract: evmContract })
        // note: pathways declared here are automatically bidirectional
        // if you declare A,B there's no need to declare B,A
        connectionConfigs.push([
            evmContract, // Chain A contract
            solanaContract, // Chain B contract
            [requiredSrcDVNs, []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
            [15, 32], // [A to B confirmations, B to A confirmations]
            [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain B enforcedOptions, Chain A enforcedOptions
        ])
    }


    const connections = await generateConnectionsConfig([
        ...connectionConfigs
    ])

    return {
        contracts: [...contracts, { contract: solanaContract }],
        connections,
    }
}