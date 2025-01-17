// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTAdapterUpgradeable.sol";

/*
GOALS
- Deploy (s)frxUSD lockboxes on Ethereum
- Connect to the standalone (s)frxUSD fraxtal lockboxes
- Connect to the proxy OFTs

TODO
- properly override fraxtal peer to standalone lockbox
- Connect to Solana OFTs
*/

contract DeployFrxUsdEthereumLockboxes is DeployFraxOFTProtocol {

    address frxUsd = 0xA8F9e149cCE34ec7F68aF720D8551cb9B39ed1f1;
    address sfrxUsd = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/txs/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function run() public override {
        // set expectedProxyOfts to [frxUsdOft, sfrxUsdOft]
        delete expectedProxyOfts;
        expectedProxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // frxUsd OFT
        expectedProxyOfts.push(0x5bff88ca1442c2496f7e475e9e7786383bc070c0); // sfrxUsd OFT

        deploySource();
        setupSource();
        setupDestinations();
    }

    // Configure (s)frxUSD addresses to the standalone fraxtal lockboxes, otherwise ethereum lockboxes
    function _overwriteFrxUsdAddrs() public override {
        if (simulateConfig.chainid == 252) {
            expectedProxyOfts[0] = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4; // frxUsd lockbox
            expectedProxyOfts[1] = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361; // sfrxUsd lockbox
        } else {
            expectedProxyOfts[0] = 0x80Eede496655FB9047dd39d9f418d5483ED600df; // frxUsd OFT
            expectedProxyOfts[1] = 0x5bff88ca1442c2496f7e475e9e7786383bc070c0; // sfrxUsd OFT
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig
    ) public virtual simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: expectedProxyOfts,
            _configs: broadcastConfigArray
        });

        setEvmPeers({
            _connectedOfts: expectedProxyOfts,
            _peerOfts: proxyOfts,
            _configs: broadcastConfigArray 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: expectedProxyOfts,
            _configs: broadcastConfigArray
        });

        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: expectedProxyOfts,
            _configs: broadcastConfigArray
        });
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        // setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        setPriviledgedRoles();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: evmConfigs
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: expectedProxyOfts,
            _configs: proxyConfigs
        });
    }

    function postDeployChecks() public override pure {}

    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(senderDeployerPK) public override {
        // TODO: proxyAdmin

        implementationMock = address(new ImplementationMock());

        (, frxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _token: frxUsd
        });

        (, sfrxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _token: sfrxUsd
        });
    }

    function deployFraxOFTUpgradeableAndProxy(address _token) public returns (address implementation, address proxy) {
        // create the implementation
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(FraxOFTAdapterUpgradeable).creationCode),
            abi.encode(_token, broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }

        // TODO: shall we init implementation with address(0) ?
        // FraxOFTAdapterUpgradeable(implementation).initialize(address(0));

        // create the proxy
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(senderDeployerPK), ""));
        proxyOfts.push(proxy);

        // upgrade and init
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTAdapterUpgradeable.initialize.selector,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });

        // transfer ownership to config deployer
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        require(
            FraxOFTAdapterUpgradeable(proxy).token() == _token,
            "OFT token not set"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }
}