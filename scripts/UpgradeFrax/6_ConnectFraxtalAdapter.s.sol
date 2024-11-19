// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";

/// @dev connect the fraxtal adapter to the upgradeable endpoints - Mode, sei, X-Layer
// forge script scripts/UpgradeFrax/6_ConnectFraxtalAdapter.s.sol --rpc-url https://rpc.frax.com
contract ConnectFraxtalAdapter is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    address[] public adapterProxyOfts;

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
        root = string.concat(root, "/scripts/UpgradeFrax/txs/");
        string memory filename = string.concat("6_ConnectFraxtalAdapter-", activeConfig.chainid.toString());
        filename = string.concat(filename, "-");
        filename = string.concat(filename, _config.chainid.toString());
        filename = string.concat(filename, ".json");

        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }

    /// @dev skip deployment, set oft addrs to[] only FRAX/sFRAX
    function run() public override {
        adapterProxyOfts.push(0x0); // TODO: Fraxtal FRAX Adapter
        adapterProxyOfts.push(0x0); // TODO: Fraxtal sFRAX Adapter

        delete proxyOfts;
        proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // FRAX
        proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sFRAX

        // deploySource();
        // setupSource();
        setupDestinations();
    }

    /// @dev only set peers
    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public override simulateAndWriteTxs(_connectedConfig) {
        // setEnforcedOptions({
        //     _connectedOfts: _connectedOfts,
        //     _configs: activeConfigArray
        // });

        // setDVNs({
        //     _connectedConfig: _connectedConfig,
        //     _connectedOfts: _connectedOfts,
        //     _configs: activeConfigArray
        // });

        setPeers({
            _connectedOfts: _connectedOfts,
            // _peerOfts: proxyOfts,
            _peerOfts: adapterProxyOfts,
            _configs: activeConfigArray
        });
    }
}