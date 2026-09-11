// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";

// Deploy everything with a hub model vs. a spoke model where the only peer is Fraxtal
// forge script scripts/FraxtalHub/1_DeployFraxOFTFraxtalHub/DeployFraxOFTFraxtalHub.s.sol --rpc-url $RPC_URL --gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc --broadcast
contract DeployFraxOFTFraxtalHub is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;
    address[] public proxyOftWallets;

    /// @notice Use --sender / --gcp instead of a raw private key.
    modifier broadcastAs(uint256) override {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

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

    /// @notice Use msg.sender as temporary proxy admin (GCS deployer broadcasts directly).
    function _proxyTempAdmin() internal view override returns (address) {
        return msg.sender;
    }

    function deploySource() public override {
        preDeployChecks();
        deployFraxOFTUpgradeablesAndProxies();
        postDeployChecks();
    }
}
