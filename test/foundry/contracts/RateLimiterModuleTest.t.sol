// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";
import { SendParam, OFTLimit } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";
import { RateLimiterModule } from "contracts/modules/RateLimiterModule.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";
import { SetRateLimits, IRateLimitedOFT } from "scripts/DeployFraxOFTProtocol/inherited/SetRateLimits.s.sol";
import { L0Config } from "scripts/L0Constants.sol";

contract ERC20Mock6 is ERC20Mock {
    constructor() ERC20Mock("Six", "SIX") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

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

    /// @notice With rate limits off, the quoted maximum is the largest amount representable in
    ///         shared decimals expressed in the token's OWN local decimals: `uint64.max * 1e12`
    ///         for an 18dp token but plain `uint64.max` for a 6dp one (Tempo's TIP-20 frxUSD).
    function test_QuoteOFTMax_FollowsDecimalConversionRate() external {
        SendParam memory sendParam;
        sendParam.dstEid = DST_EID;

        (OFTLimit memory lim18,,) = oft.quoteOFT(sendParam);
        assertEq(lim18.maxAmountLD, uint256(type(uint64).max) * 1e12, "18dp ceiling");

        FraxOFTAdapterUpgradeableRateLimitHarness six = _deployAdapter(address(new ERC20Mock6()));
        assertEq(six.decimalConversionRate(), 1, "precondition: 6dp local == 6dp shared");
        (OFTLimit memory lim6,,) = six.quoteOFT(sendParam);
        assertEq(lim6.maxAmountLD, uint256(type(uint64).max), "6dp ceiling must not carry the 18dp multiplier");
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

    // ── A default change settles inheriting EIDs under the outgoing default ─────────

    /// @notice Swapping the default must not re-decay time that elapsed under the old one. A full
    ///       bucket, 2h into a 30-day window, keeps all but 2h of decay when the window becomes 1h.
    function test_DefaultConfigChange_SettlesInheritingEidsUnderOutgoingDefault() external {
        oft.setDefaultRateLimitConfig(_config(1_000e18, 30 days, 0, 0));
        vm.prank(alice);
        oft.debit(1_000e18, 1_000e18, DST_EID);
        skip(2 hours);

        oft.setDefaultRateLimitConfig(_config(1_000e18, 1 hours, 0, 0));

        uint256 decayedUnderOldDefault = (1_000e18 * 2 hours) / uint256(30 days);
        assertEq(oft.outboundRateLimitAvailable(DST_EID), decayedUnderOldDefault, "only 2h of real decay");

        skip(1 hours); // from here the new 1h window applies, so the bucket drains completely
        assertEq(oft.outboundRateLimitAvailable(DST_EID), 1_000e18);
    }

    /// @notice An EID first written by a checkpoint, with no usage yet, is still tracked: its later
    ///         usage is settled on the next default change like any other inheriting EID.
    function test_DefaultConfigChange_SettlesEidFirstWrittenByCheckpoint() external {
        oft.setDefaultRateLimitConfig(_config(1_000e18, 30 days, 0, 0));
        uint32[] memory eids = new uint32[](1);
        eids[0] = DST_EID;
        oft.checkpointRateLimits(eids); // empty state, but stamps lastUpdated

        vm.prank(alice);
        oft.debit(1_000e18, 1_000e18, DST_EID);
        skip(2 hours);
        oft.setDefaultRateLimitConfig(_config(1_000e18, 1 hours, 0, 0));

        assertEq(oft.outboundRateLimitAvailable(DST_EID), (1_000e18 * 2 hours) / uint256(30 days));
    }

    /// @notice An EID with its own override is not touched by a default change.
    function test_DefaultConfigChange_LeavesOverriddenEidAlone() external {
        _setOverride(DST_EID, _config(1_000e18, 30 days, 0, 0));
        vm.prank(alice);
        oft.debit(1_000e18, 1_000e18, DST_EID);
        skip(2 hours);

        oft.setDefaultRateLimitConfig(_config(1_000e18, 1 hours, 0, 0));

        assertEq(oft.rateLimitConfig(DST_EID).outboundWindow, 30 days, "still on its override");
        assertEq(oft.outboundRateLimitAvailable(DST_EID), (1_000e18 * 2 hours) / uint256(30 days));
    }

    // ── A disabled direction drains instead of freezing ──────────────────────────

    /// @notice Disabling inbound by zeroing its limit and window, then routing outbound traffic for 30
    ///         days, used to leave the inbound bucket exactly as full as when it was paused: the shared
    ///         lastUpdated advanced while a zero rate decayed nothing. Re-enabling must find it empty.
    function test_DisabledDirection_DrainsInsteadOfFreezing() external {
        _setOverride(SRC_EID, _config(1_000e18, 1 days, 1_000e18, 1 days));
        oft.credit(bob, 1_000e18, SRC_EID);
        assertEq(oft.inboundRateLimitAvailable(SRC_EID), 0, "inbound bucket full");

        _setOverride(SRC_EID, _config(1_000e18, 1 days, 0, 0)); // inbound off
        for (uint256 d; d < 30; ++d) {
            skip(1 days);
            vm.prank(alice);
            oft.debit(1e18, 1e18, SRC_EID); // routine outbound traffic on the same EID
        }

        _setOverride(SRC_EID, _config(1_000e18, 1 days, 1_000e18, 1 days)); // inbound back on
        assertEq(oft.inboundRateLimitAvailable(SRC_EID), 1_000e18, "re-enabled direction starts empty");
        oft.credit(bob, 1_000e18, SRC_EID);
    }

    /// @notice Disabling only the flag, with the limit and window kept, also resets: the flag decides.
    function test_DisabledFlagWithRateKept_ResetsOnReenable() external {
        _setOverride(SRC_EID, _config(0, 0, 1_000e18, 1 days));
        oft.credit(bob, 1_000e18, SRC_EID);

        RateLimiterModule.RateLimitConfig memory paused = _config(0, 0, 1_000e18, 1 days);
        paused.inboundEnabled = false;
        _setOverride(SRC_EID, paused);
        skip(12 hours);

        _setOverride(SRC_EID, _config(0, 0, 1_000e18, 1 days));
        assertEq(oft.inboundRateLimitAvailable(SRC_EID), 1_000e18, "re-enabled direction starts empty");
    }

    /// @notice Two lanes on the same timeline, one disabled with zeroed fields and one with its limit and
    ///         window kept, come back identical.
    function test_DisabledDirection_ZeroedAndRetainedFieldsAgree() external {
        uint32 other = 30184;
        _setOverride(DST_EID, _config(100e18, 100, 0, 0));
        _setOverride(other, _config(100e18, 100, 0, 0));
        vm.startPrank(alice);
        oft.debit(100e18, 100e18, DST_EID);
        oft.debit(100e18, 100e18, other);
        vm.stopPrank();
        skip(5);

        RateLimiterModule.RateLimitConfig memory retained = _config(100e18, 100, 0, 0);
        retained.outboundEnabled = false;
        _setOverride(DST_EID, _config(0, 0, 0, 0));
        _setOverride(other, retained);
        skip(10);

        _setOverride(DST_EID, _config(100e18, 100, 0, 0));
        _setOverride(other, _config(100e18, 100, 0, 0));
        assertEq(oft.outboundRateLimitAvailable(DST_EID), 100e18, "zeroed");
        assertEq(oft.outboundRateLimitAvailable(other), 100e18, "retained");
    }

    /// @notice The global switch stops consumption without settling: usage keeps decaying meanwhile.
    function test_GlobalDisable_DecayContinues() external {
        oft.setDefaultRateLimitConfig(_config(100e18, 100, 0, 0));
        vm.prank(alice);
        oft.debit(100e18, 100e18, DST_EID);

        oft.setRateLimitGlobalConfig(RateLimiterModule.RateLimitGlobalConfig({ isGloballyDisabled: true }));
        skip(50);
        oft.setRateLimitGlobalConfig(RateLimiterModule.RateLimitGlobalConfig({ isGloballyDisabled: false }));

        assertEq(oft.outboundRateLimitAvailable(DST_EID), 50e18);
    }

    // ── Transitions settle under the old rate and fit usage to the new limit ─────

    /// @notice A drained 100-per-100s bucket, 10s later, carries 90 of usage into a 1,000-per-10s default.
    function test_DefaultConfigChange_FasterReplacementKeepsCarriedUsage() external {
        oft.setDefaultRateLimitConfig(_config(100e18, 100, 0, 0));
        vm.prank(alice);
        oft.debit(100e18, 100e18, DST_EID);
        skip(10);

        oft.setDefaultRateLimitConfig(_config(1_000e18, 10, 0, 0));
        assertEq(oft.outboundRateLimitAvailable(DST_EID), 910e18);
    }

    /// @notice Half-decayed usage under a fast default drains at the slower rate after the change.
    function test_DefaultConfigChange_SlowerReplacementCarriesUsage() external {
        oft.setDefaultRateLimitConfig(_config(100e18, 10, 0, 0));
        vm.prank(alice);
        oft.debit(100e18, 100e18, DST_EID);
        skip(5);

        oft.setDefaultRateLimitConfig(_config(100e18, 100, 0, 0));
        assertEq(oft.outboundRateLimitAvailable(DST_EID), 50e18, "50 carried");
        skip(25);
        assertEq(oft.outboundRateLimitAvailable(DST_EID), 75e18, "slow rate applies");
        skip(25);
        assertEq(oft.outboundRateLimitAvailable(DST_EID), 100e18);
    }

    /// @notice Tightening a limit below current usage clamps it to the new limit, so a lane whose other
    ///         direction keeps writing state refills on the same schedule as a quiet one.
    function test_LimitDecrease_QuietAndBusyLanesRefillAlike() external {
        uint32 busy = SRC_EID;
        oft.mint(alice, 1_000e18); // setUp mints one lane's worth
        oft.setDefaultRateLimitConfig(_config(1_000e18, 1 days, 1_000e18, 1 days));
        vm.startPrank(alice);
        oft.debit(1_000e18, 1_000e18, DST_EID);
        oft.debit(1_000e18, 1_000e18, busy);
        vm.stopPrank();

        oft.setDefaultRateLimitConfig(_config(100e18, 1 days, 1_000e18, 1 days));
        assertEq(oft.storedRateLimitState(DST_EID).outboundUsage, 100e18, "clamped to the new limit");

        skip(12 hours);
        oft.credit(bob, 1e18, busy); // inbound delivery re-anchors lastUpdated
        assertEq(oft.outboundRateLimitAvailable(DST_EID), 50e18, "quiet, half a window");
        assertEq(oft.outboundRateLimitAvailable(busy), 50e18, "busy, half a window");

        skip(12 hours);
        oft.credit(bob, 1e18, busy);
        assertEq(oft.outboundRateLimitAvailable(DST_EID), 100e18);
        assertEq(oft.outboundRateLimitAvailable(busy), 100e18);
    }

    /// @notice A per-EID override that tightens the limit clamps carried usage the same way.
    function test_OverrideTightening_ClampsUsage() external {
        oft.setDefaultRateLimitConfig(_config(1_000e18, 1 days, 0, 0));
        vm.prank(alice);
        oft.debit(1_000e18, 1_000e18, DST_EID);

        _setOverride(DST_EID, _config(100e18, 1 days, 0, 0));
        assertEq(oft.storedRateLimitState(DST_EID).outboundUsage, 100e18);
        skip(1 days);
        assertEq(oft.outboundRateLimitAvailable(DST_EID), 100e18, "one window to refill");
    }

    /// @notice The default setter settles every inheriting lane; 128 lanes with usage stay well in budget.
    function test_DefaultConfigChange_GasBoundAt128Lanes() external {
        oft.setDefaultRateLimitConfig(_config(1_000e18, 1 days, 1_000e18, 1 days));
        for (uint32 i; i < 128; ++i) {
            oft.credit(bob, 1e18, 40_000 + i);
        }
        skip(1);

        uint256 gasBefore = gasleft();
        oft.setDefaultRateLimitConfig(_config(1_000e18, 2 days, 1_000e18, 2 days));
        uint256 used = gasBefore - gasleft();
        assertEq(_trackedEidCount(), 128);
        assertLt(used, 2_000_000, "settlement loop gas");
    }

    // ── Each enabled direction recovers at least one base unit per second ───────

    /// @notice Both setters reject an enabled direction whose limit is below its window, including Zellic's
    ///         1-per-2s proof-of-concept config, and accept exactly one unit per second.
    function test_RejectsRecoveryBelowOneUnitPerSecond() external {
        _expectBothSettersReject(_config(1, 2, 0, 0));
        _expectBothSettersReject(_config(1 days - 1, 1 days, 0, 0));
        _expectBothSettersReject(_config(0, 0, 1 days - 1, 1 days));
        _expectBothSettersReject(_config(1_000e18, 1 days, 1 days - 1, 1 days));

        oft.setDefaultRateLimitConfig(_config(1 days, 1 days, 1 days, 1 days));
        _setOverride(DST_EID, _config(1 days, 1 days, 1 days, 1 days));
    }

    /// @notice Zellic's stall shape at the threshold: a 2-per-2s outbound bucket still refills one unit per
    ///         second while an inbound delivery on the same EID re-anchors the shared timestamp every second.
    function test_OppositeTrafficEverySecond_CannotStallRecovery() external {
        ERC20Mock6 sixToken = new ERC20Mock6();
        FraxOFTAdapterUpgradeableRateLimitHarness six = _deployAdapter(address(sixToken));
        six.setDefaultRateLimitConfig(_config(2, 2, 2, 2));
        sixToken.mint(alice, 100);
        sixToken.mint(address(six), 100); // escrow for the inbound credits
        vm.prank(alice);
        sixToken.approve(address(six), type(uint256).max);

        for (uint256 w; w < 3; ++w) {
            vm.prank(alice);
            six.debit(2, 2, DST_EID);
            assertEq(six.outboundRateLimitAvailable(DST_EID), 0, "saturated");
            for (uint256 t = 1; t <= 2; ++t) {
                skip(1);
                six.credit(bob, 1, DST_EID);
                assertEq(six.outboundRateLimitAvailable(DST_EID), t, "one unit per second");
            }
        }
    }

    /// @notice On a realistic config the shared timestamp costs under one base unit per write: a lane
    ///         re-anchored by 100 inbound deliveries trails a quiet lane by fewer than 100 wei, never leads it.
    function test_OppositeTraffic_TruncationUnderOneUnitPerWrite() external {
        uint32 busy = SRC_EID;
        uint256 writes = 100;
        oft.mint(alice, 1_000e18); // setUp mints one lane's worth
        oft.setDefaultRateLimitConfig(_config(1_000e18, 1 days, 1_000e18, 1 days));
        vm.startPrank(alice);
        oft.debit(1_000e18, 1_000e18, DST_EID);
        oft.debit(1_000e18, 1_000e18, busy);
        vm.stopPrank();

        for (uint256 i; i < writes; ++i) {
            skip(7); // 1,000e18 * 7 is not a multiple of 86,400, so every write floors a fraction away
            oft.credit(bob, 1, busy);
        }

        uint256 quiet = oft.outboundRateLimitAvailable(DST_EID);
        uint256 reanchored = oft.outboundRateLimitAvailable(busy);
        assertEq(quiet, uint256(1_000e18) * (7 * writes) / 1 days, "quiet lane: one projection");
        assertLt(reanchored, quiet, "truncation only slows recovery");
        assertLt(quiet - reanchored, writes, "under one unit per write");
    }

    // ── Per-EID configs must actually take effect ───────────────────────────────

    function test_SetRateLimitConfigs_RejectsLimitsWithoutOverride() external {
        RateLimiterModule.SetRateLimitConfigParam[] memory params = new RateLimiterModule.SetRateLimitConfigParam[](1);
        params[0] = RateLimiterModule.SetRateLimitConfigParam({ eid: DST_EID, config: _config(1_000e18, 1 days, 0, 0) });

        vm.expectRevert(RateLimiterModule.InvalidRateLimitConfig.selector);
        oft.setRateLimitConfigs(params);
    }

    function test_SetRateLimitConfigs_EmptyConfigClearsOverride() external {
        oft.setDefaultRateLimitConfig(_config(500e18, 1 days, 0, 0));
        _setOverride(DST_EID, _config(1_000e18, 1 days, 0, 0));
        assertEq(oft.rateLimitConfig(DST_EID).outboundLimit, 1_000e18);

        RateLimiterModule.RateLimitConfig memory empty;
        RateLimiterModule.SetRateLimitConfigParam[] memory params = new RateLimiterModule.SetRateLimitConfigParam[](1);
        params[0] = RateLimiterModule.SetRateLimitConfigParam({ eid: DST_EID, config: empty });
        oft.setRateLimitConfigs(params);

        assertEq(oft.rateLimitConfig(DST_EID).outboundLimit, 500e18, "back on the default");
    }

    // ── Manual state writes are bounded by the limit in force ───────────────────

    function test_SetRateLimitStates_RejectsUsageAboveLimit() external {
        oft.setDefaultRateLimitConfig(_config(0, 0, 100e18, 1 hours));

        vm.expectRevert(RateLimiterModule.InvalidRateLimitState.selector);
        _setState(SRC_EID, 0, 100e18 + 1);

        _setState(SRC_EID, 0, 100e18); // exactly the limit is a full bucket, which is allowed
        assertEq(oft.inboundRateLimitAvailable(SRC_EID), 0);
    }

    function test_SetRateLimitStates_RejectsUsageOnDisabledDirection() external {
        oft.setDefaultRateLimitConfig(_config(0, 0, 100e18, 1 hours)); // outbound disabled, limit 0

        vm.expectRevert(RateLimiterModule.InvalidRateLimitState.selector);
        _setState(DST_EID, 1, 0);
    }

    function test_SetRateLimitStates_RejectsUsageOnDisabledDirectionWithRetainedLimit() external {
        RateLimiterModule.RateLimitConfig memory paused = _config(100e18, 1 hours, 0, 0);
        paused.outboundEnabled = false;
        _setOverride(DST_EID, paused);

        vm.expectRevert(RateLimiterModule.InvalidRateLimitState.selector);
        _setState(DST_EID, 1, 0);
    }

    // ── Each EID is tracked once, however often its state is written ─────────────

    function test_TrackedEids_ListsEachEidOnce() external {
        oft.setDefaultRateLimitConfig(_config(1_000e18, 1 days, 1_000e18, 1 days));
        vm.startPrank(alice);
        oft.debit(1e18, 1e18, DST_EID);
        oft.debit(1e18, 1e18, DST_EID);
        vm.stopPrank();
        uint32[] memory eids = new uint32[](1);
        eids[0] = DST_EID;
        oft.checkpointRateLimits(eids);
        _setState(DST_EID, 0, 0);
        oft.setDefaultRateLimitConfig(_config(1_000e18, 2 days, 1_000e18, 2 days));

        oft.credit(bob, 1e18, SRC_EID);
        assertEq(_trackedEidCount(), 2, "two lanes, one entry each");
    }

    function test_SetRateLimitStates_RejectsZeroTimestamp() external {
        RateLimiterModule.SetRateLimitStateParam[] memory params = new RateLimiterModule.SetRateLimitStateParam[](1);
        params[0] = RateLimiterModule.SetRateLimitStateParam({
            eid: DST_EID,
            state: RateLimiterModule.RateLimitState({ outboundUsage: 0, inboundUsage: 0, lastUpdated: 0 })
        });
        vm.expectRevert(RateLimiterModule.InvalidRateLimitState.selector);
        oft.setRateLimitStates(params);
    }

    /// @dev RateLimiterStorage: globalConfig (+0), defaultConfig (+1, +2), configs (+3), states (+4), trackedEids (+5)
    function _trackedEidCount() internal view returns (uint256) {
        bytes32 base = 0xf02f50e1c246a23e457c592e128a403f9c1cc60baa3a1ad2dc69bb4a5a51be00;
        return uint256(vm.load(address(oft), bytes32(uint256(base) + 5)));
    }

    function _setOverride(uint32 _eid, RateLimiterModule.RateLimitConfig memory _cfg) internal {
        _cfg.overrideDefaultConfig = true;
        RateLimiterModule.SetRateLimitConfigParam[] memory params = new RateLimiterModule.SetRateLimitConfigParam[](1);
        params[0] = RateLimiterModule.SetRateLimitConfigParam({ eid: _eid, config: _cfg });
        oft.setRateLimitConfigs(params);
    }

    function _expectBothSettersReject(RateLimiterModule.RateLimitConfig memory _cfg) internal {
        vm.expectRevert(RateLimiterModule.InvalidRateLimitConfig.selector);
        oft.setDefaultRateLimitConfig(_cfg);

        _cfg.overrideDefaultConfig = true;
        RateLimiterModule.SetRateLimitConfigParam[] memory params = new RateLimiterModule.SetRateLimitConfigParam[](1);
        params[0] = RateLimiterModule.SetRateLimitConfigParam({ eid: DST_EID, config: _cfg });
        vm.expectRevert(RateLimiterModule.InvalidRateLimitConfig.selector);
        oft.setRateLimitConfigs(params);
    }

    function _setState(uint32 _eid, uint112 _outbound, uint112 _inbound) internal {
        RateLimiterModule.SetRateLimitStateParam[] memory params = new RateLimiterModule.SetRateLimitStateParam[](1);
        params[0] = RateLimiterModule.SetRateLimitStateParam({
            eid: _eid,
            state: RateLimiterModule.RateLimitState({
                outboundUsage: _outbound,
                inboundUsage: _inbound,
                lastUpdated: uint32(block.timestamp)
            })
        });
        oft.setRateLimitStates(params);
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
        uint112 _outboundLimit,
        uint32 _outboundWindow,
        uint112 _inboundLimit,
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

/// @dev Drives the real SetRateLimits batch builder with a desired default, recording each emitted tx.
contract SetRateLimitsHarness is SetRateLimits {
    string[] public names;
    bytes[] public datas;
    IRateLimitedOFT.RateLimitConfig internal desired;

    function setDesired(IRateLimitedOFT.RateLimitConfig memory _c) external {
        desired = _c;
    }

    function desiredDefaultRateLimitConfig(
        address
    ) public view override returns (bool shouldSet, IRateLimitedOFT.RateLimitConfig memory config) {
        return (true, desired);
    }

    function pushSerializedTx(string memory _name, address, uint256, bytes memory _data) public override {
        names.push(_name);
        datas.push(_data);
    }

    function count() external view returns (uint256) {
        return names.length;
    }
}

/// @notice The batch builder registers peered, untracked EIDs before a default change, so the
///         first armed delivery on a lane does not pay the tracking write inside lzReceive.
contract SetRateLimitsRegistrationTest is Test {
    uint32 internal constant LOCAL_EID = 30255;
    uint32 internal constant UNTRACKED_PEER = 30101;
    uint32 internal constant TRACKED_PEER = 30184;
    uint32 internal constant UNPEERED = 30999;

    FraxOFTUpgradeableRateLimitHarness internal oft;
    SetRateLimitsHarness internal script;

    function setUp() external {
        EndpointV2MockLite endpoint = new EndpointV2MockLite();
        FraxOFTUpgradeableRateLimitHarness impl = new FraxOFTUpgradeableRateLimitHarness(address(endpoint));
        oft = FraxOFTUpgradeableRateLimitHarness(
            address(
                new TransparentUpgradeableProxy(
                    address(impl),
                    address(0x9999),
                    abi.encodeWithSelector(FraxOFTUpgradeable.initialize.selector, "Mock Frax", "mFRAX", address(this))
                )
            )
        );
        oft.setPeer(UNTRACKED_PEER, bytes32(uint256(1)));
        oft.setPeer(TRACKED_PEER, bytes32(uint256(2)));
        uint32[] memory already = new uint32[](1);
        already[0] = TRACKED_PEER;
        oft.checkpointRateLimits(already); // already tracked: must not be re-registered

        script = new SetRateLimitsHarness();
        oft.transferOwnership(address(script));
        script.setDesired(
            IRateLimitedOFT.RateLimitConfig({
                overrideDefaultConfig: false,
                outboundEnabled: true,
                inboundEnabled: true,
                outboundWindow: 1 days,
                inboundWindow: 1 days,
                outboundLimit: 1_000e18,
                inboundLimit: 1_000e18
            })
        );
    }

    function _configs() internal view returns (L0Config[] memory c) {
        c = new L0Config[](4);
        c[0].chainid = block.chainid; c[0].eid = LOCAL_EID;
        c[1].chainid = 1; c[1].eid = UNTRACKED_PEER;
        c[2].chainid = 8453; c[2].eid = TRACKED_PEER;
        c[3].chainid = 999; c[3].eid = UNPEERED;
    }

    function test_RegistersOnlyPeeredUntrackedEidsBeforeTheDefault() external {
        address[] memory ofts = new address[](1);
        ofts[0] = address(oft);
        script.setRateLimits(ofts, _configs());

        assertEq(script.count(), 2, "checkpoint then default");
        assertEq(script.names(0), "checkpointRateLimits");
        assertEq(script.names(1), "setDefaultRateLimitConfig");

        uint32[] memory registered = new uint32[](1);
        registered[0] = UNTRACKED_PEER;
        assertEq(script.datas(0), abi.encodeCall(IRateLimitedOFT.checkpointRateLimits, (registered)), "only 30101");
        assertGt(oft.storedRateLimitState(UNTRACKED_PEER).lastUpdated, 0, "lane pre-written by the owner");
    }

    function test_NoRegistrationWhenTheDefaultIsAlreadyInPlace() external {
        address[] memory ofts = new address[](1);
        ofts[0] = address(oft);
        script.setRateLimits(ofts, _configs());
        uint256 before = script.count();

        script.setRateLimits(ofts, _configs());
        assertEq(script.count(), before, "re-run emits nothing");
    }
}
