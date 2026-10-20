// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTWalletUpgradeable, IHopV2 } from "contracts/FraxOFTWalletUpgradeable.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";

error MismatchedArrayLengthsTempo();

/// @notice Tempo variant of FraxOFTWalletUpgradeable that pays gas fees in TIP20 tokens
///         instead of native ETH (required by FraxOFTUpgradeableTempo / EndpointV2Alt).
contract FraxOFTWalletUpgradeableTempo is FraxOFTWalletUpgradeable {
    using SafeERC20 for IERC20;

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

    // ─── HopV2 ───────────────────────────────────────────────────────────

    /// @notice HopV2 send with wallet-held tokens, paying hop/LZ fee in TIP20 gas token.
    function hopV2WithTIP20FeeFromWallet(
        address _hop,
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external onlyOwner {
        address gasToken = _resolveGasToken();
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);

        IERC20(IOFT(_oft).token()).forceApprove(_hop, _amountLD);
        uint256 fee = IHopV2(_hop).quote(_oft, _dstEid, _recipient, _amountLD, _dstGas, _data);
        ITIP20(gasToken).transferFrom(msg.sender, address(this), fee);

        IHopV2(_hop).sendOFT(_oft, _dstEid, _recipient, _amountLD, _dstGas, _data);
    }

    /// @notice HopV2 send with sender-provided tokens, paying hop/LZ fee in TIP20 gas token.
    function hopV2WithTIP20FeeFromSender(
        address _hop,
        address _oft,
        IERC20 _token,
        address _sender,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external onlyOwner {
        address gasToken = _resolveGasToken();
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);

        _token.transferFrom(_sender, address(this), _amountLD);
        _token.forceApprove(_hop, _amountLD);

        uint256 fee = IHopV2(_hop).quote(_oft, _dstEid, _recipient, _amountLD, _dstGas, _data);
        ITIP20(gasToken).transferFrom(msg.sender, address(this), fee);

        IHopV2(_hop).sendOFT(_oft, _dstEid, _recipient, _amountLD, _dstGas, _data);
    }

    /// @notice Batch HopV2 send with wallet-held tokens, paying hop/LZ fees in TIP20 gas token.
    function batchHopV2WithTIP20FeeFromWallet(
        address _hop,
        address[] memory _ofts,
        uint32[] memory _dstEids,
        bytes32[] memory _recipients,
        uint256[] memory _amounts,
        uint128[] memory _dstGases,
        bytes[] memory _datas
    ) external onlyOwner {
        address gasToken = _resolveGasToken();
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);

        uint256 _len = _ofts.length;
        if (
            _len != _dstEids.length || _len != _recipients.length || _len != _amounts.length || _len != _dstGases.length
                || _len != _datas.length
        ) {
            revert MismatchedArrayLengthsTempo();
        }

        uint256[] memory fees = new uint256[](_len);
        uint256 totalGasFee;
        for (uint256 _i; _i < _len; _i++) {
            fees[_i] = IHopV2(_hop).quote(_ofts[_i], _dstEids[_i], _recipients[_i], _amounts[_i], _dstGases[_i], _datas[_i]);
            totalGasFee += fees[_i];
        }

        ITIP20(gasToken).transferFrom(msg.sender, address(this), totalGasFee);

        for (uint256 _i; _i < _len; _i++) {
            IERC20(IOFT(_ofts[_i]).token()).forceApprove(_hop, _amounts[_i]);
            IHopV2(_hop).sendOFT(_ofts[_i], _dstEids[_i], _recipients[_i], _amounts[_i], _dstGases[_i], _datas[_i]);
        }
    }

    /// @notice Batch HopV2 send with sender-provided tokens, paying hop/LZ fees in TIP20 gas token.
    function batchHopV2WithTIP20FeeFromSender(
        address _hop,
        address[] memory _senders,
        IERC20[] memory _tokens,
        address[] memory _ofts,
        uint32[] memory _dstEids,
        bytes32[] memory _recipients,
        uint256[] memory _amounts,
        uint128[] memory _dstGases,
        bytes[] memory _datas
    ) external onlyOwner {
        address gasToken = _resolveGasToken();
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);

        uint256 _len = _ofts.length;
        if (
            _len != _senders.length || _len != _tokens.length || _len != _dstEids.length || _len != _recipients.length
                || _len != _amounts.length || _len != _dstGases.length || _len != _datas.length
        ) {
            revert MismatchedArrayLengthsTempo();
        }

        uint256[] memory fees = new uint256[](_len);
        uint256 totalGasFee;
        for (uint256 _i; _i < _len; _i++) {
            fees[_i] = IHopV2(_hop).quote(_ofts[_i], _dstEids[_i], _recipients[_i], _amounts[_i], _dstGases[_i], _datas[_i]);
            totalGasFee += fees[_i];
        }

        ITIP20(gasToken).transferFrom(msg.sender, address(this), totalGasFee);

        for (uint256 _i; _i < _len; _i++) {
            _tokens[_i].transferFrom(_senders[_i], address(this), _amounts[_i]);
            _tokens[_i].forceApprove(_hop, _amounts[_i]);
            IHopV2(_hop).sendOFT(_ofts[_i], _dstEids[_i], _recipients[_i], _amounts[_i], _dstGases[_i], _datas[_i]);
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
