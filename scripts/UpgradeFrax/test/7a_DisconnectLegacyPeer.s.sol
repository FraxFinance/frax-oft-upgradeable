// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev On all legacy chains, remove proxy peers
// forge script scripts/UpgradeFrax/7a_DisconnectLegacyPeer.s.sol --rpc-url https://rpc.frax.com
contract DisconnectLegacyPeer is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/UpgradeFrax/txs/");
        string memory name = string.concat("7a_DisconnectLegacyPeer-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }
    
    function run() public override {
        delete legacyOfts;
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX

        // deploySource();
        // setupSource();
        setupDestinations();
    }

    function setupDestinations() public override {
        setupLegacyDestinations();
        // setupProxyDestinations();
    }

    /// @dev only set peers
    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public override simulateAndWriteTxs(_connectedConfig) {
        // setEvmEnforcedOptions({
        //     _connectedOfts: _connectedOfts,
        //     _configs: broadcastConfigArray
        // });

        setEvmPeers({
            _connectedOfts: _connectedOfts,
            // _peerOfts: proxyOfts,
            _peerOfts: legacyOfts, // overrides to address(0)
            // _configs: broadcastConfigArray 
            _configs: proxyConfigs
        });

        // setDVNs({
        //     _connectedConfig: _connectedConfig,
        //     _connectedOfts: _connectedOfts,
        //     _configs: broadcastConfigArray
        // });
    }

    /// @dev override peer address to address(0) and allow writing to active chain
    function setPeer(
        L0Config memory _config,
        address _connectedOft,
        bytes32 /* _peerOftAsBytes32 */
    ) public override {
        // cannot set peer to self
        if (block.chainid == _config.chainid) return;

        bytes memory data = abi.encodeCall(
            IOAppCore.setPeer,
            (
                uint32(_config.eid), /* _peerOftAsBytes32 */ addressToBytes32(address(0))
            )
        );
        (bool success, ) = _connectedOft.call(data);
        require(success, "Unable to setPeer");
        serializedTxs.push(
            SerializedTx({
                name: "setPeer",
                to: _connectedOft,
                value: 0,
                data: data
            })
        );
    }
}