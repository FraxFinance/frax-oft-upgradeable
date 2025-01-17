// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev On proxy OFTs, remove peer connection to legacy chains fully connect all (s)frxUSD instances
// forge script scripts/ops/UpgradeFrxUsd/7b_SetProxyPeer.s.sol --rpc-url https://rpc.frax.com
contract SetProxyPeer is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    address[] nullOfts;
    address[] fraxtalLockboxes;

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeFrxUsd/txs/");
        string memory name = string.concat("7b_SetProxyPeer-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    /// @dev skip deployment, disconnect proxy peer connections
    function run() public override {
        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        
        delete proxyOfts;
        proxyOfts.push(frxUsdOft);
        proxyOfts.push(sfrxUsdOft);

        nullOfts.push(address(0));
        nullOfts.push(address(0));

        fraxtalLockboxes.push(0x96A394058E2b84A89bac9667B19661Ed003cF5D4); // frxUSD
        fraxtalLockboxes.push(0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361); // sfrxUSD

        // deploySource();
        // setupSource();
        setupDestinations();
    }

    function setupDestinations() public override {
        // setupLegacyDestinations();
        setupProxyDestinations();
    }

    // (Fraxtal, proxy OFTs): set legacy peer to 0
    // (Fraxtal): Connect to (Mode, Sei, Xlayer) peer
    // (Mode, Sei, XLayer): connect to new OFT peer, fraxtal lockbox
    function setupProxyDestinations() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {

            // All Proxy
            if (proxyConfigs[i].chainid != 252) {
                setupDestination({
                    _connectedConfig: proxyConfigs[i],
                    _connectedOfts: proxyOfts
                });
            } else if (proxyConfigs[i].chainid == 252) {
                setupDestination({
                    _connectedConfig: proxyConfigs[i],
                    _connectedOfts: fraxtalLockboxes
                });
            }
        }
    }

    // Additional setEVM peers of null legacy chains
    // change _configs from broadcastConfigArray to proxyConfigs
    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public simulateAndWriteTxs(_connectedConfig) {
        // will overwrite some config, no issue
        setEvmEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: proxyConfigs
        });

        // remove peer of legacy chains
        setEvmPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: nullOfts,
            _configs: legacyConfigs
        });

        // set peer to (s)frxUSD (will overwrite some config, no issue)
        setEvmPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: proxyOfts,
            _configs: proxyConfigs
        });

        // will overwrite some config, no issue
        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: proxyConfigs
        });
    }

}