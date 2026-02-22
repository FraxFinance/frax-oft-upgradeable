// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { OAppSenderUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/OAppSenderUpgradeable.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { ILZEndpointDollar } from "contracts/interfaces/vendor/layerzero/ILZEndpointDollar.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IOFT, SendParam, OFTReceipt } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

/// @dev Interface for EndpointV2Alt's nativeToken function
interface IEndpointV2Alt {
    function nativeToken() external view returns (address);
}

/// @notice Tempo variant of FraxOFT that pays gas in ERC20 native token (via EndpointV2Alt)
contract FraxOFTUpgradeableTempo is FraxOFTUpgradeable {
    error NativeTokenUnavailable();
    error OFTAltCore__msg_value_not_zero(uint256 _msg_value);
    error NoSwappableWhitelistedToken(address userToken);

    ILZEndpointDollar public immutable nativeToken;

    constructor(address _lzEndpoint) FraxOFTUpgradeable(_lzEndpoint) {
        nativeToken = ILZEndpointDollar(IEndpointV2Alt(_lzEndpoint).nativeToken());
        _disableInitializers();
    }

    /// @inheritdoc IOFT
    /// @dev Overrides send to prevent msg.value being sent (EndpointV2Alt uses ERC20 for gas)
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable virtual override returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        if (msg.value > 0) revert OFTAltCore__msg_value_not_zero(msg.value);

        // Debit tokens from sender
        (uint256 amountSentLD, uint256 amountReceivedLD) = _debit(
            _sendParam.amountLD,
            _sendParam.minAmountLD,
            _sendParam.dstEid
        );

        // Build message and options
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceivedLD);

        // Send via LayerZero
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSentLD, amountReceivedLD);
    }

    /// @dev Finds the best whitelisted token that can be swapped to from `_userToken`.
    ///      Returns the whitelisted token address and the quoted input amount.
    ///      Reverts if no viable swap path exists.
    function _findSwapTarget(
        address _userToken,
        uint128 _amountOut
    ) internal view returns (address whitelistedToken, uint128 amountIn) {
        address[] memory tokens = nativeToken.getWhitelistedTokens();
        uint128 bestAmountIn = type(uint128).max;
        address bestToken;

        for (uint256 i = 0; i < tokens.length; i++) {
            // Skip the userToken itself (handled by direct wrap path)
            if (tokens[i] == _userToken) continue;

            // Try to quote a swap; if it reverts, skip this token
            try
                StdPrecompiles.STABLECOIN_DEX.quoteSwapExactAmountOut({
                    tokenIn: _userToken,
                    tokenOut: tokens[i],
                    amountOut: _amountOut
                })
            returns (uint128 quoted) {
                if (quoted < bestAmountIn) {
                    bestAmountIn = quoted;
                    bestToken = tokens[i];
                }
            } catch {
                continue;
            }
        }

        if (bestToken == address(0)) revert NoSwappableWhitelistedToken(_userToken);
        return (bestToken, bestAmountIn);
    }

    /// @dev Overrides _quote to validate the user's gas token has a viable swap path.
    ///      Returns the fee in endpoint-native (LZEndpointDollar) units.
    ///      Use quoteUserTokenFee() to estimate the cost in the user's gas token.
    function _quote(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        bool _payInLzToken
    ) internal view virtual override returns (MessagingFee memory fee) {
        // Get the base quote in endpoint native token terms
        fee = super._quote(_dstEid, _message, _options, _payInLzToken);

        if (fee.nativeFee == 0) return fee;

        address userToken = StdPrecompiles.TIP_FEE_MANAGER.userTokens(msg.sender);

        // If userToken is directly whitelisted, no swap needed
        if (nativeToken.isWhitelistedToken(userToken)) {
            return fee;
        }

        // Validate that a swap path exists (reverts if no viable path).
        // fee.nativeFee stays in endpoint-native units so _payNative() can
        // correctly determine the whitelisted-token amountOut to acquire.
        _findSwapTarget(userToken, uint128(fee.nativeFee));
    }

    /// @notice Estimates the amount of the caller's gas token needed for a given endpoint-native fee.
    /// @dev UIs should call this after quoteSend() to determine the token approval amount and
    ///      display the cost in the user's chosen gas token.
    /// @param _endpointFee The fee in endpoint-native (LZEndpointDollar) units, as returned by quoteSend().
    /// @return userTokenAmount The estimated amount of the caller's gas token required.
    function quoteUserTokenFee(uint256 _endpointFee) external view returns (uint256 userTokenAmount) {
        if (_endpointFee == 0) return 0;
        address userToken = StdPrecompiles.TIP_FEE_MANAGER.userTokens(msg.sender);
        if (nativeToken.isWhitelistedToken(userToken)) {
            return _endpointFee;
        }
        (, uint128 amountIn) = _findSwapTarget(userToken, uint128(_endpointFee));
        return amountIn;
    }

    /// @dev Handles gas payment for EndpointV2Alt which uses an ERC20 token as native.
    ///      Dynamically resolves the best whitelisted swap target from LZEndpointDollar.
    function _payNative(uint256 _nativeFee) internal virtual override returns (uint256 nativeFee) {
        if (address(nativeToken) == address(0)) revert NativeTokenUnavailable();

        address userToken = StdPrecompiles.TIP_FEE_MANAGER.userTokens(msg.sender);

        // If userToken is directly whitelisted, wrap directly
        if (nativeToken.isWhitelistedToken(userToken)) {
            ITIP20(userToken).transferFrom(msg.sender, address(this), _nativeFee);
            ITIP20(userToken).approve(address(nativeToken), _nativeFee);
            nativeToken.wrap(userToken, address(endpoint), _nativeFee);
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
        nativeToken.wrap(targetToken, address(endpoint), _nativeFee);

        return 0;
    }
}
