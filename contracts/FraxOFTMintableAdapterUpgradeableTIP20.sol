// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTAdapterUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTAdapterUpgradeable.sol";
import { OAppSenderUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/OAppSenderUpgradeable.sol";
import { SupplyTrackingModule } from "contracts/modules/SupplyTrackingModule.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { ILZEndpointDollar } from "contracts/interfaces/vendor/layerzero/ILZEndpointDollar.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IOFT, SendParam, OFTReceipt } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Interface for EndpointV2Alt's nativeToken function
interface IEndpointV2Alt {
    function nativeToken() external view returns (address);
}

contract FraxOFTMintableAdapterUpgradeableTIP20 is OFTAdapterUpgradeable, SupplyTrackingModule {
    error NativeTokenUnavailable();
    error OFTAltCore__msg_value_not_zero(uint256 _msg_value);
    error NoSwappableWhitelistedToken(address userToken);

    ILZEndpointDollar public immutable nativeToken;

    /// @notice Emitted when ERC20 tokens are recovered
    event RecoveredERC20(address indexed token, uint256 amount);

    constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        nativeToken = ILZEndpointDollar(IEndpointV2Alt(_lzEndpoint).nativeToken());
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

    /// @notice Added to support tokens
    /// @param _tokenAddress The token to recover
    /// @param _tokenAmount The amount to recover
    function recoverERC20(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        // Only the owner address can ever receive the recovery withdrawal
        SafeERC20.safeTransfer(IERC20(_tokenAddress), owner(), _tokenAmount);
        emit RecoveredERC20(_tokenAddress, _tokenAmount);
    }

    /// @notice Set the initial total supply for a given chain ID
    /// @dev added in v1.1.0
    function setInitialTotalSupply(uint32 _eid, uint256 _amount) external onlyOwner {
        _setInitialTotalSupply(_eid, _amount);
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

    /// @inheritdoc OAppSenderUpgradeable
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

    /// @inheritdoc OAppSenderUpgradeable
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
