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
import { abi as EndpointABI } from '../../../../../out/EndpointV2.sol/EndpointV2.json'
import {
    abi as FraxOFTWalletUpgradeableABI,
    bytecode as FraxOFTWalletUpgradeableBytecode,
} from '../../../../../out/FraxOFTWalletUpgradeable.sol/FraxOFTWalletUpgradeable.json'

configDotenv({ path: './.env' })

async function main() {
    const mFraxProxyAdmin = 0x8d8290d49e88d16d81c6adf6c8774ed88762274a
    const oftName = 'Mock Frax'
    const oftSymbol = 'mFRAX'
    const configDeployerPK = process.env.PK_OFT_DEPLOYER as string
    const tronWeb = getTronWeb(configDeployerPK)
    const deployerAddress = tronWeb.address.fromPrivateKey(configDeployerPK)
    const { allConfigs, broadcastConfig } = setUp()
    const endpointInstance = await tronWeb.contract(EndpointABI, tronWeb.address.fromHex(broadcastConfig.endpoint))
    await preDeployChecks(allConfigs, broadcastConfig, endpointInstance)

    const implementationMock = await deployContract(tronWeb, ImplementationMockABI, ImplementationMockBytecode, [])
    console.log('implementationMock ', implementationMock.address)

    const fraxOftUpgradeable = await deployContract(tronWeb, FraxOFTUpgradeableABI, FraxOFTUpgradeableBytecode, [
        broadcastConfig.endpoint,
    ])

    console.log('fraxOftUpgradeable ', fraxOftUpgradeable.address)

    const proxy = await deployContract(tronWeb, TransparentUpgradeableProxyABI, TransparentUpgradeableProxyBytecode, [
        implementationMock,
        deployerAddress,
        '',
    ])
    console.log('proxy ', proxy.address)

    const initializeFnSelector = tronWeb.sha3('initialize(string,string,address)').slice(0, 10)

    const encodedArgs = tronWeb.utils.abi.encodeParams(
        ['string', 'string', 'address'],
        [oftName, oftSymbol, deployerAddress]
    )

    const finalData = initializeFnSelector + encodedArgs.slice(2)

    // upgradeToAndCall
    const upgradeToAndCallTx = await proxy.upgradeToAndCall(fraxOftUpgradeable, finalData).send({
        feeLimit: 100_000_000,
        callValue: 0,
        keepTxID: true,
        shouldPollResponse: true,
    })
    console.log('upgradeToAndCallTx ', upgradeToAndCallTx)
    // change admin
    const changeProxyTx = await proxy.changeAdmin(mFraxProxyAdmin).send({
        feeLimit: 100_000_000,
        callValue: 0,
        keepTxID: true,
        shouldPollResponse: true,
    })
    console.log('changeProxyTx ', changeProxyTx)
    // State checks
    const mockFraxOftInstance = await tronWeb.contract(FraxOFTUpgradeableABI, proxy.address as string)

    const frxOftName = await mockFraxOftInstance.name().call()
    console.log('frxOftName ', frxOftName)
    if (frxOftName !== 'Mock Frax') {
        throw new Error('OFT name is incorrect')
    }

    const frxOftSymbol = await mockFraxOftInstance.symbol().call()
    console.log('frxOftSymbol ', frxOftSymbol)
    if (frxOftSymbol !== 'mFRAX') {
        throw new Error('OFT symbol is incorrect')
    }

    const endpoint = await mockFraxOftInstance.endpoint().call()
    console.log('endpoint ', endpoint)
    if (endpoint !== broadcastConfig.endpoint) {
        throw new Error('OFT endpoint is incorrect')
    }

    const delegate = await endpointInstance.delegates(proxy.address).call()
    console.log('delegate ', delegate)
    console.log('deployerAddress ', deployerAddress)
    if (delegate !== deployerAddress) {
        throw new Error('Endpoint delegate is incorrect')
    }

    const owner = await proxy.owner().call()
    console.log('owner ', owner)
    if (owner !== deployerAddress) {
        throw new Error('OFT owner is incorrect')
    }

    const fraxOFTWalletUpgradeable = await deployContract(
        tronWeb,
        FraxOFTWalletUpgradeableABI,
        FraxOFTWalletUpgradeableBytecode,
        []
    )

    console.log('fraxOFTWalletUpgradeable ', fraxOFTWalletUpgradeable.address)

    const walletProxy = await deployContract(
        tronWeb,
        TransparentUpgradeableProxyABI,
        TransparentUpgradeableProxyBytecode,
        [implementationMock, deployerAddress, '']
    )
    console.log('walletProxy ', walletProxy.address)

    const walletInitializeFnSelector = tronWeb.sha3('initialize(address)').slice(0, 10)

    const walletEncodedArgs = tronWeb.utils.abi.encodeParams(['address'], [deployerAddress])

    const walletFinalData = walletInitializeFnSelector + walletEncodedArgs.slice(2)

    // upgradeToAndCall
    const walletUpgradeToAndCallTx = await walletProxy
        .upgradeToAndCall(fraxOFTWalletUpgradeable, walletFinalData)
        .send({
            feeLimit: 100_000_000,
            callValue: 0,
            keepTxID: true,
            shouldPollResponse: true,
        })
    console.log('walletUpgradeToAndCallTx ', walletUpgradeToAndCallTx)
    // change admin
    const walletchangeProxyTx = await walletProxy.changeAdmin(mFraxProxyAdmin).send({
        feeLimit: 100_000_000,
        callValue: 0,
        keepTxID: true,
        shouldPollResponse: true,
    })
    console.log('walletchangeProxyTx ', walletchangeProxyTx)
}
main().then(console.log).catch(console.error)
