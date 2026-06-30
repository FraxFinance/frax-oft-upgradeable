// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";
import { SendParam, OFTLimit } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";
import { RateLimiterModule } from "contracts/modules/RateLimiterModule.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";

contract EndpointV2MockLite {
    mapping(address => address) public delegates;

    function setDelegate(address _delegate) external {
        delegates[msg.sender] = _delegate;
    }
}

contract FraxOFTUpgradeableRateLimitHarness is FraxOFTUpgradeable {
    constructor(address _lzEndpoint) FraxOFTUpgradeable(_lzEndpoint) {}

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    function debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) external returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        return _debit(_amountLD, _minAmountLD, _dstEid);
    }

    function credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) external returns (uint256 amountReceivedLD) {
        return _credit(_to, _amountLD, _srcEid);
    }
}

contract FraxOFTAdapterUpgradeableRateLimitHarness is FraxOFTAdapterUpgradeable {
    constructor(address _token, address _lzEndpoint) FraxOFTAdapterUpgradeable(_token, _lzEndpoint) {}

    function debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) external returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        return _debit(_amountLD, _minAmountLD, _dstEid);
    }

    function credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) external returns (uint256 amountReceivedLD) {
        return _credit(_to, _amountLD, _srcEid);
    }
}

contract RateLimiterModuleTest is Test {
    uint32 internal constant DST_EID = 30101;
    uint32 internal constant SRC_EID = 30252;

    address internal constant PROXY_ADMIN = address(0x9999);

    address internal owner = address(this);
    address internal alice = vm.addr(0x41);
    address internal bob = vm.addr(0xb0b);

    EndpointV2MockLite internal endpoint;
    FraxOFTUpgradeableRateLimitHarness internal oft;
    FraxOFTAdapterUpgradeableRateLimitHarness internal adapter;
    ERC20Mock internal token;

    function setUp() external {
        endpoint = new EndpointV2MockLite();
        oft = _deployOFT();
        token = new ERC20Mock("Mock Token", "MOCK");
        adapter = _deployAdapter(address(token));

        oft.mint(alice, 1_000e18);
        token.mint(alice, 1_000e18);

        vm.prank(alice);
        token.approve(address(adapter), type(uint256).max);
    }

    function test_OFTOutboundRateLimit_RevertsWhenCapacityExceeded() external {
        oft.setDefaultRateLimitConfig(_config(100e18, 1 hours, 0, 0));

        vm.prank(alice);
        oft.debit(60e18, 60e18, DST_EID);

        assertEq(oft.outboundRateLimitAvailable(DST_EID), 40e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiterModule.RateLimitExceeded.selector,
                DST_EID,
                true,
                41e18,
                40e18
            )
        );
        vm.prank(alice);
        oft.debit(41e18, 41e18, DST_EID);
    }

    function test_OFTOutboundRateLimit_RefillsLinearly() external {
        oft.setDefaultRateLimitConfig(_config(100e18, 100, 0, 0));

        vm.prank(alice);
        oft.debit(100e18, 100e18, DST_EID);

        assertEq(oft.outboundRateLimitAvailable(DST_EID), 0);

        vm.warp(block.timestamp + 50);
        assertEq(oft.outboundRateLimitAvailable(DST_EID), 50e18);

        vm.prank(alice);
        oft.debit(50e18, 50e18, DST_EID);

        assertEq(oft.outboundRateLimitAvailable(DST_EID), 0);
    }

    function test_OFTInboundRateLimit_RevertsThenRefills() external {
        oft.setDefaultRateLimitConfig(_config(0, 0, 75e18, 100));

        oft.credit(bob, 75e18, SRC_EID);
        assertEq(oft.balanceOf(bob), 75e18);
        assertEq(oft.inboundRateLimitAvailable(SRC_EID), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiterModule.RateLimitExceeded.selector,
                SRC_EID,
                false,
                1e18,
                0
            )
        );
        oft.credit(bob, 1e18, SRC_EID);

        vm.warp(block.timestamp + 100);
        oft.credit(bob, 75e18, SRC_EID);
        assertEq(oft.balanceOf(bob), 150e18);
    }

    function test_OFTQuoteOFT_ReportsCurrentOutboundCapacity() external {
        oft.setDefaultRateLimitConfig(_config(10e18, 1 hours, 0, 0));

        vm.prank(alice);
        oft.debit(2.5e18, 2.5e18, DST_EID);

        SendParam memory sendParam = SendParam({
            dstEid: DST_EID,
            to: bytes32(uint256(uint160(bob))),
            amountLD: 20e18,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        (OFTLimit memory limit,,) = oft.quoteOFT(sendParam);
        assertEq(limit.maxAmountLD, 7.5e18);
    }

    function test_AdapterRateLimits_ApplyOnDebitAndCredit() external {
        adapter.setDefaultRateLimitConfig(_config(100e18, 1 hours, 50e18, 1 hours));

        vm.prank(alice);
        adapter.debit(60e18, 60e18, DST_EID);

        assertEq(token.balanceOf(address(adapter)), 60e18);
        assertEq(adapter.outboundRateLimitAvailable(DST_EID), 40e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiterModule.RateLimitExceeded.selector,
                DST_EID,
                true,
                41e18,
                40e18
            )
        );
        vm.prank(alice);
        adapter.debit(41e18, 41e18, DST_EID);

        adapter.credit(bob, 50e18, SRC_EID);
        assertEq(token.balanceOf(bob), 50e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiterModule.RateLimitExceeded.selector,
                SRC_EID,
                false,
                1e18,
                0
            )
        );
        adapter.credit(bob, 1e18, SRC_EID);
    }

    function _deployOFT() internal returns (FraxOFTUpgradeableRateLimitHarness deployed) {
        FraxOFTUpgradeableRateLimitHarness implementation = new FraxOFTUpgradeableRateLimitHarness(address(endpoint));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            PROXY_ADMIN,
            abi.encodeWithSelector(FraxOFTUpgradeable.initialize.selector, "Mock Frax", "mFRAX", owner)
        );
        return FraxOFTUpgradeableRateLimitHarness(address(proxy));
    }

    function _deployAdapter(address _token) internal returns (FraxOFTAdapterUpgradeableRateLimitHarness deployed) {
        FraxOFTAdapterUpgradeableRateLimitHarness implementation = new FraxOFTAdapterUpgradeableRateLimitHarness(
            _token,
            address(endpoint)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            PROXY_ADMIN,
            abi.encodeWithSelector(FraxOFTAdapterUpgradeable.initialize.selector, owner)
        );
        return FraxOFTAdapterUpgradeableRateLimitHarness(address(proxy));
    }

    function _config(
        uint256 _outboundLimit,
        uint32 _outboundWindow,
        uint256 _inboundLimit,
        uint32 _inboundWindow
    ) internal pure returns (RateLimiterModule.RateLimitConfig memory config) {
        config = RateLimiterModule.RateLimitConfig({
            overrideDefaultConfig: false,
            outboundEnabled: _outboundLimit != 0,
            inboundEnabled: _inboundLimit != 0,
            outboundLimit: _outboundLimit,
            inboundLimit: _inboundLimit,
            outboundWindow: _outboundWindow,
            inboundWindow: _inboundWindow
        });
    }
}
