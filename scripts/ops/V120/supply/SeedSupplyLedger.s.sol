// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Base} from "scripts/ops/V120/UpgradeV120Base.s.sol";
import {NUM_OFTS} from "scripts/L0Constants.sol";
import {console} from "frax-std/FraxTest.sol";

/// @notice Emits the Safe batch that brings a chain's supply ledger into the state v1.2.0's guard
///         requires, without deploying or upgrading anything. Safe to run before or after the
///         upgrade and safe to re-run: every call is diffed against live chain state first, so a
///         value already set produces no transaction and an already-satisfied chain produces no
///         batch at all.
/// @dev The guard reverts an inbound transfer when
///      `totalTransferFrom[eid] > initialTotalSupply[eid] + totalTransferTo[eid]`. v1.1.0 populates
///      those counters but never enforces them, so enforcement begins at the v1.2.0 upgrade against
///      balances accumulated since v1.1.0 — the seed is therefore derived from the live ledger.
contract SeedSupplyLedger is UpgradeV120Base {
    function outputDirectory() public view override returns (string memory) {
        return _txsDirectory("supply");
    }

    function _batchPrefix() internal view override returns (string memory) {
        return "SeedSupply";
    }

    function _deployImplementations()
        internal
        view
        override
        returns (address[] memory implementations, ImplementationKind[] memory kinds)
    {
        implementations = new address[](NUM_OFTS);
        kinds = _kindsForChain();
    }

    function _buildAutomaticSupplySeeds(ImplementationKind[] memory _kinds)
        internal
        override
        returns (SupplySeed[] memory seeds)
    {
        if (simulateConfig.chainid == FRAXTAL_CHAIN_ID) return _buildFraxtalSupplySeeds(_kinds);
        return _buildHubFacingAllowNegativeSeeds(_kinds);
    }

    function run() public override {
        for (uint256 i; i < proxyConfigs.length; ++i) {
            if (proxyConfigs[i].chainid != block.chainid) continue;

            _prepareUpgrade(proxyConfigs[i]);
            ImplementationKind[] memory kinds = _kindsForChain();
            SupplySeed[] memory seeds = _resolveSupplySeeds(kinds);

            _simulateSeedAhead(kinds, seeds);
            _resolveUpgradeAuthority();
            _simulatePostUpgradeSeeds(kinds, seeds);

            if (phasedTxs.length == 0) {
                console.log("Supply ledger already satisfies the v1.2.0 guard; no transactions needed.");
                return;
            }
            _writeBatches();
            return;
        }
        revert("SeedSupplyLedger: chain not found in Proxy config");
    }
}
