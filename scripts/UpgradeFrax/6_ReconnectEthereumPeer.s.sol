// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev reconnect Ethereum peer to destination chains
// forge script scripts/UpgradeFrax/6_ReconnectEthereumPeer.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract ReconnectEthereumPeer is DeployFraxOFTProtocol {
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
        root = string.concat(root, "/scripts/UpgradeFrax/txs/");
        string memory filename = string.concat("6_ReconnectEthereumPeer-", _config.chainid.toString());
        filename = string.concat(filename, ".json");

        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }


    /// @dev skip deployment, set oft addrs to only FRAX/sFRAX, only setup destinations
    function run() public override {
        delete legacyOfts;
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        legacyOfts.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sFRAX

        delete proxyOfts;
        proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // FRAX
        proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sFRAX

        // deploySource();
        setupSource();
        setupDestinations();
    }

    /// @dev only set peers, simulate instead of broadcast as we're publishing msig txs
    function setupSource() public override simulateAndWriteTxs(activeConfig) {
        // setEnforcedOptions({
        //     _connectedOfts: proxyOfts,
        //     _configs: configs
        // });

        // setDVNs({
        //     _connectedConfig: activeConfig,
        //     _connectedOfts: proxyOfts,
        //     _configs: configs
        // });

        setPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: legacyOfts,
            _configs: legacyConfigs
        });

        setPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: proxyOfts,
            _configs: proxyConfigs
        });

        // setPriviledgedRoles();
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
            _peerOfts: proxyOfts,
            _configs: activeConfigArray
        });
    }
}