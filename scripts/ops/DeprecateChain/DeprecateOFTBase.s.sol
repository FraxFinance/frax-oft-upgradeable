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

/// @notice Base contract for deprecating OFT paths via LayerZero configuration resets.
///
///         Subclasses override run() to control iteration strategy:
///         - DeprecateChain: iterate all tokens for a single chain
///         - DeprecateToken: iterate all chains for a single token
///
///         For each (source chain, peer, token) triplet, every connection setting that
///         `DeployFraxOFTProtocol` wrote at connect-time is reset only when that exact
///         setting is currently dirty (so resulting Safe batches never revert with
///         SameValue / OnlyNonDefaultLib / InvalidOptions):
///
///           current state                      -> reset target
///           expected peer                      -> bytes32(0)
///           wired route send side              -> blockedLibrary
///           explicit receive library override  -> DEFAULT_LIB (address(0))
///           non-zero app ULN config            -> empty UlnConfig
///           enforced options                   -> minimal Type-3 (0x0003)
///
///         Files are written to:
///           scripts/ops/DeprecateChain/txs/<subclass-specific-path>/Deprecate-<src>-<dst>-<TOKEN>.json
///         where <src> is the chain that executes the tx and <dst> is the other side.
///         If an OApp owner-scoped tx must be executed by an owner that differs from the
///         endpoint delegate, that tx is split into:
///           Deprecate-<src>-<dst>-<TOKEN>-owner-<owner>.json
abstract contract DeprecateOFTBase is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    uint32 public constant CONFIG_TYPE_ULN = 2;

    L0Config public peerConfig;

    // Current token being processed for per-token JSON generation
    address public currentOft;
    uint256 public currentTokenIndex;

    SerializedTx[] public ownerScopedSerializedTxs;
    address public ownerScopedTxOwner;

    function _tokenNameForIndex(uint256 _idx) internal pure returns (string memory) {
        if (_idx == uint256(Token.WFRAX)) return "WFRAX";
        if (_idx == uint256(Token.SFRXUSD)) return "SFRXUSD";
        if (_idx == uint256(Token.SFRXETH)) return "SFRXETH";
        if (_idx == uint256(Token.FRXUSD)) return "FRXUSD";
        if (_idx == uint256(Token.FRXETH)) return "FRXETH";
        if (_idx == uint256(Token.FPI)) return "FPI";
        revert("unknown token index");
    }

    /// @dev Subclasses override to provide the output directory path.
    function outputDir() public view virtual returns (string memory);

    /// @dev Default filename implementation; subclasses can override if needed.
    function filename() public view virtual override returns (string memory) {
        string memory base = outputDir();
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

    function ownerFilename(address _owner) public view returns (string memory) {
        string memory base = outputDir();
        string memory tokenPart = _tokenNameForIndex(currentTokenIndex);

        return string.concat(
            base,
            "Deprecate-",
            simulateConfig.chainid.toString(),
            "-",
            peerConfig.chainid.toString(),
            "-",
            tokenPart,
            "-owner-",
            Strings.toHexString(_owner),
            ".json"
        );
    }

    modifier simulateAndWriteTxs(L0Config memory _simulateConfig) override {
        delete enforcedOptionParams;
        delete serializedTxs;
        delete ownerScopedSerializedTxs;
        ownerScopedTxOwner = address(0);

        simulateConfig = _simulateConfig;
        _populateConnectedOfts();

        vm.createSelectFork(_simulateConfig.RPC);
        vm.startPrank(_simulateConfig.delegate);
        _;
        vm.stopPrank();

        if (serializedTxs.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxs, filename());
        }
        if (ownerScopedSerializedTxs.length > 0) {
            new SafeTxUtil().writeTxs(ownerScopedSerializedTxs, ownerFilename(ownerScopedTxOwner));
        }
    }

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
        if (currentOft == address(0) || currentOft.code.length == 0) {
            _logSkip(_simulateConfig, _peer, "OFT not deployed");
            return;
        }

        bytes32 expectedPeer = _expectedPeerForConfig(_peer, _tokenIndex);
        (bool canProcess, bool hasExpectedPeer) = _peerAllowsDeprecation(currentOft, dstEid, expectedPeer);
        if (!canProcess) {
            // Absence of an output file otherwise conflates "already clean" with "refused to touch
            // this route". Only the latter needs a human, so it must not be silent: an unresolvable
            // expected peer (e.g. a chain missing from NonEvmPeers.json) leaves a live route wired
            // with nothing in the output to show for it.
            (, bytes32 currentPeer) = _tryGetPeer(currentOft, dstEid);
            if (expectedPeer == bytes32(0)) {
                _logSkip(_simulateConfig, _peer, "NEEDS REVIEW: peer set on-chain but no expected peer in config");
            } else {
                _logSkip(_simulateConfig, _peer, "NEEDS REVIEW: on-chain peer does not match expected peer");
            }
            console.log("      on-chain peer:", vm.toString(currentPeer));
            console.log("      expected peer:", vm.toString(expectedPeer));
            return;
        }

        bool routeHadWiring = hasExpectedPeer || _hasNonSendWiringEvidence(_simulateConfig, currentOft, dstEid);
        _setSendLibraryToBlockedIfWired(_simulateConfig, currentOft, dstEid, routeHadWiring);
        if (hasExpectedPeer) _clearPeer(currentOft, dstEid);
        _resetReceiveLibraryToDefaultIfNeeded(_simulateConfig, currentOft, dstEid);
        _clearEnforcedOptionsForEid(currentOft, dstEid);
        _forceOverwriteUlnToDefaultParams({_connectedConfig: _simulateConfig, _connectedOft: currentOft, _eid: dstEid});
    }

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
        bool ownerScoped;
        if (!_bypassChainCalls()) {
            ownerScoped = _simulateOwnerScopedCall(_oft, data, "setEnforcedOptions(clear)");
        }
        _pushCallerScopedSerializedTx({
            _ownerScoped: ownerScoped, _name: "setEnforcedOptions", _to: _oft, _value: 0, _data: data
        });
    }

    function _bytesEq(bytes memory _a, bytes memory _b) internal pure returns (bool) {
        return _a.length == _b.length && keccak256(_a) == keccak256(_b);
    }

    /// @dev Reports a route that produced no calldata, so a missing output file is never ambiguous.
    function _logSkip(L0Config memory _src, L0Config memory _dst, string memory _reason) internal view {
        console.log(
            string.concat(
                "  SKIP ",
                _tokenNameForIndex(currentTokenIndex),
                " ",
                _src.chainid.toString(),
                " -> ",
                _dst.chainid.toString(),
                ": ",
                _reason
            )
        );
    }

    function _tryGetPeer(address _oft, uint32 _eid) internal view returns (bool, bytes32) {
        try IOAppCore(_oft).peers(_eid) returns (bytes32 peer) {
            return (true, peer);
        } catch {
            return (false, bytes32(0));
        }
    }

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

    function _forceSetUlnDefaultOnLib(
        L0Config memory _connectedConfig,
        address _connectedOft,
        uint32 _eid,
        address _lib
    ) internal {
        if (_lib == address(0)) return;

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

        try IUlnAppConfigLike(_lib).getAppUlnConfig(_connectedOft, _eid) returns (UlnConfig memory appConfig) {
            if (_isZeroUlnConfig(appConfig)) {
                return;
            }
        } catch {
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
        bool ownerScoped;
        if (!_bypassChainCalls()) {
            ownerScoped = _simulateOwnerScopedCall(_oft, data, "setPeer");
        }
        _pushCallerScopedSerializedTx({_ownerScoped: ownerScoped, _name: "setPeer", _to: _oft, _value: 0, _data: data});
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

    function _pushCallerScopedSerializedTx(
        bool _ownerScoped,
        string memory _name,
        address _to,
        uint256 _value,
        bytes memory _data
    ) internal {
        if (_ownerScoped) {
            ownerScopedSerializedTxs.push(SerializedTx({name: _name, to: _to, value: _value, data: _data}));
        } else {
            pushSerializedTx({_name: _name, _to: _to, _value: _value, _data: _data});
        }
    }

    function _simulateOwnerScopedCall(address _oft, bytes memory _data, string memory _label) internal returns (bool) {
        (bool ok,) = _oft.call(_data);
        if (ok) return false;

        vm.stopPrank();
        address owner_;
        try Ownable(_oft).owner() returns (address _owner) {
            owner_ = _owner;
        } catch {
            owner_ = address(0);
        }
        require(owner_ != address(0), string.concat(_label, ": owner() unavailable"));
        if (ownerScopedTxOwner == address(0)) {
            ownerScopedTxOwner = owner_;
        } else {
            require(ownerScopedTxOwner == owner_, "mixed owner-scoped tx owners");
        }

        vm.startPrank(owner_);
        _safeCall(_oft, _data, string.concat(_label, "(owner)"));
        vm.stopPrank();
        vm.startPrank(simulateConfig.delegate);

        return owner_ != simulateConfig.delegate;
    }

    function _bypassChainCalls() internal view returns (bool) {
        return vm.envOr("BYPASS_CHAIN_CALLS", false);
    }
}
