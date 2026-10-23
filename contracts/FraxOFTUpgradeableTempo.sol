// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { TempoAltTokenBase } from "contracts/base/TempoAltTokenBase.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IOFT, SendParam, OFTReceipt } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

/// @notice Tempo variant of FraxOFT that pays gas in ERC20 native token (via EndpointV2Alt)
contract FraxOFTUpgradeableTempo is FraxOFTUpgradeable, TempoAltTokenBase {
    constructor(address _lzEndpoint) FraxOFTUpgradeable(_lzEndpoint) TempoAltTokenBase(_lzEndpoint) {
        _disableInitializers();
    }

    /// @inheritdoc IOFT
    /// @dev Overrides send to prevent msg.value being sent (EndpointV2Alt uses ERC20 for gas)
    /// @dev `_refundAddress` receives any fee surplus in LZEndpointDollar rather than the TIP20 paid,
    ///      so a contract passed here must be able to transfer it or call `unwrap`. See
    ///      TempoAltTokenBase.
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

    /// @notice `send()` with the LayerZero fee paid in `_feeToken` and that debit capped — the Tempo
    ///         equivalent of the `msg.value` ceiling on native chains. `IOFT.send` cannot carry a cap,
    ///         so this companion sits beside it. Takes no value.
    /// @param _feeToken TIP20 to pay the fee in. Pulled 1:1 when LZEndpointDollar whitelists it,
    ///        otherwise swapped on the StablecoinDEX; independent of the caller's FeeManager token.
    /// @param _maxFeeTokenAmount Reverts `FeeAboveCap` (nothing is kept) if the fee in `_feeToken`, as
    ///        `quoteUserTokenFee(_feeToken, _fee.nativeFee)` reports it at execution, exceeds this. Pass
    ///        that quote: on the swap path it carries the headroom, and the unspent part is refunded.
    function sendWithFeeCap(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress,
        address _feeToken,
        uint256 _maxFeeTokenAmount
    ) external virtual returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        if (_feeToken == address(0)) revert InvalidFeeToken();

        // Debit tokens from sender
        (uint256 amountSentLD, uint256 amountReceivedLD) = _debit(
            _sendParam.amountLD,
            _sendParam.minAmountLD,
            _sendParam.dstEid
        );

        // Build message and options
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceivedLD);

        // Pay the fee in TIP20 under the cap, then hand the message over: the steps of `_lzSend`
        // with its fixed `_payNative(uint256)` replaced by the capped collector.
        _payNativeAltTokenCapped(_fee.nativeFee, address(endpoint), _feeToken, _maxFeeTokenAmount);
        if (_fee.lzTokenFee > 0) _payLzToken(_fee.lzTokenFee);
        msgReceipt = _lzSendPrepaid(_sendParam.dstEid, message, options, _fee.lzTokenFee > 0, _refundAddress);
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSentLD, amountReceivedLD);
    }

    /// @dev `_lzSend` with the fee already pushed to the endpoint; EndpointV2Alt takes no value.
    function _lzSendPrepaid(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        bool _payInLzToken,
        address _refundAddress
    ) internal returns (MessagingReceipt memory) {
        return
            endpoint.send(
                MessagingParams(_dstEid, _getPeerOrRevert(_dstEid), _message, _options, _payInLzToken),
                _refundAddress
            );
    }

    /// @dev Validates the user's gas token swap path; fee stays in endpoint-native units.
    function _quote(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        bool _payInLzToken
    ) internal view virtual override returns (MessagingFee memory fee) {
        return _validateQuoteSwapPath(super._quote(_dstEid, _message, _options, _payInLzToken));
    }

    /// @dev Pays the LZ fee via ERC20 swap+wrap through TempoAltTokenBase.
    function _payNative(uint256 _nativeFee) internal virtual override returns (uint256 nativeFee) {
        return _payNativeAltToken(_nativeFee, address(endpoint));
    }

    /// @notice Set the slippage allowance applied to a quoted fee swap, in basis points.
    /// @param _bps Allowance in bps, capped by MAX_FEE_SWAP_SLIPPAGE_BPS. 0 restores the default.
    function setFeeSwapSlippageBps(uint16 _bps) external onlyOwner {
        _setFeeSwapSlippageBps(_bps);
    }

}
