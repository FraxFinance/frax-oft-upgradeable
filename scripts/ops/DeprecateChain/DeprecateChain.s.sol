// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

import "./DeprecateOFTBase.s.sol";

/// @notice Disconnects the broadcast chain from every other proxy chain bidirectionally.
///
///         Iteration behavior:
///           - EVM peers (Proxy configs): generate both directions (deprecate->peer and peer->deprecate)
///           - non-EVM peers: generate only deprecate->nonEVM from the EVM side
///             (non-EVM-side disconnect txs must be generated separately with chain-specific tooling)
///
/// Usage:
///   forge script scripts/ops/DeprecateChain/DeprecateChain.s.sol --ffi [--rpc-url <healthy-rpc>]
///
/// Optional env var:
///   DEPRECATE_CHAIN_ID Override the deprecate target chain id (defaults to broadcast chain id).
///   SKIP_DEPRECATE_CHAIN_SIM=<true|1|chainId>
///                    Skip simulating txs on the deprecate chain itself; only simulate on
///                    the other chains targeting the deprecate chain. Useful when deprecate
///                    chain RPC is unavailable.
///   TARGET_CHAIN_ID  When set, only generate JSONs for this one peer chain id (both directions),
///                    instead of iterating all proxy chains.
contract DeprecateChain is DeprecateOFTBase {
    using Strings for uint256;

    /// @dev The chain we are deprecating (defaults to broadcast chain; can be overridden by env).
    ///      All output files live in deprecate-<deprecateChainId>/ regardless of which side
    ///      a given file targets.
    uint256 public deprecateChainId;
    L0Config public deprecateConfig;

    function outputDir() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/scripts/ops/DeprecateChain/txs/deprecate-", deprecateChainId.toString(), "/");
    }

    function setUp() public override {
        super.setUp();
        deprecateChainId = vm.envOr("DEPRECATE_CHAIN_ID", broadcastConfig.chainid);
        deprecateConfig = _getProxyConfigByChainId(deprecateChainId);
    }

    function run() public override {
        vm.createDir(outputDir(), true);

        bool skipDeprecateChainSimulation = _skipDeprecateChainSimulation();
        uint256 targetChainId = vm.envOr("TARGET_CHAIN_ID", uint256(0));

        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            L0Config memory currentPeer = proxyConfigs[i];
            if (currentPeer.chainid == deprecateChainId) continue;
            if (targetChainId != 0 && currentPeer.chainid != targetChainId) continue;

            if (!skipDeprecateChainSimulation) {
                for (uint256 o = 0; o < NUM_OFTS; o++) {
                    _deprecatePairOnToken({_simulateConfig: deprecateConfig, _peer: currentPeer, _tokenIndex: o});
                }
            }

            for (uint256 o = 0; o < NUM_OFTS; o++) {
                _deprecatePairOnToken({_simulateConfig: currentPeer, _peer: deprecateConfig, _tokenIndex: o});
            }
        }

        for (uint256 i = 0; i < nonEvmConfigs.length; i++) {
            L0Config memory nonEvmPeer = nonEvmConfigs[i];
            if (targetChainId != 0 && nonEvmPeer.chainid != targetChainId) continue;

            if (!skipDeprecateChainSimulation) {
                for (uint256 o = 0; o < NUM_OFTS; o++) {
                    _deprecatePairOnToken({_simulateConfig: deprecateConfig, _peer: nonEvmPeer, _tokenIndex: o});
                }
            }
        }
    }

    function _skipDeprecateChainSimulation() internal view returns (bool) {
        string memory raw = vm.envOr("SKIP_DEPRECATE_CHAIN_SIM", string(""));
        if (bytes(raw).length == 0) return false;

        bytes32 h = keccak256(bytes(raw));
        if (h == keccak256("1") || h == keccak256("true") || h == keccak256("TRUE")) {
            return true;
        }

        return h == keccak256(bytes(deprecateChainId.toString()));
    }

    function _getProxyConfigByChainId(uint256 _chainId) internal view returns (L0Config memory) {
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == _chainId) {
                return proxyConfigs[i];
            }
        }
        revert("deprecate chain not found in proxyConfigs");
    }
}
