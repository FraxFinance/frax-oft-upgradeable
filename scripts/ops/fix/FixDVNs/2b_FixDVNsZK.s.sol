// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./FixDVNsInherited.s.sol";
/*
Re-set the DVNs of a chain based on the L0Config
*/

contract FixDVNs is FixDVNsInherited {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function filename() public view override returns (string memory) {
        return filenameForStep("2b_FixDVNsZK");
    }

    function run() public override {
        for (uint256 i = 0; i < expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (!isZkChain(proxyConfigs[i].chainid)) continue;
            if (!matchesSource(proxyConfigs[i])) continue;
            fixDVNs(proxyConfigs[i]);
        }
    }

    function fixDVNs(L0Config memory _config) public simulateAndWriteTxs(_config) {
        // loop through proxy configs, find the proxy config with the given chainID
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (!matchesEvmDestination(_config, proxyConfigs[i])) continue;

            // skip if peer is not set for one OFT, which means all OFTs
            if (!hasPeer(connectedOfts[0], proxyConfigs[i])) {
                continue;
            }

            L0Config[] memory tempConfigs = new L0Config[](1);
            tempConfigs[0] = proxyConfigs[i];
            setDVNs({_connectedConfig: _config, _connectedOfts: connectedOfts, _configs: tempConfigs});
        }
    }

    function hasPeer(address _oft, L0Config memory _dstConfig) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(uint32(_dstConfig.eid));
        return peer != bytes32(0);
    }
}
