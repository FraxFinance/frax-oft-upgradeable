// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";

error MismatchedArrayLengthsTempo();

/// @notice Tempo variant of FraxOFTWalletUpgradeable that pays gas fees in TIP20 tokens
///         instead of native ETH (required by FraxOFTUpgradeableTempo / EndpointV2Alt).
contract FraxOFTWalletUpgradeableTempo is FraxOFTWalletUpgradeable {
    // ─── Single Bridge ───────────────────────────────────────────────────

    /// @notice Bridge tokens held by this wallet, paying the LZ fee in TIP20 gas token.
    function bridgeWithTIP20FeeFromWallet(
        SendParam memory _sendParam,
        IOFT _oft,
        address _destination
    ) external onlyOwner {
        address gasToken = _resolveGasToken();
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);
        MessagingFee memory fee = _oft.quoteSend(_sendParam, false);
        ITIP20(gasToken).transferFrom(msg.sender, address(this), fee.nativeFee);
        _oft.send(_sendParam, fee, payable(_destination));
    }

    /// @notice Pull tokens from a sender, then bridge them, paying the LZ fee in TIP20 gas token.
    function bridgeWithTIP20FeeFromSender(
        SendParam memory _sendParam,
        IOFT _oft,
        IERC20 _token,
        address _sender,
        address _destination
    ) external onlyOwner {
        address gasToken = _resolveGasToken();
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);
        _token.transferFrom(_sender, address(this), _sendParam.amountLD);
        MessagingFee memory fee = _oft.quoteSend(_sendParam, false);
        ITIP20(gasToken).transferFrom(msg.sender, address(this), fee.nativeFee);
        _oft.send(_sendParam, fee, payable(_destination));
    }

    // ─── Batch Bridge ────────────────────────────────────────────────────

    /// @notice Batch bridge tokens held by this wallet, paying LZ fees in TIP20 gas token.
    function batchBridgeWithTIP20FeeFromWallet(
        SendParam[] memory _sendParams,
        IOFT[] memory _ofts,
        address[] memory _destinations
    ) external onlyOwner {
        address gasToken = _resolveGasToken();
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);
        uint256 _len = _sendParams.length;
        if (_len != _ofts.length || _len != _destinations.length) {
            revert MismatchedArrayLengthsTempo();
        }
        MessagingFee[] memory fees = new MessagingFee[](_len);
        uint256 totalGasFee;
        for (uint256 _i; _i < _len; _i++) {
            fees[_i] = _ofts[_i].quoteSend(_sendParams[_i], false);
            totalGasFee += fees[_i].nativeFee;
        }
        ITIP20(gasToken).transferFrom(msg.sender, address(this), totalGasFee);
        for (uint256 _i; _i < _len; _i++) {
            _ofts[_i].send(_sendParams[_i], fees[_i], _destinations[_i]);
        }
    }

    /// @notice Batch pull tokens from senders and bridge them, paying LZ fees in TIP20 gas token.
    function batchBridgeWithTIP20FeeFromSender(
        SendParam[] memory _sendParams,
        address[] memory _senders,
        IERC20[] memory _tokens,
        IOFT[] memory _ofts,
        address[] memory _destinations
    ) external onlyOwner {
        address gasToken = _resolveGasToken();
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);
        uint256 _len = _sendParams.length;
        if (_len != _senders.length || _len != _tokens.length || _len != _ofts.length || _len != _destinations.length) {
            revert MismatchedArrayLengthsTempo();
        }
        MessagingFee[] memory fees = new MessagingFee[](_len);
        uint256 totalGasFee;
        for (uint256 _i; _i < _len; _i++) {
            _tokens[_i].transferFrom(_senders[_i], address(this), _sendParams[_i].amountLD);
            fees[_i] = _ofts[_i].quoteSend(_sendParams[_i], false);
            totalGasFee += fees[_i].nativeFee;
        }
        ITIP20(gasToken).transferFrom(msg.sender, address(this), totalGasFee);
        for (uint256 _i; _i < _len; _i++) {
            _ofts[_i].send(_sendParams[_i], fees[_i], _destinations[_i]);
        }
    }

    // ─── Internal ────────────────────────────────────────────────────────

    /// @dev Resolve the gas token using the caller's fee token preference:
    ///      1. `TIP_FEE_MANAGER.userTokens(msg.sender)` — caller's explicit choice
    ///      2. Falls back to `PATH_USD` if no token is set (address(0))
    function _resolveGasToken() internal view returns (address gasToken) {
        gasToken = StdPrecompiles.TIP_FEE_MANAGER.userTokens(msg.sender);
        if (gasToken == address(0)) {
            gasToken = StdTokens.PATH_USD_ADDRESS;
        }
    }
}
