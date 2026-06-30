// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

abstract contract RateLimiterModule {
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

    struct RateLimitState {
        uint256 outboundUsage;
        uint256 inboundUsage;
        uint40 lastUpdated;
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
        0xbc2f4e0019400f86d65d92ee20d8164c6b63b661679e24c1985de9d3497f1b00;

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
        uint40 lastUpdated
    );
    event RateLimitCheckpointed(
        uint32 indexed eid,
        uint256 outboundUsage,
        uint256 inboundUsage,
        uint40 lastUpdated
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
    error RateLimitManagerOnly();
    error OwnerUnavailable();

    function _getRateLimiterStorage() private pure returns (RateLimiterStorage storage $) {
        assembly {
            $.slot := RateLimiterStorageLocation
        }
    }

    modifier onlyRateLimitManager() {
        if (msg.sender != _rateLimitOwner()) revert RateLimitManagerOnly();
        _;
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
        return _effectiveRateLimitConfig(_eid);
    }

    function storedRateLimitState(uint32 _eid) public view returns (RateLimitState memory state) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        return $.states[_eid];
    }

    function rateLimitState(uint32 _eid) public view returns (RateLimitState memory state) {
        RateLimitConfig memory config = _effectiveRateLimitConfig(_eid);
        return _currentRateLimitState(_eid, config);
    }

    function outboundRateLimitAvailable(uint32 _eid) public view returns (uint256 availableLD) {
        return _outboundRateLimitAvailable(_eid);
    }

    function inboundRateLimitAvailable(uint32 _eid) public view returns (uint256 availableLD) {
        return _inboundRateLimitAvailable(_eid);
    }

    function setRateLimitGlobalConfig(RateLimitGlobalConfig calldata _globalConfig) external onlyRateLimitManager {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        $.globalConfig = _globalConfig;
        emit RateLimitGlobalConfigSet(_globalConfig.isGloballyDisabled);
    }

    function setDefaultRateLimitConfig(RateLimitConfig calldata _defaultConfig) external onlyRateLimitManager {
        _validateRateLimitConfig(_defaultConfig);

        RateLimiterStorage storage $ = _getRateLimiterStorage();
        $.defaultConfig = _defaultConfig;

        emit DefaultRateLimitConfigSet(
            _defaultConfig.outboundEnabled,
            _defaultConfig.inboundEnabled,
            _defaultConfig.outboundLimit,
            _defaultConfig.inboundLimit,
            _defaultConfig.outboundWindow,
            _defaultConfig.inboundWindow
        );
    }

    function setRateLimitConfigs(SetRateLimitConfigParam[] calldata _params) external onlyRateLimitManager {
        RateLimiterStorage storage $ = _getRateLimiterStorage();

        uint256 length = _params.length;
        for (uint256 i; i < length; ++i) {
            _validateRateLimitConfig(_params[i].config);
            _checkpointRateLimit(_params[i].eid, _effectiveRateLimitConfig(_params[i].eid));

            $.configs[_params[i].eid] = _params[i].config;

            emit RateLimitConfigSet(
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

    function setRateLimitStates(SetRateLimitStateParam[] calldata _params) external onlyRateLimitManager {
        RateLimiterStorage storage $ = _getRateLimiterStorage();

        uint256 length = _params.length;
        for (uint256 i; i < length; ++i) {
            _validateRateLimitState(_params[i].state);
            $.states[_params[i].eid] = _params[i].state;

            emit RateLimitStateSet(
                _params[i].eid,
                _params[i].state.outboundUsage,
                _params[i].state.inboundUsage,
                _params[i].state.lastUpdated
            );
        }
    }

    function checkpointRateLimits(uint32[] calldata _eids) external onlyRateLimitManager {
        uint256 length = _eids.length;
        for (uint256 i; i < length; ++i) {
            _checkpointRateLimit(_eids[i], _effectiveRateLimitConfig(_eids[i]));
        }
    }

    function _consumeOutboundRateLimit(uint32 _dstEid, uint256 _amountLD) internal {
        _consumeRateLimit(_dstEid, _amountLD, true);
    }

    function _consumeInboundRateLimit(uint32 _srcEid, uint256 _amountLD) internal {
        _consumeRateLimit(_srcEid, _amountLD, false);
    }

    function _outboundRateLimitAvailable(uint32 _dstEid) internal view returns (uint256 availableLD) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        if ($.globalConfig.isGloballyDisabled) return type(uint256).max;

        RateLimitConfig memory config = _effectiveRateLimitConfig(_dstEid);
        if (!config.outboundEnabled) return type(uint256).max;

        RateLimitState memory state = _currentRateLimitState(_dstEid, config);
        if (state.outboundUsage >= config.outboundLimit) return 0;

        return config.outboundLimit - state.outboundUsage;
    }

    function _inboundRateLimitAvailable(uint32 _srcEid) internal view returns (uint256 availableLD) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        if ($.globalConfig.isGloballyDisabled) return type(uint256).max;

        RateLimitConfig memory config = _effectiveRateLimitConfig(_srcEid);
        if (!config.inboundEnabled) return type(uint256).max;

        RateLimitState memory state = _currentRateLimitState(_srcEid, config);
        if (state.inboundUsage >= config.inboundLimit) return 0;

        return config.inboundLimit - state.inboundUsage;
    }

    function _effectiveRateLimitConfig(uint32 _eid) internal view returns (RateLimitConfig memory config) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        config = $.configs[_eid];
        if (!config.overrideDefaultConfig) {
            config = $.defaultConfig;
        }
    }

    function _currentRateLimitState(
        uint32 _eid,
        RateLimitConfig memory _config
    ) internal view returns (RateLimitState memory state) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        state = $.states[_eid];

        uint40 currentTimestamp = uint40(block.timestamp);
        uint40 lastUpdated = state.lastUpdated;
        if (lastUpdated == 0 || lastUpdated >= currentTimestamp) {
            state.lastUpdated = currentTimestamp;
            return state;
        }

        uint256 elapsed = currentTimestamp - lastUpdated;
        state.outboundUsage = _decayUsage(state.outboundUsage, _config.outboundLimit, _config.outboundWindow, elapsed);
        state.inboundUsage = _decayUsage(state.inboundUsage, _config.inboundLimit, _config.inboundWindow, elapsed);
        state.lastUpdated = currentTimestamp;
    }

    function _checkpointRateLimit(uint32 _eid, RateLimitConfig memory _config) internal {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        RateLimitState memory currentState = _currentRateLimitState(_eid, _config);
        $.states[_eid] = currentState;

        emit RateLimitCheckpointed(
            _eid,
            currentState.outboundUsage,
            currentState.inboundUsage,
            currentState.lastUpdated
        );
    }

    function _consumeRateLimit(uint32 _eid, uint256 _amountLD, bool _isOutbound) internal {
        if (_amountLD == 0) return;

        RateLimiterStorage storage $ = _getRateLimiterStorage();
        if ($.globalConfig.isGloballyDisabled) return;

        RateLimitConfig memory config = _effectiveRateLimitConfig(_eid);
        if (_isOutbound && !config.outboundEnabled) return;
        if (!_isOutbound && !config.inboundEnabled) return;

        RateLimitState memory currentState = _currentRateLimitState(_eid, config);

        uint256 limit = _isOutbound ? config.outboundLimit : config.inboundLimit;
        uint256 usage = _isOutbound ? currentState.outboundUsage : currentState.inboundUsage;
        uint256 available = usage >= limit ? 0 : limit - usage;
        if (_amountLD > available) revert RateLimitExceeded(_eid, _isOutbound, _amountLD, available);

        if (_isOutbound) {
            currentState.outboundUsage = usage + _amountLD;
        } else {
            currentState.inboundUsage = usage + _amountLD;
        }

        $.states[_eid] = currentState;

        emit RateLimitConsumed(
            _eid,
            _isOutbound,
            _amountLD,
            _isOutbound ? currentState.outboundUsage : currentState.inboundUsage,
            limit
        );
    }

    function _validateRateLimitConfig(RateLimitConfig memory _config) internal pure {
        if (_config.outboundEnabled && (_config.outboundLimit == 0 || _config.outboundWindow == 0)) {
            revert InvalidRateLimitConfig();
        }
        if (_config.inboundEnabled && (_config.inboundLimit == 0 || _config.inboundWindow == 0)) {
            revert InvalidRateLimitConfig();
        }
    }

    function _validateRateLimitState(RateLimitState memory _state) internal view {
        if (_state.lastUpdated > block.timestamp) revert InvalidRateLimitState();
        if (_state.lastUpdated == 0 && (_state.outboundUsage != 0 || _state.inboundUsage != 0)) {
            revert InvalidRateLimitState();
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

        uint256 replenished = (_limit * _elapsed) / _window;
        return replenished >= _usage ? 0 : _usage - replenished;
    }

    function _rateLimitedMaxAmountLD(uint32 _dstEid) internal view returns (uint256 maxAmountLD) {
        return _min(_outboundRateLimitAvailable(_dstEid), uint256(type(uint64).max));
    }

    function _min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a < _b ? _a : _b;
    }

    function _rateLimitOwner() internal view returns (address ownerAddress) {
        (bool success, bytes memory data) = address(this).staticcall(abi.encodeWithSignature("owner()"));
        if (!success || data.length < 32) revert OwnerUnavailable();
        ownerAddress = abi.decode(data, (address));
    }
}
