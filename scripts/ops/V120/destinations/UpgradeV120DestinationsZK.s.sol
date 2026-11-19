// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Destinations} from "./UpgradeV120Destinations.s.sol";

// Upgrades active ZK-stack destination chains only.
contract UpgradeV120DestinationsZK is UpgradeV120Destinations {
    function run() public override {
        _upgradeDestinations({ _zkOnly: true });
    }
}
