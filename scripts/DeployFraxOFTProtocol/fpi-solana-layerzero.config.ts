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
    address: "FFozEKoFQ1CZD6Kn7bpwAxaWhK1jEA76pjucvBBHf9ZH",
}

enum MsgType {
    SEND = 1,
    SEND_AND_CALL = 2,
}

const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: MsgType.SEND,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 80000,
        value: 0,
    },
    {
        msgType: MsgType.SEND_AND_CALL,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 80000,
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
        let confirmations: number[] = []
        if (_chainid === 1) {
            OFTAddress = "0x9033BAD7aA130a2466060A2dA71fAe2219781B4b"
            confirmations = [15, 32]
        } else if (_chainid === 252) {
            OFTAddress = "0x75c38D46001b0F8108c4136216bd2694982C20FC"
            confirmations = [5, 32]
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
            contractName: "FPIOFT",
            address: OFTAddress
        }
        contracts.push({ contract: evmContract })
        // note: pathways declared here are automatically bidirectional
        // if you declare A,B there's no need to declare B,A
        connectionConfigs.push([
            evmContract, // Chain A contract
            solanaContract, // Chain B contract
            [requiredSrcDVNs, []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
            confirmations, // [A to B confirmations, B to A confirmations]
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