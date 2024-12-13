// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev now that the oft is deployed, setup the adapter
/// @todo base broadcast
contract SetupAdapter is DeployFraxOFTProtocol {
    address oft = 0x0; // @todo fraxtal oft
    address adapter = 0x0; // @todo base adapter

    address[] public connectedOfts;
    address[] public peerOfts;

    constructor() {
        connectedOfts.push(adapter);
        peerOfts.push(oft);
    }

    function run() public override {
        // deploySource();
        // setupSource();
        setupDestinations();   
    }

    function setupDestinations() public override {
        setupLegacyDestinations();
        // setupProxyDestinations();
    }

    function setupLegacyDestinations() public virtual {
        for (uint256 i=0; i<legacyConfigs.length; i++) {
            setupDestination({
                _connectedConfig: legacyConfigs[i],
                _connectedOfts: /* legacyOfts */ connectedOfts
            });
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public virtual /* simulateAndWriteTxs(_connectedConfig) */ broadcastAs(configDeployerPK) {
        setEvmEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: /* broadcastConfigArray */ legacyConfigs // includes base
        });

        setEvmPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: /* proxyOfts */ peerOfts,
            _configs: /* broadcastConfigArray */ legacyConfigs // includes base 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: /* broadcastConfigArray */ legacyConfigs // includes base
        });
    }
}