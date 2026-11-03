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

/// @dev Implemented by RemoteHopV2Tempo / RemoteHopV201Tempo (TempoGasTokenBase).
interface ITempoGasFeeQuoter {
    /// @notice Amount of `_userToken` the hop will pull for an endpoint-native fee of `_endpointFee`.
    function quoteUserTokenFee(address _userToken, uint256 _endpointFee) external view returns (uint256);
}

/// @notice Tempo variant of FraxOFTWalletUpgradeable that pays gas fees in TIP20 tokens
///         instead of native ETH (required by FraxOFTUpgradeableTempo / EndpointV2Alt).
contract FraxOFTWalletUpgradeableTempo is FraxOFTWalletUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev Single HopV2 send, bundled to keep the TIP20 fee path clear of stack-too-deep.
    struct HopV2Send {
        address hop;
        address oft;
        address oftToken;
        uint32 dstEid;
        bytes32 recipient;
        uint256 amountLD;
        uint128 dstGas;
        bytes data;
    }

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
        uint256 gasFee = ITempoGasFeeQuoter(address(_oft)).quoteUserTokenFee(gasToken, fee.nativeFee);
        if (gasFee > 0) ITIP20(gasToken).transferFrom(msg.sender, address(this), gasFee);
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
        uint256 gasFee = ITempoGasFeeQuoter(address(_oft)).quoteUserTokenFee(gasToken, fee.nativeFee);
        if (gasFee > 0) ITIP20(gasToken).transferFrom(msg.sender, address(this), gasFee);
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
            totalGasFee += ITempoGasFeeQuoter(address(_ofts[_i])).quoteUserTokenFee(gasToken, fees[_i].nativeFee);
        }
        if (totalGasFee > 0) ITIP20(gasToken).transferFrom(msg.sender, address(this), totalGasFee);
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
            totalGasFee += ITempoGasFeeQuoter(address(_ofts[_i])).quoteUserTokenFee(gasToken, fees[_i].nativeFee);
        }
        if (totalGasFee > 0) ITIP20(gasToken).transferFrom(msg.sender, address(this), totalGasFee);
        for (uint256 _i; _i < _len; _i++) {
            _ofts[_i].send(_sendParams[_i], fees[_i], _destinations[_i]);
        }
    }

    // ─── HopV2 ───────────────────────────────────────────────────────────
    //
    // RemoteHopV2Tempo collects its fee from the wallet with `transferFrom` in the wallet's TIP20 fee
    // token, so the hop needs an allowance for both the bridged amount and the fee. When the bridged
    // token *is* the fee token (e.g. frxUSD), both allowances live on the same token and are combined.
    // The owner (msg.sender) funds the fee: approve this wallet for the fee token before calling.

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
        _hopV2WithTIP20Fee(
            HopV2Send({
                hop: _hop,
                oft: _oft,
                oftToken: IOFT(_oft).token(),
                dstEid: _dstEid,
                recipient: _recipient,
                amountLD: _amountLD,
                dstGas: _dstGas,
                data: _data
            }),
            _useGasToken()
        );
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
        _token.safeTransferFrom(_sender, address(this), _amountLD);
        _hopV2WithTIP20Fee(
            HopV2Send({
                hop: _hop,
                oft: _oft,
                oftToken: address(_token),
                dstEid: _dstEid,
                recipient: _recipient,
                amountLD: _amountLD,
                dstGas: _dstGas,
                data: _data
            }),
            _useGasToken()
        );
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
        HopV2Batch memory batch = HopV2Batch({
            hop: _hop,
            ofts: _ofts,
            dstEids: _dstEids,
            recipients: _recipients,
            amounts: _amounts,
            dstGases: _dstGases,
            datas: _datas
        });
        _validateHopV2Batch(batch);

        address gasToken = _useGasToken();
        for (uint256 _i; _i < batch.ofts.length; _i++) {
            _hopV2WithTIP20Fee(_toHopV2Send(batch, _i, IOFT(batch.ofts[_i]).token()), gasToken);
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
        HopV2SenderBatch memory senderBatch = HopV2SenderBatch({
            batch: HopV2Batch({
                hop: _hop,
                ofts: _ofts,
                dstEids: _dstEids,
                recipients: _recipients,
                amounts: _amounts,
                dstGases: _dstGases,
                datas: _datas
            }),
            senders: _senders,
            tokens: _tokens
        });
        _validateHopV2SenderBatch(senderBatch);

        _sendHopV2SenderBatchWithTIP20Fee(senderBatch, _useGasToken());
    }

    // ─── Internal ────────────────────────────────────────────────────────

    function _sendHopV2SenderBatchWithTIP20Fee(HopV2SenderBatch memory _senderBatch, address _gasToken) internal {
        HopV2Batch memory batch = _senderBatch.batch;
        for (uint256 _i; _i < batch.ofts.length; _i++) {
            _senderBatch.tokens[_i].safeTransferFrom(_senderBatch.senders[_i], address(this), batch.amounts[_i]);
            _hopV2WithTIP20Fee(_toHopV2Send(batch, _i, address(_senderBatch.tokens[_i])), _gasToken);
        }
    }

    /// @dev Quote the hop fee in `_gasToken` units, pull it from the owner, approve the hop for amount + fee, send.
    ///      Quoting per send (rather than once up front for a batch) keeps the fee exact even when earlier
    ///      sends in the same batch move the stablecoin DEX price used for the fee swap.
    function _hopV2WithTIP20Fee(HopV2Send memory _send, address _gasToken) internal {
        uint256 nativeFee =
            IHopV2(_send.hop).quote(_send.oft, _send.dstEid, _send.recipient, _send.amountLD, _send.dstGas, _send.data);
        uint256 gasFee = ITempoGasFeeQuoter(_send.hop).quoteUserTokenFee(_gasToken, nativeFee);
        if (gasFee > 0) ITIP20(_gasToken).transferFrom(msg.sender, address(this), gasFee);

        if (_send.oftToken == _gasToken) {
            IERC20(_send.oftToken).forceApprove(_send.hop, _send.amountLD + gasFee);
        } else {
            IERC20(_send.oftToken).forceApprove(_send.hop, _send.amountLD);
            IERC20(_gasToken).forceApprove(_send.hop, gasFee);
        }

        IHopV2(_send.hop).sendOFT(_send.oft, _send.dstEid, _send.recipient, _send.amountLD, _send.dstGas, _send.data);
    }

    function _toHopV2Send(HopV2Batch memory _batch, uint256 _i, address _oftToken)
        internal
        pure
        returns (HopV2Send memory)
    {
        return HopV2Send({
            hop: _batch.hop,
            oft: _batch.ofts[_i],
            oftToken: _oftToken,
            dstEid: _batch.dstEids[_i],
            recipient: _batch.recipients[_i],
            amountLD: _batch.amounts[_i],
            dstGas: _batch.dstGases[_i],
            data: _batch.datas[_i]
        });
    }

    /// @dev Resolve the owner's fee token and make it this wallet's fee token too, so the hop's
    ///      `_resolveUserToken()` (which reads the wallet's preference) charges the same token we approved.
    function _useGasToken() internal returns (address gasToken) {
        gasToken = _resolveGasToken();
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);
    }

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
