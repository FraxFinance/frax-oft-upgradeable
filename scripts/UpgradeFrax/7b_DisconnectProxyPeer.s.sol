// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev On proxy OFTs, remove peer connection to legacy chains
// forge script scripts/UpgradeFrax/7b_DisconnectProxyOFT.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract DisconnectProxyPeer is DeployFraxOFTProtocol {
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
        string memory filename = string.concat("7b_DisconnectProxyOFT-", _config.chainid.toString());
        filename = string.concat(filename, ".json");

        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }


    /// @dev skip deployment, disconnect proxy peer connections
    function run() public override {
        delete proxyOfts;
        proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // FRAX
        proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sFRAX

        // deploySource();
        // setupSource();
        setupDestinations();
    }

    function setupDestinations() public override {
        // setupLegacyDestinations();
        setupProxyDestinations();
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
            // _configs: activeConfigArray
            _configs: legacyConfigs
        });
    }

    /// @dev override peer address to address(0)
    function setPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address connectedOft = _connectedOfts[o];
            address peerOft = _peerOfts[o];
            for (uint256 c=0; c<_configs.length; c++) {
                uint32 eid = uint32(_configs[c].eid);

                // cannot set peer to self
                if (chainid == activeConfig.chainid && eid == activeConfig.eid) continue;

                bytes memory data = abi.encodeCall(
                    IOAppCore.setPeer,
                    (
                        // eid, addressToBytes32(peerOft)
                        eid, addressToBytes32(address(0))
                    )
                );
                (bool success, ) = connectedOft.call(data);
                require(success, "Unable to setPeer");
                serializedTxs.push(
                    SerializedTx({
                        name: "setPeer",
                        to: connectedOft,
                        value: 0,
                        data: data
                    })
                );
            }
        }
    }
}