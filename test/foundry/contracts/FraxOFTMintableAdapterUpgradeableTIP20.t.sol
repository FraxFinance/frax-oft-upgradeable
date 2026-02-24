// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTMintableAdapterUpgradeableTIP20 } from "contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol";
import { TempoAltTokenBase } from "contracts/base/TempoAltTokenBase.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { ITIP20RolesAuth } from "tempo-std/interfaces/ITIP20RolesAuth.sol";
import { IStablecoinDEX } from "tempo-std/interfaces/IStablecoinDEX.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SendParam, OFTReceipt } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { TempoTestHelpers } from "test/foundry/helpers/TempoTestHelpers.sol";

/// @notice Mock LZEndpointDollar for testing
contract MockLZEndpointDollarForAdapter {
    string public name = "LZ Endpoint Dollar";
    string public symbol = "LZUSD";
    uint8 public constant decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) private _whitelistedTokens;
    address[] private _whitelistedTokensList;
    uint256 public totalSupply;

    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event TokenWrapped(address indexed token, address indexed from, address indexed to, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    function whitelistToken(address token) external {
        _whitelistedTokens[token] = true;
        _whitelistedTokensList.push(token);
    }

    function isWhitelistedToken(address token) external view returns (bool) {
        return _whitelistedTokens[token];
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return _whitelistedTokensList;
    }

    function wrap(address token, address to, uint256 amount) external {
        require(_whitelistedTokens[token], "Not whitelisted");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
        emit TokenWrapped(token, msg.sender, to, amount);
    }

    function unwrap(address token, address to, uint256 amount) external {
        require(_whitelistedTokens[token], "Not whitelisted");
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        IERC20(token).transfer(to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice Mock LZ endpoint simulating EndpointV2Alt behavior (ERC20 as native)
/// @dev Mimics how Tempo's endpoint uses LZEndpointDollar ERC20 balance instead of msg.value
contract MockLzEndpoint {
    uint32 public eid;
    uint64 public nonce;
    uint256 public lastNativeFee;
    mapping(address => address) public delegates;

    /// @dev Mock LZEndpointDollar that wraps PATH_USD
    MockLZEndpointDollarForAdapter public nativeErc20;

    constructor(uint32 _eid) {
        eid = _eid;
        nativeErc20 = new MockLZEndpointDollarForAdapter();
        // Whitelist PATH_USD by default
        nativeErc20.whitelistToken(0x20C0000000000000000000000000000000000000);
    }

    /// @dev Mock setDelegate called during OApp initialization
    function setDelegate(address _delegate) external {
        delegates[msg.sender] = _delegate;
    }

    /// @dev Simulates EndpointV2Alt.send() behavior
    function send(MessagingParams calldata, address) external payable returns (MessagingReceipt memory) {
        require(msg.value == 0, "LZ_OnlyAltToken");
        nonce++;
        lastNativeFee = nativeErc20.balanceOf(address(this));

        return
            MessagingReceipt({
                guid: bytes32(uint256(nonce)),
                nonce: nonce,
                fee: MessagingFee({ nativeFee: lastNativeFee, lzTokenFee: 0 })
            });
    }

    uint256 public mockNativeFee = 10e6;

    function setMockNativeFee(uint256 _fee) external {
        mockNativeFee = _fee;
    }

    function quote(MessagingParams calldata, address) external view returns (MessagingFee memory) {
        return MessagingFee({ nativeFee: mockNativeFee, lzTokenFee: 0 });
    }

    function nativeToken() external view returns (address) {
        return address(nativeErc20);
    }

    receive() external payable {}
}

/// @notice Struct matching LZ endpoint's MessagingParams
struct MessagingParams {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
}

/// @title FraxOFTMintableAdapterUpgradeableTIP20 Unit Tests
/// @dev Only LZ endpoint is mocked; Tempo precompiles are real
contract FraxOFTMintableAdapterUpgradeableTIP20Test is TempoTestHelpers {
    using OptionsBuilder for bytes;

    FraxOFTMintableAdapterUpgradeableTIP20 adapter;
    ITIP20 frxUsdToken;

    address proxyAdmin = address(0x9999);
    address contractOwner = address(this);
    MockLzEndpoint lzEndpoint;

    address alice = vm.addr(0x41);
    address bob = vm.addr(0xb0b);

    // LayerZero EID constants
    uint32 constant SRC_EID = 30252; // Example: Tempo EID
    uint32 constant DST_EID = 30101; // Example: Ethereum EID

    function setUp() external {
        // Create TIP20 token with DEX pair
        frxUsdToken = _createTIP20WithDexPair("Frax USD", "frxUSD", keccak256("frxUSD-salt"));

        // Grant PATH_USD minting for liquidity provider
        _grantPathUsdIssuerRole(address(this));

        // Deploy mock LZ endpoint that receives native value
        lzEndpoint = new MockLzEndpoint(SRC_EID);

        // Deploy implementation
        FraxOFTMintableAdapterUpgradeableTIP20 implementation = new FraxOFTMintableAdapterUpgradeableTIP20(
            address(frxUsdToken),
            address(lzEndpoint)
        );

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            FraxOFTMintableAdapterUpgradeableTIP20.initialize.selector,
            contractOwner
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            proxyAdmin,
            initData
        );

        adapter = FraxOFTMintableAdapterUpgradeableTIP20(address(proxy));

        // Grant ISSUER_ROLE to adapter
        _grantIssuerRole(address(frxUsdToken), address(adapter));
    }

    // ---------------------------------------------------
    // LayerZero Test Helpers
    // ---------------------------------------------------

    /// @dev Setup peer for destination chain
    function _setupPeer() internal {
        bytes32 peer = bytes32(uint256(uint160(address(0xDEAD))));
        adapter.setPeer(DST_EID, peer);
    }

    /// @dev Build a standard SendParam for tests
    function _buildSendParam(uint256 sendAmount) internal view returns (SendParam memory) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
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

    /// @dev Execute adapter.send with standard parameters (for PATH_USD gas token)
    /// @notice With EndpointV2Alt, PATH_USD is pulled from user as ERC20, not via msg.value
    function _executeSend(address sender, uint256 sendAmount, uint256 nativeFee) internal {
        SendParam memory sendParam = _buildSendParam(sendAmount);
        vm.prank(sender);
        adapter.send{ value: 0 }(sendParam, MessagingFee({ nativeFee: nativeFee, lzTokenFee: 0 }), sender);
    }

    /// @dev Execute adapter.send when gas token is TIP20 (swapped to PATH_USD by _payNative)
    /// @notice The _payNative override swaps user's TIP20 to PATH_USD.
    ///         Tempo's forked Foundry treats PATH_USD ERC20 = native, so after swap adapter can call endpoint.send{value: X}
    function _executeSendWithSwap(address sender, uint256 sendAmount, uint256 nativeFee) internal {
        SendParam memory sendParam = _buildSendParam(sendAmount);
        vm.prank(sender);
        adapter.send{ value: 0 }(sendParam, MessagingFee({ nativeFee: nativeFee, lzTokenFee: 0 }), sender);
    }

    // ---------------------------------------------------
    // Version Tests
    // ---------------------------------------------------

    function test_Version_returnsExpected() external {
        assertEq(adapter.version(), "1.1.0");
    }

    // ---------------------------------------------------
    // Token/Owner Tests
    // ---------------------------------------------------

    function test_Token_returnsExpected() external {
        assertEq(adapter.token(), address(frxUsdToken));
    }

    function test_Owner_returnsExpected() external {
        assertEq(adapter.owner(), contractOwner);
    }

    // ---------------------------------------------------
    // Supply Tracking Tests
    // ---------------------------------------------------

    function test_SetInitialTotalSupply_succeeds() external {
        uint256 initialSupply = 1_000_000e6;

        adapter.setInitialTotalSupply(DST_EID, initialSupply);

        assertEq(adapter.initialTotalSupply(DST_EID), initialSupply);
        assertEq(adapter.totalTransferTo(DST_EID), 0);
    }

    function test_SetInitialTotalSupply_OnlyOwner() external {
        vm.prank(alice);
        vm.expectRevert();
        adapter.setInitialTotalSupply(DST_EID, 1_000_000e6);
    }

    // ---------------------------------------------------
    // Recovery Tests
    // ---------------------------------------------------

    /// @dev Only owner can call recoverERC20
    function test_RecoverERC20_onlyOwner() external {
        // Create another token to recover
        ITIP20 otherToken = _createTIP20("Other Token", "OTHER", bytes32(uint256(100)));

        uint256 stuckBalance = 50e6;
        otherToken.mint(address(adapter), stuckBalance);

        // Non-owner cannot call
        vm.prank(alice);
        vm.expectRevert();
        adapter.recoverERC20(address(otherToken), stuckBalance);

        // Owner can call
        adapter.recoverERC20(address(otherToken), stuckBalance);
        assertEq(otherToken.balanceOf(contractOwner), stuckBalance);
        assertEq(otherToken.balanceOf(address(adapter)), 0);
    }

    /// @dev recoverERC20 emits RecoveredERC20 event
    function test_RecoverERC20_emitsEvent() external {
        ITIP20 otherToken = _createTIP20("Other Token Emit", "OTHERE", bytes32(uint256(101)));

        uint256 stuckBalance = 50e6;
        otherToken.mint(address(adapter), stuckBalance);

        vm.expectEmit(true, false, false, true, address(adapter));
        emit FraxOFTMintableAdapterUpgradeableTIP20.RecoveredERC20(address(otherToken), stuckBalance);

        adapter.recoverERC20(address(otherToken), stuckBalance);
    }

    // ---------------------------------------------------
    // _lzSend TIP20 Gas Token Swap Tests
    // ---------------------------------------------------

    /// @dev When user's gas token is innerToken, swap to PATH_USD should occur
    /// @notice Asserts events for _debit (transfer+burn) and _payNative (swap flow)
    function test_LzSend_SwapsInnerTokenToPathUsd_WhenUserGasTokenIsInnerToken() external {
        uint256 sendAmount = 100e6;
        uint256 nativeFee = 20_000e6; // Must be >= MIN_ORDER_AMOUNT (10_000e6)

        _setUserGasToken(alice, address(frxUsdToken));
        frxUsdToken.mint(alice, sendAmount + nativeFee);
        _addDexLiquidity(address(frxUsdToken), nativeFee * 2);
        _setupPeer();

        vm.prank(alice);
        frxUsdToken.approve(address(adapter), type(uint256).max);

        // Track balance before
        uint256 aliceGasTokenBefore = frxUsdToken.balanceOf(alice);

        // --- EXPECTED EVENTS ---
        // 1. _debit: Transfer frxUSD from alice to adapter
        vm.expectEmit(true, true, false, true, address(frxUsdToken));
        emit ITIP20.Transfer(alice, address(adapter), sendAmount);

        // 2. _debit: Burn frxUSD (transfer to zero address)
        vm.expectEmit(true, true, false, true, address(frxUsdToken));
        emit ITIP20.Transfer(address(adapter), address(0), sendAmount);

        // 3. _payNative: Transfer frxUSD (gas) from alice to adapter
        vm.expectEmit(true, true, false, true, address(frxUsdToken));
        emit ITIP20.Transfer(alice, address(adapter), nativeFee);

        // 4. _payNative: Approval for DEX
        vm.expectEmit(true, true, false, true, address(frxUsdToken));
        emit ITIP20.Approval(address(adapter), address(StdPrecompiles.STABLECOIN_DEX), nativeFee);

        // 5. DEX: OrderFilled during swap
        vm.expectEmit(false, true, true, true, address(StdPrecompiles.STABLECOIN_DEX));
        emit IStablecoinDEX.OrderFilled({
            orderId: 0,
            maker: address(0x1111),
            taker: address(adapter),
            amountFilled: uint128(nativeFee),
            partialFill: true
        });

        _executeSendWithSwap(alice, sendAmount, nativeFee);

        // Gas token balance after
        uint256 aliceGasTokenAfter = frxUsdToken.balanceOf(alice);

        // _debit pulls sendAmount, _payNative pulls nativeFee for swap
        assertEq(
            aliceGasTokenAfter,
            aliceGasTokenBefore - sendAmount - nativeFee,
            "Gas token (frxUSD) balance mismatch"
        );
        // Endpoint receives LZEndpointDollar (wrapped PATH_USD)
        assertEq(lzEndpoint.nativeErc20().balanceOf(address(lzEndpoint)), nativeFee, "Endpoint should receive LZEndpointDollar");
    }

    /// @dev When user's gas token is PATH_USD, no swap occurs - PATH_USD pulled directly from user
    /// @notice Asserts events for _debit (transfer+burn) and _payNative (direct transfer to endpoint)
    function test_LzSend_NoSwap_WhenUserGasTokenIsPathUsd() external {
        uint256 sendAmount = 100e6;
        uint256 nativeFee = 10e6;

        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);
        frxUsdToken.mint(alice, sendAmount);
        StdTokens.PATH_USD.mint(alice, nativeFee); // Mint PATH_USD for gas payment
        _setupPeer();

        vm.startPrank(alice);
        frxUsdToken.approve(address(adapter), type(uint256).max);
        StdTokens.PATH_USD.approve(address(adapter), type(uint256).max); // Approve PATH_USD for gas
        vm.stopPrank();

        // Track balances before
        uint256 aliceFrxUsdBefore = frxUsdToken.balanceOf(alice);
        uint256 alicePathUsdBefore = StdTokens.PATH_USD.balanceOf(alice);

        // --- EXPECTED EVENTS ---
        // 1. _debit: Transfer frxUSD from alice to adapter
        vm.expectEmit(true, true, false, true, address(frxUsdToken));
        emit ITIP20.Transfer(alice, address(adapter), sendAmount);

        // 2. _debit: Burn frxUSD (transfer to zero address)
        vm.expectEmit(true, true, false, true, address(frxUsdToken));
        emit ITIP20.Transfer(address(adapter), address(0), sendAmount);

        // 3. _payNative: Transfer PATH_USD from alice to adapter for wrapping
        vm.expectEmit(true, true, false, true, StdTokens.PATH_USD_ADDRESS);
        emit ITIP20.Transfer(alice, address(adapter), nativeFee);

        _executeSend(alice, sendAmount, nativeFee);

        // Track balances after
        uint256 aliceFrxUsdAfter = frxUsdToken.balanceOf(alice);
        uint256 alicePathUsdAfter = StdTokens.PATH_USD.balanceOf(alice);

        // frxUSD: only sendAmount deducted (for _debit)
        assertEq(
            aliceFrxUsdAfter,
            aliceFrxUsdBefore - sendAmount,
            "frxUSD balance mismatch - only sendAmount should be deducted"
        );
        // PATH_USD: nativeFee deducted (pulled by _payNative and wrapped)
        assertEq(alicePathUsdAfter, alicePathUsdBefore - nativeFee, "PATH_USD balance should be reduced by nativeFee");
        // Endpoint receives LZEndpointDollar (wrapped PATH_USD)
        assertEq(lzEndpoint.nativeErc20().balanceOf(address(lzEndpoint)), nativeFee, "Endpoint should receive LZEndpointDollar");
    }

    /// @dev When user's gas token is any TIP20 (not PATH_USD), swap to PATH_USD should occur
    /// @notice Asserts events and state changes during the _payNative swap flow
    function test_LzSend_SwapsAnyTip20ToPathUsd() external {
        // Create another TIP20 token for gas payment
        ITIP20 otherToken = _createTIP20WithDexPair("Other Token Swap", "OTHERS", bytes32(uint256(2)));

        uint256 sendAmount = 100e6;
        uint256 nativeFee = 20_000e6;

        _setUserGasToken(alice, address(otherToken));
        frxUsdToken.mint(alice, sendAmount);
        otherToken.mint(alice, nativeFee);
        _addDexLiquidity(address(otherToken), nativeFee * 2);
        _setupPeer();

        vm.startPrank(alice);
        frxUsdToken.approve(address(adapter), type(uint256).max);
        otherToken.approve(address(adapter), type(uint256).max);
        vm.stopPrank();

        // Track balances before
        uint256 aliceFrxBalanceBefore = frxUsdToken.balanceOf(alice);
        uint256 aliceGasTokenBefore = otherToken.balanceOf(alice);
        uint256 adapterGasTokenBefore = otherToken.balanceOf(address(adapter));
        uint256 adapterPathUsdBefore = StdTokens.PATH_USD.balanceOf(address(adapter));

        // --- EXPECTED EVENTS during _payNative swap flow ---
        // 1. Transfer: user's gas token pulled from alice to adapter
        vm.expectEmit(true, true, false, true, address(otherToken));
        emit ITIP20.Transfer(alice, address(adapter), nativeFee);

        // 2. Approval: adapter approves DEX to spend gas token
        vm.expectEmit(true, true, false, true, address(otherToken));
        emit ITIP20.Approval(address(adapter), address(StdPrecompiles.STABLECOIN_DEX), nativeFee);

        // 3. OrderFilled: DEX fills order during swap
        // Skip orderId check (unknown), but verify maker (liquidity provider), taker (adapter), amount, partialFill
        vm.expectEmit(false, true, true, true, address(StdPrecompiles.STABLECOIN_DEX));
        emit IStablecoinDEX.OrderFilled({
            orderId: 0, // ignored due to expectEmit(false, ...)
            maker: address(0x1111), // liquidity provider from _addDexLiquidity
            taker: address(adapter),
            amountFilled: uint128(nativeFee),
            partialFill: true
        });

        _executeSendWithSwap(alice, sendAmount, nativeFee);

        // Track balances after
        uint256 aliceFrxBalanceAfter = frxUsdToken.balanceOf(alice);
        uint256 aliceGasTokenAfter = otherToken.balanceOf(alice);
        uint256 adapterGasTokenAfter = otherToken.balanceOf(address(adapter));
        uint256 adapterPathUsdAfter = StdTokens.PATH_USD.balanceOf(address(adapter));
        uint256 endpointLzUsdAfter = lzEndpoint.nativeErc20().balanceOf(address(lzEndpoint));

        // --- BALANCE ASSERTIONS ---
        // frxUSD: only sendAmount deducted (for _debit)
        assertEq(aliceFrxBalanceAfter, aliceFrxBalanceBefore - sendAmount, "frxUSD balance mismatch");
        // Gas token (otherToken): nativeFee deducted (for gas swap)
        assertEq(aliceGasTokenAfter, aliceGasTokenBefore - nativeFee, "Gas token balance mismatch");

        // --- STATE ASSERTIONS ---
        // Adapter should not retain gas tokens after swap (all swapped to PATH_USD)
        assertEq(adapterGasTokenAfter, adapterGasTokenBefore, "Adapter should not retain gas token");
        // Adapter should not retain PATH_USD - wrapped and sent to endpoint
        assertEq(adapterPathUsdAfter, adapterPathUsdBefore, "Adapter should not retain PATH_USD");
        // Verify endpoint received the LZEndpointDollar (wrapped PATH_USD)
        assertEq(endpointLzUsdAfter, nativeFee, "Endpoint should receive LZEndpointDollar");
        assertEq(lzEndpoint.lastNativeFee(), nativeFee, "Endpoint recorded correct nativeFee");

        // --- ALLOWANCE ASSERTIONS ---
        // Adapter's allowance to DEX should be zero or reduced after swap
        uint256 adapterAllowanceToDex = otherToken.allowance(address(adapter), address(StdPrecompiles.STABLECOIN_DEX));
        assertEq(adapterAllowanceToDex, 0, "DEX allowance should be consumed");
    }

    // ---------------------------------------------------
    // _debit Tests
    // ---------------------------------------------------

    function test_Debit_BurnsTokensAndTracksSupply() external {
        uint256 sendAmount = 100e6;
        uint256 nativeFee = 10e6;

        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);
        frxUsdToken.mint(alice, sendAmount);
        StdTokens.PATH_USD.mint(alice, nativeFee); // Mint PATH_USD for gas payment
        _setupPeer();

        vm.startPrank(alice);
        frxUsdToken.approve(address(adapter), type(uint256).max);
        StdTokens.PATH_USD.approve(address(adapter), type(uint256).max); // Approve PATH_USD for gas
        vm.stopPrank();

        uint256 totalSupplyBefore = frxUsdToken.totalSupply();

        _executeSend(alice, sendAmount, nativeFee);

        assertEq(adapter.totalTransferTo(DST_EID), sendAmount);
        assertEq(frxUsdToken.totalSupply(), totalSupplyBefore - sendAmount);
    }

    // ---------------------------------------------------
    // _quote Override Tests
    // ---------------------------------------------------

    /// @dev Helper to build a SendParam suitable for quoting (minAmountLD = 0 to avoid slippage checks)
    function _buildQuoteSendParam(uint256 sendAmount) internal view returns (SendParam memory) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
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
        MessagingFee memory fee = adapter.quoteSend(sendParam, false);

        assertEq(fee.nativeFee, expectedFee, "Fee should be in endpoint native token terms (no conversion)");
        assertEq(fee.lzTokenFee, 0, "lzTokenFee should be 0");
    }

    /// @dev When user's gas token is non-whitelisted, quoteSend returns fee in endpoint-native units
    function test_QuoteSend_ReturnsEndpointNativeFee_WhenUserGasTokenIsNonWhitelisted() external {
        uint256 sendAmount = 100e6;
        uint256 nativeFee = 20_000e6; // Must be >= MIN_ORDER_AMOUNT for DEX quote

        lzEndpoint.setMockNativeFee(nativeFee);
        _setUserGasToken(alice, address(frxUsdToken));
        _addDexLiquidity(address(frxUsdToken), nativeFee * 2);
        _setupPeer();

        SendParam memory sendParam = _buildQuoteSendParam(sendAmount);
        vm.prank(alice);
        MessagingFee memory fee = adapter.quoteSend(sendParam, false);

        // Fee stays in endpoint-native units — use quoteUserTokenFee() for user token cost
        assertEq(fee.nativeFee, nativeFee, "Fee should remain in endpoint-native units (no conversion)");
        assertEq(fee.lzTokenFee, 0, "lzTokenFee should be 0");
    }

    /// @dev quoteUserTokenFee returns the user's gas token amount for a given endpoint fee
    function test_QuoteUserTokenFee_ReturnsUserTokenAmount() external {
        uint256 endpointFee = 20_000e6;

        _addDexLiquidity(address(frxUsdToken), endpointFee * 2);

        uint256 userTokenAmount = adapter.quoteUserTokenFee(address(frxUsdToken), endpointFee);

        // At 1:1 stablecoin pricing, userToken amount should be >= endpoint fee (swap overhead)
        assertGe(userTokenAmount, endpointFee, "User token amount should be >= endpoint fee");
    }

    /// @dev quoteUserTokenFee returns endpoint fee directly for whitelisted tokens
    function test_QuoteUserTokenFee_ReturnsEndpointFee_WhenWhitelisted() external {
        uint256 endpointFee = 10e6;

        uint256 userTokenAmount = adapter.quoteUserTokenFee(StdTokens.PATH_USD_ADDRESS, endpointFee);

        assertEq(userTokenAmount, endpointFee, "Whitelisted token should return endpoint fee 1:1");
    }

    /// @dev quoteUserTokenFee returns 0 for zero fee
    function test_QuoteUserTokenFee_ReturnsZero_WhenFeeIsZero() external {
        uint256 userTokenAmount = adapter.quoteUserTokenFee(address(frxUsdToken), 0);

        assertEq(userTokenAmount, 0, "Should return 0 for zero fee");
    }

    /// @dev quoteSend with zero nativeFee returns zero (no conversion needed)
    function test_QuoteSend_ReturnsZero_WhenNativeFeeIsZero() external {
        uint256 sendAmount = 100e6;

        lzEndpoint.setMockNativeFee(0);
        _setUserGasToken(alice, address(frxUsdToken));
        _setupPeer();

        SendParam memory sendParam = _buildQuoteSendParam(sendAmount);
        vm.prank(alice);
        MessagingFee memory fee = adapter.quoteSend(sendParam, false);

        assertEq(fee.nativeFee, 0, "Fee should be 0 when no native fee required");
    }

    // ---------------------------------------------------
    // Initialization Tests
    // ---------------------------------------------------

    function test_Implementation_CannotBeInitialized() external {
        FraxOFTMintableAdapterUpgradeableTIP20 newImpl = new FraxOFTMintableAdapterUpgradeableTIP20(
            address(frxUsdToken),
            address(lzEndpoint)
        );

        vm.expectRevert();
        newImpl.initialize(alice);
    }

    function test_Proxy_CannotBeReinitialized() external {
        vm.expectRevert();
        adapter.initialize(alice);
    }

    // ---------------------------------------------------
    // send() Override Tests
    // ---------------------------------------------------

    /// @dev send() reverts when msg.value > 0 (EndpointV2Alt uses ERC20 for gas, not native ETH)
    function test_Send_RevertsWhenMsgValueNonZero() external {
        uint256 sendAmount = 100e6;
        uint256 nativeFee = 10e6;

        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);
        frxUsdToken.mint(alice, sendAmount);
        StdTokens.PATH_USD.mint(alice, nativeFee);
        _setupPeer();

        vm.startPrank(alice);
        frxUsdToken.approve(address(adapter), type(uint256).max);
        StdTokens.PATH_USD.approve(address(adapter), type(uint256).max);
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
        adapter.send{ value: 1 ether }(sendParam, MessagingFee({ nativeFee: nativeFee, lzTokenFee: 0 }), alice);
    }

    /// @dev send() succeeds when msg.value == 0 (correct usage for EndpointV2Alt)
    function test_Send_SucceedsWhenMsgValueZero() external {
        uint256 sendAmount = 100e6;
        uint256 nativeFee = 10e6;

        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);
        frxUsdToken.mint(alice, sendAmount);
        StdTokens.PATH_USD.mint(alice, nativeFee);
        _setupPeer();

        vm.startPrank(alice);
        frxUsdToken.approve(address(adapter), type(uint256).max);
        StdTokens.PATH_USD.approve(address(adapter), type(uint256).max);
        vm.stopPrank();

        SendParam memory sendParam = _buildSendParam(sendAmount);

        // Should succeed with msg.value == 0
        vm.prank(alice);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) = adapter.send{ value: 0 }(
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
