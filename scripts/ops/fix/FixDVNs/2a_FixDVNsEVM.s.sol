// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./FixDVNsInherited.s.sol";

// Reset the DVNs of a chain based on it's config (`config/`)
contract FixDVNs is FixDVNsInherited {
    using stdJson for string;
    using Strings for uint256;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/fix/FixDVNs/txs/");
        string memory name = string.concat((block.timestamp).toString(), "-2a_FixDVNsEVM-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function setChainList() public override {
        chainIds = [
            34443, // mode
            1329, // sei
            252, // fraxtal
            196, // xlayer
            146, // sonic
            57073, // ink
            42161, // arbitrum
            10, // optimism
            137, // polygon
            43114, // avalanche
            56, // bsc
            1101, // polygon zkevm
            1, // ethereum,
            81457, // blast
            8453, // base
            80094, // berachain
            59144 // linea
        ];
    }

    function run() public override {
        for (uint256 i = 0; i < expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            for (uint256 j = 0; j < chainIds.length; j++) {
                if (proxyConfigs[i].chainid == chainIds[j]) {
                    fixDVNs(proxyConfigs[i]);
                }
            }
        }
    }

    function fixDVNs(L0Config memory _config) public simulateAndWriteTxs(_config) {
        // loop through proxy configs, find the proxy config with the given chainID
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            for (uint256 j = 0; j < chainIds.length; j++) {
                if (proxyConfigs[i].chainid != chainIds[j] || proxyConfigs[i].chainid == _config.chainid) continue;

                // skip if peer is not set for one OFT, which means all OFTs
                if (!hasPeer(connectedOfts[0], proxyConfigs[i])) {
                    continue;
                }

                L0Config[] memory tempConfigs = new L0Config[](1);
                tempConfigs[0] = proxyConfigs[i];

                setDVNs({ _connectedConfig: _config, _connectedOfts: connectedOfts, _configs: tempConfigs });
            }
        }
    }

    function setDVNs(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public override {
        // Hardcoded chunk ranges — update manually between script runs
        uint256 oftStart = 1;
        uint256 oftEnd = 2; // exclusive
        uint256 cfgStart = 0;
        uint256 cfgEnd = 1; // exclusive

        // Clamp to array length
        if (oftEnd > _connectedOfts.length) oftEnd = _connectedOfts.length;
        if (cfgEnd > _configs.length) cfgEnd = _configs.length;

        for (uint256 o = oftStart; o < oftEnd; o++) {
            for (uint256 c = cfgStart; c < cfgEnd; c++) {
                // Skip if setting config to self
                if (_connectedConfig.chainid == _configs[c].chainid) continue;
                setConfigs({
                    _connectedConfig: _connectedConfig,
                    _connectedOft: _connectedOfts[o],
                    _config: _configs[c]
                });
            }
        }
    }

    function hasPeer(address _oft, L0Config memory _dstConfig) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(uint32(_dstConfig.eid));
        return peer != bytes32(0);
    }
}
