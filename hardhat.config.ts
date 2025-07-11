// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'

import 'hardhat-deploy'
import 'hardhat-contract-sizer'
import '@nomiclabs/hardhat-ethers'
import '@layerzerolabs/toolbox-hardhat'
import { HardhatUserConfig, HttpNetworkAccountsUserConfig } from 'hardhat/types'

import { EndpointId } from '@layerzerolabs/lz-definitions'

// TODO: uncomment while performing Solana ops
import './tasks/index'

// Set your preferred authentication method
//
// If you prefer using a mnemonic, set a MNEMONIC environment variable
// to a valid mnemonic
const MNEMONIC = process.env.MNEMONIC

// If you prefer to be authenticated using a private key, set a PRIVATE_KEY environment variable
const PRIVATE_KEY = process.env.PRIVATE_KEY

const accounts: HttpNetworkAccountsUserConfig | undefined = MNEMONIC
    ? { mnemonic: MNEMONIC }
    : PRIVATE_KEY
      ? [PRIVATE_KEY]
      : undefined

if (accounts == null) {
    console.warn(
        'Could not find MNEMONIC or PRIVATE_KEY environment variables. It will not be possible to execute transactions in your example.'
    )
}

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: '0.8.22',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
        "fraxtal-mainnet":{
            eid: EndpointId.FRAXTAL_V2_MAINNET,
            url: process.env.RPC_URL_FRAXTAL || 'https://rpc.frax.com/',
            accounts,
        },
        "ethereum-mainnet":{
            eid: EndpointId.ETHEREUM_V2_MAINNET,
            url: process.env.RPC_URL_ETHEREUM || 'https://ethereum-rpc.publicnode.com',
            accounts,
        },
        "blast-mainnet":{
            eid: EndpointId.BLAST_V2_MAINNET,
            url: process.env.RPC_URL_BLAST || 'https://rpc.blast.io',
            accounts,
        },
        "base-mainnet":{
            eid: EndpointId.BASE_V2_MAINNET,
            url: process.env.RPC_URL_BASE || 'https://1rpc.io/base',
            accounts,
        },
        "mode-mainnet":{
            eid: EndpointId.MODE_V2_MAINNET,
            url: process.env.RPC_URL_MODE || 'https://mainnet.mode.network',
            accounts,
        },
        "sei-mainnet":{
            eid: EndpointId.SEI_V2_MAINNET,
            url: process.env.RPC_URL_SEI || 'https://evm-rpc.sei-apis.com',
            accounts,
        },
        "xlayer-mainnet":{
            eid: EndpointId.XLAYER_V2_MAINNET,
            url: process.env.RPC_URL_XLAYER || 'https://endpoints.omniatech.io/v1/xlayer/mainnet/public',
            accounts,
        },
        "sonic-mainnet":{
            eid: EndpointId.SONIC_V2_MAINNET,
            url: process.env.RPC_URL_SONIC || 'https://rpc.soniclabs.com',
            accounts,
        },
        "ink-mainnet":{
            eid: EndpointId.INK_V2_MAINNET,
            url: process.env.RPC_URL_INK || 'https://rpc-gel.inkonchain.com',
            accounts,
        },
        "arbitrum-mainnet":{
            eid: EndpointId.ARBITRUM_V2_MAINNET,
            url: process.env.RPC_URL_ARBITRUM || 'https://arbitrum-one-rpc.publicnode.com',
            accounts,
        },
        "optimism-mainnet":{
            eid: EndpointId.OPTIMISM_V2_MAINNET,
            url: process.env.RPC_URL_OPTIMISM || 'https://optimism-rpc.publicnode.com',
            accounts,
        },
        "polygon-mainnet":{
            eid: EndpointId.POLYGON_V2_MAINNET,
            url: process.env.RPC_URL_POLYGON || 'https://polygon-rpc.com',
            accounts,
        },
        "avalanche-mainnet":{
            eid: EndpointId.AVALANCHE_V2_MAINNET,
            url: process.env.RPC_URL_AVALANCHE || 'https://avax-mainnet.g.alchemy.com/v2/ISqt4ylM2QDVoqg8av78v4Jz6Gb426JT',
            accounts,
        },
        "bsc-mainnet":{
            eid: EndpointId.BSC_V2_MAINNET,
            url: process.env.RPC_URL_BSC || 'https://bsc-rpc.publicnode.com',
            accounts,
        },
        "zkpolygon-mainnet":{
            eid: EndpointId.ZKPOLYGON_V2_MAINNET,
            url: process.env.RPC_URL_ZKEVM || 'https://polygon-zkevm-mainnet.public.blastapi.io',
            accounts,
        },
        "zkconsensys-mainnet":{
            eid: EndpointId.ZKCONSENSYS_V2_MAINNET,
            url: process.env.RPC_URL_LINEA || 'https://rpc.linea.build',
            accounts,
        },
        "bera-mainnet":{
            eid: EndpointId.BERA_V2_MAINNET,
            url: process.env.RPC_URL_BERACHAIN || 'https://rpc.berachain.com',
            accounts,
        },
        "worldchain-mainnet":{
            eid: EndpointId.WORLDCHAIN_V2_MAINNET,
            url: process.env.RPC_URL_WORLDCHAIN || 'https://worldchain-mainnet.gateway.tenderly.co',
            accounts,
        },
        "unichain-mainnet":{
            eid: EndpointId.UNICHAIN_V2_MAINNET,
            url: process.env.RPC_URL_UNICHAIN || 'https://unichain-rpc.publicnode.com',
            accounts,
        },
        "abstract-mainnet":{
            eid: EndpointId.ABSTRACT_V2_MAINNET,
            url: process.env.RPC_URL_ABSTRACT || 'https://api.mainnet.abs.xyz',
            accounts,
        },
        "zksync-mainnet":{
            eid: EndpointId.ZKSYNC_V2_MAINNET,
            url: process.env.RPC_URL_ZKSYNC || 'https://mainnet.era.zksync.io',
            accounts,
        },
        sepolia: {
            eid: EndpointId.SEPOLIA_V2_TESTNET,
            url: process.env.RPC_URL_SEPOLIA || 'https://rpc.sepolia.org/',
            accounts,
        },
        fuji: {
            eid: EndpointId.AVALANCHE_V2_TESTNET,
            url: process.env.RPC_URL_FUJI || 'https://rpc.ankr.com/avalanche_fuji',
            accounts,
        },
        amoy: {
            eid: EndpointId.AMOY_V2_TESTNET,
            url: process.env.RPC_URL_AMOY || 'https://polygon-amoy-bor-rpc.publicnode.com',
            accounts,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0, // wallet address of index[0], of the mnemonic in .env
        },
    },
}

export default config
