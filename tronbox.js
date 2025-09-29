const port = process.env.HOST_PORT || 9090

module.exports = {
  migrations_directory: "./scripts/FraxtalHub/tron",
  networks: {
    mainnet: {
      privateKey: process.env.PRIVATE_KEY_TRON_MAINNET,
      userFeePercentage: 100,
      feeLimit: 1000 * 1e6,
      fullHost: 'https://api.trongrid.io',
      network_id: '1'
    },
    development: {
      // For tronbox/tre docker image
      privateKey: '0000000000000000000000000000000000000000000000000000000000000001',
      userFeePercentage: 0,
      feeLimit: 1000 * 1e6,
      fullHost: 'http://host.docker.internal:' + port,
      network_id: '9'
    },
    compilers: {
      solc: {
        version: '0.8.22'
      }
    }
  }
}
