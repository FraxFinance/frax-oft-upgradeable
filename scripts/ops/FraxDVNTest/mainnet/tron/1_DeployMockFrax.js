const FraxOFTUpgradeable = artifacts.require('./FraxOFTUpgradeable.sol');
const ImplementationMock = artifacts.require('./ImplementationMock.sol');
const L0Config = require("../../../../L0Config.json")

// PK_OFT_DEPLOYER=0
// PK_CONFIG_DEPLOYER=1

module.exports = async function (deployer, network, accounts) {

    // The final array
    const allConfigs = [];

    // Push everything from Legacy
    if (Array.isArray(json.Legacy)) {
        allConfigs.push(...L0Config.Legacy);
    }

    // Push from Proxy, with filtering on chainid
    if (Array.isArray(L0Config.Proxy)) {
        const filtered = L0Config.Proxy.filter(cfg => ![1, 81457, 1088, 8453].includes(cfg.chainid));
        allConfigs.push(...filtered);
    }

    // Push everything from Non-EVM
    if (Array.isArray(L0Config["Non-EVM"])) {
        allConfigs.push(...L0Config["Non-EVM"]);
    }

    // Push everything from Testnet
    if (Array.isArray(L0Config.Testnet)) {
        allConfigs.push(...L0Config.Testnet);
    }

    // Pre Deploy Check


    // Deploy ImplementationMock
    const ImplementationMockInstance = await deployer.deploy(ImplementationMock)

    // Deploy FraxOFTUpgradeable
    const fraxOftUpgradeableInstance = await deployer.deploy(FraxOFTUpgradeable,);
};
