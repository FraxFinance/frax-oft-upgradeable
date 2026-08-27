// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

interface IEndpointDelegates {
    function blockedLibrary() external view returns (address);
    function delegates(address _oapp) external view returns (address);
}

/// @notice Generate Safe batch JSON for setting explicit send/receive libraries on legacy OFTs.
///
/// Optional env filters:
/// - SOURCE_CHAIN_ID: only generate for this legacy source chain. Default: all legacy chains.
/// - SOURCE_RPC_URL: override the source chain RPC when SOURCE_CHAIN_ID selects one chain.
/// - DST_CHAIN_ID: only wire this destination chain. Default: all legacy destinations.
/// - LEGACY_OFTS: comma-separated OFT addresses. Default: all ethLockboxesLegacy entries.
/// - LEGACY_OFT_MASK: bitmask over ethLockboxesLegacy when LEGACY_OFTS is unset. Default: 0x3f.
/// - INCLUDE_SEND_LIB / INCLUDE_RECEIVE_LIB: include each call type. Defaults: both true.
/// - REQUIRE_PEER: only set libs for already-peered routes. Default: true.
contract SetLegacyOFTLibs is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    uint256 internal constant ALL_CHAINS = 0;
    uint256 internal constant ALL_LEGACY_OFTS_MASK = 0x3f;

    uint256 public sourceChainId;
    uint256 public dstChainId;
    bool public includeSendLib;
    bool public includeReceiveLib;
    bool public requirePeer;
    address public outputOft;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/fix/SetLegacyOFTLibs/txs/");

        string memory name = string.concat(block.timestamp.toString(), "-SetLegacyOFTLibs-");
        name = string.concat(name, simulateConfig.chainid.toString());
        if (dstChainId != ALL_CHAINS) {
            name = string.concat(name, "-to-");
            name = string.concat(name, dstChainId.toString());
        }

        address oftForFilename = outputOft;
        if (oftForFilename == address(0) && legacyOfts.length == 1) {
            oftForFilename = legacyOfts[0];
        }
        if (oftForFilename != address(0)) {
            name = string.concat(name, "-");
            name = string.concat(name, _legacyOftLabel(oftForFilename));
        }

        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function run() public override {
        _loadEnv();
        _loadLegacyOfts();

        require(includeSendLib || includeReceiveLib, "No library call type selected");
        require(legacyOfts.length > 0, "No legacy OFTs selected");

        for (uint256 i = 0; i < legacyConfigs.length; i++) {
            if (sourceChainId != ALL_CHAINS && legacyConfigs[i].chainid != sourceChainId) continue;
            L0Config memory srcConfig = legacyConfigs[i];
            if (sourceChainId != ALL_CHAINS) {
                srcConfig.RPC = vm.envOr("SOURCE_RPC_URL", srcConfig.RPC);
            }

            for (uint256 o = 0; o < legacyOfts.length; o++) {
                setLegacyOFTLibsForOft(srcConfig, legacyOfts[o]);
            }
        }
    }

    function setLegacyOFTLibs(L0Config memory _srcConfig) public simulateAndWriteTxs(_srcConfig) {
        outputOft = address(0);
        for (uint256 o = 0; o < legacyOfts.length; o++) {
            _setLegacyOFTLibsForOft(_srcConfig, legacyOfts[o]);
        }
    }

    function setLegacyOFTLibsForOft(L0Config memory _srcConfig, address _oft) public simulateAndWriteTxs(_srcConfig) {
        outputOft = _oft;
        _setLegacyOFTLibsForOft(_srcConfig, _oft);
    }

    function _loadEnv() internal {
        sourceChainId = vm.envOr("SOURCE_CHAIN_ID", uint256(ALL_CHAINS));
        dstChainId = vm.envOr("DST_CHAIN_ID", uint256(ALL_CHAINS));
        includeSendLib = vm.envOr("INCLUDE_SEND_LIB", true);
        includeReceiveLib = vm.envOr("INCLUDE_RECEIVE_LIB", true);
        requirePeer = vm.envOr("REQUIRE_PEER", true);
    }

    function _loadLegacyOfts() internal {
        delete legacyOfts;

        address[] memory emptyOfts;
        address[] memory envOfts = vm.envOr("LEGACY_OFTS", ",", emptyOfts);
        if (envOfts.length > 0) {
            for (uint256 i = 0; i < envOfts.length; i++) {
                legacyOfts.push(envOfts[i]);
            }
            return;
        }

        uint256 mask = vm.envOr("LEGACY_OFT_MASK", uint256(ALL_LEGACY_OFTS_MASK));
        for (uint256 i = 0; i < ethLockboxesLegacy.length; i++) {
            if ((mask & (uint256(1) << i)) != 0) {
                legacyOfts.push(ethLockboxesLegacy[i]);
            }
        }
    }

    function _setLegacyOFTLibsForOft(L0Config memory _srcConfig, address _oft) internal {
        if (_oft.code.length == 0) return;
        if (!_isDelegate(_srcConfig, _oft)) return;

        for (uint256 d = 0; d < legacyConfigs.length; d++) {
            L0Config memory dstConfig = legacyConfigs[d];
            if (dstConfig.eid == _srcConfig.eid) continue;
            if (dstChainId != ALL_CHAINS && dstConfig.chainid != dstChainId) continue;
            if (requirePeer && !_hasPeer(_oft, dstConfig)) continue;

            if (includeSendLib) {
                _setSendLibIfNeeded(_srcConfig, _oft, dstConfig);
            }

            if (includeReceiveLib) {
                _setReceiveLibIfNeeded(_srcConfig, _oft, dstConfig);
            }
        }
    }

    function _setSendLibIfNeeded(L0Config memory _srcConfig, address _oft, L0Config memory _dstConfig) internal {
        address currentLib =
            IMessageLibManager(_srcConfig.endpoint).getSendLibrary({_sender: _oft, _eid: uint32(_dstConfig.eid)});
        bool isDefault =
            IMessageLibManager(_srcConfig.endpoint).isDefaultSendLibrary({_sender: _oft, _eid: uint32(_dstConfig.eid)});

        if (currentLib == IEndpointDelegates(_srcConfig.endpoint).blockedLibrary()) return;
        if (currentLib == _srcConfig.sendLib302 && !isDefault) return;

        bytes memory data =
            abi.encodeCall(IMessageLibManager.setSendLibrary, (_oft, uint32(_dstConfig.eid), _srcConfig.sendLib302));

        _safeCall(_srcConfig.endpoint, data, "setSendLibrary");
        serializedTxs.push(SerializedTx({name: "setSendLibrary", to: _srcConfig.endpoint, value: 0, data: data}));
    }

    function _setReceiveLibIfNeeded(L0Config memory _srcConfig, address _oft, L0Config memory _dstConfig) internal {
        (address currentLib, bool isDefault) =
            IMessageLibManager(_srcConfig.endpoint).getReceiveLibrary({_receiver: _oft, _eid: uint32(_dstConfig.eid)});

        if (currentLib == _srcConfig.receiveLib302 && !isDefault) return;

        bytes memory data = abi.encodeCall(
            IMessageLibManager.setReceiveLibrary, (_oft, uint32(_dstConfig.eid), _srcConfig.receiveLib302, 0)
        );

        _safeCall(_srcConfig.endpoint, data, "setReceiveLibrary");
        serializedTxs.push(SerializedTx({name: "setReceiveLibrary", to: _srcConfig.endpoint, value: 0, data: data}));
    }

    function _isDelegate(L0Config memory _srcConfig, address _oft) internal view returns (bool) {
        return IEndpointDelegates(_srcConfig.endpoint).delegates(_oft) == _srcConfig.delegate;
    }

    function _hasPeer(address _oft, L0Config memory _dstConfig) internal view returns (bool) {
        (bool success, bytes memory result) = _oft.staticcall(abi.encodeCall(IOAppCore.peers, (uint32(_dstConfig.eid))));
        if (!success || result.length < 32) return false;

        return abi.decode(result, (bytes32)) != bytes32(0);
    }

    function _legacyOftLabel(address _oft) internal view returns (string memory) {
        if (_oft == ethFraxLockboxLegacy) return "FRAX(FXS)";
        if (_oft == ethSFraxLockboxLegacy) return "sFRAX";
        if (_oft == ethSFrxEthLockboxLegacy) return "sfrxETH";
        if (_oft == ethFrxUsdLockboxLegacy) return "LFRAX";
        if (_oft == ethFrxEthLockboxLegacy) return "frxETH";
        if (_oft == ethFpiLockboxLegacy) return "FPI";

        return Strings.toHexString(uint256(uint160(_oft)), 20);
    }
}
