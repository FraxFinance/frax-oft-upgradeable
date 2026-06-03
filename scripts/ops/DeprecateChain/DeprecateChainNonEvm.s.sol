// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IMessageLib } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLib.sol";
import { Constant } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/test/util/Constant.sol";
import { UlnConfig } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/uln/UlnBase.sol";

/// @notice Disconnects Fraxtal from non-EVM destinations only (Aptos + Movement).
///         Generates Fraxtal-side Safe JSONs for each token and non-EVM destination EID.
///
/// forge script scripts/ops/DeprecateChain/DeprecateChainNonEvm.s.sol --rpc-url https://rpc.frax.com --ffi
contract DeprecateChainNonEvm is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    uint32 public constant APTOS_EID = 30108;
    uint32 public constant MOVEMENT_EID = 30325;

    L0Config public fraxtalConfig;

    // Current token being processed for per-token JSON generation
    address public currentOft;
    uint256 public currentTokenIndex;

    // Current destination eid for path-specific tx generation
    uint32 public currentDstEid;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory base = string.concat(root, "/scripts/ops/DeprecateChain/txs/");
        string memory tokenPart = _tokenNameForIndex(currentTokenIndex);

        return string.concat(
            base,
            "Deprecate-252-",
            uint256(currentDstEid).toString(),
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

        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 252) fraxtalConfig = proxyConfigs[i];
        }

        require(fraxtalConfig.chainid == 252, "fraxtalConfig not found");
    }

    function run() public override {
        address[] memory fraxtalOfts = _getChainPeers(fraxtalConfig.chainid);

        for (uint256 o = 0; o < fraxtalOfts.length; o++) {
            _deprecateFraxtalTokenToEid({
                _oft: fraxtalOfts[o],
                _tokenIndex: o,
                _dstEid: APTOS_EID
            });

            _deprecateFraxtalTokenToEid({
                _oft: fraxtalOfts[o],
                _tokenIndex: o,
                _dstEid: MOVEMENT_EID
            });
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _requireNonZeroCurrentOft(uint256 _idx, string memory _stage) internal view {
        require(
            currentOft != address(0),
            string.concat(
                "connected OFT is zero @",
                _stage,
                " idx=",
                _idx.toString(),
                " simulateChain=",
                simulateConfig.chainid.toString()
            )
        );
    }

    function _deprecateFraxtalTokenToEid(
        address _oft,
        uint256 _tokenIndex,
        uint32 _dstEid
    ) internal simulateAndWriteTxs(fraxtalConfig) {
        currentDstEid = _dstEid;
        currentTokenIndex = _tokenIndex;
        currentOft = _oft;
        _requireNonZeroCurrentOft(_tokenIndex, "non-evm-deprecate");

        _resetPathToEndpointDefaults({
            _connectedConfig: fraxtalConfig,
            _connectedOft: currentOft,
            _eid: currentDstEid
        });
        _forceOverwriteUlnToDefaultParams({
            _connectedConfig: fraxtalConfig,
            _connectedOft: currentOft,
            _eid: currentDstEid
        });
        _zeroPeerByEid(currentOft, currentDstEid);
    }

    /// @dev Restores OApp path to endpoint defaults by:
    ///      1) clearing custom receive timeout (if any),
    ///      2) setting send library override to DEFAULT_LIB (address(0)),
    ///      3) setting receive library override to DEFAULT_LIB (address(0)).
    function _resetPathToEndpointDefaults(
        L0Config memory _connectedConfig,
        address _connectedOft,
        uint32 _eid
    ) internal {
        if (_bypassChainCalls()) {
            bytes memory sendDataBypass = abi.encodeCall(
                IMessageLibManager.setSendLibrary,
                (_connectedOft, _eid, address(0))
            );
            pushSerializedTx({
                _name: "setSendLibrary",
                _to: _connectedConfig.endpoint,
                _value: 0,
                _data: sendDataBypass
            });

            bytes memory timeoutDataBypass = abi.encodeCall(
                IMessageLibManager.setReceiveLibraryTimeout,
                (_connectedOft, _eid, address(0), 0)
            );
            pushSerializedTx({
                _name: "setReceiveLibraryTimeout",
                _to: _connectedConfig.endpoint,
                _value: 0,
                _data: timeoutDataBypass
            });

            bytes memory receiveDataBypass = abi.encodeCall(
                IMessageLibManager.setReceiveLibrary,
                (_connectedOft, _eid, address(0), 0)
            );
            pushSerializedTx({
                _name: "setReceiveLibrary",
                _to: _connectedConfig.endpoint,
                _value: 0,
                _data: receiveDataBypass
            });
            return;
        }

        // Send library: reset custom override to endpoint default.
        bool isDefaultSend = IMessageLibManager(_connectedConfig.endpoint).isDefaultSendLibrary({
            _sender: _connectedOft,
            _eid: _eid
        });
        if (!isDefaultSend) {
            bytes memory sendData = abi.encodeCall(
                IMessageLibManager.setSendLibrary,
                (_connectedOft, _eid, address(0))
            );
            _safeCall(_connectedConfig.endpoint, sendData, "setSendLibrary(DEFAULT)");
            pushSerializedTx({
                _name: "setSendLibrary",
                _to: _connectedConfig.endpoint,
                _value: 0,
                _data: sendData
            });
        }

        // Receive library: clear custom timeout first if currently non-default.
        (address currentReceiveLib, bool isDefaultReceive) = IMessageLibManager(_connectedConfig.endpoint)
            .getReceiveLibrary({ _receiver: _connectedOft, _eid: _eid });

        if (!isDefaultReceive) {
            bytes memory timeoutData = abi.encodeCall(
                IMessageLibManager.setReceiveLibraryTimeout,
                (_connectedOft, _eid, currentReceiveLib, 0)
            );
            _safeCall(_connectedConfig.endpoint, timeoutData, "setReceiveLibraryTimeout(clear)");
            pushSerializedTx({
                _name: "setReceiveLibraryTimeout",
                _to: _connectedConfig.endpoint,
                _value: 0,
                _data: timeoutData
            });

            bytes memory receiveData = abi.encodeCall(
                IMessageLibManager.setReceiveLibrary,
                (_connectedOft, _eid, address(0), 0)
            );
            _safeCall(_connectedConfig.endpoint, receiveData, "setReceiveLibrary(DEFAULT)");
            pushSerializedTx({
                _name: "setReceiveLibrary",
                _to: _connectedConfig.endpoint,
                _value: 0,
                _data: receiveData
            });
        }
    }

    /// @dev Explicitly overwrites app-level ULN config to DEFAULT values (inherit endpoint defaults)
    ///      on both send and receive libs, when the lib supports the path EID.
    function _forceOverwriteUlnToDefaultParams(
        L0Config memory _connectedConfig,
        address _connectedOft,
        uint32 _eid
    ) internal {
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

        if (_bypassChainCalls()) {
            UlnConfig memory desiredConfigBypass;
            desiredConfigBypass.confirmations = 0;
            desiredConfigBypass.requiredDVNCount = 0;
            desiredConfigBypass.optionalDVNCount = 0;
            desiredConfigBypass.optionalDVNThreshold = 0;
            desiredConfigBypass.requiredDVNs = new address[](0);
            desiredConfigBypass.optionalDVNs = new address[](0);

            SetConfigParam[] memory setConfigParamArrayBypass = new SetConfigParam[](1);
            setConfigParamArrayBypass[0] = SetConfigParam({
                eid: _eid,
                configType: Constant.CONFIG_TYPE_ULN,
                config: abi.encode(desiredConfigBypass)
            });

            bytes memory dataBypass = abi.encodeCall(
                IMessageLibManager.setConfig,
                (_connectedOft, _lib, setConfigParamArrayBypass)
            );
            pushSerializedTx({
                _name: "setConfig",
                _to: _connectedConfig.endpoint,
                _value: 0,
                _data: dataBypass
            });
            return;
        }

        // Per-lib validity check: skip if library does not support this EID.
        bool supportsEid;
        try IMessageLib(_lib).isSupportedEid(_eid) returns (bool _supports) {
            supportsEid = _supports;
        } catch {
            return;
        }
        if (!supportsEid) return;

        UlnConfig memory desiredConfig;
        desiredConfig.confirmations = 0;
        desiredConfig.requiredDVNCount = 0;
        desiredConfig.optionalDVNCount = 0;
        desiredConfig.optionalDVNThreshold = 0;
        desiredConfig.requiredDVNs = new address[](0);
        desiredConfig.optionalDVNs = new address[](0);

        // Idempotency guard: do not emit tx if app ULN config is already default params.
        try IMessageLibManager(_connectedConfig.endpoint).getConfig(
            _connectedOft,
            _lib,
            _eid,
            Constant.CONFIG_TYPE_ULN
        ) returns (bytes memory rawCurrentConfig) {
            if (rawCurrentConfig.length > 0) {
                UlnConfig memory currentConfig = abi.decode(rawCurrentConfig, (UlnConfig));
                if (_ulnConfigEquals(currentConfig, desiredConfig)) {
                    return;
                }
            }
        } catch {
            // If we cannot introspect current config, keep going and attempt setConfig directly.
        }

        SetConfigParam[] memory setConfigParamArray = new SetConfigParam[](1);
        setConfigParamArray[0] = SetConfigParam({
            eid: _eid,
            configType: Constant.CONFIG_TYPE_ULN,
            config: abi.encode(desiredConfig)
        });

        bytes memory data = abi.encodeCall(
            IMessageLibManager.setConfig,
            (_connectedOft, _lib, setConfigParamArray)
        );
        _safeCall(_connectedConfig.endpoint, data, "setConfig(ULN->DEFAULT)");
        pushSerializedTx({
            _name: "setConfig",
            _to: _connectedConfig.endpoint,
            _value: 0,
            _data: data
        });
    }

    function _ulnConfigEquals(UlnConfig memory _a, UlnConfig memory _b) internal pure returns (bool) {
        if (_a.confirmations != _b.confirmations) return false;
        if (_a.requiredDVNCount != _b.requiredDVNCount) return false;
        if (_a.optionalDVNCount != _b.optionalDVNCount) return false;
        if (_a.optionalDVNThreshold != _b.optionalDVNThreshold) return false;
        if (_a.requiredDVNs.length != _b.requiredDVNs.length) return false;
        if (_a.optionalDVNs.length != _b.optionalDVNs.length) return false;

        for (uint256 i = 0; i < _a.requiredDVNs.length; i++) {
            if (_a.requiredDVNs[i] != _b.requiredDVNs[i]) return false;
        }
        for (uint256 i = 0; i < _a.optionalDVNs.length; i++) {
            if (_a.optionalDVNs[i] != _b.optionalDVNs[i]) return false;
        }

        return true;
    }

    /// @dev Encodes and queues a setPeer(eid, bytes32(0)) call directly by EID.
    function _zeroPeerByEid(address _oft, uint32 _eid) internal {
        bytes memory data = abi.encodeCall(IOAppCore.setPeer, (_eid, bytes32(0)));
        if (!_bypassChainCalls()) {
            _safeCall(_oft, data, "setPeer");
        }
        pushSerializedTx({
            _name: "setPeer",
            _to: _oft,
            _value: 0,
            _data: data
        });
    }

    function _bypassChainCalls() internal view returns (bool) {
        return vm.envOr("BYPASS_CHAIN_CALLS", false);
    }
}
