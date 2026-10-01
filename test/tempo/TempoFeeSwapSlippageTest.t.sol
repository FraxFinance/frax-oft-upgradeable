// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { ITIP20RolesAuth } from "tempo-std/interfaces/ITIP20RolesAuth.sol";
import { IStablecoinDEX } from "tempo-std/interfaces/IStablecoinDEX.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { TempoAltTokenBase } from "contracts/base/TempoAltTokenBase.sol";

// Imported so forge compiles the reference implementations that `deployCodeTo` places at the
// precompile addresses.
import { TIP20 as TempoTIP20 } from "@tempo/TIP20.sol";
import { StablecoinDEX as TempoStablecoinDEX } from "@tempo/StablecoinDEX.sol";

/// @notice Exercises the quote/settlement rounding divergence in Tempo's StablecoinDEX and the
///         slippage allowance that `TempoAltTokenBase` applies to fee swaps.
/// @dev Runs against Tempo's own Solidity reference implementations placed at their precompile
///      addresses, so no Tempo toolchain is required. The reference carries the same per-tick vs
///      per-order note as the Rust node, which is the behaviour under test.
///
///      Liquidity is placed at a NON-ZERO tick and split across several orders. At tick 0 the
///      conversion is an exact integer ratio and the divergence cannot occur, which is why the
///      repo's `_addDexLiquidity` helper (tick 0, single order) never surfaced it.
contract TempoFeeSwapSlippageTest is Test {
    IStablecoinDEX internal constant DEX = StdPrecompiles.STABLECOIN_DEX;

    // Mirrors TempoAltTokenBase.
    uint16 internal constant DEFAULT_FEE_SWAP_SLIPPAGE_BPS = 50;
    uint16 internal constant MAX_FEE_SWAP_SLIPPAGE_BPS = 200;

    // Parameters from the disclosed proof of concept.
    int16 internal constant TICK = 10;
    uint128 internal constant ORDER_SIZE = 100_000_003;
    uint256 internal constant ORDER_COUNT = 6;
    uint128 internal constant NATIVE_FEE = 500_000_000;

    ITIP20 internal pathUsd;
    ITIP20 internal gasToken;

    address internal constant PAYER = address(0xBEEF);
    address internal constant MAKER = address(0x1111);

    function setUp() public {
        // Tempo reference implementations at their canonical precompile addresses.
        // TIP20 only consults two predicates on the policy registry; a permissive stand-in keeps
        // the order book itself authentic while removing policy enforcement from the picture.
        vm.etch(
            StdPrecompiles.TIP403_REGISTRY_ADDRESS,
            address(new PermissiveTIP403Registry()).code
        );
        deployCodeTo("StablecoinDEX.sol:StablecoinDEX", StdPrecompiles.STABLECOIN_DEX_ADDRESS);

        deployCodeTo(
            "TIP20.sol:TIP20",
            abi.encode("Path USD", "PATH_USD", "USD", StdTokens.PATH_USD_ADDRESS, address(this), address(this)),
            StdTokens.PATH_USD_ADDRESS
        );
        pathUsd = ITIP20(StdTokens.PATH_USD_ADDRESS);

        gasToken = ITIP20(_deployTIP20("Gas Token", "GAS", StdTokens.ALPHA_USD_ADDRESS));

        ITIP20RolesAuth(address(pathUsd)).grantRole(pathUsd.ISSUER_ROLE(), address(this));
        ITIP20RolesAuth(address(gasToken)).grantRole(gasToken.ISSUER_ROLE(), address(this));

        DEX.createPair(address(gasToken));

        // Six separate resting bids at the same non-zero tick: settlement walks them one at a time.
        pathUsd.mint(MAKER, uint256(ORDER_SIZE) * ORDER_COUNT * 4);
        vm.startPrank(MAKER);
        pathUsd.approve(address(DEX), type(uint256).max);
        for (uint256 i; i < ORDER_COUNT; ++i) {
            DEX.place(address(gasToken), ORDER_SIZE, true, TICK);
        }
        vm.stopPrank();

        gasToken.mint(PAYER, uint256(ORDER_SIZE) * ORDER_COUNT * 4);
    }

    /// @dev TIP20 is only recognised by the DEX at a `0x20c0`-prefixed address, so each token is
    ///      placed at one of the canonical stablecoin slots.
    function _deployTIP20(string memory name, string memory symbol, address at) internal returns (address) {
        deployCodeTo(
            "TIP20.sol:TIP20",
            abi.encode(name, symbol, "USD", StdTokens.PATH_USD_ADDRESS, address(this), address(this)),
            at
        );
        return at;
    }

    /// @dev The allowance TempoAltTokenBase applies. Always at least one unit, because the
    ///      divergence is a rounding artefact that a percentage rounds away on small amounts.
    function _withSlippage(uint128 amountIn, uint16 bps) internal pure returns (uint128) {
        uint256 padded = (uint256(amountIn) * (10_000 + uint256(bps))) / 10_000;
        if (padded <= uint256(amountIn)) padded = uint256(amountIn) + 1;
        return padded > type(uint128).max ? type(uint128).max : uint128(padded);
    }

    /// @notice The defect: settlement charges more than the quote promised.
    function test_QuoteUnderStatesSettlement() public {
        uint128 quoted = DEX.quoteSwapExactAmountOut(address(gasToken), address(pathUsd), NATIVE_FEE);

        uint256 snap = vm.snapshot();
        vm.startPrank(PAYER);
        gasToken.approve(address(DEX), type(uint256).max);
        uint128 actual = DEX.swapExactAmountOut(address(gasToken), address(pathUsd), NATIVE_FEE, type(uint128).max);
        vm.stopPrank();
        vm.revertTo(snap);

        console.log("quoted :", quoted);
        console.log("actual :", actual);
        assertGt(actual, quoted, "book did not diverge; adjust tick/order split");
    }

    /// @notice Passing the raw quote through as the cap is what reverts the user's whole send.
    function test_RawQuoteAsCap_Reverts() public {
        uint128 quoted = DEX.quoteSwapExactAmountOut(address(gasToken), address(pathUsd), NATIVE_FEE);

        vm.startPrank(PAYER);
        gasToken.approve(address(DEX), type(uint256).max);
        vm.expectRevert(IStablecoinDEX.MaxInputExceeded.selector);
        DEX.swapExactAmountOut(address(gasToken), address(pathUsd), NATIVE_FEE, quoted);
        vm.stopPrank();
    }

    /// @notice With the allowance applied the swap settles, and the DEX takes only what it needs.
    function test_BufferedCap_Succeeds_AndOverpaymentIsNotConsumed() public {
        uint128 quoted = DEX.quoteSwapExactAmountOut(address(gasToken), address(pathUsd), NATIVE_FEE);
        uint128 maxIn = _withSlippage(quoted, DEFAULT_FEE_SWAP_SLIPPAGE_BPS);

        uint256 balanceBefore = gasToken.balanceOf(PAYER);

        vm.startPrank(PAYER);
        gasToken.approve(address(DEX), maxIn);
        uint128 spent = DEX.swapExactAmountOut(address(gasToken), address(pathUsd), NATIVE_FEE, maxIn);
        vm.stopPrank();

        assertLe(spent, maxIn, "settlement exceeded the buffered cap");
        assertGt(spent, quoted, "control: this book should under-quote");
        assertEq(pathUsd.balanceOf(PAYER), NATIVE_FEE, "payer did not receive the exact fee amount");
        // Only the consumed amount leaves the payer: the unconsumed allowance is never transferred,
        // which is what makes the adapter's refund of `maxIn - spent` whole.
        assertEq(balanceBefore - gasToken.balanceOf(PAYER), spent, "DEX debited more than it consumed");
    }

    /// @notice A percentage alone rounds to nothing on small amounts; the +1 floor is load-bearing.
    function test_SlippageFloorIsAtLeastOneUnit() public {
        assertEq(_withSlippage(1, 50), 2, "no headroom added to a 1-unit quote");
        assertEq(_withSlippage(100, 50), 101, "no headroom added to a 100-unit quote");
        assertGt(_withSlippage(199, 50), 199, "no headroom added");
        assertEq(_withSlippage(1_000_000, 50), 1_005_000, "bps applied incorrectly at scale");
    }

    /// @notice The allowance must stay inside the configured ceiling.
    function test_MaxSlippageIsBounded() public {
        uint128 quoted = 1_000_000;
        uint128 maxAllowed = _withSlippage(quoted, MAX_FEE_SWAP_SLIPPAGE_BPS);
        assertEq(maxAllowed, 1_020_000, "ceiling is not 2%");
    }


    /// @notice End-to-end through the adapter: the swap settles despite the divergence, and every
    ///         unit pulled but not consumed is returned to the payer.
    function test_PayNativeAltToken_SettlesAndRefundsRemainder() public {
        vm.etch(StdPrecompiles.TIP_FEE_MANAGER_ADDRESS, address(new MockFeeManager(address(gasToken))).code);

        MockLZEndpointDollar lzDollar = new MockLZEndpointDollar(address(pathUsd));
        AltTokenHarness harness = new AltTokenHarness(address(new MockEndpointV2Alt(address(lzDollar))));

        uint128 quoted = DEX.quoteSwapExactAmountOut(address(gasToken), address(pathUsd), NATIVE_FEE);
        uint128 maxIn = _withSlippage(quoted, DEFAULT_FEE_SWAP_SLIPPAGE_BPS);

        uint256 payerBefore = gasToken.balanceOf(PAYER);

        vm.prank(PAYER);
        gasToken.approve(address(harness), maxIn);

        vm.prank(PAYER);
        harness.pay(NATIVE_FEE, address(0xE4D)); // endpoint receives the wrapped fee

        uint256 spent = payerBefore - gasToken.balanceOf(PAYER);

        // Settlement cost more than the quote, so the raw quote would have reverted here.
        assertGt(spent, quoted, "control: this book should under-quote");
        assertLe(spent, maxIn, "spent more than the buffered cap");
        // Nothing is stranded in the adapter: the buffer is pulled, then returned.
        assertEq(gasToken.balanceOf(address(harness)), 0, "adapter retained leftover gas token");
        assertEq(pathUsd.balanceOf(address(0xE4D)), NATIVE_FEE, "endpoint did not receive the fee");
        // And no standing allowance is left pointing at the DEX.
        assertEq(
            gasToken.allowance(address(harness), address(DEX)), 0, "residual DEX allowance left open"
        );
    }

    /// @notice The owner-configurable allowance is honoured end to end.
    function test_PayNativeAltToken_RespectsConfiguredBps() public {
        vm.etch(StdPrecompiles.TIP_FEE_MANAGER_ADDRESS, address(new MockFeeManager(address(gasToken))).code);

        MockLZEndpointDollar lzDollar = new MockLZEndpointDollar(address(pathUsd));
        AltTokenHarness harness = new AltTokenHarness(address(new MockEndpointV2Alt(address(lzDollar))));

        assertEq(harness.feeSwapSlippageBps(), DEFAULT_FEE_SWAP_SLIPPAGE_BPS, "unexpected default");
        harness.setBps(MAX_FEE_SWAP_SLIPPAGE_BPS);
        assertEq(harness.feeSwapSlippageBps(), MAX_FEE_SWAP_SLIPPAGE_BPS, "setter did not take");
        harness.setBps(0);
        assertEq(harness.feeSwapSlippageBps(), DEFAULT_FEE_SWAP_SLIPPAGE_BPS, "0 should restore default");

        vm.expectRevert(
            abi.encodeWithSelector(TempoAltTokenBase.FeeSwapSlippageTooHigh.selector, MAX_FEE_SWAP_SLIPPAGE_BPS + 1)
        );
        harness.setBps(MAX_FEE_SWAP_SLIPPAGE_BPS + 1);
    }

    /// @notice Control: a single order at the same tick does not diverge.
    function test_Control_SingleOrder_NoDivergence() public {
        ITIP20 solo = ITIP20(_deployTIP20("Solo", "SOLO", StdTokens.BETA_USD_ADDRESS));
        ITIP20RolesAuth(address(solo)).grantRole(solo.ISSUER_ROLE(), address(this));
        DEX.createPair(address(solo));

        pathUsd.mint(MAKER, uint256(ORDER_SIZE) * ORDER_COUNT * 4);
        vm.startPrank(MAKER);
        pathUsd.approve(address(DEX), type(uint256).max);
        DEX.place(address(solo), ORDER_SIZE * uint128(ORDER_COUNT), true, TICK);
        vm.stopPrank();

        solo.mint(PAYER, uint256(ORDER_SIZE) * ORDER_COUNT * 4);

        uint128 quoted = DEX.quoteSwapExactAmountOut(address(solo), address(pathUsd), NATIVE_FEE);
        vm.startPrank(PAYER);
        solo.approve(address(DEX), type(uint256).max);
        uint128 actual = DEX.swapExactAmountOut(address(solo), address(pathUsd), NATIVE_FEE, type(uint128).max);
        vm.stopPrank();

        assertEq(actual, quoted, "single order should quote exactly");
    }

    /// @notice Control: at tick 0 the conversion is exact, so no divergence regardless of order count.
    function test_Control_TickZero_NoDivergence() public {
        ITIP20 flat = ITIP20(_deployTIP20("Flat", "FLAT", StdTokens.THETA_USD_ADDRESS));
        ITIP20RolesAuth(address(flat)).grantRole(flat.ISSUER_ROLE(), address(this));
        DEX.createPair(address(flat));

        pathUsd.mint(MAKER, uint256(ORDER_SIZE) * ORDER_COUNT * 4);
        vm.startPrank(MAKER);
        pathUsd.approve(address(DEX), type(uint256).max);
        for (uint256 i; i < ORDER_COUNT; ++i) {
            DEX.place(address(flat), ORDER_SIZE, true, 0);
        }
        vm.stopPrank();

        flat.mint(PAYER, uint256(ORDER_SIZE) * ORDER_COUNT * 4);

        uint128 quoted = DEX.quoteSwapExactAmountOut(address(flat), address(pathUsd), NATIVE_FEE);
        vm.startPrank(PAYER);
        flat.approve(address(DEX), type(uint256).max);
        uint128 actual = DEX.swapExactAmountOut(address(flat), address(pathUsd), NATIVE_FEE, type(uint128).max);
        vm.stopPrank();

        assertEq(actual, quoted, "tick 0 should quote exactly");
    }
}

