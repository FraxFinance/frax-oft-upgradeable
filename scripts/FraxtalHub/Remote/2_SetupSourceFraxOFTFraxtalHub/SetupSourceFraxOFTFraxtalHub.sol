// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

abstract contract SetupSourceFraxOFTFraxtalHub is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;

    function run() public override {
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
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

        setupSource();
    }

    function setupNonEvms() public override {}

    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        setDVNs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: proxyConfigs });

        setLibs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: proxyConfigs });

        setPriviledgedRoles();
    }
}
