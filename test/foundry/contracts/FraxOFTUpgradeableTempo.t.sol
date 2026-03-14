// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTUpgradeableTempo } from "contracts/FraxOFTUpgradeableTempo.sol";
import { TempoAltTokenBase } from "contracts/base/TempoAltTokenBase.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { IStablecoinDEX } from "tempo-std/interfaces/IStablecoinDEX.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SendParam, OFTReceipt } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { OFTMsgCodec } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/libs/OFTMsgCodec.sol";
import { Origin } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppReceiver.sol";
import { TempoTestHelpers } from "test/foundry/helpers/TempoTestHelpers.sol";
import { LZTestHelperOz4, EndpointV2AltMockOz4 } from "test/helpers/LZTestHelperOz4.sol";

contract FraxOFTUpgradeableTempoTest is TempoTestHelpers, LZTestHelperOz4 {
    using OptionsBuilder for bytes;
    using OFTMsgCodec for bytes;

    FraxOFTUpgradeableTempo oft;
    EndpointV2AltMockOz4 lzEndpoint;

    address contractOwner = address(this);
    address alice = vm.addr(0x41);
    address bob = vm.addr(0xb0b);

    uint32 constant SRC_EID = 30100;
    uint32 constant DST_EID = 30101;

    function setUp() external {
        lzEndpoint = createAltEndpoint(SRC_EID, StdTokens.PATH_USD_ADDRESS);

        FraxOFTUpgradeableTempo implementation = new FraxOFTUpgradeableTempo(address(lzEndpoint));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(0x9999),
            abi.encodeWithSignature("initialize(string,string,address)", "Frax USD", "frxUSD", contractOwner)
        );
        oft = FraxOFTUpgradeableTempo(address(proxy));

        lzEndpoint.setDelegate(contractOwner);
        _grantPathUsdIssuerRole(address(this));
        StdTokens.PATH_USD.mint(address(this), 1_000_000e6);
    }

    function _setupPeer() internal {
        bytes32 peer = bytes32(uint256(uint160(address(0xdead))));
        vm.prank(contractOwner);
        oft.setPeer(DST_EID, peer);
    }

    function _buildSendParam(uint256 sendAmount) internal view returns (SendParam memory) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(100_000, 0);
        return
            SendParam({
                dstEid: DST_EID,
                to: bytes32(uint256(uint160(bob))),
                amountLD: sendAmount,
                minAmountLD: sendAmount,
                extraOptions: options,
                composeMsg: "",
                oftCmd: ""
            });
    }

    function _executeSend(address sender, uint256 sendAmount, uint256 nativeFee) internal {
        SendParam memory sendParam = _buildSendParam(sendAmount);
        vm.prank(sender);
        oft.send{ value: 0 }(sendParam, MessagingFee({ nativeFee: nativeFee, lzTokenFee: 0 }), sender);
    }

    function _executeSendWithSwap(address sender, uint256 sendAmount, uint256 nativeFee) internal {
        SendParam memory sendParam = _buildSendParam(sendAmount);
        vm.prank(sender);
        oft.send{ value: 0 }(sendParam, MessagingFee({ nativeFee: nativeFee, lzTokenFee: 0 }), sender);
    }

    function _deployTempoOFT(address endpointAddr) internal returns (FraxOFTUpgradeableTempo newOft) {
        FraxOFTUpgradeableTempo implementation = new FraxOFTUpgradeableTempo(endpointAddr);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(0x9999),
            abi.encodeWithSignature("initialize(string,string,address)", "Frax USD", "frxUSD", contractOwner)
        );
        newOft = FraxOFTUpgradeableTempo(address(proxy));
    }

    function _deliverToDst(
        FraxOFTUpgradeableTempo dstOft,
        EndpointV2AltMockOz4 dstEndpoint,
        address recipient,
        uint256 sendAmount
    ) internal {
        (bytes memory msgPayload, bool hasCompose) = OFTMsgCodec.encode(
            bytes32(uint256(uint160(recipient))),
            uint64(sendAmount / dstOft.decimalConversionRate()),
            ""
        );
        assertFalse(hasCompose, "compose not expected");

        Origin memory origin = Origin({
            srcEid: SRC_EID,
            sender: bytes32(uint256(uint160(address(oft)))),
            nonce: lzEndpoint.nonce()
        });

        vm.prank(address(dstEndpoint));
        dstOft.lzReceive(origin, bytes32(uint256(1)), msgPayload, address(0), "");
    }

    function test_AltEndpoint_PayNative_NoSwap_PathUsd() external {
        uint256 sendAmount = 1_000_000_000_000; // avoid dust
        uint256 nativeFee = 10e6;

        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);
        _setupPeer();

        deal(address(oft), alice, sendAmount);
        StdTokens.PATH_USD.mint(alice, nativeFee);

        vm.startPrank(alice);
        oft.approve(address(oft), type(uint256).max);
        StdTokens.PATH_USD.approve(address(oft), type(uint256).max);
        vm.stopPrank();

        // PATH_USD is whitelisted, so it gets transferred to OFT for wrapping
        vm.expectEmit(true, true, false, true, StdTokens.PATH_USD_ADDRESS);
        emit ITIP20.Transfer(alice, address(oft), nativeFee);

        _executeSend(alice, sendAmount, nativeFee);

        assertEq(lzEndpoint.nativeErc20().balanceOf(address(lzEndpoint)), nativeFee, "endpoint should receive LZEndpointDollar");
    }

    function test_AltEndpoint_PayNative_SwapToPathUsd() external {
        uint256 sendAmount = 1_000_000_000_000; // avoid dust
        uint256 nativeFee = 20_000e6;

        ITIP20 gasToken = _createTIP20WithDexPair("Other", "OTHER", keccak256("test_AltEndpoint_PayNative_SwapToPathUsd"));
        _setUserGasToken(alice, address(gasToken));
        _setupPeer();

        deal(address(oft), alice, sendAmount);
        gasToken.mint(alice, nativeFee);
        _addDexLiquidity(address(gasToken), nativeFee * 2);

        vm.startPrank(alice);
        oft.approve(address(oft), type(uint256).max);
        gasToken.approve(address(oft), type(uint256).max);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true, address(gasToken));
        emit ITIP20.Transfer(alice, address(oft), nativeFee);

        vm.expectEmit(true, true, false, true, address(gasToken));
        emit ITIP20.Approval(address(oft), address(StdPrecompiles.STABLECOIN_DEX), nativeFee);

        vm.expectEmit(false, true, true, true, address(StdPrecompiles.STABLECOIN_DEX));
        emit IStablecoinDEX.OrderFilled({
            orderId: 0,
            maker: address(0x1111),
            taker: address(oft),
            amountFilled: uint128(nativeFee),
            partialFill: true
        });

        _executeSendWithSwap(alice, sendAmount, nativeFee);

        assertEq(lzEndpoint.nativeErc20().balanceOf(address(lzEndpoint)), nativeFee, "endpoint should receive LZEndpointDollar");
    }

    function test_AltEndpoint_CrossChain_SendReceive_PathUsdNative() external {
        uint256 sendAmount = 1_000_000_000_000;
        uint256 nativeFee = 10e6;

        // Source setup (already deployed in setUp)
        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);

        // Destination setup
        EndpointV2AltMockOz4 dstEndpoint = createAltEndpoint(DST_EID, StdTokens.PATH_USD_ADDRESS);
        FraxOFTUpgradeableTempo dstOft = _deployTempoOFT(address(dstEndpoint));
        dstEndpoint.setDelegate(contractOwner);

        // Wire peers
        vm.prank(contractOwner);
        oft.setPeer(DST_EID, bytes32(uint256(uint160(address(dstOft)))));
        vm.prank(contractOwner);
        dstOft.setPeer(SRC_EID, bytes32(uint256(uint160(address(oft)))));

        // Fund sender
        deal(address(oft), alice, sendAmount);
        StdTokens.PATH_USD.mint(alice, nativeFee);

        vm.startPrank(alice);
        oft.approve(address(oft), type(uint256).max);
        StdTokens.PATH_USD.approve(address(oft), type(uint256).max);
        vm.stopPrank();

        // Send from source to destination
        _executeSend(alice, sendAmount, nativeFee);

        _deliverToDst(dstOft, dstEndpoint, bob, sendAmount);

        assertEq(dstOft.balanceOf(bob), sendAmount, "dst should mint to recipient");
        assertEq(lzEndpoint.nativeErc20().balanceOf(address(lzEndpoint)), nativeFee, "src endpoint should hold LZEndpointDollar fee");
    }

    // ---------------------------------------------------
    // _quote Override Tests
    // ---------------------------------------------------

    /// @dev Helper to build a SendParam suitable for quoting (minAmountLD = 0 to avoid slippage checks)
    function _buildQuoteSendParam(uint256 sendAmount) internal view returns (SendParam memory) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(100_000, 0);
        return
            SendParam({
                dstEid: DST_EID,
                to: bytes32(uint256(uint160(bob))),
                amountLD: sendAmount,
                minAmountLD: 0, // Use 0 for quote to avoid slippage check
                extraOptions: options,
                composeMsg: "",
                oftCmd: ""
            });
    }

    /// @dev When user's gas token is the endpoint's native token, quoteSend returns fee without conversion
    function test_QuoteSend_ReturnsNativeFee_WhenUserGasTokenIsEndpointNative() external {
        uint256 sendAmount = 100e6;
        uint256 expectedFee = 10e6; // mockNativeFee default

        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);
        _setupPeer();

        SendParam memory sendParam = _buildQuoteSendParam(sendAmount);
        vm.prank(alice);
        MessagingFee memory fee = oft.quoteSend(sendParam, false);

        assertEq(fee.nativeFee, expectedFee, "Fee should be in endpoint native token terms (no conversion)");
        assertEq(fee.lzTokenFee, 0, "lzTokenFee should be 0");
    }

    /// @dev quoteSend with zero nativeFee returns zero (no conversion needed)
    function test_QuoteSend_ReturnsZero_WhenNativeFeeIsZero() external {
        uint256 sendAmount = 100e6;

        lzEndpoint.setMockNativeFee(0);
        // Use a different gas token - PATH_USD works fine for zero fee test
        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);
        _setupPeer();

        SendParam memory sendParam = _buildQuoteSendParam(sendAmount);
        vm.prank(alice);
        MessagingFee memory fee = oft.quoteSend(sendParam, false);

        assertEq(fee.nativeFee, 0, "Fee should be 0 when no native fee required");
    }

    /// @dev When user's gas token is non-whitelisted, quoteSend returns fee in endpoint-native units
    function test_QuoteSend_ReturnsEndpointNativeFee_WhenUserGasTokenIsNonWhitelisted() external {
        uint256 sendAmount = 100e6;
        uint256 nativeFee = 20_000e6;

        lzEndpoint.setMockNativeFee(nativeFee);

        ITIP20 gasToken = _createTIP20WithDexPair("QuoteGas", "QGAS", keccak256("test_QuoteSend_NonWhitelisted"));
        _setUserGasToken(alice, address(gasToken));
        _addDexLiquidity(address(gasToken), nativeFee * 2);
        _setupPeer();

        SendParam memory sendParam = _buildQuoteSendParam(sendAmount);
        vm.prank(alice);
        MessagingFee memory fee = oft.quoteSend(sendParam, false);

        // Fee stays in endpoint-native units — use quoteUserTokenFee() for user token cost
        assertEq(fee.nativeFee, nativeFee, "Fee should remain in endpoint-native units (no conversion)");
        assertEq(fee.lzTokenFee, 0, "lzTokenFee should be 0");
    }

    // ---------------------------------------------------
    // quoteUserTokenFee Tests
    // ---------------------------------------------------

    /// @dev quoteUserTokenFee returns the user's gas token amount for a given endpoint fee
    function test_QuoteUserTokenFee_ReturnsUserTokenAmount() external {
        uint256 endpointFee = 20_000e6;

        ITIP20 gasToken = _createTIP20WithDexPair("FeeGas", "FGAS", keccak256("test_QuoteUserTokenFee"));
        _addDexLiquidity(address(gasToken), endpointFee * 2);

        uint256 userTokenAmount = oft.quoteUserTokenFee(address(gasToken), endpointFee);

        assertGe(userTokenAmount, endpointFee, "User token amount should be >= endpoint fee");
    }

    /// @dev quoteUserTokenFee returns endpoint fee directly for whitelisted tokens
    function test_QuoteUserTokenFee_ReturnsEndpointFee_WhenWhitelisted() external {
        uint256 endpointFee = 10e6;

        uint256 userTokenAmount = oft.quoteUserTokenFee(StdTokens.PATH_USD_ADDRESS, endpointFee);

        assertEq(userTokenAmount, endpointFee, "Whitelisted token should return endpoint fee 1:1");
    }

    /// @dev quoteUserTokenFee returns 0 for zero fee
    function test_QuoteUserTokenFee_ReturnsZero_WhenFeeIsZero() external {
        uint256 userTokenAmount = oft.quoteUserTokenFee(StdTokens.PATH_USD_ADDRESS, 0);

        assertEq(userTokenAmount, 0, "Should return 0 for zero fee");
    }

    // ---------------------------------------------------
    // send() Override Tests
    // ---------------------------------------------------

    /// @dev send() reverts when msg.value > 0 (EndpointV2Alt uses ERC20 for gas, not native ETH)
    function test_Send_RevertsWhenMsgValueNonZero() external {
        uint256 sendAmount = 1_000_000_000_000; // avoid dust
        uint256 nativeFee = 10e6;

        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);
        _setupPeer();

        deal(address(oft), alice, sendAmount);
        StdTokens.PATH_USD.mint(alice, nativeFee);

        vm.startPrank(alice);
        oft.approve(address(oft), type(uint256).max);
        StdTokens.PATH_USD.approve(address(oft), type(uint256).max);
        vm.stopPrank();

        SendParam memory sendParam = _buildSendParam(sendAmount);

        // Attempt to send with msg.value > 0 should revert
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                TempoAltTokenBase.OFTAltCore__msg_value_not_zero.selector,
                1 ether
            )
        );
        oft.send{ value: 1 ether }(sendParam, MessagingFee({ nativeFee: nativeFee, lzTokenFee: 0 }), alice);
    }

    /// @dev send() succeeds when msg.value == 0 and returns valid receipts
    function test_Send_SucceedsWhenMsgValueZero_ReturnsValidReceipts() external {
        uint256 sendAmount = 1_000_000_000_000; // avoid dust
        uint256 nativeFee = 10e6;

        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);
        _setupPeer();

        deal(address(oft), alice, sendAmount);
        StdTokens.PATH_USD.mint(alice, nativeFee);

        vm.startPrank(alice);
        oft.approve(address(oft), type(uint256).max);
        StdTokens.PATH_USD.approve(address(oft), type(uint256).max);
        vm.stopPrank();

        SendParam memory sendParam = _buildSendParam(sendAmount);

        // Should succeed with msg.value == 0 and return valid receipts
        vm.prank(alice);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) = oft.send{ value: 0 }(
            sendParam,
            MessagingFee({ nativeFee: nativeFee, lzTokenFee: 0 }),
            alice
        );

        // Verify receipts are valid
        assertGt(uint256(msgReceipt.guid), 0, "guid should be non-zero");
        assertEq(oftReceipt.amountSentLD, sendAmount, "amountSentLD should match");
        assertEq(oftReceipt.amountReceivedLD, sendAmount, "amountReceivedLD should match");
    }
}