/// @dev Minimal stand-in for the transfer-policy registry: TIP20 only asks whether a policy exists
///      and whether an address is authorised. Both are permissive here so the test exercises the
///      order book rather than policy enforcement.
contract PermissiveTIP403Registry {
    function policyExists(uint64) external pure returns (bool) {
        return true;
    }

    function isAuthorized(uint64, address) external pure returns (bool) {
        return true;
    }
}

/// @dev Minimal LZEndpointDollar: only the whitelist queries and `wrap` are exercised here.
contract MockLZEndpointDollar {
    address public immutable whitelisted;

    constructor(address _whitelisted) {
        whitelisted = _whitelisted;
    }

    function isWhitelistedToken(address _token) external view returns (bool) {
        return _token == whitelisted;
    }

    function getWhitelistedTokens() external view returns (address[] memory out) {
        out = new address[](1);
        out[0] = whitelisted;
    }

    function wrap(address _token, address _to, uint256 _amount) external {
        ITIP20(_token).transferFrom(msg.sender, _to, _amount);
    }

    function unwrap(address, address, uint256) external {}

    function decimals() external pure returns (uint8) {
        return 6;
    }
}

/// @dev Endpoint stub whose `nativeToken()` the base reads in its constructor.
contract MockEndpointV2Alt {
    address public immutable nativeToken;

    constructor(address _nativeToken) {
        nativeToken = _nativeToken;
    }
}

/// @dev Exposes the internal fee-payment path for direct exercise.
contract AltTokenHarness is TempoAltTokenBase {
    constructor(address _endpoint) TempoAltTokenBase(_endpoint) {}

    function pay(uint256 _fee, address _endpointAddr) external returns (uint256) {
        return _payNativeAltToken(_fee, _endpointAddr);
    }

    function setBps(uint16 _bps) external {
        _setFeeSwapSlippageBps(_bps);
    }
}

/// @dev Fee manager stub: reports a fixed gas token for every caller.
contract MockFeeManager {
    address public immutable token;

    constructor(address _token) {
        token = _token;
    }

    function userTokens(address) external view returns (address) {
        return token;
    }
}
