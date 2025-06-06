// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Set Berachain peers to zero address for chain other than Ethereum and Fraxtal
// forge script scripts/ops/fix/FixPeers/FixBerachainPeers.s.sol --rpc-url https://rpc.berachain.com
contract FixBerachainPeers is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    address[] public zeroAddressPeers;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory name = string.concat(root, "/scripts/ops/fix/FixPeers/txs/FixBerachainPeers.json");
        return name;
    }

    function _populateConnectedOfts() public override {}

    function run() public override simulateAndWriteTxs(broadcastConfig) {
        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            zeroAddressPeers.push(address(0));
        }

        setEvmPeers({
            _connectedOfts: expectedProxyOfts,
            _peerOfts: zeroAddressPeers,
            _configs: proxyConfigs
        });
    }
    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");

        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address peerOft = _peerOfts[o];

            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                // skip if not Ethereum / Fraxtal
                if (_configs[c].chainid == 1 || _configs[c].chainid == 252) continue;
                // skip if not berachain
                if (_configs[c].chainid == 80094) continue;

                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }
}