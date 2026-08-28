// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Base, L0Config} from "scripts/ops/V120/UpgradeV120Base.s.sol";

contract UpgradeV120Fraxtal is UpgradeV120Base {
    function outputDirectory() public view override returns (string memory) {
        return string.concat(vm.projectRoot(), "/scripts/ops/V120/fraxtal/txs");
    }

    function run() public override {
        for (uint256 i; i < proxyConfigs.length; ++i) {
            L0Config memory config = proxyConfigs[i];
            if (config.chainid != FRAXTAL_CHAIN_ID) continue;

            _prepareChain(config);
            (address[] memory implementations, ImplementationKind[] memory kinds) =
                _deployFraxtalImplementations();
            _submitUpgrades(implementations, kinds);
            return;
        }
        revert("V120: Fraxtal config not found");
    }
}
