// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Deploy everything with a hub model vs. a spoke model where the only peer is Fraxtal
contract DeployFraxOFTProtocolFraxtalHub is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;

    function run() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // Set up destinations for Fraxtal lockboxes only
            if (
                proxyConfigs[i].chainid == 252 ||
                proxyConfigs[i].chainid == broadcastConfig.chainid
            ) {
                tempConfigs.push(proxyConfigs[i]);
            }
        }

        delete proxyConfigs;
        for (uint256 i=0; i<tempConfigs.length; i++) {
            proxyConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        super.run();
    }

}
