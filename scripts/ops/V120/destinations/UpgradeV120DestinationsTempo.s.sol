// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Base} from "scripts/ops/V120/UpgradeV120Base.s.sol";

/// @notice Upgrades only the Tempo destination profile.
contract UpgradeV120DestinationsTempo is UpgradeV120Base {
    function outputDirectory() public view override returns (string memory) {
        return _txsDirectory("destinations");
    }

    function _deployImplementations()
        internal
        override
        returns (address[] memory implementations, ImplementationKind[] memory kinds)
    {
        return _deployTempoImplementations();
    }

    function _buildAutomaticSupplySeeds(ImplementationKind[] memory _kinds)
        internal
        view
        override
        returns (SupplySeed[] memory seeds)
    {
        return _buildHubFacingAllowNegativeSeeds(_kinds);
    }

    function run() public override {
        _upgradeChainById(TEMPO_CHAIN_ID);
    }
}
