// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";
import { Origin } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppReceiver.sol";
import { SendParam, OFTLimit, OFTReceipt } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { FraxOFTUpgradeableTempo } from "contracts/FraxOFTUpgradeableTempo.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";
import { FraxOFTMintableAdapterUpgradeable } from "contracts/FraxOFTMintableAdapterUpgradeable.sol";
import { FraxOFTMintableAdapterUpgradeableTIP20 } from "contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol";
import { WFRAXTokenOFTUpgradeable } from "contracts/WFRAXTokenOFTUpgradeable.sol";
import { FrxUSDOFTUpgradeable } from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import { SFrxUSDOFTUpgradeable } from "contracts/frxUsd/SFrxUSDOFTUpgradeable.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";

/// @dev Minimal endpoint: free quotes, records the last outbound message.
contract SDCeilingEndpointMock {
    mapping(address => address) public delegates;
    bytes public lastMessage;
    uint64 public sendCount;

    function setDelegate(address _delegate) external {
        delegates[msg.sender] = _delegate;
    }

    /// @dev Read by the Tempo variants' constructors (EndpointV2Alt); nothing here uses it.
    function nativeToken() external pure returns (address) {
        return address(0);
    }

    function quote(MessagingParams calldata, address) external pure returns (MessagingFee memory) {
        return MessagingFee(0, 0);
    }

    function send(MessagingParams calldata _params, address) external payable returns (MessagingReceipt memory receipt) {
        lastMessage = _params.message;
        receipt.nonce = ++sendCount;
        receipt.guid = keccak256(abi.encode(msg.sender, receipt.nonce));
    }
}

