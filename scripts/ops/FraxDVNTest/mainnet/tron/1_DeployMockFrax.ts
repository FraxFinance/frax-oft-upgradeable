import { getTronWeb } from './tron'
import { deployContract, preDeployChecks, setUp } from './tron-helper'
import { configDotenv } from 'dotenv'
import {
    abi as ImplementationMockABI,
    bytecode as ImplementationMockBytecode,
} from '../../../../../out/ImplementationMock.sol/ImplementationMock.json'
import {
    abi as FraxOFTUpgradeableABI,
    bytecode as FraxOFTUpgradeableBytecode,
} from '../../../../../out/FraxOFTUpgradeable.sol/FraxOFTUpgradeable.json'
import {
    abi as TransparentUpgradeableProxyABI,
    bytecode as TransparentUpgradeableProxyBytecode,
} from '../../../../../out/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json'

configDotenv({ path: './.env' })

// async function main() {
//     let contract_instance = await getTronWeb().contract().new({
//         abi: ImplementationMockArtifacts.abi,
//         bytecode: ImplementationMockArtifacts.bytecode.object,
//         feeLimit: 1000000000,
//         callValue: 0,
//         userFeePercentage: 1,
//         originEnergyLimit: 10000000,
//     });
//     return utils.base58.encode58(contract_instance.address as string)
//     // return getTronWeb().trx.getBlockByNumber(12345).then(result => {console.log(result)});
// }

// main().then(console.log).catch(console.error)

async function main() {
    const mFraxProxyAdmin = 0x8d8290d49e88D16d81C6aDf6C8774eD88762274A;
    const configDeployerPK = process.env.PK_OFT_DEPLOYER as string
    const tronWeb = getTronWeb(configDeployerPK)
    const deployerAddress = tronWeb.address.fromPrivateKey(configDeployerPK);
    const { allConfigs, broadcastConfig } = setUp()
    await preDeployChecks(tronWeb, allConfigs, broadcastConfig)

    const implementationMock = await deployContract(tronWeb, ImplementationMockABI, ImplementationMockBytecode, [])

    const implementation = await deployContract(tronWeb, FraxOFTUpgradeableABI, FraxOFTUpgradeableBytecode, [
        broadcastConfig.endpoint,
    ])

    const proxy = await deployContract(tronWeb, TransparentUpgradeableProxyABI, TransparentUpgradeableProxyBytecode, [
        implementationMock,
        deployerAddress,
        '',
    ])

    const initializeFnSelector = tronWeb.sha3('initialize(string,string,address)').slice(0, 10);

    const encodedArgs = tronWeb.utils.abi.encodeParams(
        ['string', 'string', 'address'],
        ["Mock Frax", "mFRAX", deployerAddress]
    );

    const finalData = initializeFnSelector + encodedArgs.slice(2);

    const proxyInstance = await tronWeb.contract(TransparentUpgradeableProxyABI, proxy)
    // upgradeToAndCall
    const res = proxyInstance.upgradeToAndCall(implementation, finalData).send({
        feeLimit: 100_000_000,
        callValue: 0,
        tokenId: 1000036,
        tokenValue: 100,
        shouldPollResponse: true
    });
    // change admin
    const res1 = proxyInstance.changeAdmin(mFraxProxyAdmin).send({
        feeLimit: 100_000_000,
        callValue: 0,
        tokenId: 1000036,
        tokenValue: 100,
        shouldPollResponse: true
    });
    // State checks
    // require(isStringEqual(FraxOFTUpgradeable(proxy).name(), _name), "OFT name incorrect");
    // require(isStringEqual(FraxOFTUpgradeable(proxy).symbol(), _symbol), "OFT symbol incorrect");
    // require(address(FraxOFTUpgradeable(proxy).endpoint()) == broadcastConfig.endpoint, "OFT endpoint incorrect");
    // require(
    //     EndpointV2(broadcastConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
    //     "Endpoint delegate incorrect"
    // );
    // require(FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK), "OFT owner incorrect");

    // deployFraxOFTWalletUpgradeableAndProxy
}
main().then(console.log).catch(console.error)
