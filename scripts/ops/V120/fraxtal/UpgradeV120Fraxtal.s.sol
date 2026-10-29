// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Base} from "scripts/ops/V120/UpgradeV120Base.s.sol";

contract UpgradeV120Fraxtal is UpgradeV120Base {
    function outputDirectory() public view override returns (string memory) {
        return _txsDirectory("fraxtal");
    }

    function _deployImplementations()
        internal
        override
        returns (address[] memory implementations, ImplementationKind[] memory kinds)
    {
        return _deployFraxtalImplementations();
    }

    function _buildAutomaticSupplySeeds(ImplementationKind[] memory _kinds)
        internal
        override
        returns (SupplySeed[] memory seeds)
    {
        return _buildFraxtalSupplySeeds(_kinds);
    }

    function run() public override {
        _upgradeChainById(FRAXTAL_CHAIN_ID);
    }
}
