// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Base, L0Config} from "scripts/ops/V120/UpgradeV120Base.s.sol";

abstract contract UpgradeV120Destinations is UpgradeV120Base {
    function outputDirectory() public view override returns (string memory) {
        return string.concat(vm.projectRoot(), "/scripts/ops/V120/destinations/txs");
    }

    function upgradeToV120(L0Config memory _config) public {
        require(_config.chainid != ETHEREUM_CHAIN_ID, "V120: use Ethereum script");
        require(_config.chainid != FRAXTAL_CHAIN_ID, "V120: use Fraxtal script");

        _prepareChain(_config);
        (address[] memory implementations, ImplementationKind[] memory kinds) =
            _config.chainid == TEMPO_CHAIN_ID
                ? _deployTempoImplementations()
                : _deployStandardDestinationImplementations();
        _submitUpgrades(implementations, kinds);
    }
}
