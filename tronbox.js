var HDWalletProvider = require("@truffle/hdwallet-provider");

const port = process.env.HOST_PORT || 9090

const privateKeys = [process.env.PK_OFT_DEPLOYER, process.env.PK_CONFIG_DEPLOYER]

module.exports = {
  solidityLog: {
    displayPrefix: " :",
    preventConsoleLogMigration: true
  },
  contracts_directory: "./contracts-tron/",
  migrations_directory: "./scripts/FraxtalHub/tron",
  networks: {
    mainnet: {
      provider: () => new HDWalletProvider({
        privateKeys: privateKeys,
        providerOrUrl: 'https://api.trongrid.io',
        numberOfAddresses: 2
      }),
      userFeePercentage: 100,
      feeLimit: 1000 * 1e6,
      network_id: '1',
    },
    shasta: {
      privateKey: process.env.PRIVATE_KEY,
      userFeePercentage: 50,
      feeLimit: 1000 * 1e6,
      fullHost: 'https://api.shasta.trongrid.io',
      network_id: '2'
    },
    development: {
      // For tronbox/tre docker image
      privateKey: '0000000000000000000000000000000000000000000000000000000000000001',
      userFeePercentage: 0,
      feeLimit: 1000 * 1e6,
      fullHost: 'http://host.docker.internal:' + port,
      network_id: '9'
    },
  },
  compilers: {
    solc: {
      version: '0.8.22',
      settings: {
        optimizer: {
          enabled: true,
          runs: 200   // Optimize for how many times you intend to run the code
        },
      },
    }
  },
  contracts_build_directory: "./out/contracts-tron",
}
