// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Destinations, L0Config} from "./UpgradeV120Destinations.s.sol";

// forge script scripts/ops/V120/destinations/UpgradeV120DestinationsEVM.s.sol
contract UpgradeV120DestinationsEVM is UpgradeV120Destinations {

    function run() public override {
        for (uint256 i; i < proxyConfigs.length; ++i) {
            L0Config memory proxyConfig = proxyConfigs[i];
            if (proxyConfig.chainid == ETHEREUM_CHAIN_ID) continue;
            if (proxyConfig.chainid == FRAXTAL_CHAIN_ID) continue;
            if (isDeprecatedChain(proxyConfig.chainid)) continue;
            if (proxyConfig.chainid == 324 || proxyConfig.chainid == 2741) continue;

            upgradeToV120(proxyConfig);
        }
    }
}
