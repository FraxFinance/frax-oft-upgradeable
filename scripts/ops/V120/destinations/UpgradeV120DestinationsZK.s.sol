// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Destinations, L0Config} from "./UpgradeV120Destinations.s.sol";


contract UpgradeV120DestinationsZK is UpgradeV120Destinations {

    function run() public override {
        for (uint256 i; i < proxyConfigs.length; ++i) {
            L0Config memory proxyConfig = proxyConfigs[i];
            if (isDeprecatedChain(proxyConfig.chainid)) continue;
            if (proxyConfig.chainid != 324 && proxyConfig.chainid != 2741) continue;

            upgradeToV120(proxyConfig);
        }
    }
}
