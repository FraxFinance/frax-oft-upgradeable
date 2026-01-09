// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTAdapterUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTAdapterUpgradeable.sol";
import { OAppSenderUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/OAppSenderUpgradeable.sol";
import { SupplyTrackingModule } from "contracts/modules/SupplyTrackingModule.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract FraxOFTMintableAdapterUpgradeableTIP20 is OFTAdapterUpgradeable, SupplyTrackingModule {
    constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    function version() public pure returns (string memory) {
        return "1.1.0";
    }

    /// @dev This method is called specifically when deploying a new OFT
    function initialize(address _delegate) external initializer {
        __OFTAdapter_init(_delegate);
        __Ownable_init();
        _transferOwnership(_delegate);
    }

    /// @notice Recover all tokens to owner
    /// @dev added in v1.1.0
    function recover() external {
        uint256 balance = innerToken.balanceOf(address(this));
        if (balance == 0) return;

        innerToken.transfer(owner(), balance);
    }

    /// @notice Set the initial total supply for a given chain ID
    /// @dev added in v1.1.0
    function setInitialTotalSupply(uint32 _eid, uint256 _amount) external onlyOwner {
        _setInitialTotalSupply(_eid, _amount);
    }

    /// @dev overrides OFTAdapterUpgradeable.sol to burn the tokens from the sender/track supply
    /// @dev added in v1.1.0
    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        _addToTotalTransferTo(_dstEid, amountSentLD);

        ITIP20(address(innerToken)).transferFrom(msg.sender, address(this), amountSentLD);

        ITIP20(address(innerToken)).burn(amountSentLD);
    }

    /// @dev overrides OFTAdapterUpgradeable to mint the tokens to the sender/track supply
    /// @dev added in v1.1.0
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal override returns (uint256 amountReceivedLD) {
        _addToTotalTransferFrom(_srcEid, _amountLD);

        ITIP20(address(innerToken)).mint(_to, _amountLD);

        return _amountLD;
    }

    /// @inheritdoc OAppSenderUpgradeable
    function _lzSend(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        MessagingFee memory _fee,
        address _refundAddress
    ) internal override returns (MessagingReceipt memory receipt) {
        // If user's gas token is innerToken, swap to PATH_USD for LayerZero endpoint
        address userToken = StdPrecompiles.TIP_FEE_MANAGER.userTokens(msg.sender);
        if (userToken == address(innerToken)) {
            uint128 amountIn = uint128(_fee.nativeFee);
            // Approve StablecoinExchange to spend innerToken
            ITIP20(address(innerToken)).approve(address(StdPrecompiles.STABLECOIN_EXCHANGE), amountIn);
            // Swap innerToken for PATH_USD
            StdPrecompiles.STABLECOIN_EXCHANGE.swapExactAmountIn({
                tokenIn: address(innerToken),
                tokenOut: StdTokens.PATH_USD_ADDRESS,
                amountIn: amountIn,
                minAmountOut: amountIn
            });
        }

        // @dev Push corresponding fees to the endpoint, any excess is sent back to the _refundAddress from the endpoint.
        uint256 messageValue = _payNative(_fee.nativeFee);
        if (_fee.lzTokenFee > 0) _payLzToken(_fee.lzTokenFee);

        return
            endpoint.send{ value: messageValue }(
                // solhint-disable-next-line check-send-result
                MessagingParams(_dstEid, _getPeerOrRevert(_dstEid), _message, _options, _fee.lzTokenFee > 0),
                _refundAddress
            );
    }
}
