// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Destinations} from "./UpgradeV120Destinations.s.sol";

// forge script scripts/ops/V120/destinations/UpgradeV120DestinationsEVM.s.sol
contract UpgradeV120DestinationsEVM is UpgradeV120Destinations {
    function run() public override {
        _upgradeDestinations({ _zkOnly: false });
    }
}
