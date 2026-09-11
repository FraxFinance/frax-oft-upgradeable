// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {
    SendParam,
    OFTReceipt,
    MessagingFee,
    IOFT
} from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error WithdrawEthFailed();
error MismatchedArrayLengths();

interface IHopV2 {
    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD) external payable;

    function sendOFT(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external payable;

    function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external view returns (uint256 fee);
}

interface IRemoteHop {
    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD) external payable;

    function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD
    ) external view returns (MessagingFee memory fee);
}

contract FraxOFTWalletUpgradeable is Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    struct HopV2Batch {
        address hop;
        address[] ofts;
        uint32[] dstEids;
        bytes32[] recipients;
        uint256[] amounts;
        uint128[] dstGases;
        bytes[] datas;
    }

    struct HopV2SenderBatch {
        HopV2Batch batch;
        address[] senders;
        IERC20[] tokens;
    }

    constructor() {
        _disableInitializers();
    }

    function batchBridgeWithEthFeeFromWallet(
        SendParam[] memory _sendParams,
        IOFT[] memory _ofts,
        address[] memory _destinations
    ) external payable onlyOwner {
        uint256 _sendParamLength = _sendParams.length;
        uint256 _oftLength = _ofts.length;
        uint256 _destinationLength = _destinations.length;
        if (_sendParamLength != _oftLength || _oftLength != _destinationLength) {
            revert MismatchedArrayLengths();
        }
        for (uint256 _i; _i < _sendParamLength; _i++) {
            MessagingFee memory fee = _ofts[_i].quoteSend(_sendParams[_i], false);
            _ofts[_i].send{value: fee.nativeFee}(_sendParams[_i], fee, _destinations[_i]);
        }
    }

    function batchBridgeWithEthFeeFromSender(
        SendParam[] memory _sendParams,
        address[] memory _senders,
        IERC20[] memory _tokens,
        IOFT[] memory _ofts,
        address[] memory _destinations
    ) external payable onlyOwner {
        uint256 _sendParamLength = _sendParams.length;
        uint256 _senderLength = _senders.length;
        uint256 _tokenLength = _tokens.length;
        uint256 _oftLength = _ofts.length;
        uint256 _destinationLength = _destinations.length;
        if (
            _sendParamLength != _senderLength || _senderLength != _tokenLength || _tokenLength != _oftLength
                || _oftLength != _destinationLength
        ) {
            revert MismatchedArrayLengths();
        }
        for (uint256 _i; _i < _sendParamLength; _i++) {
            _tokens[_i].transferFrom(_senders[_i], address(this), _sendParams[_i].amountLD);
            MessagingFee memory fee = _ofts[_i].quoteSend(_sendParams[_i], false);
            _ofts[_i].send{value: fee.nativeFee}(_sendParams[_i], fee, _destinations[_i]);
        }
    }

    function bridgeWithEthFeeFromWallet(SendParam memory sendParam, IOFT _oft, address _destination)
        external
        payable
        onlyOwner
    {
        MessagingFee memory fee = _oft.quoteSend(sendParam, false);
        _oft.send{value: fee.nativeFee}(sendParam, fee, payable(_destination));
    }

    function bridgeWithEthFeeFromSender(
        SendParam memory sendParam,
        IOFT _oft,
        IERC20 _token,
        address _sender,
        address _destination
    ) external payable onlyOwner {
        _token.transferFrom(_sender, address(this), sendParam.amountLD);
        MessagingFee memory fee = _oft.quoteSend(sendParam, false);
        _oft.send{value: fee.nativeFee}(sendParam, fee, payable(_destination));
    }

    function batchHopV2WithEthFeeFromWallet(
        address _hop,
        address[] memory _ofts,
        uint32[] memory _dstEids,
        bytes32[] memory _recipients,
        uint256[] memory _amounts,
        uint128[] memory _dstGases,
        bytes[] memory _datas
    ) external payable onlyOwner {
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

        (uint256[] memory fees, uint256 totalFee) = _quoteHopV2Batch(batch);
        require(msg.value >= totalFee, "Insufficient ETH for fees");

        _sendHopV2BatchFromWallet(batch, fees);
    }

    function batchHopV2WithEthFeeFromSender(
        address _hop,
        address[] memory _senders,
        IERC20[] memory _tokens,
        address[] memory _ofts,
        uint32[] memory _dstEids,
        bytes32[] memory _recipients,
        uint256[] memory _amounts,
        uint128[] memory _dstGases,
        bytes[] memory _datas
    ) external payable onlyOwner {
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

        (uint256[] memory fees, uint256 totalFee) = _quoteHopV2Batch(senderBatch.batch);
        require(msg.value >= totalFee, "Insufficient ETH for fees");

        _sendHopV2BatchFromSender(senderBatch, fees);
    }

    function hopV2WithEthFeeFromWallet(
        address _hop,
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external payable onlyOwner {
        IERC20(IOFT(_oft).token()).forceApprove(_hop, _amountLD);
        uint256 fee = IHopV2(_hop).quote(_oft, _dstEid, _recipient, _amountLD, _dstGas, _data);
        IHopV2(_hop).sendOFT{value: fee}(_oft, _dstEid, _recipient, _amountLD, _dstGas, _data);
    }

    function hopV2WithEthFeeFromSender(
        address _hop,
        address _oft,
        IERC20 _token,
        address _sender,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external payable onlyOwner {
        _token.transferFrom(_sender, address(this), _amountLD);
        _token.forceApprove(_hop, _amountLD);
        uint256 fee = IHopV2(_hop).quote(_oft, _dstEid, _recipient, _amountLD, _dstGas, _data);
        IHopV2(_hop).sendOFT{value: fee}(_oft, _dstEid, _recipient, _amountLD, _dstGas, _data);
    }

    function batchHopWithEthFeeFromWallet(
        address _hop,
        address[] memory _ofts,
        uint32[] memory _dstEids,
        bytes32[] memory _recipients,
        uint256[] memory _amounts
    ) external payable onlyOwner {
        uint256 _len = _ofts.length;
        if (_len != _dstEids.length || _len != _recipients.length || _len != _amounts.length) {
            revert MismatchedArrayLengths();
        }

        MessagingFee[] memory fees = new MessagingFee[](_len);
        uint256 totalFee;
        for (uint256 _i; _i < _len; _i++) {
            fees[_i] = IRemoteHop(_hop).quote(_ofts[_i], _dstEids[_i], _recipients[_i], _amounts[_i]);
            totalFee += fees[_i].nativeFee;
        }
        require(msg.value >= totalFee, "Insufficient ETH for fees");

        for (uint256 _i; _i < _len; _i++) {
            IERC20(IOFT(_ofts[_i]).token()).forceApprove(_hop, _amounts[_i]);
            IRemoteHop(_hop).sendOFT{value: fees[_i].nativeFee}(_ofts[_i], _dstEids[_i], _recipients[_i], _amounts[_i]);
        }
    }

    function batchHopWithEthFeeFromSender(
        address _hop,
        address[] memory _senders,
        IERC20[] memory _tokens,
        address[] memory _ofts,
        uint32[] memory _dstEids,
        bytes32[] memory _recipients,
        uint256[] memory _amounts
    ) external payable onlyOwner {
        uint256 _len = _ofts.length;
        if (
            _len != _senders.length || _len != _tokens.length || _len != _dstEids.length || _len != _recipients.length
                || _len != _amounts.length
        ) {
            revert MismatchedArrayLengths();
        }

        MessagingFee[] memory fees = new MessagingFee[](_len);
        uint256 totalFee;
        for (uint256 _i; _i < _len; _i++) {
            fees[_i] = IRemoteHop(_hop).quote(_ofts[_i], _dstEids[_i], _recipients[_i], _amounts[_i]);
            totalFee += fees[_i].nativeFee;
        }
        require(msg.value >= totalFee, "Insufficient ETH for fees");

        for (uint256 _i; _i < _len; _i++) {
            _tokens[_i].transferFrom(_senders[_i], address(this), _amounts[_i]);
            _tokens[_i].forceApprove(_hop, _amounts[_i]);
            IRemoteHop(_hop).sendOFT{value: fees[_i].nativeFee}(_ofts[_i], _dstEids[_i], _recipients[_i], _amounts[_i]);
        }
    }

    function hopWithEthFeeFromWallet(address _hop, address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD)
        external
        payable
        onlyOwner
    {
        IERC20(IOFT(_oft).token()).forceApprove(_hop, _amountLD);
        MessagingFee memory fee = IRemoteHop(_hop).quote(_oft, _dstEid, _recipient, _amountLD);
        IRemoteHop(_hop).sendOFT{value: fee.nativeFee}(_oft, _dstEid, _recipient, _amountLD);
    }

    function hopWithEthFeeFromSender(
        address _hop,
        address _oft,
        IERC20 _token,
        address _sender,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD
    ) external payable onlyOwner {
        _token.transferFrom(_sender, address(this), _amountLD);
        _token.forceApprove(_hop, _amountLD);
        MessagingFee memory fee = IRemoteHop(_hop).quote(_oft, _dstEid, _recipient, _amountLD);
        IRemoteHop(_hop).sendOFT{value: fee.nativeFee}(_oft, _dstEid, _recipient, _amountLD);
    }

    function _validateHopV2Batch(HopV2Batch memory _batch) internal pure {
        uint256 length = _batch.ofts.length;
        if (
            length != _batch.dstEids.length || length != _batch.recipients.length || length != _batch.amounts.length
                || length != _batch.dstGases.length || length != _batch.datas.length
        ) {
            revert MismatchedArrayLengths();
        }
    }

    function _validateHopV2SenderBatch(HopV2SenderBatch memory _senderBatch) internal pure {
        uint256 length = _senderBatch.batch.ofts.length;
        if (_senderBatch.senders.length != _senderBatch.tokens.length || _senderBatch.tokens.length != length) {
            revert MismatchedArrayLengths();
        }

        _validateHopV2Batch(_senderBatch.batch);
    }

    function _quoteHopV2Batch(HopV2Batch memory _batch)
        internal
        view
        returns (uint256[] memory fees, uint256 totalFee)
    {
        uint256 length = _batch.ofts.length;
        fees = new uint256[](length);
        for (uint256 _i; _i < length; _i++) {
            fees[_i] = IHopV2(_batch.hop)
                .quote(
                    _batch.ofts[_i],
                    _batch.dstEids[_i],
                    _batch.recipients[_i],
                    _batch.amounts[_i],
                    _batch.dstGases[_i],
                    _batch.datas[_i]
                );
            totalFee += fees[_i];
        }
    }

    function _sendHopV2BatchFromWallet(HopV2Batch memory _batch, uint256[] memory _fees) internal {
        for (uint256 _i; _i < _batch.ofts.length; _i++) {
            IERC20(IOFT(_batch.ofts[_i]).token()).forceApprove(_batch.hop, _batch.amounts[_i]);
            IHopV2(_batch.hop).sendOFT{value: _fees[_i]}(
                _batch.ofts[_i],
                _batch.dstEids[_i],
                _batch.recipients[_i],
                _batch.amounts[_i],
                _batch.dstGases[_i],
                _batch.datas[_i]
            );
        }
    }

    function _sendHopV2BatchFromSender(HopV2SenderBatch memory _senderBatch, uint256[] memory _fees) internal {
        HopV2Batch memory batch = _senderBatch.batch;

        for (uint256 _i; _i < batch.ofts.length; _i++) {
            _senderBatch.tokens[_i].transferFrom(_senderBatch.senders[_i], address(this), batch.amounts[_i]);
            _senderBatch.tokens[_i].forceApprove(batch.hop, batch.amounts[_i]);
            IHopV2(batch.hop).sendOFT{value: _fees[_i]}(
                batch.ofts[_i],
                batch.dstEids[_i],
                batch.recipients[_i],
                batch.amounts[_i],
                batch.dstGases[_i],
                batch.datas[_i]
            );
        }
    }

    function withdrawOFT(IERC20 _token, address _beneficiary, uint256 _amount) external onlyOwner {
        _token.safeTransfer(_beneficiary, _amount);
    }

    function withdrawEth(address _beneficiary) external onlyOwner {
        (bool _success,) = payable(_beneficiary).call{value: address(this).balance}("");
        if (!_success) {
            revert WithdrawEthFailed();
        }
    }

    function approveToken(IERC20 _token, address _spender, uint256 _amount) external onlyOwner {
        _token.forceApprove(_spender, _amount);
    }

    // Admin

    function initialize(address _delegate) external initializer {
        __Ownable_init();
        _transferOwnership(_delegate);
    }
}
