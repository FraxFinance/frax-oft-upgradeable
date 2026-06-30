// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { L0Config } from "scripts/L0Constants.sol";
import { BaseInherited } from "./BaseInherited.sol";
import { Script } from "forge-std/Script.sol";

interface IRateLimitedOFT {
    struct RateLimitGlobalConfig {
        bool isGloballyDisabled;
    }

    struct RateLimitConfig {
        bool overrideDefaultConfig;
        bool outboundEnabled;
        bool inboundEnabled;
        uint256 outboundLimit;
        uint256 inboundLimit;
        uint32 outboundWindow;
        uint32 inboundWindow;
    }

    struct SetRateLimitConfigParam {
        uint32 eid;
        RateLimitConfig config;
    }

    function rateLimitGlobalConfig() external view returns (RateLimitGlobalConfig memory config);
    function defaultRateLimitConfig() external view returns (RateLimitConfig memory config);
    function storedRateLimitConfig(uint32 _eid) external view returns (RateLimitConfig memory config);
    function setRateLimitGlobalConfig(RateLimitGlobalConfig calldata _globalConfig) external;
    function setDefaultRateLimitConfig(RateLimitConfig calldata _defaultConfig) external;
    function setRateLimitConfigs(SetRateLimitConfigParam[] calldata _params) external;
}

