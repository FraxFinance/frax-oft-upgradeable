// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// Deploy to sonic without setting up DVNs, maintain configDeployerPK as owner/delegate
contract DeploySonic is DeployFraxOFTProtocol {
    /// @dev skip setting DVNs
    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        /// @dev configures legacy configs as well
        // setDVNs({
        //     _connectedConfig: broadcastConfig,
        //     _connectedOfts: proxyOfts,
        //     _configs: allConfigs
        // });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        // setPriviledgedRoles();
    }
}