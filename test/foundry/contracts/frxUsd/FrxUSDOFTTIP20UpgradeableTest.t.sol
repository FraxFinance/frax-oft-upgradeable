// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FrxUSDOFTTIP20Upgradeable } from "contracts/frxUsd/FrxUSDOFTTIP20Upgradeable.sol";
import { ITIP20Frax } from "contracts/interfaces/ITIP20Frax.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { FraxTest } from "frax-std/FraxTest.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";

contract FrxUSDOFTTIP20UpgradeableTest is FraxTest {
    FrxUSDOFTTIP20Upgradeable oft;
    address proxyAdmin = address(0x9999); // Separate proxy admin address
    address contractOwner = address(this); // Contract owner for roles
    address lzEndpoint = address(0x1234); // Mock LZ endpoint
    address quoteToken = address(0x5678); // Mock quote token
    address al = vm.addr(0x41);
    address bob = vm.addr(0xb0b);
    address carl = vm.addr(0xc421);

    function setUp() external {
        // Mock the LayerZero endpoint
        vm.etch(lzEndpoint, hex"00");
        
        // Mock the quote token with quoteToken() returning address(0)
        vm.etch(quoteToken, hex"00");
        vm.mockCall(
            quoteToken,
            abi.encodeWithSignature("quoteToken()"),
            abi.encode(address(0))
        );
        
        // Mock TIP403 Registry precompile to always return true for isAuthorized
        address tip403Registry = 0x403c000000000000000000000000000000000000;
        vm.mockCall(
            tip403Registry,
            abi.encodeWithSignature("isAuthorized(uint64,address)"),
            abi.encode(true)
        );
        
        // Mock TIP20Factory to always return true for isTIP20
        address factory = 0x20Fc000000000000000000000000000000000000;
        vm.mockCall(
            factory,
            abi.encodeWithSignature("isTIP20(address)"),
            abi.encode(true)
        );
        
        // Deploy implementation
        FrxUSDOFTTIP20Upgradeable implementation = new FrxUSDOFTTIP20Upgradeable(lzEndpoint);
        
        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            FrxUSDOFTTIP20Upgradeable.initialize.selector,
            contractOwner,         // _delegate (owner)
            "USD",                 // _currency
            ITIP20(quoteToken),    // _quoteToken
            contractOwner          // _admin (gets all roles)
        );
        
        // Deploy TransparentUpgradeableProxy with initialization
        // Use a different address as proxy admin so test contract can interact normally
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            proxyAdmin,  // proxy admin address (different from contract owner)
            initData
        );
        
        // Cast proxy to interface
        oft = FrxUSDOFTTIP20Upgradeable(address(proxy));
    }

    // ---------------------------------------------------
    // Paused Tests
    // ---------------------------------------------------

    /// @dev Verifies paused() returns false when contract is not paused
    function test_Paused_returnsFalse() external {
        assertFalse(oft.paused());
    }

    /// @dev Verifies paused() returns true after pause() is called
    function test_Paused_returnsTrue() external {
        vm.prank(oft.owner());
        oft.pause();
        assertTrue(oft.paused());
    }

    // ---------------------------------------------------
    // SupplyCap Tests
    // ---------------------------------------------------

    /// @dev Verifies supply cap is initially set to type(uint128).max
    function test_SupplyCap_initiallyZero() external {
        assertEq(oft.supplyCap(), type(uint128).max);
    }

    /// @dev Verifies owner can successfully set a supply cap
    function test_SetSupplyCap_succeeds() external {
        uint256 newCap = 1_000_000e18;

        vm.prank(oft.owner());
        oft.setSupplyCap(newCap);

        assertEq(oft.supplyCap(), newCap);
    }

    /// @dev Verifies non-owner cannot set supply cap
    function test_SetSupplyCap_OnlyOwner() external {
        vm.prank(al);
        vm.expectRevert();
        oft.setSupplyCap(1_000_000e18);
    }

    // ---------------------------------------------------
    // TransferPolicyId Tests
    // ---------------------------------------------------

    /// @dev Verifies transfer policy ID is initially 1 (always-allow policy)
    function test_TransferPolicyId_initiallyZero() external {
        assertEq(oft.transferPolicyId(), 1);
    }

    /// @dev Verifies owner can successfully change transfer policy ID
    function test_ChangeTransferPolicyId_succeeds() external {
        uint64 newPolicyId = 42;

        vm.prank(oft.owner());
        oft.changeTransferPolicyId(newPolicyId);

        assertEq(oft.transferPolicyId(), newPolicyId);
    }

    /// @dev Verifies non-owner cannot change transfer policy ID
    function test_ChangeTransferPolicyId_OnlyOwner() external {
        vm.prank(al);
        vm.expectRevert();
        oft.changeTransferPolicyId(42);
    }

    // ---------------------------------------------------
    // Currency Tests
    // ---------------------------------------------------

    /// @dev Verifies currency string is initially "USD"
    function test_Currency_initiallyEmpty() external {
        assertEq(oft.currency(), "USD");
    }

    // ---------------------------------------------------
    // QuoteToken Tests
    // ---------------------------------------------------

    /// @dev Verifies quote token is initially set to the provided token
    function test_QuoteToken_initiallyZero() external {
        assertEq(address(oft.quoteToken()), quoteToken);
    }

    /// @dev Verifies next quote token is initially set to the provided token
    function test_NextQuoteToken_initiallyZero() external {
        assertEq(address(oft.nextQuoteToken()), quoteToken);
    }

    /// @dev Verifies owner can set next quote token
    function test_SetNextQuoteToken_succeeds() external {
        address anotherToken = address(0xABC123);
        
        // Mock currency() to return "USD"
        vm.mockCall(
            anotherToken,
            abi.encodeWithSignature("currency()"),
            abi.encode("USD")
        );

        vm.prank(oft.owner());
        oft.setNextQuoteToken(ITIP20(anotherToken));

        assertEq(address(oft.nextQuoteToken()), anotherToken);
    }

    /// @dev Verifies non-owner cannot set next quote token
    function test_SetNextQuoteToken_OnlyOwner() external {
        vm.prank(al);
        vm.expectRevert();
        oft.setNextQuoteToken(ITIP20(address(0x123)));
    }

    /// @dev Verifies quote token update completion moves nextQuoteToken to quoteToken
    function test_CompleteQuoteTokenUpdate_succeeds() external {
        address anotherToken = address(0xABC123);
        
        // Mock currency() and quoteToken() to return proper values
        vm.mockCall(
            anotherToken,
            abi.encodeWithSignature("currency()"),
            abi.encode("USD")
        );
        vm.mockCall(
            anotherToken,
            abi.encodeWithSignature("quoteToken()"),
            abi.encode(address(0))
        );

        vm.startPrank(oft.owner());
        oft.setNextQuoteToken(ITIP20(anotherToken));

        vm.expectEmit(true, true, false, false);
        emit ITIP20Frax.QuoteTokenUpdate(oft.owner(), ITIP20(anotherToken));
        oft.completeQuoteTokenUpdate();
        vm.stopPrank();

        assertEq(address(oft.quoteToken()), address(anotherToken));
        // nextQuoteToken remains as set, it's not reset to 0
        assertEq(address(oft.nextQuoteToken()), address(anotherToken));
    }

    /// @dev Verifies completing quote token update reverts if nextQuoteToken creates a loop
    function test_CompleteQuoteTokenUpdate_InvalidQuoteToken_reverts() external {
        // Create a mock token that has THIS token as its quote token (loop)
        address loopToken = address(0xDEAD);
        
        // Mock loopToken.currency() to return "USD"
        vm.mockCall(
            loopToken,
            abi.encodeWithSignature("currency()"),
            abi.encode("USD")
        );
        
        // Mock loopToken.quoteToken() to return address(oft) - this creates a loop!
        vm.mockCall(
            loopToken,
            abi.encodeWithSignature("quoteToken()"),
            abi.encode(address(oft))
        );
        
        vm.startPrank(oft.owner());
        oft.setNextQuoteToken(ITIP20(loopToken));
        
        vm.expectRevert(ITIP20Frax.InvalidQuoteToken.selector);
        oft.completeQuoteTokenUpdate();
        vm.stopPrank();
    }

    /// @dev Verifies non-owner cannot complete quote token update
    function test_CompleteQuoteTokenUpdate_OnlyOwner() external {
        vm.prank(al);
        vm.expectRevert();
        oft.completeQuoteTokenUpdate();
    }

    // ---------------------------------------------------
    // Reward Functions Tests
    // ---------------------------------------------------

    /// @dev Verifies global reward per token is initially zero
    function test_GlobalRewardPerToken_initiallyZero() external {
        assertEq(oft.globalRewardPerToken(), 0);
    }

    /// @dev Verifies opted-in supply is initially zero
    function test_OptedInSupply_initiallyZero() external {
        assertEq(oft.optedInSupply(), 0);
    }

    /// @dev Verifies user reward info is initially empty for any address
    function test_UserRewardInfo_initiallyEmpty() external {
        (address rewardRecipient, uint256 rewardPerToken, uint256 rewardBalance) = oft.userRewardInfo(al);
        assertEq(rewardRecipient, address(0));
        assertEq(rewardPerToken, 0);
        assertEq(rewardBalance, 0);
    }

    /// @dev Verifies user can set their own reward recipient
    function test_SetRewardRecipient_succeeds() external {
        vm.prank(al);
        vm.expectEmit(true, true, false, false);
        emit ITIP20Frax.RewardRecipientSet(al, bob);
        oft.setRewardRecipient(bob);

        (address rewardRecipient, , ) = oft.userRewardInfo(al);
        assertEq(rewardRecipient, bob);
    }

    /// @dev Verifies startReward reverts when seconds_ > 0 (scheduled rewards disabled)
    function test_StartReward_ScheduledRewardsDisabled_reverts() external {
        // First mint tokens to owner
        vm.prank(oft.owner());
        oft.mint(oft.owner(), 1000e18);
        
        vm.prank(oft.owner());
        vm.expectRevert(ITIP20Frax.ScheduledRewardsDisabled.selector);
        oft.startReward(1000e18, 100); // seconds_ > 0
    }

    /// @dev Verifies startReward reverts when no supply has opted in
    function test_StartReward_NoOptedInSupply_reverts() external {
        // First mint tokens to owner
        vm.prank(oft.owner());
        oft.mint(oft.owner(), 1000e18);
        
        vm.prank(oft.owner());
        vm.expectRevert(ITIP20Frax.NoOptedInSupply.selector);
        oft.startReward(1000e18, 0);
    }

    /// @dev Verifies non-owner cannot start rewards
    function test_StartReward_OnlyOwner() external {
        vm.prank(al);
        vm.expectRevert();
        oft.startReward(1000e18, 0);
    }

    /// @dev Verifies claimRewards returns zero when no rewards available
    function test_ClaimRewards_returnsZero() external {
        vm.prank(al);
        uint256 claimed = oft.claimRewards();
        assertEq(claimed, 0);
    }

    // ---------------------------------------------------
    // Burn Tests
    // ---------------------------------------------------

    /// @dev Verifies user can burn their own tokens
    function test_Burn_succeeds() external {
        deal(address(oft), al, 10e18);

        vm.prank(al);
        vm.expectEmit(true, false, false, true);
        emit ITIP20Frax.Burn(al, 5e18);
        oft.burn(5e18);

        assertEq(oft.balanceOf(al), 5e18);
    }

    /// @dev Verifies user can burn their entire balance
    function test_Burn_fullBalance_succeeds() external {
        deal(address(oft), al, 10e18);

        vm.prank(al);
        oft.burn(10e18);

        assertEq(oft.balanceOf(al), 0);
    }

    /// @dev Verifies owner can burn tokens from blocked accounts
    function test_BurnBlocked_succeeds() external {
        deal(address(oft), al, 10e18);

        // Mock TIP403 to return false for this address (blocked)
        address tip403Registry = 0x403c000000000000000000000000000000000000;
        vm.mockCall(
            tip403Registry,
            abi.encodeWithSignature("isAuthorized(uint64,address)", 1, al),
            abi.encode(false)
        );

        vm.prank(oft.owner());
        vm.expectEmit(true, false, false, true);
        emit ITIP20Frax.BurnBlocked(al, 5e18);
        oft.burnBlocked(al, 5e18);

        assertEq(oft.balanceOf(al), 5e18);
    }

    /// @dev Verifies non-owner cannot burn from blocked accounts
    function test_BurnBlocked_OnlyOwner() external {
        deal(address(oft), al, 10e18);

        vm.prank(bob);
        vm.expectRevert();
        oft.burnBlocked(al, 5e18);
    }

    /// @dev Verifies user can burn tokens with an attached memo
    function test_BurnWithMemo_succeeds() external {
        deal(address(oft), al, 10e18);
        bytes32 memo = keccak256("test memo");

        vm.prank(al);
        vm.expectEmit(true, false, false, true);
        emit ITIP20Frax.Burn(al, 5e18);
        oft.burnWithMemo(5e18, memo);

        assertEq(oft.balanceOf(al), 5e18);
    }

    // ---------------------------------------------------
    // Mint Tests
    // ---------------------------------------------------

    /// @dev Verifies owner can mint tokens to any address
    function test_Mint_succeeds() external {
        vm.prank(oft.owner());
        vm.expectEmit(true, false, false, true);
        emit ITIP20Frax.Mint(al, 100e18);
        oft.mint(al, 100e18);

        assertEq(oft.balanceOf(al), 100e18);
    }

    /// @dev Verifies non-owner cannot mint tokens
    function test_Mint_OnlyOwner() external {
        vm.prank(al);
        vm.expectRevert();
        oft.mint(bob, 100e18);
    }

    /// @dev Verifies minting reverts when it would exceed supply cap
    function test_Mint_SupplyCapExceeded_reverts() external {
        vm.startPrank(oft.owner());
        oft.setSupplyCap(100e18);

        vm.expectRevert(ITIP20Frax.SupplyCapExceeded.selector);
        oft.mint(al, 101e18);
        vm.stopPrank();
    }

    /// @dev Verifies minting succeeds when exactly at supply cap
    function test_Mint_atSupplyCap_succeeds() external {
        vm.startPrank(oft.owner());
        oft.setSupplyCap(100e18);
        oft.mint(al, 100e18);
        vm.stopPrank();

        assertEq(oft.balanceOf(al), 100e18);
    }

    /// @dev Verifies unlimited minting when no supply cap is set
    function test_Mint_noSupplyCap_succeeds() external {
        vm.prank(oft.owner());
        oft.mint(al, 1_000_000e18);

        assertEq(oft.balanceOf(al), 1_000_000e18);
    }

    /// @dev Verifies owner can mint tokens with an attached memo
    function test_MintWithMemo_succeeds() external {
        bytes32 memo = keccak256("mint memo");

        vm.prank(oft.owner());
        vm.expectEmit(true, false, false, true);
        emit ITIP20Frax.Mint(al, 100e18);
        oft.mintWithMemo(al, 100e18, memo);

        assertEq(oft.balanceOf(al), 100e18);
    }

    /// @dev Verifies non-owner cannot mint with memo
    function test_MintWithMemo_OnlyOwner() external {
        vm.prank(al);
        vm.expectRevert();
        oft.mintWithMemo(bob, 100e18, keccak256("memo"));
    }

    /// @dev Verifies mintWithMemo also respects supply cap
    function test_MintWithMemo_SupplyCapExceeded_reverts() external {
        vm.startPrank(oft.owner());
        oft.setSupplyCap(100e18);

        vm.expectRevert(ITIP20Frax.SupplyCapExceeded.selector);
        oft.mintWithMemo(al, 101e18, keccak256("memo"));
        vm.stopPrank();
    }

    // ---------------------------------------------------
    // Transfer With Memo Tests
    // ---------------------------------------------------

    /// @dev Verifies user can transfer tokens with an attached memo
    function test_TransferWithMemo_succeeds() external {
        deal(address(oft), al, 100e18);
        bytes32 memo = keccak256("transfer memo");

        vm.prank(al);
        vm.expectEmit(true, true, true, true);
        emit ITIP20Frax.TransferWithMemo(al, bob, 50e18, memo);
        oft.transferWithMemo(bob, 50e18, memo);

        assertEq(oft.balanceOf(al), 50e18);
        assertEq(oft.balanceOf(bob), 50e18);
    }

    /// @dev Verifies transferFrom with memo works with proper allowance
    function test_TransferFromWithMemo_succeeds() external {
        deal(address(oft), al, 100e18);
        bytes32 memo = keccak256("transferFrom memo");

        vm.prank(al);
        oft.approve(bob, 50e18);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit ITIP20Frax.TransferWithMemo(al, carl, 50e18, memo);
        bool success = oft.transferFromWithMemo(al, carl, 50e18, memo);

        assertTrue(success);
        assertEq(oft.balanceOf(al), 50e18);
        assertEq(oft.balanceOf(carl), 50e18);
    }

    /// @dev Verifies transferFromWithMemo reverts with insufficient allowance
    function test_TransferFromWithMemo_insufficientAllowance_reverts() external {
        deal(address(oft), al, 100e18);

        vm.prank(al);
        oft.approve(bob, 25e18);

        vm.prank(bob);
        vm.expectRevert();
        oft.transferFromWithMemo(al, carl, 50e18, keccak256("memo"));
    }

    // ---------------------------------------------------
    // SystemTransferFrom Tests
    // ---------------------------------------------------

    /// @dev Verifies TIP_FEE_MANAGER_ADDRESS can perform system transfers
    function test_SystemTransferFrom_succeeds() external {
        // Mint tokens to al
        vm.prank(oft.owner());
        oft.mint(al, 100e18);

        address tipFeeManager = 0xfeEC000000000000000000000000000000000000;
        vm.prank(tipFeeManager);
        bool success = oft.systemTransferFrom(al, bob, 50e18);

        assertTrue(success);
        assertEq(oft.balanceOf(al), 50e18);
        assertEq(oft.balanceOf(bob), 50e18);
    }

    /// @dev Verifies non-TIP_FEE_MANAGER cannot perform system transfers
    function test_SystemTransferFrom_OnlyOwner() external {
        // Mint tokens to al
        vm.prank(oft.owner());
        oft.mint(al, 100e18);

        vm.prank(bob);
        vm.expectRevert();
        oft.systemTransferFrom(al, carl, 50e18);
    }

    /// @dev Verifies system transfers do not require allowance
    function test_SystemTransferFrom_noAllowanceRequired() external {
        // Mint tokens to al
        vm.prank(oft.owner());
        oft.mint(al, 100e18);
        // No approval given, but TIP_FEE_MANAGER can still transfer

        address tipFeeManager = 0xfeEC000000000000000000000000000000000000;
        vm.prank(tipFeeManager);
        bool success = oft.systemTransferFrom(al, bob, 100e18);

        assertTrue(success);
        assertEq(oft.balanceOf(al), 0);
        assertEq(oft.balanceOf(bob), 100e18);
    }

    // ---------------------------------------------------
    // Fee Hook Tests (empty implementations)
    // ---------------------------------------------------

    /// @dev Verifies transferFeePreTx hook does not revert (empty implementation)
    function test_TransferFeePreTx_doesNotRevert() external {
        // First mint tokens to al
        vm.prank(oft.owner());
        oft.mint(al, 100e18);
        
        // Call as TIP_FEE_MANAGER_ADDRESS
        address tipFeeManager = 0xfeEC000000000000000000000000000000000000;
        vm.prank(tipFeeManager);
        oft.transferFeePreTx(al, 100e18);
    }

    /// @dev Verifies transferFeePostTx hook does not revert (empty implementation)
    function test_TransferFeePostTx_doesNotRevert() external {
        // First mint tokens to TIP_FEE_MANAGER_ADDRESS
        address tipFeeManager = 0xfeEC000000000000000000000000000000000000;
        vm.prank(oft.owner());
        oft.mint(tipFeeManager, 100e18);
        
        // Call as TIP_FEE_MANAGER_ADDRESS
        vm.prank(tipFeeManager);
        oft.transferFeePostTx(al, 50e18, 25e18);
    }

    // ---------------------------------------------------
    // Integration Tests
    // ---------------------------------------------------

    /// @dev Verifies balance and total supply remain correct after mint and burn
    function test_MintThenBurn_maintainsCorrectBalance() external {
        vm.startPrank(oft.owner());
        oft.mint(al, 100e18);
        vm.stopPrank();

        assertEq(oft.balanceOf(al), 100e18);
        assertEq(oft.totalSupply(), 100e18);

        vm.prank(al);
        oft.burn(30e18);

        assertEq(oft.balanceOf(al), 70e18);
        assertEq(oft.totalSupply(), 70e18);
    }

    /// @dev Verifies supply cap is enforced across multiple mint operations
    function test_SupplyCapEnforcedAcrossMultipleMints() external {
        vm.startPrank(oft.owner());
        oft.setSupplyCap(100e18);
        oft.mint(al, 50e18);
        oft.mint(bob, 40e18);

        // This should fail - would exceed cap
        vm.expectRevert(ITIP20Frax.SupplyCapExceeded.selector);
        oft.mint(carl, 20e18);

        // This should succeed - exactly at cap
        oft.mint(carl, 10e18);
        vm.stopPrank();

        assertEq(oft.totalSupply(), 100e18);
    }
}
