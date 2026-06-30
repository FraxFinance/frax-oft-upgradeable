// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTAdapterUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTAdapterUpgradeable.sol";
import { SendParam, OFTLimit, OFTFeeDetail, OFTReceipt } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { RateLimiterModule } from "contracts/modules/RateLimiterModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FraxOFTAdapterUpgradeable is OFTAdapterUpgradeable, RateLimiterModule {
    using SafeERC20 for IERC20;

    constructor(
        address _token,
        address _lzEndpoint
    ) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    function version() public pure returns (string memory) {
        return "1.0.1";
    }

    // Admin

    function initialize(address _delegate) external initializer {
        __OFTCore_init(_delegate);
        __Ownable_init();
        _transferOwnership(_delegate);
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

    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        _consumeOutboundRateLimit(_dstEid, amountSentLD);
        innerToken.safeTransferFrom(msg.sender, address(this), amountSentLD);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal override returns (uint256 amountReceivedLD) {
        _consumeInboundRateLimit(_srcEid, _amountLD);
        innerToken.safeTransfer(_to, _amountLD);
        return _amountLD;
    }
}
