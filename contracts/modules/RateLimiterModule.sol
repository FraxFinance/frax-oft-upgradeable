// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {RateLimiterLib} from "contracts/libraries/RateLimiterLib.sol";

/// @notice Rate limiting for OFT transfers.
abstract contract RateLimiterModule {
    struct RateLimitGlobalConfig {
        bool isGloballyDisabled;
    }

    /// @dev packed into 2 storage slots: (bools + windows + outboundLimit) | (inboundLimit)
    struct RateLimitConfig {
        bool overrideDefaultConfig;
        bool outboundEnabled;
        bool inboundEnabled;
        uint32 outboundWindow;
        uint32 inboundWindow;
        uint112 outboundLimit;
        uint112 inboundLimit;
    }

    /// @dev packed into a single storage slot; usage never exceeds the uint112 limit
    struct RateLimitState {
        uint112 outboundUsage;
        uint112 inboundUsage;
        uint32 lastUpdated;
    }

    struct SetRateLimitConfigParam {
        uint32 eid;
        RateLimitConfig config;
    }

    struct SetRateLimitStateParam {
        uint32 eid;
        RateLimitState state;
    }

    struct RateLimiterStorage {
        RateLimitGlobalConfig globalConfig;
        RateLimitConfig defaultConfig;
        mapping(uint32 eid => RateLimitConfig config) configs;
        mapping(uint32 eid => RateLimitState state) states;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.RateLimiterModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RateLimiterStorageLocation =
        0xf02f50e1c246a23e457c592e128a403f9c1cc60baa3a1ad2dc69bb4a5a51be00;

    event RateLimitGlobalConfigSet(bool isGloballyDisabled);
    event DefaultRateLimitConfigSet(
        bool outboundEnabled,
        bool inboundEnabled,
        uint256 outboundLimit,
        uint256 inboundLimit,
        uint32 outboundWindow,
        uint32 inboundWindow
    );
    event RateLimitConfigSet(
        uint32 indexed eid,
        bool overrideDefaultConfig,
        bool outboundEnabled,
        bool inboundEnabled,
        uint256 outboundLimit,
        uint256 inboundLimit,
        uint32 outboundWindow,
        uint32 inboundWindow
    );
    event RateLimitStateSet(
        uint32 indexed eid,
        uint256 outboundUsage,
        uint256 inboundUsage,
        uint32 lastUpdated
    );
    event RateLimitCheckpointed(
        uint32 indexed eid,
        uint256 outboundUsage,
        uint256 inboundUsage,
        uint32 lastUpdated
    );
    event RateLimitConsumed(
        uint32 indexed eid,
        bool indexed isOutbound,
        uint256 amountLD,
        uint256 usage,
        uint256 limit
    );

    error RateLimitExceeded(uint32 eid, bool isOutbound, uint256 amountLD, uint256 availableLD);
    error InvalidRateLimitConfig();
    error InvalidRateLimitState();

    function _getRateLimiterStorage() private pure returns (RateLimiterStorage storage $) {
        assembly {
            $.slot := RateLimiterStorageLocation
        }
    }

    function rateLimitGlobalConfig() public view returns (RateLimitGlobalConfig memory config) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        return $.globalConfig;
    }

    function defaultRateLimitConfig() public view returns (RateLimitConfig memory config) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        return $.defaultConfig;
    }

    function storedRateLimitConfig(uint32 _eid) public view returns (RateLimitConfig memory config) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        return $.configs[_eid];
    }

    function rateLimitConfig(uint32 _eid) public view returns (RateLimitConfig memory config) {
        return RateLimiterLib.effectiveRateLimitConfig(_eid);
    }

    function storedRateLimitState(uint32 _eid) public view returns (RateLimitState memory state) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        return $.states[_eid];
    }

    function rateLimitState(uint32 _eid) public view returns (RateLimitState memory state) {
        return RateLimiterLib.currentRateLimitState(_eid);
    }

    function outboundRateLimitAvailable(uint32 _eid) public view returns (uint256 availableLD) {
        return RateLimiterLib.outboundRateLimitAvailable(_eid);
    }

    function inboundRateLimitAvailable(uint32 _eid) public view returns (uint256 availableLD) {
        return RateLimiterLib.inboundRateLimitAvailable(_eid);
    }

    function _setRateLimitGlobalConfig(RateLimitGlobalConfig calldata _globalConfig) internal {
        RateLimiterLib.setRateLimitGlobalConfig(_globalConfig);
    }

    function _setDefaultRateLimitConfig(RateLimitConfig calldata _defaultConfig) internal {
        RateLimiterLib.setDefaultRateLimitConfig(_defaultConfig);
    }

    function _setRateLimitConfigs(SetRateLimitConfigParam[] calldata _params) internal {
        RateLimiterLib.setRateLimitConfigs(_params);
    }

    function _setRateLimitStates(SetRateLimitStateParam[] calldata _params) internal {
        RateLimiterLib.setRateLimitStates(_params);
    }

    function _checkpointRateLimits(uint32[] calldata _eids) internal {
        RateLimiterLib.checkpointRateLimits(_eids);
    }

    function _consumeOutboundRateLimit(uint32 _dstEid, uint256 _amountLD) internal {
        RateLimiterLib.consumeRateLimit(_dstEid, _amountLD, true);
    }

    function _consumeInboundRateLimit(uint32 _srcEid, uint256 _amountLD) internal {
        RateLimiterLib.consumeRateLimit(_srcEid, _amountLD, false);
    }

    function _outboundRateLimitAvailable(uint32 _dstEid) internal view returns (uint256 availableLD) {
        return RateLimiterLib.outboundRateLimitAvailable(_dstEid);
    }

    function _inboundRateLimitAvailable(uint32 _srcEid) internal view returns (uint256 availableLD) {
        return RateLimiterLib.inboundRateLimitAvailable(_srcEid);
    }

    function _rateLimitedMaxAmountLD(uint32 _dstEid) internal view returns (uint256 maxAmountLD) {
        return _min(RateLimiterLib.outboundRateLimitAvailable(_dstEid), uint256(type(uint64).max)*1E12);
    }

    function _min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a < _b ? _a : _b;
    }
}
