// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Base} from "scripts/ops/V120/UpgradeV120Base.s.sol";

contract UpgradeV120Ethereum is UpgradeV120Base {
    function outputDirectory() public view override returns (string memory) {
        return _txsDirectory("ethereum");
    }

    function _deployImplementations()
        internal
        override
        returns (address[] memory implementations, ImplementationKind[] memory kinds)
    {
        return _deployEthereumImplementations();
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
        _upgradeChainById(ETHEREUM_CHAIN_ID);
    }
}
