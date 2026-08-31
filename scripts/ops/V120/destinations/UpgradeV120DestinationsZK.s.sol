// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Destinations} from "./UpgradeV120Destinations.s.sol";

contract UpgradeV120DestinationsZK is UpgradeV120Destinations {
    function run() public override {
        _upgradeDestinations({ _zkOnly: true });
    }
}
