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

    /// @dev override to alter file save location
    modifier simulateAndWriteTxs(L0Config memory _config) override {
        // Clear out arrays
        delete enforcedOptionsParams;
        delete setConfigParams;
        delete serializedTxs;

        vm.createSelectFork(_config.RPC);
        chainid = _config.chainid;
        vm.startPrank(_config.delegate);
        _;
        vm.stopPrank();

        // create filename and save
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/FixDVNs/txs/");
        string memory filename = string.concat(_config.chainid.toString(), "-fixed.json");
        string memory filepath = string.concat(root, filename);
        new SafeTxUtil().writeTxs(serializedTxs, filepath);
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
    function setupSource() public override simulateAndWriteTxs(activeConfig) {
        // // TODO: this will break if proxyOFT addrs are not the pre-determined addrs verified in postDeployChecks()
        // setEnforcedOptions({
        //     _connectedOfts: proxyOfts,
        //     _configs: configs
        // });

        setDVNs({
            _connectedConfig: activeConfig,
            _connectedOfts: proxyOfts,
            _configs: configs
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