contract SetRateLimits is BaseInherited, Script {
    /// @notice Apply any desired rate-limit config for every OFT in `_connectedOfts`.
    /// @dev Override the desired* hook methods in a downstream deployment script to opt in.
    function setRateLimits(
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public virtual {
        for (uint256 o; o < _connectedOfts.length; ++o) {
            _setRateLimitGlobalConfig(_connectedOfts[o]);
            _setDefaultRateLimitConfig(_connectedOfts[o]);
            _setRateLimitConfigs(_connectedOfts[o], _configs);
        }
    }

    function desiredRateLimitGlobalConfig(
        address /* _connectedOft */
    ) public view virtual returns (bool shouldSet, IRateLimitedOFT.RateLimitGlobalConfig memory config) {}

    function desiredDefaultRateLimitConfig(
        address /* _connectedOft */
    ) public view virtual returns (bool shouldSet, IRateLimitedOFT.RateLimitConfig memory config) {}

    function desiredRateLimitConfig(
        address /* _connectedOft */,
        uint32 /* _eid */
    ) public view virtual returns (bool shouldSet, IRateLimitedOFT.RateLimitConfig memory config) {}

    function _setRateLimitGlobalConfig(address _connectedOft) internal virtual {
        (bool shouldSet, IRateLimitedOFT.RateLimitGlobalConfig memory desiredConfig) =
            desiredRateLimitGlobalConfig(_connectedOft);
        if (!shouldSet) return;

        IRateLimitedOFT.RateLimitGlobalConfig memory currentConfig =
            IRateLimitedOFT(_connectedOft).rateLimitGlobalConfig();
        if (_rateLimitGlobalConfigsEqual(currentConfig, desiredConfig)) return;

        bytes memory data = abi.encodeCall(IRateLimitedOFT.setRateLimitGlobalConfig, (desiredConfig));
        _rateLimitSafeCall(_connectedOft, data, "setRateLimitGlobalConfig");
        pushSerializedTx({
            _name: "setRateLimitGlobalConfig",
            _to: _connectedOft,
            _value: 0,
            _data: data
        });
    }

    function _setDefaultRateLimitConfig(address _connectedOft) internal virtual {
        (bool shouldSet, IRateLimitedOFT.RateLimitConfig memory desiredConfig) =
            desiredDefaultRateLimitConfig(_connectedOft);
        if (!shouldSet) return;

        IRateLimitedOFT.RateLimitConfig memory currentConfig =
            IRateLimitedOFT(_connectedOft).defaultRateLimitConfig();
        if (_rateLimitConfigsEqual(currentConfig, desiredConfig)) return;

        bytes memory data = abi.encodeCall(IRateLimitedOFT.setDefaultRateLimitConfig, (desiredConfig));
        _rateLimitSafeCall(_connectedOft, data, "setDefaultRateLimitConfig");
        pushSerializedTx({
            _name: "setDefaultRateLimitConfig",
            _to: _connectedOft,
            _value: 0,
            _data: data
        });
    }

    function _setRateLimitConfigs(address _connectedOft, L0Config[] memory _configs) internal virtual {
        uint256 numConfigsToSet;

        for (uint256 c; c < _configs.length; ++c) {
            if (_configs[c].chainid == block.chainid) continue;

            (bool shouldSet, IRateLimitedOFT.RateLimitConfig memory desiredConfig) =
                desiredRateLimitConfig(_connectedOft, uint32(_configs[c].eid));
            if (!shouldSet) continue;

            IRateLimitedOFT.RateLimitConfig memory currentConfig =
                IRateLimitedOFT(_connectedOft).storedRateLimitConfig(uint32(_configs[c].eid));
            if (_rateLimitConfigsEqual(currentConfig, desiredConfig)) continue;

            ++numConfigsToSet;
        }

        if (numConfigsToSet == 0) return;

        IRateLimitedOFT.SetRateLimitConfigParam[] memory params =
            new IRateLimitedOFT.SetRateLimitConfigParam[](numConfigsToSet);
        uint256 writeIndex;

        for (uint256 c; c < _configs.length; ++c) {
            if (_configs[c].chainid == block.chainid) continue;

            uint32 eid = uint32(_configs[c].eid);
            (bool shouldSet, IRateLimitedOFT.RateLimitConfig memory desiredConfig) =
                desiredRateLimitConfig(_connectedOft, eid);
            if (!shouldSet) continue;

            IRateLimitedOFT.RateLimitConfig memory currentConfig = IRateLimitedOFT(_connectedOft).storedRateLimitConfig(eid);
            if (_rateLimitConfigsEqual(currentConfig, desiredConfig)) continue;

            params[writeIndex] = IRateLimitedOFT.SetRateLimitConfigParam({
                eid: eid,
                config: desiredConfig
            });
            ++writeIndex;
        }

        bytes memory data = abi.encodeCall(IRateLimitedOFT.setRateLimitConfigs, (params));
        _rateLimitSafeCall(_connectedOft, data, "setRateLimitConfigs");
        pushSerializedTx({
            _name: "setRateLimitConfigs",
            _to: _connectedOft,
            _value: 0,
            _data: data
        });
    }

    function _rateLimitGlobalConfigsEqual(
        IRateLimitedOFT.RateLimitGlobalConfig memory _a,
        IRateLimitedOFT.RateLimitGlobalConfig memory _b
    ) internal pure returns (bool) {
        return _a.isGloballyDisabled == _b.isGloballyDisabled;
    }

    function _rateLimitConfigsEqual(
        IRateLimitedOFT.RateLimitConfig memory _a,
        IRateLimitedOFT.RateLimitConfig memory _b
    ) internal pure returns (bool) {
        return _a.overrideDefaultConfig == _b.overrideDefaultConfig
            && _a.outboundEnabled == _b.outboundEnabled
            && _a.inboundEnabled == _b.inboundEnabled
            && _a.outboundLimit == _b.outboundLimit
            && _a.inboundLimit == _b.inboundLimit
            && _a.outboundWindow == _b.outboundWindow
            && _a.inboundWindow == _b.inboundWindow;
    }

    function _rateLimitSafeCall(
        address _target,
        bytes memory _data,
        string memory _errorContext
    ) internal {
        (bool success, bytes memory returnData) = _target.call(_data);
        if (!success) {
            if (returnData.length > 0) {
                /// @solidity memory-safe-assembly
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            }

            revert(string.concat(_errorContext, ": call reverted without reason"));
        }
    }
}
