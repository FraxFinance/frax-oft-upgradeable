// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TempoAltTokenBase} from "contracts/base/TempoAltTokenBase.sol";
import {ITIP20} from "@tempo/interfaces/ITIP20.sol";
import {StdPrecompiles} from "tempo-std/StdPrecompiles.sol";
import {StdTokens} from "tempo-std/StdTokens.sol";
import {ILZEndpointDollar} from "contracts/interfaces/vendor/layerzero/ILZEndpointDollar.sol";

/// @notice Tempo alt-token fee routing: swap-target discovery, quoting and payment.
/// @dev Linked library. Runs via delegatecall, so msg.sender (fee payer) and address(this) (swap
///      custody) are the calling OFT's. `nativeToken` is passed in; libraries cannot read immutables.
library TempoAltTokenLib {
    /// @dev Mirrors TempoAltTokenBase._resolveUserToken (msg.sender preserved under DELEGATECALL).
    function _resolveUserToken() private view returns (address userToken) {
        userToken = StdPrecompiles.TIP_FEE_MANAGER.userTokens(msg.sender);
        if (userToken == address(0)) {
            userToken = StdTokens.PATH_USD_ADDRESS;
        }
    }

    function findSwapTarget(
        ILZEndpointDollar _nativeToken,
        address _userToken,
        uint128 _amountOut
    ) public view returns (address whitelistedToken, uint128 amountIn) {
        address[] memory _tokens = _nativeToken.getWhitelistedTokens();
        uint128 _bestAmountIn = type(uint128).max;
        address _bestToken;

        uint256 _tokenCount = _tokens.length;

        for (uint256 i = 0; i < _tokenCount; i++) {
            // Skip the userToken itself (handled by direct wrap path)
            if (_tokens[i] == _userToken) continue;

            // Try to quote a swap; if it reverts, skip this token
            try
                StdPrecompiles.STABLECOIN_DEX.quoteSwapExactAmountOut({
                    tokenIn: _userToken,
                    tokenOut: _tokens[i],
                    amountOut: _amountOut
                })
            returns (uint128 _quoted) {
                if (_quoted < _bestAmountIn) {
                    _bestAmountIn = _quoted;
                    _bestToken = _tokens[i];
                }
            } catch {
                continue;
            }
        }

        if (_bestToken == address(0)) revert TempoAltTokenBase.NoSwappableWhitelistedToken(_userToken);
        return (_bestToken, _bestAmountIn);
    }

    function quoteUserTokenFee(
        ILZEndpointDollar _nativeToken,
        address _userToken,
        uint256 _endpointFee,
        uint16 _slippageBps
    ) external view returns (uint256) {
        if (_endpointFee == 0) return 0;
        if (_userToken == address(0)) _userToken = StdTokens.PATH_USD_ADDRESS;
        if (_nativeToken.isWhitelistedToken(_userToken)) {
            return _endpointFee; // wrapped 1:1, no swap and therefore no slippage
        }
        (, uint128 _amountIn) = findSwapTarget(_nativeToken, _userToken, uint128(_endpointFee));
        return _withSlippage(_amountIn, _slippageBps);
    }

    /// @dev Always adds at least one unit: the quote/settlement divergence is a rounding
    ///      artefact, so a percentage allowance alone rounds away on small amounts.
    function _withSlippage(uint128 _amountIn, uint16 _bps) internal pure returns (uint128) {
        uint256 padded = (uint256(_amountIn) * (10_000 + uint256(_bps))) / 10_000;
        if (padded <= uint256(_amountIn)) padded = uint256(_amountIn) + 1;
        return padded > type(uint128).max ? type(uint128).max : uint128(padded);
    }

    function validateQuoteSwapPath(ILZEndpointDollar _nativeToken, uint256 _nativeFee) external view {
        if (_nativeFee == 0) return;

        address userToken = _resolveUserToken();

        // If userToken is directly whitelisted, no swap needed
        if (_nativeToken.isWhitelistedToken(userToken)) {
            return;
        }

        // Validate that a swap path exists (reverts if no viable path).
        // fee.nativeFee stays in endpoint-native units so _payNative() can
        // correctly determine the whitelisted-token amountOut to acquire.
        findSwapTarget(_nativeToken, userToken, uint128(_nativeFee));
    }

    function payNativeAltToken(
        ILZEndpointDollar _nativeToken,
        uint256 _nativeFee,
        address _endpointAddr,
        uint16 _slippageBps
    ) external returns (uint256) {
        if (_nativeFee == 0) return 0;
        if (address(_nativeToken) == address(0)) revert TempoAltTokenBase.NativeTokenUnavailable();

        address userToken = _resolveUserToken();

        // If userToken is directly whitelisted, wrap directly
        if (_nativeToken.isWhitelistedToken(userToken)) {
            ITIP20(userToken).transferFrom(msg.sender, address(this), _nativeFee);
            ITIP20(userToken).approve(address(_nativeToken), _nativeFee);
            _nativeToken.wrap(userToken, _endpointAddr, _nativeFee);
            return 0;
        }

        // Find the cheapest whitelisted token to swap to. The cap carries a slippage allowance
        // because settlement may require marginally more input than the quote returned; the DEX
        // debits only what it consumes and the remainder is refunded below.
        (address targetToken, uint128 quotedAmountIn) = findSwapTarget(_nativeToken, userToken, uint128(_nativeFee));
        uint128 maxAmountIn = _withSlippage(quotedAmountIn, _slippageBps);

        ITIP20(userToken).transferFrom(msg.sender, address(this), maxAmountIn);
        ITIP20(userToken).approve(address(StdPrecompiles.STABLECOIN_DEX), maxAmountIn);
        uint128 spentAmountIn = StdPrecompiles.STABLECOIN_DEX.swapExactAmountOut({
            tokenIn: userToken,
            tokenOut: targetToken,
            amountOut: uint128(_nativeFee),
            maxAmountIn: maxAmountIn
        });

        if (maxAmountIn > spentAmountIn) {
            ITIP20(userToken).approve(address(StdPrecompiles.STABLECOIN_DEX), 0);
            ITIP20(userToken).transfer(msg.sender, maxAmountIn - spentAmountIn);
        }

        // Wrap the target whitelisted token and send to endpoint
        ITIP20(targetToken).approve(address(_nativeToken), _nativeFee);
        _nativeToken.wrap(targetToken, _endpointAddr, _nativeFee);

        return 0;
    }
}
