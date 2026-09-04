// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Setup source with a hub model vs. a spoke model where the only peer is Fraxtal
abstract contract SetupSourceFraxOFTFraxtalHub is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;

    function run() public virtual override {
        _validateAddrs();
        _validateLibs();
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

    function setupNonEvms() public virtual override {}

    function setupSource() public virtual override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        setDVNs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: proxyConfigs });

        setLibs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: proxyConfigs });

        setPriviledgedRoles();
    }

    function _validateAddrs() internal view virtual {
        require(isStringEqual(IERC20Metadata(wfraxOft).symbol(), "WFRAX"), "wFraxOft != WFRAX");
        require(isStringEqual(IERC20Metadata(sfrxUsdOft).symbol(), "sfrxUSD"), "sfrxUsdOft != sfrxUSD");
        require(isStringEqual(IERC20Metadata(sfrxEthOft).symbol(), "sfrxETH"), "sfrxEthOft != sfrxETH");
        _validateFrxUsdAddr();
        require(isStringEqual(IERC20Metadata(frxEthOft).symbol(), "frxETH"), "frxEthOft != frxETH");
        require(isStringEqual(IERC20Metadata(fpiOft).symbol(), "FPI"), "fpiOft != FPI");
    }

    /// @notice Validates frxUSD OFT symbol. Override for adapter-based deployments (e.g. Tempo TIP20).
    function _validateFrxUsdAddr() internal view virtual {
        require(isStringEqual(IERC20Metadata(frxUsdOft).symbol(), "frxUSD"), "frxUsdOft != frxUSD");
    }

    /// @notice Validates the L0Config libs are registered on the endpoint so setLibs() pins real
    ///         libraries instead of reverting mid-batch on a stale or fat-fingered address.
    function _validateLibs() internal view virtual {
        require(broadcastConfig.sendLib302 != address(0), "L0Config: sendLib302 not set");
        require(broadcastConfig.receiveLib302 != address(0), "L0Config: receiveLib302 not set");
        require(
            IMessageLibManager(broadcastConfig.endpoint).isRegisteredLibrary(broadcastConfig.sendLib302),
            "L0Config: sendLib302 not registered on endpoint"
        );
        require(
            IMessageLibManager(broadcastConfig.endpoint).isRegisteredLibrary(broadcastConfig.receiveLib302),
            "L0Config: receiveLib302 not registered on endpoint"
        );
    }

    function setPriviledgedRoles() public virtual override {
        proxyAdmin = broadcastConfig.proxyAdmin;

        if (proxyAdmin == address(0)) revert("ProxyAdmin cannot be zero address");

        for (uint256 o = 0; o < proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            require(
                proxyAdmin == FraxProxyAdmin(proxyAdmin).getProxyAdmin(TransparentUpgradeableProxy(payable(proxyOft))),
                "ProxyAdmin is not admin of oft proxy"
            );
        }

        super.setPriviledgedRoles();
    }
}
