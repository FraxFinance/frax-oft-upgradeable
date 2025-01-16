// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// for each batch deployed chain, change peer of fraxtal to predeterministic address
// simulate as fraxtal
contract ChangeFraxtalPeer is DeployFraxOFTProtocol {
    address[] standaloneAdapters;
    L0Config[] batchConfigArray;

    constructor() {
        standaloneAdapters.push(0x96A394058E2b84A89bac9667B19661Ed003cF5D4); // frxUSD
        standaloneAdapters.push(0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361); // sfrxUSD

        proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // frxUSD
        proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sfrxUSD
    }
/*
                            
*/

    function run() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // skip if not (ink, sonic, arbitrum, optimism, polygon, avalanche, bsc, polygon zkevm)
            if (
                proxyConfigs[i].chainid != 57073 && proxyConfigs[i].chainid != 146 &&
                proxyConfigs[i].chainid != 42161 && proxyConfigs[i].chainid != 10 &&
                proxyConfigs[i].chainid != 137 && proxyConfigs[i].chainid != 43114 &&
                proxyConfigs[i].chainid != 56 && proxyConfigs[i].chainid != 1101
            ) continue;
            // set chain peers to fraxtal
            setEvmPeers({
                _connectedOfts: proxyOfts,
                _peerOfts: proxyOfts,
                _configs: broadcastConfigArray,
                _connectedConfig: proxyConfigs[i]
            });

            // store config for later destination setup
            batchConfigArray.push(proxyConfigs[i]);
        }

        // setup fraxtal lockbox to point to the peers of each chain
        setupDestination(broadcastConfig);
    }

    // add _connectedConfig argument and simulate instead of broadcast
    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs,
        L0Config memory _connectedConfig
    ) public simulateAndWriteTxs(_connectedConfig) {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(_peerOfts[o])
                });
            }
        }
    }

    // overwrite configs to batch chains
    function setupDestination(
        L0Config memory _connectedConfig
    ) public override simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: /* broadcastConfigArray */ batchConfigArray
        });

        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: /* expectedProxyOfts */ proxyOfts,
            _configs: /* broadcastConfigArray */ batchConfigArray 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: proxyOfts,
            _configs: /* broadcastConfigArray */ batchConfigArray
        });

        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: proxyOfts,
            _configs: batchConfigArray
        });
    }
}