pragma solidity ^0.8.22;

import { BaseScript } from "frax-std/BaseScript.sol";
import { FrxUSD110Mock } from "contracts/mocks/FrxUsd110Mock.sol";
import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

contract DeployFrxUsdMock is BaseScript {
    function run() external broadcaster {

        (address implementation, address proxy) = deployFrxUsdOFTUpgradeableMockAndProxy();
        FrxUSD110Mock(proxy).mint(0xb0E1650A9760e0f383174af042091fc544b8356f, 1_000_000e18);
        FrxUSD110Mock(proxy).mint(0xC6EF452b0de9E95Ccb153c2A5A7a90154aab3419, 1_000_000e18);
    }

    function deployFrxUsdOFTUpgradeableMockAndProxy() public virtual returns (address implementation, address proxy) {
        implementation = address(new FrxUSD110Mock(0x1a44076050125825900e736c501f859c50fE728c)); 
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(0x8f1B9c1fd67136D525E14D96Efb3887a33f16250, deployer, ""));

        bytes memory initializeArgs = abi.encodeWithSelector(
            FrxUSDOFTUpgradeable.initialize.selector,
            deployer
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(0x223a681fc5c5522c85C96157c0efA18cd6c5405c);
    }
}