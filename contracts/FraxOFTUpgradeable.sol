// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTUpgradeable.sol";
import { SendParam, OFTLimit, OFTFeeDetail, OFTReceipt } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import {EIP3009Module} from "contracts/modules/EIP3009Module.sol";
import {PermitModule} from "contracts/modules/PermitModule.sol";
import {RateLimiterModule} from "contracts/modules/RateLimiterModule.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract FraxOFTUpgradeable is OFTUpgradeable, EIP3009Module, PermitModule, RateLimiterModule {
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    function version() public pure returns (string memory) {
        return "1.1.0";
    }

    //==============================================================================
    // Admin
    //==============================================================================

    /// @dev This method is called specifically when deploying a new OFT
    function initialize(string memory _name, string memory _symbol, address _delegate) external reinitializer(3) {
        __EIP712_init(_name, version());
        __OFT_init(_name, _symbol, _delegate);
        __Ownable_init();
        _transferOwnership(_delegate);
    }

    /// @dev This method is called specifically when upgrading an existing OFT
    function initializeV110() external reinitializer(3) {
        __EIP712_init(name(), version());
    }

    //==============================================================================
    // Helper view
    //==============================================================================

    function toLD(uint64 _amountSD) external view returns (uint256 amountLD) {
        return _toLD(_amountSD);
    }

    function toSD(uint256 _amountLD) external view returns (uint64 amountSD) {
        return _toSD(_amountLD);
    }

    function removeDust(uint256 _amountLD) public view returns (uint256 amountLD) {
        return _removeDust(_amountLD);
    }

    function debitView(uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid) external view returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        /// @dev: _dstEid is unused in _debitView
        return _debitView(_amountLD, _minAmountLD, _dstEid);
    }

    function buildMsgAndOptions(
        SendParam calldata _sendParam,
        uint256 _amountLD
    ) external view returns (bytes memory message, bytes memory options) {
        return _buildMsgAndOptions(_sendParam, _amountLD);
    }

    function quoteOFT(
        SendParam calldata _sendParam
    )
        external
        view
        override
        returns (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt)
    {
        uint256 minAmountLD = 0;
        uint256 maxAmountLD = _removeDust(_rateLimitedMaxAmountLD(_sendParam.dstEid));
        oftLimit = OFTLimit(minAmountLD, maxAmountLD);

        oftFeeDetails = new OFTFeeDetail[](0);

        (uint256 amountSentLD, uint256 amountReceivedLD) = _debitView(
            _sendParam.amountLD,
            _sendParam.minAmountLD,
            _sendParam.dstEid
        );
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);
    }

    //==============================================================================
    // Overrides
    //==============================================================================

    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        _consumeOutboundRateLimit(_dstEid, amountSentLD);
        _burn(msg.sender, amountSentLD);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal override returns (uint256 amountReceivedLD) {
        _consumeInboundRateLimit(_srcEid, _amountLD);
        _mint(_to, _amountLD);
        return _amountLD;
    }

    /// @dev supports EIP3009
    function _transfer(address from, address to, uint256 amount) internal override(EIP3009Module, ERC20Upgradeable) {
        return ERC20Upgradeable._transfer(from, to, amount);
    }

    /// @dev supports EIP2612
    function _approve(address owner, address spender, uint256 amount) internal override(PermitModule, ERC20Upgradeable) {
        return ERC20Upgradeable._approve(owner, spender, amount);
    }
}