contract SDCeilingOFTHarness is FraxOFTUpgradeable {
    constructor(address _endpoint) FraxOFTUpgradeable(_endpoint) {}

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

contract SDCeilingToken6 is ERC20Mock {
    constructor() ERC20Mock("Six", "SIX") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @notice OFT payloads carry the amount as a uint64 in shared decimals. The fork's _toSD reverts when an amount does
///         not fit, so a send above the ceiling fails instead of debiting the full amount and encoding only the low
///         64 bits (audit finding ZELLIC-BFHKMW).
contract SharedDecimalCeilingTest is Test {
    uint32 internal constant DST_EID = 30101;
    address internal constant PROXY_ADMIN = address(0x9999);
    uint256 internal constant EIP170_LIMIT = 24_576;

    address internal alice = vm.addr(0x41);
    address internal bob = vm.addr(0xb0b);

    SDCeilingEndpointMock internal endpoint;
    SDCeilingOFTHarness internal oft;

    /// @dev 1e12: 18 local decimals over 6 shared decimals
    uint256 internal rate;
    /// @dev type(uint64).max shared units in local decimals: the largest sendable amount, as quoteOFT advertises it.
    ///      One shared unit more is 2**64 shared units, which an unchecked narrowing encodes as 0.
    uint256 internal maxLD;

    function setUp() external {
        endpoint = new SDCeilingEndpointMock();
        SDCeilingOFTHarness implementation = new SDCeilingOFTHarness(address(endpoint));
        oft = SDCeilingOFTHarness(
            address(
                new TransparentUpgradeableProxy(
                    address(implementation),
                    PROXY_ADMIN,
                    abi.encodeCall(FraxOFTUpgradeable.initialize, ("Mock Frax", "mFRAX", address(this)))
                )
            )
        );
        oft.setPeer(DST_EID, _bytes32(bob));

        rate = oft.decimalConversionRate();
        maxLD = uint256(type(uint64).max) * rate;
    }

    function test_ToSD_RevertsExactlyAboveTheCeiling() external {
        assertEq(oft.toSD(maxLD), type(uint64).max);
        assertEq(oft.toSD(maxLD + rate - 1), type(uint64).max, "dust below the next shared unit still fits");

        _expectCeilingRevert();
        oft.toSD(maxLD + rate);

        // 2**65 + 5 shared units: an unchecked narrowing would encode 5
        _expectCeilingRevert();
        oft.toSD(((uint256(1) << 65) + 5) * rate);
    }

    function testFuzz_ToSD_RevertsExactlyAboveTheCeiling(uint256 _amountLD) external {
        _amountLD = bound(_amountLD, maxLD - 2 * rate, maxLD + 2 * rate);
        if (_amountLD / rate > type(uint64).max) {
            _expectCeilingRevert();
            oft.toSD(_amountLD);
        } else {
            assertEq(oft.toSD(_amountLD), _amountLD / rate);
        }
    }

    function test_Send_RevertsAboveTheCeilingAndSendsAtIt() external {
        oft.mint(alice, maxLD + rate);

        _expectCeilingRevert();
        vm.prank(alice);
        oft.send(_param(maxLD + rate, 0, ""), MessagingFee(0, 0), alice);

        vm.prank(alice);
        (, OFTReceipt memory receipt) = oft.send(_param(maxLD, maxLD, ""), MessagingFee(0, 0), alice);

        assertEq(receipt.amountSentLD, maxLD);
        assertEq(receipt.amountReceivedLD, maxLD);
        assertEq(oft.balanceOf(alice), rate);
        // bytes32 sendTo | uint64 amountSD
        _assertLastMessage(40, type(uint64).max);
    }

    function test_SendAndCall_RevertsAboveTheCeilingAndSendsAtIt() external {
        oft.mint(alice, maxLD + rate);

        _expectCeilingRevert();
        vm.prank(alice);
        oft.send(_param(maxLD + rate, 0, hex"01"), MessagingFee(0, 0), alice);

        vm.prank(alice);
        oft.send(_param(maxLD, maxLD, hex"01"), MessagingFee(0, 0), alice);

        // bytes32 sendTo | uint64 amountSD | bytes32 composeFrom | composeMsg
        _assertLastMessage(73, type(uint64).max);
    }

    function test_DustAboveTheCeiling_TrimsToIt() external {
        oft.mint(alice, maxLD + rate - 1);

        vm.prank(alice);
        (, OFTReceipt memory receipt) = oft.send(_param(maxLD + rate - 1, 0, ""), MessagingFee(0, 0), alice);

        assertEq(receipt.amountSentLD, maxLD);
        assertEq(oft.balanceOf(alice), rate - 1, "dust stays with the sender");
        _assertLastMessage(40, type(uint64).max);
    }

    function test_QuoteSend_AgreesWithSendAtTheBoundary() external {
        oft.quoteSend(_param(maxLD, 0, ""), false);

        _expectCeilingRevert();
        oft.quoteSend(_param(maxLD + rate, 0, ""), false);
    }

    /// @dev The ceiling is enforced where the amount is encoded. quoteOFT and debitView still answer for an oversize
    ///      amount, and quoteOFT reports the ceiling as maxAmountLD the same way it reports the outbound rate limit.
    function test_OnlyEncodingRejectsOversizeAmounts() external {
        (OFTLimit memory limit,, OFTReceipt memory receipt) = oft.quoteOFT(_param(maxLD + rate, 0, ""));
        assertEq(limit.maxAmountLD, maxLD);
        assertEq(receipt.amountReceivedLD, maxLD + rate);

        (, uint256 amountReceivedLD) = oft.debitView(maxLD + rate, 0, DST_EID);
        assertEq(amountReceivedLD, maxLD + rate);

        oft.buildMsgAndOptions(_param(maxLD, 0, ""), maxLD);
        _expectCeilingRevert();
        oft.buildMsgAndOptions(_param(maxLD + rate, 0, ""), maxLD + rate);
    }

    function test_LzReceive_CreditsTheCeiling() external {
        vm.prank(address(endpoint));
        oft.lzReceive(
            Origin({ srcEid: DST_EID, sender: _bytes32(bob), nonce: 1 }),
            bytes32(uint256(1)),
            abi.encodePacked(_bytes32(alice), type(uint64).max),
            address(0),
            ""
        );

        assertEq(oft.balanceOf(alice), maxLD);
    }

    function test_FrxUSD_EnforcesTheCeiling() external {
        FrxUSDOFTUpgradeable implementation = new FrxUSDOFTUpgradeable(address(endpoint));
        FrxUSDOFTUpgradeable frxUsd = FrxUSDOFTUpgradeable(
            address(
                new TransparentUpgradeableProxy(
                    address(implementation),
                    PROXY_ADMIN,
                    abi.encodeCall(FrxUSDOFTUpgradeable.initialize, (address(this)))
                )
            )
        );
        frxUsd.setPeer(DST_EID, _bytes32(bob));
        deal(address(frxUsd), alice, maxLD + rate, true);

        _expectCeilingRevert();
        vm.prank(alice);
        frxUsd.send(_param(maxLD + rate, 0, ""), MessagingFee(0, 0), alice);

        vm.prank(alice);
        frxUsd.send(_param(maxLD, maxLD, ""), MessagingFee(0, 0), alice);

        assertEq(frxUsd.balanceOf(alice), rate);
        assertEq(frxUsd.totalSupply(), rate);
        _assertLastMessage(40, type(uint64).max);
    }

    /// @dev A 6-decimal local token (the Tempo frxUSD shape) has rate 1, so the ceiling is plain uint64.max.
    function test_SixDecimalAdapter_CeilingIsUint64Max() external {
        SDCeilingToken6 token = new SDCeilingToken6();
        FraxOFTAdapterUpgradeable implementation = new FraxOFTAdapterUpgradeable(address(token), address(endpoint));
        FraxOFTAdapterUpgradeable adapter = FraxOFTAdapterUpgradeable(
            address(
                new TransparentUpgradeableProxy(
                    address(implementation),
                    PROXY_ADMIN,
                    abi.encodeCall(FraxOFTAdapterUpgradeable.initialize, (address(this)))
                )
            )
        );
        adapter.setPeer(DST_EID, _bytes32(bob));
        assertEq(adapter.decimalConversionRate(), 1);

        uint256 max = type(uint64).max;
        token.mint(alice, max + 1);
        vm.prank(alice);
        token.approve(address(adapter), type(uint256).max);

        _expectCeilingRevert();
        vm.prank(alice);
        adapter.send(_param(max + 1, 0, ""), MessagingFee(0, 0), alice);

        vm.prank(alice);
        adapter.send(_param(max, max, ""), MessagingFee(0, 0), alice);

        assertEq(token.balanceOf(address(adapter)), max);
        _assertLastMessage(40, type(uint64).max);
    }

    /// @dev Sizes match production under the default profile only; forge coverage builds unoptimized and fails this test.
    function test_Implementations_FitEIP170() external {
        SDCeilingToken6 token = new SDCeilingToken6();
        address lzEndpoint = address(endpoint);

        _assertFitsEIP170(address(new FrxUSDOFTUpgradeable(lzEndpoint)), "FrxUSDOFTUpgradeable");
        _assertFitsEIP170(address(new SFrxUSDOFTUpgradeable(lzEndpoint)), "SFrxUSDOFTUpgradeable");
        _assertFitsEIP170(address(new WFRAXTokenOFTUpgradeable(lzEndpoint)), "WFRAXTokenOFTUpgradeable");
        _assertFitsEIP170(address(new FraxOFTUpgradeable(lzEndpoint)), "FraxOFTUpgradeable");
        _assertFitsEIP170(address(new FraxOFTUpgradeableTempo(lzEndpoint)), "FraxOFTUpgradeableTempo");
        _assertFitsEIP170(address(new FraxOFTAdapterUpgradeable(address(token), lzEndpoint)), "FraxOFTAdapterUpgradeable");
        _assertFitsEIP170(
            address(new FraxOFTMintableAdapterUpgradeable(address(token), lzEndpoint)),
            "FraxOFTMintableAdapterUpgradeable"
        );
        _assertFitsEIP170(
            address(new FraxOFTMintableAdapterUpgradeableTIP20(address(token), lzEndpoint)),
            "FraxOFTMintableAdapterUpgradeableTIP20"
        );
    }

    /// @dev The fork's check is a bare require, so the revert has no data.
    function _expectCeilingRevert() internal {
        vm.expectRevert(bytes(""));
    }

    function _assertFitsEIP170(address _implementation, string memory _name) internal {
        assertLe(_implementation.code.length, EIP170_LIMIT, _name);
    }

    /// @dev OFT message layout: bytes32 sendTo | uint64 amountSD | [bytes32 composeFrom | composeMsg]
    function _assertLastMessage(uint256 _length, uint64 _amountSD) internal {
        bytes memory message = endpoint.lastMessage();
        assertEq(message.length, _length, "message length");
        uint64 amountSD;
        assembly {
            amountSD := shr(192, mload(add(message, 64)))
        }
        assertEq(amountSD, _amountSD, "amountSD");
    }

    function _param(uint256 _amountLD, uint256 _minAmountLD, bytes memory _composeMsg)
        internal
        view
        returns (SendParam memory)
    {
        return SendParam({
            dstEid: DST_EID,
            to: _bytes32(bob),
            amountLD: _amountLD,
            minAmountLD: _minAmountLD,
            extraOptions: "",
            composeMsg: _composeMsg,
            oftCmd: ""
        });
    }

    function _bytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
