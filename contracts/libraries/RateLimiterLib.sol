// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {RateLimiterModule} from "contracts/modules/RateLimiterModule.sol";

/// @notice Rate limit accounting for OFT transfers.
/// @dev Linked library. Runs via delegatecall against RateLimiterModule's namespaced storage
///      and emits its events, so callers observe the module's own logs and revert data.
library RateLimiterLib {
    /// @dev Must equal RateLimiterModule.RateLimiterStorageLocation.
    ///      keccak256(abi.encode(uint256(keccak256("frax.storage.RateLimiterModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RateLimiterStorageLocation =
        0xf02f50e1c246a23e457c592e128a403f9c1cc60baa3a1ad2dc69bb4a5a51be00;

    function _getRateLimiterStorage() private pure returns (RateLimiterModule.RateLimiterStorage storage $) {
        assembly {
            $.slot := RateLimiterStorageLocation
        }
    }

    function setRateLimitGlobalConfig(RateLimiterModule.RateLimitGlobalConfig calldata _globalConfig) external {
        RateLimiterModule.RateLimiterStorage storage $ = _getRateLimiterStorage();
        $.globalConfig = _globalConfig;
        emit RateLimiterModule.RateLimitGlobalConfigSet(_globalConfig.isGloballyDisabled);
    }

    function setDefaultRateLimitConfig(RateLimiterModule.RateLimitConfig calldata _defaultConfig) external {
        _validateRateLimitConfig(_defaultConfig);

        RateLimiterModule.RateLimiterStorage storage $ = _getRateLimiterStorage();
        $.defaultConfig = _defaultConfig;

        emit RateLimiterModule.DefaultRateLimitConfigSet(
            _defaultConfig.outboundEnabled,
            _defaultConfig.inboundEnabled,
            _defaultConfig.outboundLimit,
            _defaultConfig.inboundLimit,
            _defaultConfig.outboundWindow,
            _defaultConfig.inboundWindow
        );
    }

    function setRateLimitConfigs(RateLimiterModule.SetRateLimitConfigParam[] calldata _params) external {
        RateLimiterModule.RateLimiterStorage storage $ = _getRateLimiterStorage();

        uint256 length = _params.length;
        for (uint256 i; i < length; ++i) {
            _validateRateLimitConfig(_params[i].config);
            _checkpointRateLimit(_params[i].eid, _effectiveRateLimitConfig(_params[i].eid));

            $.configs[_params[i].eid] = _params[i].config;

            emit RateLimiterModule.RateLimitConfigSet(
                _params[i].eid,
                _params[i].config.overrideDefaultConfig,
                _params[i].config.outboundEnabled,
                _params[i].config.inboundEnabled,
                _params[i].config.outboundLimit,
                _params[i].config.inboundLimit,
                _params[i].config.outboundWindow,
                _params[i].config.inboundWindow
            );
        }
    }

    function setRateLimitStates(RateLimiterModule.SetRateLimitStateParam[] calldata _params) external {
        RateLimiterModule.RateLimiterStorage storage $ = _getRateLimiterStorage();

        uint256 length = _params.length;
        for (uint256 i; i < length; ++i) {
            _validateRateLimitState(_params[i].state);
            $.states[_params[i].eid] = _params[i].state;

            emit RateLimiterModule.RateLimitStateSet(
                _params[i].eid,
                _params[i].state.outboundUsage,
                _params[i].state.inboundUsage,
                _params[i].state.lastUpdated
            );
        }
    }

    function checkpointRateLimits(uint32[] calldata _eids) external {
        uint256 length = _eids.length;
        for (uint256 i; i < length; ++i) {
            _checkpointRateLimit(_eids[i], _effectiveRateLimitConfig(_eids[i]));
        }
    }

    function consumeRateLimit(uint32 _eid, uint256 _amountLD, bool _isOutbound) external {
        if (_amountLD == 0) return;

        RateLimiterModule.RateLimiterStorage storage $ = _getRateLimiterStorage();
        if ($.globalConfig.isGloballyDisabled) return;

        RateLimiterModule.RateLimitConfig memory config = _effectiveRateLimitConfig(_eid);
        if (_isOutbound && !config.outboundEnabled) return;
        if (!_isOutbound && !config.inboundEnabled) return;

        RateLimiterModule.RateLimitState memory currentState = _currentRateLimitState(_eid, config);

        uint256 limit = _isOutbound ? config.outboundLimit : config.inboundLimit;
        uint256 usage = _isOutbound ? currentState.outboundUsage : currentState.inboundUsage;
        uint256 available = usage >= limit ? 0 : limit - usage;
        if (_amountLD > available) {
            revert RateLimiterModule.RateLimitExceeded(_eid, _isOutbound, _amountLD, available);
        }

        // safe downcasts: usage + _amountLD <= limit <= type(uint112).max (checked above)
        if (_isOutbound) {
            currentState.outboundUsage = uint112(usage + _amountLD);
        } else {
            currentState.inboundUsage = uint112(usage + _amountLD);
        }

        $.states[_eid] = currentState;

        emit RateLimiterModule.RateLimitConsumed(
            _eid,
            _isOutbound,
            _amountLD,
            _isOutbound ? currentState.outboundUsage : currentState.inboundUsage,
            limit
        );
    }

    function effectiveRateLimitConfig(
        uint32 _eid
    ) external view returns (RateLimiterModule.RateLimitConfig memory config) {
        return _effectiveRateLimitConfig(_eid);
    }

    function currentRateLimitState(uint32 _eid) external view returns (RateLimiterModule.RateLimitState memory state) {
        return _currentRateLimitState(_eid, _effectiveRateLimitConfig(_eid));
    }

    function outboundRateLimitAvailable(uint32 _dstEid) external view returns (uint256 availableLD) {
        RateLimiterModule.RateLimiterStorage storage $ = _getRateLimiterStorage();
        if ($.globalConfig.isGloballyDisabled) return type(uint256).max;

        RateLimiterModule.RateLimitConfig memory config = _effectiveRateLimitConfig(_dstEid);
        if (!config.outboundEnabled) return type(uint256).max;

        RateLimiterModule.RateLimitState memory state = _currentRateLimitState(_dstEid, config);
        if (state.outboundUsage >= config.outboundLimit) return 0;

        return config.outboundLimit - state.outboundUsage;
    }

    function inboundRateLimitAvailable(uint32 _srcEid) external view returns (uint256 availableLD) {
        RateLimiterModule.RateLimiterStorage storage $ = _getRateLimiterStorage();
        if ($.globalConfig.isGloballyDisabled) return type(uint256).max;

        RateLimiterModule.RateLimitConfig memory config = _effectiveRateLimitConfig(_srcEid);
        if (!config.inboundEnabled) return type(uint256).max;

        RateLimiterModule.RateLimitState memory state = _currentRateLimitState(_srcEid, config);
        if (state.inboundUsage >= config.inboundLimit) return 0;

        return config.inboundLimit - state.inboundUsage;
    }

    function _effectiveRateLimitConfig(
        uint32 _eid
    ) internal view returns (RateLimiterModule.RateLimitConfig memory config) {
        RateLimiterModule.RateLimiterStorage storage $ = _getRateLimiterStorage();
        RateLimiterModule.RateLimitConfig storage stored = $.configs[_eid];
        // peek the flag before copying so the common (default) case skips the per-eid struct copy
        config = stored.overrideDefaultConfig ? stored : $.defaultConfig;
    }

    function _currentRateLimitState(
        uint32 _eid,
        RateLimiterModule.RateLimitConfig memory _config
    ) internal view returns (RateLimiterModule.RateLimitState memory state) {
        RateLimiterModule.RateLimiterStorage storage $ = _getRateLimiterStorage();
        state = $.states[_eid];

        uint32 currentTimestamp = uint32(block.timestamp);
        uint32 lastUpdated = state.lastUpdated;
        if (lastUpdated == 0 || lastUpdated >= currentTimestamp) {
            state.lastUpdated = currentTimestamp;
            return state;
        }

        uint256 elapsed = currentTimestamp - lastUpdated;
        // safe downcasts: decayed usage never exceeds the stored uint112 usage
        state.outboundUsage =
            uint112(_decayUsage(state.outboundUsage, _config.outboundLimit, _config.outboundWindow, elapsed));
        state.inboundUsage =
            uint112(_decayUsage(state.inboundUsage, _config.inboundLimit, _config.inboundWindow, elapsed));
        state.lastUpdated = currentTimestamp;
    }

    function _checkpointRateLimit(uint32 _eid, RateLimiterModule.RateLimitConfig memory _config) internal {
        RateLimiterModule.RateLimiterStorage storage $ = _getRateLimiterStorage();
        RateLimiterModule.RateLimitState memory currentState = _currentRateLimitState(_eid, _config);
        $.states[_eid] = currentState;

        emit RateLimiterModule.RateLimitCheckpointed(
            _eid,
            currentState.outboundUsage,
            currentState.inboundUsage,
            currentState.lastUpdated
        );
    }

    function _validateRateLimitConfig(RateLimiterModule.RateLimitConfig memory _config) internal pure {
        if (_config.outboundEnabled && (_config.outboundLimit == 0 || _config.outboundWindow == 0)) {
            revert RateLimiterModule.InvalidRateLimitConfig();
        }
        if (_config.inboundEnabled && (_config.inboundLimit == 0 || _config.inboundWindow == 0)) {
            revert RateLimiterModule.InvalidRateLimitConfig();
        }
    }

    function _validateRateLimitState(RateLimiterModule.RateLimitState memory _state) internal view {
        if (_state.lastUpdated > block.timestamp) revert RateLimiterModule.InvalidRateLimitState();
        if (_state.lastUpdated == 0 && (_state.outboundUsage != 0 || _state.inboundUsage != 0)) {
            revert RateLimiterModule.InvalidRateLimitState();
        }
    }

    function _decayUsage(
        uint256 _usage,
        uint256 _limit,
        uint32 _window,
        uint256 _elapsed
    ) internal pure returns (uint256 decayedUsage) {
        if (_usage == 0 || _limit == 0 || _window == 0 || _elapsed == 0) {
            return _usage;
        }
        if (_elapsed >= _window) {
            return 0;
        }

        // cannot overflow: _limit <= type(uint112).max and _elapsed < _window <= type(uint32).max
        uint256 replenished = (_limit * _elapsed) / _window;
        return replenished >= _usage ? 0 : _usage - replenished;
    }
}
