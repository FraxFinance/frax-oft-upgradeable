// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev creates 34443 files with set DVNs for all chains- 

/*
Goal: change _configs from activeConfigArray to all configs as setupSource uses configs.
ie: through non-removal of old arrays (https://github.com/FraxFinance/frax-oft-upgradeable/pull/11),
  the prior DVN configurations were overwritten in setupSource() with invalid activeConfigArray DVN addrs.
*/

contract FixDeployDVNs is DeployFraxOFTProtocol {
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
        root = string.concat(root, "/scripts/DeployFraxOFTProtocol/txs/FixDeployDVNs/");
        string memory filename = string.concat(_config.chainid.toString(), "-fixed.json");
        
        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }


    function setUp() public override {
        super.setUp();
    }

    function run() public override {
        // deploySource();
        // setupSource();
        proxyOfts.push(0x64445f0aecC51E94aD52d8AC56b7190e764E561a);
        proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0);
        proxyOfts.push(0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45);
        proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df);
        setupDestinations();
    }

    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public override simulateAndWriteTxs(_connectedConfig) {
        // setEnforcedOptions({
        //     _connectedOfts: _connectedOfts,
        //     _configs: activeConfigArray
        // });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: configs
        });

        // setPeers({
        //     _connectedOfts: _connectedOfts,
        //     _peerOfts: proxyOfts,
        //     _configs: configs
        // });
    }
}
