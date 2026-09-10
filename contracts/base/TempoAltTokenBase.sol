// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { ILZEndpointDollar } from "contracts/interfaces/vendor/layerzero/ILZEndpointDollar.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {TempoAltTokenLib} from "contracts/libraries/TempoAltTokenLib.sol";

/// @dev Interface for EndpointV2Alt's nativeToken function
interface IEndpointV2Alt {
    function nativeToken() external view returns (address);
}

/// @title TempoAltTokenBase
/// @notice Shared base for Tempo OFT variants that pay LayerZero fees via ERC20 (EndpointV2Alt).
///         Provides the swap-routing logic for converting any user TIP20 gas token into
///         an LZEndpointDollar-whitelisted stablecoin for fee payment.
/// @dev Routing, quoting and payment are delegated to `TempoAltTokenLib`; `nativeToken` is passed
///      in explicitly because libraries cannot read immutables.
abstract contract TempoAltTokenBase {
    error NativeTokenUnavailable();
    error OFTAltCore__msg_value_not_zero(uint256 _msg_value);
    error NoSwappableWhitelistedToken(address userToken);
    error FeeSwapSlippageTooHigh(uint16 bps);

    /// @notice Emitted when the fee-swap slippage allowance changes.
    event FeeSwapSlippageBpsSet(uint16 bps);

    /// @dev Applied to the quoted input of a fee swap. The DEX quote and its settlement round
    ///      differently across order boundaries, so settlement can require marginally more input
    ///      than quoted; without headroom the swap reverts with MaxInputExceeded. Anything not
    ///      consumed is returned to the payer.
    uint16 internal constant DEFAULT_FEE_SWAP_SLIPPAGE_BPS = 50;
    uint16 internal constant MAX_FEE_SWAP_SLIPPAGE_BPS = 200;

    struct AltTokenStorage {
        uint16 feeSwapSlippageBps;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.TempoAltTokenBase")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AltTokenStorageLocation =
        0x8c8147e168837ec687c20ac8f558b015dbf33e0ef9d2d8c77772e8c47e12ff00;

    function _getAltTokenStorage() private pure returns (AltTokenStorage storage $) {
        assembly {
            $.slot := AltTokenStorageLocation
        }
    }

    ILZEndpointDollar public immutable nativeToken;

    /// @notice Slippage allowance applied to a quoted fee swap, in basis points.
    function feeSwapSlippageBps() public view returns (uint16) {
        uint16 configured = _getAltTokenStorage().feeSwapSlippageBps;
        return configured == 0 ? DEFAULT_FEE_SWAP_SLIPPAGE_BPS : configured;
    }

    /// @dev Pass 0 to fall back to DEFAULT_FEE_SWAP_SLIPPAGE_BPS.
    function _setFeeSwapSlippageBps(uint16 _bps) internal {
        if (_bps > MAX_FEE_SWAP_SLIPPAGE_BPS) revert FeeSwapSlippageTooHigh(_bps);
        _getAltTokenStorage().feeSwapSlippageBps = _bps;
        emit FeeSwapSlippageBpsSet(_bps);
    }

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
        return TempoAltTokenLib.findSwapTarget(nativeToken, _userToken, _amountOut);
    }

    // ─── Quote Helpers ───────────────────────────────────────────────────

    /// @notice Estimates the amount of a given gas token needed for a given endpoint-native fee.
    /// @dev UIs should call this after quoteSend() to determine the token approval amount and
    ///      display the cost in the user's chosen gas token. The caller passes the token address
    ///      explicitly so the quote works even before `setUserToken` is called on-chain.
    /// @param _userToken The TIP20 gas token to quote for.
    /// @param _endpointFee The fee in endpoint-native (LZEndpointDollar) units, as returned by quoteSend().
    /// @return The estimated amount of `_userToken` required, including the slippage allowance
    ///         applied when the fee must be swapped. Approve at least this much.
    function quoteUserTokenFee(address _userToken, uint256 _endpointFee) external view returns (uint256) {
        return TempoAltTokenLib.quoteUserTokenFee(nativeToken, _userToken, _endpointFee, feeSwapSlippageBps());
    }

    /// @dev Validates that the user's gas token has a viable swap path.
    ///      Returns the fee unchanged — fee.nativeFee stays in endpoint-native units.
    ///      Children call this from their _quote() override.
    function _validateQuoteSwapPath(MessagingFee memory fee) internal view returns (MessagingFee memory) {
        TempoAltTokenLib.validateQuoteSwapPath(nativeToken, fee.nativeFee);
        return fee;
    }

    // ─── Payment ─────────────────────────────────────────────────────────

    /// @dev Handles gas payment for EndpointV2Alt which uses an ERC20 token as native.
    ///      Dynamically resolves the best whitelisted swap target from LZEndpointDollar.
    ///      Children call this from their _payNative() override, passing `address(endpoint)`.
    /// @param _nativeFee The fee in endpoint-native (LZEndpointDollar) units.
    /// @param _endpointAddr The address of the LZ endpoint to send wrapped tokens to.
    function _payNativeAltToken(uint256 _nativeFee, address _endpointAddr) internal returns (uint256) {
        return TempoAltTokenLib.payNativeAltToken(nativeToken, _nativeFee, _endpointAddr, feeSwapSlippageBps());
    }
}
