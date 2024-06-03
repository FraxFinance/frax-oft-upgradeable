// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// TODO: package names under same base dir
import { BaseScript } from "frax-std/BaseScript.sol";
import { Constants } from "frax-template/src/contracts/Constants.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";


/*
https://etherscan.io/tx/0xc83526447f7c7467d16ea65975a2b39edeb3ebe7c88959af333194a0a24ef0e4#eventlog
(FXS) Mainnet => Base

Required DVNs:
- 0x380275805876Ff19055EA900CDb2B46a94ecF20D
- 0x589dEDbD617e0CBcB916A9223F4d1300c294236b

Delegate & owner: 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27

Mainnet Addresses
- FXSOFTAdapter:        0x23432452B720C80553458496D4D9d7C5003280d0
- sFRAXOFTAdapter:      0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E
- sfrxETHOFTAdapter:    0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A
- FRAXOFTAdapter:       0x909DBdE1eBE906Af95660033e478D59EFe831fED
    > Has no TVL / txs
    > I have not confirmed DVNs
*/


contract DeployFraxOFTProtocol is BaseScript {

    // TODO: convert to PK
    address public proxyDeployer = 0xDed884435f2db0169010b3c325e733dF0038E51d;
    address public basicDeployer = address(0x123); // TODO

    address public delegate;
    address public endpoint;
    function setUp() external {
        // Set constants based on deployment chain id
        if (block.chainid == 1) {
            delegate = Constants.Mainnet.TIMELOCK_ADDRESS;
            endpoint = Constants.Mainnet.L0_ENDPOINT; // TODO: does this vary per OFT?
        }
    }

    function run() external {
        // Deploy FXS
        address frxFxsOft = deployFraxOFTUpgradeableAndProxy({
            _oftBytecode: type(OFTUpgradeable).creationCode,
            _constructorArgs: abi.encode(endpoint),
            _initializeArgs: abi.encodeWithSelector(
                FraxOFTUpgradeable.initialize.selector,
                "Frax Share",
                "FXS",
                delegate
            )
        });

        // Deploy sFRAX
        address sFraxOft = deployFraxOFTUpgradeableAndProxy({
            _oftBytecode: type(OFTUpgradeable).creationCode,
            _constructorArgs: abi.encode(endpoint),
            _initializeArgs: abi.encodeWithSelector(
                FraxOFTUpgradeable.initialize.selector,
                "Staked Frax",
                "sFRAX",
                delegate
            )
        });

        // sfrxETH
        address frxEthOft = deployFraxOFTUpgradeableAndProxy({
            _oftBytecode: type(OFTUpgradeable).creationCode,
            _constructorArgs: abi.encode(endpoint),
            _initializeArgs: abi.encodeWithSelector(
                FraxOFTUpgradeable.initialize.selector,
                "Frax Ether",
                "frxETH",
                delegate
            )
        });

        // Deploy FRAX
        address sFraxOft = deployFraxOFTUpgradeableAndProxy({
            _oftBytecode: type(OFTUpgradeable).creationCode,
            _constructorArgs: abi.encode(endpoint),
            _initializeArgs: abi.encodeWithSelector(
                FraxOFTUpgradeable.initialize.selector,
                "Frax",
                "FRAX",
                delegate
            )
        });

        // Deploy FPI
        // address frxEthOft = deployFraxOFTUpgradeableAndProxy({
        //     _oftBytecode: type(OFTUpgradeable).creationCode,
        //     _constructorArgs: abi.encode(endpoint),
        //     _initializeArgs: abi.encodeWithSelector(
        //         FraxOFTUpgradeable.initialize.selector,
        //         "Frax Price Index",
        //         "FPI",
        //         delegate
        //     )
        // });

    // TODO: set peers, set enforced options, set delegate, transfer owership of oft, transfer proxy ownership

    }


    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    function deployFraxOFTUpgradeableAndProxy(
        bytes memory _oftBytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs,
        address _delegate
    ) returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oftBytecode), _constructorArgs);
        vm.broadcast(basicDeployer);
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: OFT delegate is proxy admin
        vm.broadcast(proxyDeployer);
        proxy = address(new TransparentUpgradeableProxy(implementation, basicDeployer, _initializeArgs));
    }

}
