// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Destinations, L0Config} from "./UpgradeV120Destinations.s.sol";

/// @notice Generates a V120 Safe batch only for the chain selected by --rpc-url.
contract UpgradeV120Destination is UpgradeV120Destinations {
    function run() public override {
        for (uint256 i; i < proxyConfigs.length; ++i) {
            L0Config memory config = proxyConfigs[i];
            if (config.chainid != block.chainid) continue;
            require(!isDeprecatedChain(config.chainid), "V120: selected chain is deprecated");
            upgradeToV120(config);
            return;
        }
        revert("V120: chain not found in Proxy config");
    }
}
