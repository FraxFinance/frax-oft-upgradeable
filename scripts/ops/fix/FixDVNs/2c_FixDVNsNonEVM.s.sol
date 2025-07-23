// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Reset the DVNs of a chain based on it's config (`config/`)
contract FixDVNs is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    uint256[] public chainIds;

    constructor() {
        // Initialize the chainIds array with the desired chain IDs
        chainIds = [
            111111111 // solana
            // 22222222, // movement
            // 33333333 // aptos
        ];
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/fix/FixDVNs/txs/");
        string memory name = string.concat((block.timestamp).toString(), "-2c_FixDVNsNonEVM-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function run() public override {
        for (uint256 i = 0; i < expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid != 1 && proxyConfigs[i].chainid != 252) continue;
            // skip zk-chains
            if (proxyConfigs[i].chainid == 324 || proxyConfigs[i].chainid == 2741) {
                continue;
            }

            fixDVNs(proxyConfigs[i]);
        }
    }

    function fixDVNs(L0Config memory _config) public simulateAndWriteTxs(_config) {
        for (uint256 i = 0; i < nonEvmConfigs.length; i++) {
            if (nonEvmConfigs[i].chainid != 111111111) continue; // only consider solana
            // skip if peer is not set for one OFT, which means all OFTs
            if (!hasPeer(connectedOfts[0], nonEvmConfigs[i])) {
                continue;
            }

            L0Config[] memory tempConfigs = new L0Config[](1);
            tempConfigs[0] = nonEvmConfigs[i];
            setDVNs({ _connectedConfig: _config, _connectedOfts: connectedOfts, _configs: tempConfigs });
        }
    }

    function hasPeer(address _oft, L0Config memory _dstConfig) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(uint32(_dstConfig.eid));
        return peer != bytes32(0);
    }
}
