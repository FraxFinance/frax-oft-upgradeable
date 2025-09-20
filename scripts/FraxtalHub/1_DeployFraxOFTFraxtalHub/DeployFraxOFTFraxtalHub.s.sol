// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";

// Deploy everything with a hub model vs. a spoke model where the only peer is Fraxtal
// forge script scripts/FraxtalHub/1_DeployFraxOFTFraxtalHub/DeployFraxOFTFraxtalHub.s.sol --rpc-url $RPC_URL --broadcast
contract DeployFraxOFTFraxtalHub is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;
    address[] public proxyOftWallets;

    function run() public override {
        require(broadcastConfig.chainid != 252, "Deployment not allowed on fraxtal");
        for (uint256 i; i < proxyConfigs.length; i++) {
            // Set up destinations for Fraxtal lockboxes only
            if (proxyConfigs[i].chainid == 252 || proxyConfigs[i].chainid == broadcastConfig.chainid) {
                tempConfigs.push(proxyConfigs[i]);
            }
        }

        require(tempConfigs.length == 2, "Incorrect tempConfigs array");

        delete proxyConfigs;
        for (uint256 i = 0; i < tempConfigs.length; i++) {
            proxyConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        deploySource();
    }

    function preDeployChecks() public view override {
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            uint32 eid = uint32(proxyConfigs[i].eid);
            require(
                IMessageLibManager(broadcastConfig.endpoint).isSupportedEid(eid),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
    }

    function deploySource() public override {
        preDeployChecks();
        deployFraxOFTUpgradeablesAndProxies();
        deployFraxOFTWalletUpgradeableAndProxy();
        postDeployChecks();
    }

    function deployFraxOFTWalletUpgradeableAndProxy() public returns (address implementation, address proxy) {
        implementation = address(new FraxOFTWalletUpgradeable());
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));
        /// @dev: broadcastConfig deployer is temporary owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTWalletUpgradeable.initialize.selector,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        proxyOftWallets.push(proxy);
    }

    function postDeployChecks() internal view override {
        super.postDeployChecks();
        require(proxyOftWallets.length == 1, "Did not deploy proxy OFT wallet");
    }
}
