// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import {IMessageLib} from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLib.sol";
import {
    EnforcedOptionParam,
    IOAppOptionsType3
} from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {UlnConfig} from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/uln/UlnBase.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IEndpointBlockedLibrary {
    function blockedLibrary() external view returns (address);
}

interface IOAppEnforcedOptionsLike {
    function enforcedOptions(uint32 _eid, uint16 _msgType) external view returns (bytes memory);
}

interface IUlnAppConfigLike {
    function getAppUlnConfig(address _oapp, uint32 _remoteEid) external view returns (UlnConfig memory);
}

/// @notice Disconnects the broadcast chain from every other proxy chain bidirectionally.
///
///         For each (broadcast, other) pair, on BOTH sides, every connection setting that
///         `DeployFraxOFTProtocol` wrote at connect-time is reset only when that exact
///         setting is currently dirty (so resulting Safe batches never revert with
///         SameValue / OnlyNonDefaultLib / InvalidOptions and untouched routes do not
///         get new overrides):
///
///           current state                      -> reset target
///           expected peer                      -> bytes32(0)
///           wired route send side              -> blockedLibrary
///           explicit receive library override  -> DEFAULT_LIB (address(0))
///           non-zero app ULN config            -> empty UlnConfig
///           enforced options                   -> minimal Type-3 (0x0003)
///
///         A zero peer does NOT prove the path is clean; the other settings are still checked
///         independently. An unexpected non-zero peer is skipped for manual review instead of
///         generating calldata against the wrong route.
///
///         Files are written to:
///           scripts/ops/DeprecateChain/txs/deprecate-<broadcastChainId>/Deprecate-<src>-<dst>-<TOKEN>.json
///         where <src> is the chain that executes the tx and <dst> is the other side.
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
contract DeprecateChain is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    uint32 public constant CONFIG_TYPE_ULN = 2;

    /// @dev The chain we are deprecating (defaults to broadcast chain; can be overridden by env).
    ///      All output files live in deprecate-<deprecateChainId>/ regardless of which side
    ///      a given file targets.
    uint256 public deprecateChainId;
    L0Config public deprecateConfig;

    L0Config public peerConfig;

    // Current token being processed for per-token JSON generation
    address public currentOft;
    uint256 public currentTokenIndex;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory base =
            string.concat(root, "/scripts/ops/DeprecateChain/txs/deprecate-", deprecateChainId.toString(), "/");
        string memory tokenPart = _tokenNameForIndex(currentTokenIndex);

        return string.concat(
            base,
            "Deprecate-",
            simulateConfig.chainid.toString(),
            "-",
            peerConfig.chainid.toString(),
            "-",
            tokenPart,
            ".json"
        );
    }

    function _tokenNameForIndex(uint256 _idx) internal pure returns (string memory) {
        if (_idx == uint256(Token.WFRAX)) return "WFRAX";
        if (_idx == uint256(Token.SFRXUSD)) return "SFRXUSD";
        if (_idx == uint256(Token.SFRXETH)) return "SFRXETH";
        if (_idx == uint256(Token.FRXUSD)) return "FRXUSD";
        if (_idx == uint256(Token.FRXETH)) return "FRXETH";
        if (_idx == uint256(Token.FPI)) return "FPI";
        revert("unknown token index");
    }

    function setUp() public override {
        super.setUp();
        deprecateChainId = vm.envOr("DEPRECATE_CHAIN_ID", broadcastConfig.chainid);
        deprecateConfig = _getProxyConfigByChainId(deprecateChainId);
    }

    function run() public override {
        // Ensure the per-deprecation output folder exists before any vm.writeFile.
        string memory outDir =
            string.concat(vm.projectRoot(), "/scripts/ops/DeprecateChain/txs/deprecate-", deprecateChainId.toString());
        vm.createDir(outDir, true);

        bool skipDeprecateChainSimulation = _skipDeprecateChainSimulation();
        uint256 targetChainId = vm.envOr("TARGET_CHAIN_ID", uint256(0));

        // EVM peers: generate both directions.
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

        // non-EVM peers: generate only EVM-side (deprecate -> non-EVM) batches.
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

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Simulates a single source chain and disconnects one OFT path from `_peer`.
    function _deprecatePairOnToken(L0Config memory _simulateConfig, L0Config memory _peer, uint256 _tokenIndex)
        public
        simulateAndWriteTxs(_simulateConfig)
    {
        // connectedOFTs are populated via simulateAndWriteTxs- this is a sanity check
        require(connectedOfts.length == NUM_OFTS, "Missing connected OFTs");
        require(_tokenIndex < connectedOfts.length, "token index out of bounds");

        peerConfig = _peer;
        uint32 dstEid = uint32(_peer.eid);

        currentTokenIndex = _tokenIndex;
        currentOft = connectedOfts[_tokenIndex];
        // Some chains may not have every OFT deployed; skip missing slots to avoid aborting the entire chain run.
        if (currentOft == address(0)) return;
        if (currentOft.code.length == 0) return;

        (bool canProcess, bool hasExpectedPeer) =
            _peerAllowsDeprecation(currentOft, dstEid, _expectedPeerForConfig(_peer, _tokenIndex));
        if (!canProcess) return;

        bool routeHadWiring = hasExpectedPeer || _hasNonSendWiringEvidence(_simulateConfig, currentOft, dstEid);
        _setSendLibraryToBlockedIfWired(_simulateConfig, currentOft, dstEid, routeHadWiring);
        if (hasExpectedPeer) _clearPeer(currentOft, dstEid);
        _resetReceiveLibraryToDefaultIfNeeded(_simulateConfig, currentOft, dstEid);
        _clearEnforcedOptionsForEid(currentOft, dstEid);
        _forceOverwriteUlnToDefaultParams({_connectedConfig: _simulateConfig, _connectedOft: currentOft, _eid: dstEid});
    }

    /// @dev Original setup writes enforcedOptions for msgType 1 and msgType 2 per peer EID via
    ///      `DeployFraxOFTProtocol.setEvmEnforcedOptions()`. To fully tear down the connection
    ///      we set both back to the minimal valid Type-3 prefix (0x0003) which is the smallest
    ///      OptionsBuilder.newOptions() output and is the closest equivalent of "no extra options".
    ///      Empty bytes would revert with `InvalidOptions` because the contract asserts type 3.
    ///      Skipped per msgType if already equal to that minimal blob (or empty).
    function _clearEnforcedOptionsForEid(address _oft, uint32 _eid) internal {
        bytes memory cleared = hex"0003"; // OptionsBuilder.newOptions() with no entries

        bytes memory existingOne;
        bytes memory existingTwo;
        try IOAppEnforcedOptionsLike(_oft).enforcedOptions(_eid, 1) returns (bytes memory _e) {
            existingOne = _e;
        } catch {}
        try IOAppEnforcedOptionsLike(_oft).enforcedOptions(_eid, 2) returns (bytes memory _e) {
            existingTwo = _e;
        } catch {}

        bool clearOne = !_bytesEq(existingOne, cleared) && existingOne.length != 0;
        bool clearTwo = !_bytesEq(existingTwo, cleared) && existingTwo.length != 0;
        if (!clearOne && !clearTwo) return;

        uint256 count = (clearOne ? 1 : 0) + (clearTwo ? 1 : 0);
        EnforcedOptionParam[] memory params = new EnforcedOptionParam[](count);
        uint256 idx;
        if (clearOne) {
            params[idx++] = EnforcedOptionParam({eid: _eid, msgType: 1, options: cleared});
        }
        if (clearTwo) {
            params[idx++] = EnforcedOptionParam({eid: _eid, msgType: 2, options: cleared});
        }

        bytes memory data = abi.encodeCall(IOAppOptionsType3.setEnforcedOptions, (params));
        if (!_bypassChainCalls()) {
            _simulateOwnerScopedCall(_oft, data, "setEnforcedOptions(clear)");
        }
        pushSerializedTx({_name: "setEnforcedOptions", _to: _oft, _value: 0, _data: data});
    }

    function _bytesEq(bytes memory _a, bytes memory _b) internal pure returns (bool) {
        return _a.length == _b.length && keccak256(_a) == keccak256(_b);
    }

    /// @dev Reads OApp peer mapping without aborting the whole deprecation run.
    function _tryGetPeer(address _oft, uint32 _eid) internal view returns (bool, bytes32) {
        try IOAppCore(_oft).peers(_eid) returns (bytes32 peer) {
            return (true, peer);
        } catch {
            return (false, bytes32(0));
        }
    }

    /// @dev Sets the send library to blockedLibrary(). Explicit send overrides are always
    ///      blocked; default-resolved sends are only blocked if another current-state route
    ///      setting proves the path was wired.
    function _setSendLibraryToBlockedIfWired(
        L0Config memory _connectedConfig,
        address _connectedOft,
        uint32 _eid,
        bool _routeHadWiring
    ) internal {
        IMessageLibManager endpoint = IMessageLibManager(_connectedConfig.endpoint);

        bool isDefaultSend;
        try endpoint.isDefaultSendLibrary(_connectedOft, _eid) returns (bool _isDefaultSend) {
            isDefaultSend = _isDefaultSend;
        } catch {
            return;
        }

        address desiredSendLib = IEndpointBlockedLibrary(_connectedConfig.endpoint).blockedLibrary();

        if (isDefaultSend) {
            if (!_routeHadWiring) return;

            // If the endpoint default already resolves to the blocked library, avoid adding
            // a redundant explicit override. If the default is unavailable, setting the
            // blocked library may still be valid, so keep going.
            try endpoint.getSendLibrary(_connectedOft, _eid) returns (address currentSendLib) {
                if (currentSendLib == desiredSendLib) return;
            } catch {}
        } else {
            address currentSendLib;
            try endpoint.getSendLibrary(_connectedOft, _eid) returns (address _currentSendLib) {
                currentSendLib = _currentSendLib;
            } catch {
                return;
            }
            if (currentSendLib == desiredSendLib) return;
        }

        bytes memory sendData = abi.encodeCall(IMessageLibManager.setSendLibrary, (_connectedOft, _eid, desiredSendLib));
        if (!_bypassChainCalls()) {
            _safeCall(_connectedConfig.endpoint, sendData, "setSendLibrary(blocked)");
        }
        pushSerializedTx({_name: "setSendLibrary", _to: _connectedConfig.endpoint, _value: 0, _data: sendData});
    }

    /// @dev Resets an explicit receive library override to endpoint default.
    function _resetReceiveLibraryToDefaultIfNeeded(L0Config memory _connectedConfig, address _connectedOft, uint32 _eid)
        internal
    {
        IMessageLibManager endpoint = IMessageLibManager(_connectedConfig.endpoint);

        bool isDefaultReceive;
        try endpoint.getReceiveLibrary(_connectedOft, _eid) returns (address, bool _isDefaultReceive) {
            isDefaultReceive = _isDefaultReceive;
        } catch {
            return;
        }
        if (isDefaultReceive) return;

        bytes memory data = abi.encodeCall(IMessageLibManager.setReceiveLibrary, (_connectedOft, _eid, address(0), 0));
        if (!_bypassChainCalls()) {
            _safeCall(_connectedConfig.endpoint, data, "setReceiveLibrary(DEFAULT)");
        }
        pushSerializedTx({_name: "setReceiveLibrary", _to: _connectedConfig.endpoint, _value: 0, _data: data});
    }

    /// @dev Explicitly overwrites app-level ULN config to DEFAULT values (inherit endpoint defaults)
    ///      on both send and receive libs, when the lib supports the path EID.
    function _forceOverwriteUlnToDefaultParams(L0Config memory _connectedConfig, address _connectedOft, uint32 _eid)
        internal
    {
        _forceSetUlnDefaultOnLib({
            _connectedConfig: _connectedConfig,
            _connectedOft: _connectedOft,
            _eid: _eid,
            _lib: _connectedConfig.sendLib302
        });

        if (_connectedConfig.receiveLib302 != _connectedConfig.sendLib302) {
            _forceSetUlnDefaultOnLib({
                _connectedConfig: _connectedConfig,
                _connectedOft: _connectedOft,
                _eid: _eid,
                _lib: _connectedConfig.receiveLib302
            });
        }
    }

    /// @dev Writes setConfig(configType=ULN) only when:
    ///      - library supports the EID, and
    ///      - current app config is not already DEFAULT params.
    function _forceSetUlnDefaultOnLib(
        L0Config memory _connectedConfig,
        address _connectedOft,
        uint32 _eid,
        address _lib
    ) internal {
        if (_lib == address(0)) return;

        // Per-lib validity check: skip if library does not support this EID.
        bool supportsEid;
        try IMessageLib(_lib).isSupportedEid(_eid) returns (bool _supports) {
            supportsEid = _supports;
        } catch {
            return;
        }
        if (!supportsEid) return;

        UlnConfig memory desiredConfig;
        desiredConfig.requiredDVNs = new address[](0);
        desiredConfig.optionalDVNs = new address[](0);

        // Idempotency guard on raw app config only. If app config is already zero/default,
        // do not emit a tx just because effective config inherits non-zero endpoint defaults.
        try IUlnAppConfigLike(_lib).getAppUlnConfig(_connectedOft, _eid) returns (UlnConfig memory appConfig) {
            if (_isZeroUlnConfig(appConfig)) {
                return;
            }
        } catch {
            // If app-level introspection is unavailable, skip to avoid false-positive tx generation.
            return;
        }

        SetConfigParam[] memory setConfigParamArray = new SetConfigParam[](1);
        setConfigParamArray[0] =
            SetConfigParam({eid: _eid, configType: CONFIG_TYPE_ULN, config: abi.encode(desiredConfig)});

        bytes memory data = abi.encodeCall(IMessageLibManager.setConfig, (_connectedOft, _lib, setConfigParamArray));
        if (!_bypassChainCalls()) {
            _safeCall(_connectedConfig.endpoint, data, "setConfig(ULN->DEFAULT)");
        }
        pushSerializedTx({_name: "setConfig", _to: _connectedConfig.endpoint, _value: 0, _data: data});
    }

    function _isZeroUlnConfig(UlnConfig memory _cfg) internal pure returns (bool) {
        return _cfg.confirmations == 0 && _cfg.requiredDVNCount == 0 && _cfg.optionalDVNCount == 0
            && _cfg.optionalDVNThreshold == 0 && _cfg.requiredDVNs.length == 0 && _cfg.optionalDVNs.length == 0;
    }

    /// @dev Returns whether the path can be safely processed and whether its peer proves
    ///      this exact route is currently wired. Unexpected non-zero peers are skipped so
    ///      the script cannot silently deprecate a route that points somewhere other than
    ///      the requested target chain/token.
    function _peerAllowsDeprecation(address _oft, uint32 _eid, bytes32 _expectedPeer)
        internal
        view
        returns (bool, bool)
    {
        (bool hasPeer, bytes32 currentPeer) = _tryGetPeer(_oft, _eid);
        if (!hasPeer) return (false, false);
        if (currentPeer == bytes32(0)) return (true, false);
        if (_expectedPeer == bytes32(0) || currentPeer != _expectedPeer) return (false, false);
        return (true, true);
    }

    function _clearPeer(address _oft, uint32 _eid) internal {
        bytes memory data = abi.encodeCall(IOAppCore.setPeer, (_eid, bytes32(0)));
        if (!_bypassChainCalls()) {
            _simulateOwnerScopedCall(_oft, data, "setPeer");
        }
        pushSerializedTx({_name: "setPeer", _to: _oft, _value: 0, _data: data});
    }

    function _hasNonSendWiringEvidence(L0Config memory _connectedConfig, address _connectedOft, uint32 _eid)
        internal
        view
        returns (bool)
    {
        if (_hasExplicitReceiveLibrary(_connectedConfig, _connectedOft, _eid)) return true;
        if (_hasDirtyEnforcedOptions(_connectedOft, _eid)) return true;
        if (_hasDirtyUlnAppConfig(_connectedOft, _eid, _connectedConfig.sendLib302)) return true;
        if (_connectedConfig.receiveLib302 != _connectedConfig.sendLib302) {
            if (_hasDirtyUlnAppConfig(_connectedOft, _eid, _connectedConfig.receiveLib302)) return true;
        }
        return false;
    }

    function _hasExplicitReceiveLibrary(L0Config memory _connectedConfig, address _connectedOft, uint32 _eid)
        internal
        view
        returns (bool)
    {
        try IMessageLibManager(_connectedConfig.endpoint).getReceiveLibrary(_connectedOft, _eid) returns (
            address, bool isDefaultReceive
        ) {
            return !isDefaultReceive;
        } catch {
            return false;
        }
    }

    function _hasDirtyEnforcedOptions(address _oft, uint32 _eid) internal view returns (bool) {
        bytes memory cleared = hex"0003";

        try IOAppEnforcedOptionsLike(_oft).enforcedOptions(_eid, 1) returns (bytes memory existingOne) {
            if (!_bytesEq(existingOne, cleared) && existingOne.length != 0) return true;
        } catch {}

        try IOAppEnforcedOptionsLike(_oft).enforcedOptions(_eid, 2) returns (bytes memory existingTwo) {
            if (!_bytesEq(existingTwo, cleared) && existingTwo.length != 0) return true;
        } catch {}

        return false;
    }

    function _hasDirtyUlnAppConfig(address _connectedOft, uint32 _eid, address _lib) internal view returns (bool) {
        if (_lib == address(0)) return false;

        try IMessageLib(_lib).isSupportedEid(_eid) returns (bool supportsEid) {
            if (!supportsEid) return false;
        } catch {
            return false;
        }

        try IUlnAppConfigLike(_lib).getAppUlnConfig(_connectedOft, _eid) returns (UlnConfig memory appConfig) {
            return !_isZeroUlnConfig(appConfig);
        } catch {
            return false;
        }
    }

    function _expectedPeerForConfig(L0Config memory _peer, uint256 _tokenIndex) internal view returns (bytes32) {
        (bool isNonEvm, bytes32 nonEvmPeer) = _tryGetNonEvmPeer(_peer, _tokenIndex);
        if (isNonEvm) return nonEvmPeer;

        address[] memory peerOfts = _getChainPeers(_peer.chainid);
        address expectedPeer = peerOfts[_tokenIndex];
        if (expectedPeer == address(0)) return bytes32(0);
        return addressToBytes32(expectedPeer);
    }

    function _tryGetNonEvmPeer(L0Config memory _peer, uint256 _tokenIndex) internal view returns (bool, bytes32) {
        for (uint256 i = 0; i < nonEvmConfigs.length; i++) {
            if (nonEvmConfigs[i].chainid != _peer.chainid) continue;
            if (nonEvmConfigs[i].eid != _peer.eid) continue;
            if (i >= nonEvmPeersArrays.length) return (true, bytes32(0));
            if (_tokenIndex >= nonEvmPeersArrays[i].length) return (true, bytes32(0));
            return (true, nonEvmPeersArrays[i][_tokenIndex]);
        }

        return (false, bytes32(0));
    }

    /// @dev Simulates an OApp owner-scoped call. During simulation, endpoint ops run as the chain
    ///      delegate, but ops like setPeer / setEnforcedOptions are gated by Ownable and require
    ///      the OApp owner. For most chains owner == delegate so the delegate call succeeds. For
    ///      paths like Ethereum FRXUSD lockbox where they differ, fall back to owner and restore
    ///      the delegate prank afterwards.
    function _simulateOwnerScopedCall(address _oft, bytes memory _data, string memory _label) internal {
        (bool ok,) = _oft.call(_data);
        if (ok) return;

        vm.stopPrank();
        address owner_;
        try Ownable(_oft).owner() returns (address _owner) {
            owner_ = _owner;
        } catch {
            owner_ = address(0);
        }
        require(owner_ != address(0), string.concat(_label, ": owner() unavailable"));

        vm.startPrank(owner_);
        _safeCall(_oft, _data, string.concat(_label, "(owner)"));
        vm.stopPrank();
        vm.startPrank(simulateConfig.delegate);
    }

    function _bypassChainCalls() internal view returns (bool) {
        return vm.envOr("BYPASS_CHAIN_CALLS", false);
    }

    function _skipDeprecateChainSimulation() internal view returns (bool) {
        string memory raw = vm.envOr("SKIP_DEPRECATE_CHAIN_SIM", string(""));
        if (bytes(raw).length == 0) return false;

        bytes32 h = keccak256(bytes(raw));
        if (h == keccak256("1") || h == keccak256("true") || h == keccak256("TRUE")) {
            return true;
        }

        // Also allow passing the chain id directly, e.g. SKIP_DEPRECATE_CHAIN_SIM=1101.
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
