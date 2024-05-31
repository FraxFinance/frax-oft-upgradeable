// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// TODO: package names under same base dir
import { BaseScript } from "frax-std/BaseScript.sol";
import { Constants } from "frax-template/src/contracts/Constants.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";

/// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
function deployFraxOFTUpgradeableAndProxy(
    bytes memory _oftBytecode,
    bytes memory _constructorArgs,
    bytes memory _initializeArgs,
    address _delegate
) returns (address addr) {
    bytes memory bytecode = bytes.concat(abi.encodePacked(_oftBytecode), _constructorArgs);
    assembly {
        addr := create(0, add(bytecode, 0x20), mload(bytecode))
        if iszero(extcodesize(addr)) {
            revert(0, 0)
        }
        /// @dev: OFT delegate is proxy admin
        return address(new TransparentUpgradeableProxy(addr, _delegate, _initializeArgs));
    }
}

contract DeployFraxOFTProtocol is BaseScript {
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
        // Deploy FRAX
        address fraxOft = deployFraxOFTUpgradeableAndProxy({
            _oftBytecode: type(OFTUpgradeable).creationCode,
            _constructorArgs: abi.encode(endpoint),
            _initializeArgs: abi.encodeWithSelector(
                FraxOFTUpgradeable.initialize.selector,
                "Frax",
                "FRAX",
                delegate
            )
        });

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

        // Deploy FPI
        address frxEthOft = deployFraxOFTUpgradeableAndProxy({
            _oftBytecode: type(OFTUpgradeable).creationCode,
            _constructorArgs: abi.encode(endpoint),
            _initializeArgs: abi.encodeWithSelector(
                FraxOFTUpgradeable.initialize.selector,
                "Frax Price Index",
                "FPI",
                delegate
            )
        });

        // frxETH
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
    }

    // TODO: set peers
}