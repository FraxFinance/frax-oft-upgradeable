// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./FixLegacyDVNsInherited.s.sol";
import {IOAppCore} from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppCore.sol";
import {SetConfigParam, IMessageLibManager} from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";
import {Constant} from "@fraxfinance/layerzero-v2-upgradeable/messagelib/test/util/Constant.sol";
import {UlnConfig} from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/uln/UlnBase.sol";
import {Arrays} from "@openzeppelin-5/contracts/utils/Arrays.sol";

error LZ_SameValue();

/// @title Step 2+3: Set DVN config and restore send lib for legacy OFTs
/// @notice For Ethereum, Blast, Base: sets 3/3 DVN config (Frax + Horizen + L0) on both
///         send and receive ULN libraries, then restores the send library to the proper sendLib302.
///         For Metis: keeps existing 2/2 DVN config (no Frax DVN available), only restores send lib.
/// @dev This script should be executed AFTER Step 1 (block send lib) has been confirmed on-chain.
///      Steps 2 and 3 are batched together so they execute atomically in a single Safe TX batch.
contract FixDVNsAndRestoreSendLibLegacy is FixLegacyDVNsInherited {
    using stdJson for string;
    using Strings for uint256;

    struct LegacyDvnStack {
        address frax;
        address horizen;
        address lz;
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/fix/FixLegacyDVNs/txs/");
        string memory name = string.concat((block.timestamp).toString(), "-2_FixDVNsAndRestoreSendLibLegacy-");
        name = string.concat(name, currentOftName, "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function run() public override {
        for (uint256 o = 0; o < legacyOftAddresses.length; o++) {
            currentOftName = legacyOftNames[o];
            for (uint256 i = 0; i < legacyConfigs.length; i++) {
                for (uint256 j = 0; j < legacyChainIds.length; j++) {
                    if (legacyConfigs[i].chainid == legacyChainIds[j]) {
                        fixDVNsAndRestoreSendLibForOft(legacyConfigs[i], legacyOftAddresses[o]);
                    }
                }
            }
        }
    }

    function fixDVNsAndRestoreSendLibForOft(L0Config memory _config, address _oft) public simulateAndWriteTxs(_config) {
        for (uint256 d = 0; d < legacyChainIds.length; d++) {
            // Skip self
            if (legacyChainIds[d] == _config.chainid) continue;

            L0Config memory dstConfig = findLegacyConfig(legacyChainIds[d]);

            // Only set DVN config if BOTH source and destination have Frax DVN
            bool bothHaveFraxDvn = hasFraxDvn(_config.chainid) && hasFraxDvn(legacyChainIds[d]);

            // Skip if peer is not set
            if (!hasPeer(_oft, uint32(dstConfig.eid))) continue;

            // --- Step 2: Set DVN config (only for pathways where both sides have Frax DVN) ---
            if (bothHaveFraxDvn) {
                _setDVNConfig(_oft, _config, dstConfig);
            }

            // --- Step 3: Restore send library ---
            _restoreSendLib(_oft, _config, dstConfig);
        }
    }

    /// @notice Set 3/3 DVN config (Frax + Horizen + L0) on both sendLib and receiveLib
    function _setDVNConfig(
        address _oft,
        L0Config memory _srcConfig,
        L0Config memory _dstConfig
    ) internal {
        // Build the desired DVN array from the dvn config files
        address[] memory desiredDVNs = _craftLegacyDvnStack(_srcConfig.chainid, _dstConfig.chainid);

        // Set config on send library
        _setUlnConfig(_oft, _srcConfig, _dstConfig, _srcConfig.sendLib302, desiredDVNs);

        // Set config on receive library
        _setUlnConfig(_oft, _srcConfig, _dstConfig, _srcConfig.receiveLib302, desiredDVNs);
    }

    function _setUlnConfig(
        address _oft,
        L0Config memory _srcConfig,
        L0Config memory _dstConfig,
        address _lib,
        address[] memory _desiredDVNs
    ) internal {
        UlnConfig memory desiredUlnConfig;
        desiredUlnConfig.requiredDVNCount = uint8(_desiredDVNs.length);
        desiredUlnConfig.requiredDVNs = _desiredDVNs;

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({
            eid: uint32(_dstConfig.eid),
            configType: Constant.CONFIG_TYPE_ULN,
            config: abi.encode(desiredUlnConfig)
        });

        bytes memory data = abi.encodeCall(
            IMessageLibManager.setConfig,
            (_oft, _lib, params)
        );
        (bool success,) = _srcConfig.endpoint.call(data);
        require(success, "Failed to setConfig DVNs");

        serializedTxs.push(
            SerializedTx({
                name: "setConfig",
                to: _srcConfig.endpoint,
                value: 0,
                data: data
            })
        );
    }

    /// @notice Restore send library from blocked to sendLib302
    function _restoreSendLib(
        address _oft,
        L0Config memory _srcConfig,
        L0Config memory _dstConfig
    ) internal {
        bytes memory data = abi.encodeCall(
            IMessageLibManager.setSendLibrary,
            (_oft, uint32(_dstConfig.eid), _srcConfig.sendLib302)
        );
        (bool success, bytes memory returnData) = _srcConfig.endpoint.call(data);

        if (!success) {
            if (returnData.length >= 4) {
                bytes4 errorSelector;
                assembly {
                    errorSelector := mload(add(returnData, 32))
                }

                if (errorSelector != LZ_SameValue.selector) {
                    revert("Failed to restore send library");
                }
            }
        }

        serializedTxs.push(
            SerializedTx({
                name: "SetSendLib",
                to: _srcConfig.endpoint,
                value: 0,
                data: data
            })
        );
    }

    /// @notice Build the sorted 3-DVN array (Frax + Horizen + L0) from dvn config files.
    ///         Reads config/dvn/{srcChainId}.json -> key {dstChainId}.
    function _craftLegacyDvnStack(
        uint256 _srcChainId,
        uint256 _dstChainId
    ) internal returns (address[] memory desiredDVNs) {
        // Load DVN stack from config file (uses the existing SetDVNs.getDvnStack pattern)
        DvnStack memory srcStack = getDvnStack(_srcChainId, _dstChainId);

        // For legacy upgrade we expect exactly: frax + horizen + lz
        require(srcStack.frax != address(0), "Frax DVN missing in src config");
        require(srcStack.horizen != address(0), "Horizen DVN missing in src config");
        require(srcStack.lz != address(0), "L0 DVN missing in src config");

        desiredDVNs = new address[](3);
        desiredDVNs[0] = srcStack.frax;
        desiredDVNs[1] = srcStack.horizen;
        desiredDVNs[2] = srcStack.lz;

        // Sort ascending (required by LayerZero ULN)
        desiredDVNs = Arrays.sort(desiredDVNs);
    }
}
