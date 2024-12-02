// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/*
Re-set the DVNs of a chain based on the L0Config
*/

contract FixDVNs is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function version() public virtual override pure returns (uint256, uint256, uint256) {
        return (1, 0, 2);
    }

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/FixDVNs/txs/");
        string memory name = string.concat(simulateConfig.chainid.toString(), "-fixed.json");

        return string.concat(root, name);
    }

    function setUp() public override {
        super.setUp();
    }

    function run() public override {
        // deploySource();
        setupSource();
        // setupDestinations();
    }

    /// @dev simulating the active config delegate to create the new DVN txs
    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        // // TODO: this will break if proxyOFT addrs are not the pre-determined addrs verified in postDeployChecks()
        // setEnforcedOptions({
        //     _connectedOfts: proxyOfts,
        //     _configs: configs
        // });

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: evmConfigs
        });

        // /// @dev legacy, non-upgradeable OFTs
        // setPeers({
        //     _connectedOfts: proxyOfts,
        //     _peerOfts: legacyOfts,
        //     _configs: legacyConfigs
        // });
        // /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        // setPeers({
        //     _connectedOfts: proxyOfts,
        //     _peerOfts: proxyOfts,
        //     _configs: proxyConfigs
        // });

        // setPriviledgedRoles();
    }
}
