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

    /// @dev Step 2 (supply ledger) is ~50 writes; above ~2 KB a Ledger signing through MetaMask rejects
    ///      the SafeTx (0x6a00), so it is written as parts. The 1,956-byte first version was signed on Ledgers.
    function _maxBatchBytes() internal pure override returns (uint256) {
        return 2_000;
    }

    function run() public override {
        _upgradeChainById(FRAXTAL_CHAIN_ID);
    }
}
