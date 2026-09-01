// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Base, L0Config} from "scripts/ops/V120/UpgradeV120Base.s.sol";

abstract contract UpgradeV120Destinations is UpgradeV120Base {
    function outputDirectory() public view override returns (string memory) {
        return _txsDirectory("destinations");
    }

    function _deployImplementations()
        internal
        virtual
        override
        returns (address[] memory implementations, ImplementationKind[] memory kinds)
    {
        return _deployStandardDestinationImplementations();
    }

    function _buildAutomaticSupplySeeds(ImplementationKind[] memory)
        internal
        virtual
        override
        returns (SupplySeed[] memory seeds)
    {
        return new SupplySeed[](0);
    }

    /// @notice Upgrade every active destination. `_zkOnly` selects the ZK-stack chains (zkSync,
    ///         Abstract) handled by the dedicated ZK script; the EVM script takes the complement.
    ///         Ethereum, Fraxtal, Tempo, and deprecated chains are always excluded.
    function _upgradeDestinations(bool _zkOnly) internal {
        for (uint256 i; i < proxyConfigs.length; ++i) {
            uint256 chainid = proxyConfigs[i].chainid;
            if (isDeprecatedChain(chainid)) continue;
            if (chainid == ETHEREUM_CHAIN_ID || chainid == FRAXTAL_CHAIN_ID || chainid == TEMPO_CHAIN_ID) continue;
            if (_isZkStackChain(chainid) != _zkOnly) continue;
            upgradeToV120(proxyConfigs[i]);
        }
    }

    function upgradeToV120(L0Config memory _config) public {
        require(_config.chainid != ETHEREUM_CHAIN_ID, "V120: use Ethereum script");
        require(_config.chainid != FRAXTAL_CHAIN_ID, "V120: use Fraxtal script");
        require(_config.chainid != TEMPO_CHAIN_ID, "V120: use Tempo destination script");
        _upgradeChain(_config);
    }
}
