// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

import "./DeprecateOFTBase.s.sol";

/// @notice Deprecates a single token across all LayerZero chains.
///
///         For each (source chain, peer) pair on both EVM and non-EVM networks,
///         disconnects the target token and resets all connection settings.
///
///         Iteration behavior:
///           - EVM peers (Proxy configs): generate both directions (chain->peer and peer->chain)
///           - non-EVM peers: generate only chain->nonEVM from the EVM side
///             (non-EVM-side disconnect txs must be generated separately with chain-specific tooling)
///
/// Usage:
///   DEPRECATE_TOKEN=FPI forge script scripts/ops/DeprecateChain/DeprecateToken.s.sol --ffi [--rpc-url <healthy-rpc>]
///
/// Env vars:
///   DEPRECATE_TOKEN       Token symbol to deprecate (WFRAX|SFRXUSD|SFRXETH|FRXUSD|FRXETH|FPI). Preferred.
///   DEPRECATE_TOKEN_INDEX Raw Token enum index; only consulted when DEPRECATE_TOKEN is unset.
///   SOURCE_CHAIN_ID       Only emit batches executed on (and forked from) this chain. This is the
///                         chunking unit used by run-deprecate-token.sh: one chunk == one RPC.
///   SKIP_SIMULATE_CHAIN_ID If set, never fork this chain id. Useful when its RPC is unavailable.
///   TARGET_CHAIN_ID       Only emit batches whose peer is this chain id. Composes with
///                         SOURCE_CHAIN_ID to isolate a single route.
contract DeprecateToken is DeprecateOFTBase {
    using Strings for uint256;

    uint256 public tokenIndexToDeprecate;

    function outputDir() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory tokenPart = _tokenNameForIndex(tokenIndexToDeprecate);
        return string.concat(root, "/scripts/ops/DeprecateChain/txs/deprecate-", tokenPart, "/");
    }

    function setUp() public override {
        super.setUp();

        // Prefer the symbolic name; a mistyped raw index would tear down a different token
        // across the whole mesh, and the resulting batches look identical at a glance.
        string memory name = vm.envOr("DEPRECATE_TOKEN", string(""));
        if (bytes(name).length != 0) {
            tokenIndexToDeprecate = _tokenIndexForName(name);
        } else {
            tokenIndexToDeprecate = vm.envUint("DEPRECATE_TOKEN_INDEX");
        }
        require(tokenIndexToDeprecate < NUM_OFTS, "token index out of bounds");
    }

    function _tokenIndexForName(string memory _name) internal pure returns (uint256) {
        bytes32 h = keccak256(bytes(_name));
        if (h == keccak256("WFRAX")) return uint256(Token.WFRAX);
        if (h == keccak256("SFRXUSD")) return uint256(Token.SFRXUSD);
        if (h == keccak256("SFRXETH")) return uint256(Token.SFRXETH);
        if (h == keccak256("FRXUSD")) return uint256(Token.FRXUSD);
        if (h == keccak256("FRXETH")) return uint256(Token.FRXETH);
        if (h == keccak256("FPI")) return uint256(Token.FPI);
        revert("DEPRECATE_TOKEN: unknown token name");
    }

    function run() public override {
        vm.createDir(outputDir(), true);

        uint256 sourceChainId = vm.envOr("SOURCE_CHAIN_ID", uint256(0));
        uint256 skipSimulateChainId = vm.envOr("SKIP_SIMULATE_CHAIN_ID", uint256(0));
        uint256 targetChainId = vm.envOr("TARGET_CHAIN_ID", uint256(0));

        // Ordered (src, dst) pairs, one direction each, so every route is emitted exactly once.
        // Only `src` is forked, so filtering on it hoists the whole RPC cost out of the inner loop:
        // SOURCE_CHAIN_ID=X is one chunk == one endpoint, and a dead chain fails only its own chunk.
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            L0Config memory src = proxyConfigs[i];
            if (sourceChainId != 0 && src.chainid != sourceChainId) continue;
            if (skipSimulateChainId != 0 && src.chainid == skipSimulateChainId) continue;

            for (uint256 j = 0; j < proxyConfigs.length; j++) {
                L0Config memory dst = proxyConfigs[j];
                if (dst.chainid == src.chainid) continue;
                if (targetChainId != 0 && dst.chainid != targetChainId) continue;

                _deprecatePairOnToken({
                    _simulateConfig: src,
                    _peer: dst,
                    _tokenIndex: tokenIndexToDeprecate
                });
            }

            // EVM -> non-EVM only; the non-EVM side needs chain-specific tooling.
            for (uint256 j = 0; j < nonEvmConfigs.length; j++) {
                L0Config memory nonEvmDst = nonEvmConfigs[j];
                if (targetChainId != 0 && nonEvmDst.chainid != targetChainId) continue;

                _deprecatePairOnToken({
                    _simulateConfig: src,
                    _peer: nonEvmDst,
                    _tokenIndex: tokenIndexToDeprecate
                });
            }
        }
    }
}
