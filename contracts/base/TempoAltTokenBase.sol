// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { ILZEndpointDollar } from "contracts/interfaces/vendor/layerzero/ILZEndpointDollar.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/// @dev Interface for EndpointV2Alt's nativeToken function
interface IEndpointV2Alt {
    function nativeToken() external view returns (address);
}

/// @title TempoAltTokenBase
/// @notice Shared base for Tempo OFT variants that pay LayerZero fees via ERC20 (EndpointV2Alt).
///         Provides the swap-routing logic for converting any user TIP20 gas token into
///         an LZEndpointDollar-whitelisted stablecoin for fee payment.
abstract contract TempoAltTokenBase {
    error NativeTokenUnavailable();
    error OFTAltCore__msg_value_not_zero(uint256 _msg_value);
    error NoSwappableWhitelistedToken(address userToken);

    ILZEndpointDollar public immutable nativeToken;

    constructor(address _lzEndpoint) {
        nativeToken = ILZEndpointDollar(IEndpointV2Alt(_lzEndpoint).nativeToken());
    }

    // ─── Token Resolution ────────────────────────────────────────────────

    /// @dev Resolves the caller's TIP20 fee token using Tempo's cascading selection:
    ///      1. `TIP_FEE_MANAGER.userTokens(msg.sender)` — user's explicit choice
    ///      2. Falls back to `PATH_USD` if no token is set (address(0))
    ///      Mirrors the FeeManager spec's `collectFeePreTx` / `collectFeePostTx` fallback.
    function _resolveUserToken() internal view returns (address userToken) {
        userToken = StdPrecompiles.TIP_FEE_MANAGER.userTokens(msg.sender);
        if (userToken == address(0)) {
            userToken = StdTokens.PATH_USD_ADDRESS;
        }
    }

    // ─── Swap Routing ────────────────────────────────────────────────────

    /// @dev Finds the best whitelisted token that can be swapped to from `_userToken`.
    ///      Returns the whitelisted token address and the quoted input amount.
    ///      Reverts if no viable swap path exists.
    function _findSwapTarget(
        address _userToken,
        uint128 _amountOut
    ) internal view returns (address whitelistedToken, uint128 amountIn) {
        address[] memory _tokens = nativeToken.getWhitelistedTokens();
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

        if (_bestToken == address(0)) revert NoSwappableWhitelistedToken(_userToken);
        return (_bestToken, _bestAmountIn);
    }

    // ─── Quote Helpers ───────────────────────────────────────────────────

    /// @notice Estimates the amount of a given gas token needed for a given endpoint-native fee.
    /// @dev UIs should call this after quoteSend() to determine the token approval amount and
    ///      display the cost in the user's chosen gas token. The caller passes the token address
    ///      explicitly so the quote works even before `setUserToken` is called on-chain.
    /// @param _userToken The TIP20 gas token to quote for.
    /// @param _endpointFee The fee in endpoint-native (LZEndpointDollar) units, as returned by quoteSend().
    /// @return The estimated amount of `_userToken` required.
    function quoteUserTokenFee(address _userToken, uint256 _endpointFee) external view returns (uint256) {
        if (_endpointFee == 0) return 0;
        if (_userToken == address(0)) _userToken = StdTokens.PATH_USD_ADDRESS;
        if (nativeToken.isWhitelistedToken(_userToken)) {
            return _endpointFee;
        }
        (, uint128 _amountIn) = _findSwapTarget(_userToken, uint128(_endpointFee));
        return _amountIn;
    }

    /// @dev Validates that the user's gas token has a viable swap path.
    ///      Returns the fee unchanged — fee.nativeFee stays in endpoint-native units.
    ///      Children call this from their _quote() override.
    function _validateQuoteSwapPath(MessagingFee memory fee) internal view returns (MessagingFee memory) {
        if (fee.nativeFee == 0) return fee;

        address userToken = _resolveUserToken();

        // If userToken is directly whitelisted, no swap needed
        if (nativeToken.isWhitelistedToken(userToken)) {
            return fee;
        }

        // Validate that a swap path exists (reverts if no viable path).
        // fee.nativeFee stays in endpoint-native units so _payNative() can
        // correctly determine the whitelisted-token amountOut to acquire.
        _findSwapTarget(userToken, uint128(fee.nativeFee));

        return fee;
    }

    // ─── Payment ─────────────────────────────────────────────────────────

    /// @dev Handles gas payment for EndpointV2Alt which uses an ERC20 token as native.
    ///      Dynamically resolves the best whitelisted swap target from LZEndpointDollar.
    ///      Children call this from their _payNative() override, passing `address(endpoint)`.
    /// @param _nativeFee The fee in endpoint-native (LZEndpointDollar) units.
    /// @param _endpointAddr The address of the LZ endpoint to send wrapped tokens to.
    function _payNativeAltToken(uint256 _nativeFee, address _endpointAddr) internal returns (uint256) {
        if (_nativeFee == 0) return 0;
        if (address(nativeToken) == address(0)) revert NativeTokenUnavailable();

        address userToken = _resolveUserToken();

        // If userToken is directly whitelisted, wrap directly
        if (nativeToken.isWhitelistedToken(userToken)) {
            ITIP20(userToken).transferFrom(msg.sender, address(this), _nativeFee);
            ITIP20(userToken).approve(address(nativeToken), _nativeFee);
            nativeToken.wrap(userToken, _endpointAddr, _nativeFee);
            return 0;
        }

        // Find the cheapest whitelisted token to swap to
        (address targetToken, uint128 userTokenAmount) = _findSwapTarget(userToken, uint128(_nativeFee));

        ITIP20(userToken).transferFrom(msg.sender, address(this), userTokenAmount);
        ITIP20(userToken).approve(address(StdPrecompiles.STABLECOIN_DEX), userTokenAmount);
        StdPrecompiles.STABLECOIN_DEX.swapExactAmountOut({
            tokenIn: userToken,
            tokenOut: targetToken,
            amountOut: uint128(_nativeFee),
            maxAmountIn: userTokenAmount
        });

        // Wrap the target whitelisted token and send to endpoint
        ITIP20(targetToken).approve(address(nativeToken), _nativeFee);
        nativeToken.wrap(targetToken, _endpointAddr, _nativeFee);

        return 0;
    }
}
