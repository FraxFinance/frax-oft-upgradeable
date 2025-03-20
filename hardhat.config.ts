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
// import './tasks/index'

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
        fraxtal:{
            eid: EndpointId.FRAXTAL_V2_MAINNET,
            url: process.env.RPC_URL_FRAXTAL || 'https://rpc.frax.com/',
            accounts,
        },
        ethereum:{
            eid: EndpointId.ETHEREUM_V2_MAINNET,
            url: process.env.RPC_URL_ETHEREUM || 'https://ethereum-rpc.publicnode.com',
            accounts,
        },
        blast:{
            eid: EndpointId.BLAST_V2_MAINNET,
            url: process.env.RPC_URL_BLAST || 'https://rpc.blast.io',
            accounts,
        },
        base:{
            eid: EndpointId.BASE_V2_MAINNET,
            url: process.env.RPC_URL_BASE || 'https://mainnet.base.org',
            accounts,
        },
        mode:{
            eid: EndpointId.MODE_V2_MAINNET,
            url: process.env.RPC_URL_MODE || 'https://mainnet.mode.network',
            accounts,
        },
        sei:{
            eid: EndpointId.SEI_V2_MAINNET,
            url: process.env.RPC_URL_SEI || 'https://twilight-crimson-grass.sei-pacific.quiknode.pro/1fe7cb5c6950df0f3ebceead37f8eefdf41ddbe9/',
            accounts,
        },
        xlayer:{
            eid: EndpointId.XLAYER_V2_MAINNET,
            url: process.env.RPC_URL_XLAYER || 'https://rpc.xlayer.tech',
            accounts,
        },
        sonic:{
            eid: EndpointId.SONIC_V2_MAINNET,
            url: process.env.RPC_URL_SONIC || 'https://rpc.soniclabs.com',
            accounts,
        },
        ink:{
            eid: EndpointId.INK_V2_MAINNET,
            url: process.env.RPC_URL_INK || 'https://rpc-gel.inkonchain.com',
            accounts,
        },
        arbitrum:{
            eid: EndpointId.ARBITRUM_V2_MAINNET,
            url: process.env.RPC_URL_ARBITRUM || 'https://endpoints.omniatech.io/v1/arbitrum/one/public',
            accounts,
        },
        optimism:{
            eid: EndpointId.OPTIMISM_V2_MAINNET,
            url: process.env.RPC_URL_OPTIMISM || 'https://optimism-rpc.publicnode.com',
            accounts,
        },
        polygon:{
            eid: EndpointId.POLYGON_V2_MAINNET,
            url: process.env.RPC_URL_POLYGON || 'https://polygon-rpc.com',
            accounts,
        },
        avalanche:{
            eid: EndpointId.AVALANCHE_V2_MAINNET,
            url: process.env.RPC_URL_AVALANCHE || 'https://avalanche-c-chain-rpc.publicnode.com',
            accounts,
        },
        bsc:{
            eid: EndpointId.BSC_V2_MAINNET,
            url: process.env.RPC_URL_BSC || 'https://bsc-rpc.publicnode.com',
            accounts,
        },
        zkevm:{
            eid: EndpointId.ZKPOLYGON_V2_MAINNET,
            url: process.env.RPC_URL_ZKEVM || 'https://endpoints.omniatech.io/v1/polygon-zkevm/mainnet/public',
            accounts,
        },
        linea:{
            eid: EndpointId.ZKCONSENSYS_V2_MAINNET,
            url: process.env.RPC_URL_LINEA || 'https://rpc.linea.build',
            accounts,
        },
        berachain:{
            eid: EndpointId.BERA_V2_MAINNET,
            url: process.env.RPC_URL_BERACHAIN || 'https://rpc.berachain.com',
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
