// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Setup source with a hub model vs. a spoke model where the only peer is Fraxtal
abstract contract SetupSourceFraxOFTFraxtalHub is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;

    function run() public override {
        _validateAddrs();
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

    function _validateAddrs() internal view {
        require(isStringEqual(IERC20Metadata(frxUsdOft).symbol(), "frxUSD"), "frxUsdOft != frxUSD");
        require(isStringEqual(IERC20Metadata(sfrxUsdOft).symbol(), "sfrxUSD"), "sfrxUsdOft != sfrxUSD");
        require(isStringEqual(IERC20Metadata(frxEthOft).symbol(), "frxETH"), "frxEthOft != frxETH");
        require(isStringEqual(IERC20Metadata(sfrxEthOft).symbol(), "sfrxETH"), "sfrxEthOft != sfrxETH");
        require(isStringEqual(IERC20Metadata(wfraxOft).symbol(), "WFRAX"), "wFraxOft != WFRAX");
        require(isStringEqual(IERC20Metadata(fpiOft).symbol(), "FPI"), "fpiOft != FPI");
    }
}
