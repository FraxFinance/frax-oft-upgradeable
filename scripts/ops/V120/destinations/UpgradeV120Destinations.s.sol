// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {UpgradeV120Base, L0Config} from "scripts/ops/V120/UpgradeV120Base.s.sol";
import {console} from "forge-std/console.sol";

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
            if (_isLegacyOnlyChain(chainid)) continue;
            if (chainid == ETHEREUM_CHAIN_ID || chainid == FRAXTAL_CHAIN_ID || chainid == TEMPO_CHAIN_ID) continue;
            if (_isZkStackChain(chainid) != _zkOnly) continue;
            if (_needsDedicatedRun(chainid)) {
                console.log("V120: skipping chain in sweep (needs its own run, see README):", chainid);
                continue;
            }
            upgradeToV120(proxyConfigs[i]);
        }
    }

    /// @notice Chains the multi-chain sweep cannot fork-simulate; run `UpgradeV120Destination`
    ///         against them individually instead of letting one of them abort the whole sweep.
    /// @dev Somnia (5031): its RPCs reject the EIP-1898 block-hash queries forge's fork backend
    ///      needs — deploy with `forge create` and hand-build the batch. HyperEVM (999): the fork
    ///      inherits the chain's small-block gas cap and the implementation deploys run out of gas
    ///      in simulation; broadcast with big blocks enabled for the deployer.
    function _needsDedicatedRun(uint256 _chainid) internal pure returns (bool) {
        return _chainid == 5031 || _chainid == 999;
    }

    function upgradeToV120(L0Config memory _config) public {
        require(_config.chainid != ETHEREUM_CHAIN_ID, "V120: use Ethereum script");
        require(_config.chainid != FRAXTAL_CHAIN_ID, "V120: use Fraxtal script");
        require(_config.chainid != TEMPO_CHAIN_ID, "V120: use Tempo destination script");
        _upgradeChain(_config);
    }
}
