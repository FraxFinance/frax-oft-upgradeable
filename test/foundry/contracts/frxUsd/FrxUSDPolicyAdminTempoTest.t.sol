// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { FrxUSDPolicyAdminTempo } from "contracts/frxUsd/FrxUSDPolicyAdminTempo.sol";
import { ITIP403Registry } from "tempo-std/interfaces/ITIP403Registry.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { TempoTestHelpers } from "test/foundry/helpers/TempoTestHelpers.sol";

contract FrxUSDPolicyAdminTempoTest is TempoTestHelpers {
    FrxUSDPolicyAdminTempo public implementation;
    FrxUSDPolicyAdminTempo public policyAdmin;
    
    address owner = makeAddr("owner");
    address freezer = makeAddr("freezer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carl = makeAddr("carl");

    uint64 constant TEST_POLICY_ID = 1;

    function setUp() public {
        // Deploy implementation
        implementation = new FrxUSDPolicyAdminTempo();
        
        // Deploy proxy and initialize
        bytes memory initData = abi.encodeCall(FrxUSDPolicyAdminTempo.initialize, (owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        policyAdmin = FrxUSDPolicyAdminTempo(address(proxy));
    }

    // ---------------------------------------------------
    // Initialization tests
    // ---------------------------------------------------

    function test_Initialize_SetsOwner() public {
        assertEq(policyAdmin.owner(), owner);
    }

    function test_Initialize_CreatesPolicyId() public {
        assertGt(policyAdmin.policyId(), 0);
    }

    function test_Initialize_Version() public {
        assertEq(policyAdmin.version(), "1.0.0");
    }

    function test_Initialize_CannotReinitialize() public {
        vm.expectRevert();
        policyAdmin.initialize(alice);
    }

    function test_InitializeWithPolicy_SetsOwner() public {
        // Deploy new proxy with existing policy
        bytes memory initData = abi.encodeCall(
            FrxUSDPolicyAdminTempo.initializeWithPolicy, 
            (owner, TEST_POLICY_ID)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        FrxUSDPolicyAdminTempo admin = FrxUSDPolicyAdminTempo(address(proxy));
        
        assertEq(admin.owner(), owner);
        assertEq(admin.policyId(), TEST_POLICY_ID);
    }

    // ---------------------------------------------------
    // Freezer management tests
    // ---------------------------------------------------

    function test_AddFreezer_Succeeds() public {
        assertFalse(policyAdmin.isFreezer(freezer));
        
        vm.prank(owner);
        policyAdmin.addFreezer(freezer);
        
        assertTrue(policyAdmin.isFreezer(freezer));
        assertTrue(policyAdmin.freezers(freezer));
    }

    function test_AddFreezer_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit FrxUSDPolicyAdminTempo.AddFreezer(freezer);
        policyAdmin.addFreezer(freezer);
    }

    function test_AddFreezer_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        policyAdmin.addFreezer(freezer);
    }

    function test_AddFreezer_AlreadyFreezer_Reverts() public {
        vm.startPrank(owner);
        policyAdmin.addFreezer(freezer);
        
        vm.expectRevert(FrxUSDPolicyAdminTempo.AlreadyFreezer.selector);
        policyAdmin.addFreezer(freezer);
    }

    function test_RemoveFreezer_Succeeds() public {
        vm.startPrank(owner);
        policyAdmin.addFreezer(freezer);
        assertTrue(policyAdmin.isFreezer(freezer));
        
        policyAdmin.removeFreezer(freezer);
        assertFalse(policyAdmin.isFreezer(freezer));
    }

    function test_RemoveFreezer_EmitsEvent() public {
        vm.startPrank(owner);
        policyAdmin.addFreezer(freezer);
        
        vm.expectEmit(true, false, false, false);
        emit FrxUSDPolicyAdminTempo.RemoveFreezer(freezer);
        policyAdmin.removeFreezer(freezer);
    }

    function test_RemoveFreezer_OnlyOwner() public {
        vm.prank(owner);
        policyAdmin.addFreezer(freezer);
        
        vm.prank(alice);
        vm.expectRevert();
        policyAdmin.removeFreezer(freezer);
    }

    function test_RemoveFreezer_NotFreezer_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(FrxUSDPolicyAdminTempo.NotFreezer.selector);
        policyAdmin.removeFreezer(freezer);
    }

    // ---------------------------------------------------
    // Freeze tests
    // ---------------------------------------------------

    function test_Freeze_AsOwner_Succeeds() public {
        assertFalse(policyAdmin.isFrozen(alice));
        
        vm.prank(owner);
        policyAdmin.freeze(alice);
        
        assertTrue(policyAdmin.isFrozen(alice));
    }

    function test_Freeze_AsFreezer_Succeeds() public {
        vm.prank(owner);
        policyAdmin.addFreezer(freezer);
        
        assertFalse(policyAdmin.isFrozen(alice));
        
        vm.prank(freezer);
        policyAdmin.freeze(alice);
        
        assertTrue(policyAdmin.isFrozen(alice));
    }

    function test_Freeze_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit FrxUSDPolicyAdminTempo.AccountFrozen(alice);
        policyAdmin.freeze(alice);
    }

    function test_Freeze_NotFreezerOrOwner_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(FrxUSDPolicyAdminTempo.NotFreezer.selector);
        policyAdmin.freeze(bob);
    }

    function test_FreezeMany_AsOwner_Succeeds() public {
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = carl;
        
        vm.prank(owner);
        policyAdmin.freezeMany(accounts);
        
        assertTrue(policyAdmin.isFrozen(alice));
        assertTrue(policyAdmin.isFrozen(bob));
        assertTrue(policyAdmin.isFrozen(carl));
    }

    function test_FreezeMany_AsFreezer_Succeeds() public {
        vm.prank(owner);
        policyAdmin.addFreezer(freezer);
        
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        
        vm.prank(freezer);
        policyAdmin.freezeMany(accounts);
        
        assertTrue(policyAdmin.isFrozen(alice));
        assertTrue(policyAdmin.isFrozen(bob));
    }

    function test_FreezeMany_EmitsEvents() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit FrxUSDPolicyAdminTempo.AccountFrozen(alice);
        vm.expectEmit(true, false, false, false);
        emit FrxUSDPolicyAdminTempo.AccountFrozen(bob);
        policyAdmin.freezeMany(accounts);
    }

    function test_FreezeMany_NotFreezerOrOwner_Reverts() public {
        address[] memory accounts = new address[](1);
        accounts[0] = bob;
        
        vm.prank(alice);
        vm.expectRevert(FrxUSDPolicyAdminTempo.NotFreezer.selector);
        policyAdmin.freezeMany(accounts);
    }

    // ---------------------------------------------------
    // Thaw tests
    // ---------------------------------------------------

    function test_Thaw_Succeeds() public {
        vm.startPrank(owner);
        policyAdmin.freeze(alice);
        assertTrue(policyAdmin.isFrozen(alice));
        
        policyAdmin.thaw(alice);
        assertFalse(policyAdmin.isFrozen(alice));
    }

    function test_Thaw_EmitsEvent() public {
        vm.startPrank(owner);
        policyAdmin.freeze(alice);
        
        vm.expectEmit(true, false, false, false);
        emit FrxUSDPolicyAdminTempo.AccountThawed(alice);
        policyAdmin.thaw(alice);
    }

    function test_Thaw_OnlyOwner() public {
        vm.prank(owner);
        policyAdmin.freeze(alice);
        
        // Freezer cannot thaw
        vm.prank(owner);
        policyAdmin.addFreezer(freezer);
        
        vm.prank(freezer);
        vm.expectRevert();
        policyAdmin.thaw(alice);
    }

    function test_ThawMany_Succeeds() public {
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = carl;
        
        vm.startPrank(owner);
        policyAdmin.freezeMany(accounts);
        
        assertTrue(policyAdmin.isFrozen(alice));
        assertTrue(policyAdmin.isFrozen(bob));
        assertTrue(policyAdmin.isFrozen(carl));
        
        policyAdmin.thawMany(accounts);
        
        assertFalse(policyAdmin.isFrozen(alice));
        assertFalse(policyAdmin.isFrozen(bob));
        assertFalse(policyAdmin.isFrozen(carl));
    }

    function test_ThawMany_EmitsEvents() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        
        vm.startPrank(owner);
        policyAdmin.freezeMany(accounts);
        
        vm.expectEmit(true, false, false, false);
        emit FrxUSDPolicyAdminTempo.AccountThawed(alice);
        vm.expectEmit(true, false, false, false);
        emit FrxUSDPolicyAdminTempo.AccountThawed(bob);
        policyAdmin.thawMany(accounts);
    }

    function test_ThawMany_OnlyOwner() public {
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        
        vm.prank(owner);
        policyAdmin.freezeMany(accounts);
        
        vm.prank(freezer);
        vm.expectRevert();
        policyAdmin.thawMany(accounts);
    }

    // ---------------------------------------------------
    // View function tests
    // ---------------------------------------------------

    function test_IsFrozen_ReturnsFalseWhenNotFrozen() public {
        assertFalse(policyAdmin.isFrozen(alice));
    }

    function test_IsFreezer_ReturnsFalseWhenNotFreezer() public {
        assertFalse(policyAdmin.isFreezer(alice));
    }

    function test_GetPolicyData_ReturnsBlacklist() public {
        (ITIP403Registry.PolicyType policyType, address admin) = policyAdmin.getPolicyData();
        assertEq(uint8(policyType), uint8(ITIP403Registry.PolicyType.BLACKLIST));
        assertEq(admin, address(policyAdmin));
    }

    // ---------------------------------------------------
    // SetPolicyAdmin tests
    // ---------------------------------------------------

    function test_SetPolicyAdmin_Succeeds() public {
        vm.prank(owner);
        policyAdmin.setPolicyAdmin(alice);
        
        (, address admin) = policyAdmin.getPolicyData();
        assertEq(admin, alice);
    }

    function test_SetPolicyAdmin_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        policyAdmin.setPolicyAdmin(bob);
    }

    // ---------------------------------------------------
    // Ownership transfer tests (Ownable2Step)
    // ---------------------------------------------------

    function test_TransferOwnership_TwoStep() public {
        vm.prank(owner);
        policyAdmin.transferOwnership(alice);
        
        // Still old owner until accepted
        assertEq(policyAdmin.owner(), owner);
        assertEq(policyAdmin.pendingOwner(), alice);
        
        vm.prank(alice);
        policyAdmin.acceptOwnership();
        
        assertEq(policyAdmin.owner(), alice);
        assertEq(policyAdmin.pendingOwner(), address(0));
    }

    function test_AcceptOwnership_OnlyPendingOwner() public {
        vm.prank(owner);
        policyAdmin.transferOwnership(alice);
        
        vm.prank(bob);
        vm.expectRevert();
        policyAdmin.acceptOwnership();
    }

    // ---------------------------------------------------
    // TIP20 Integration tests - Freeze blocks transfers
    // ---------------------------------------------------

    function _createTIP20WithPolicy() internal returns (ITIP20 token) {
        // Create TIP20 token using shared helper
        token = _createTIP20("Test Token", "TEST", bytes32(uint256(1)));
        
        // Assign policyAdmin's policy to token
        token.changeTransferPolicyId(policyAdmin.policyId());
        
        // Mint tokens to users
        token.mint(alice, 1000e6);
        token.mint(bob, 1000e6);
        token.mint(carl, 1000e6);
    }

    function test_TIP20_UnfrozenUsersCanTransferByDefault() public {
        ITIP20 token = _createTIP20WithPolicy();
        
        // Verify policy is BLACKLIST type
        (ITIP403Registry.PolicyType policyType,) = policyAdmin.getPolicyData();
        assertEq(uint8(policyType), uint8(ITIP403Registry.PolicyType.BLACKLIST));
        
        // No freeze operations - all users should transfer normally
        
        // Alice transfers to Bob
        vm.prank(alice);
        token.transfer(bob, 100e6);
        assertEq(token.balanceOf(alice), 900e6);
        assertEq(token.balanceOf(bob), 1100e6);
        
        // Bob transfers to Carl
        vm.prank(bob);
        token.transfer(carl, 200e6);
        assertEq(token.balanceOf(bob), 900e6);
        assertEq(token.balanceOf(carl), 1200e6);
        
        // Carl transfers to Alice
        vm.prank(carl);
        token.transfer(alice, 150e6);
        assertEq(token.balanceOf(carl), 1050e6);
        assertEq(token.balanceOf(alice), 1050e6);
    }

    function test_TIP20_FrozenUserCannotTransfer() public {
        ITIP20 token = _createTIP20WithPolicy();
        
        // Freeze alice
        vm.prank(owner);
        policyAdmin.freeze(alice);
        
        // Alice cannot transfer (frozen) - use try-catch for precompile
        vm.prank(alice);
        try token.transfer(bob, 100e6) {
            fail("Transfer should have reverted");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), ITIP20.PolicyForbids.selector);
        }
        
        // Bob can still transfer (not frozen)
        vm.prank(bob);
        token.transfer(carl, 100e6);
        assertEq(token.balanceOf(carl), 1100e6);
    }

    function test_TIP20_FrozenUserCannotReceive() public {
        ITIP20 token = _createTIP20WithPolicy();
        
        // Freeze alice
        vm.prank(owner);
        policyAdmin.freeze(alice);
        
        // Bob cannot send to alice (alice is frozen) - use try-catch for precompile
        vm.prank(bob);
        try token.transfer(alice, 100e6) {
            fail("Transfer should have reverted");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), ITIP20.PolicyForbids.selector);
        }
        
        // Bob can send to carl (carl not frozen)
        vm.prank(bob);
        token.transfer(carl, 100e6);
        assertEq(token.balanceOf(carl), 1100e6);
    }

    function test_TIP20_FreezeManyBlocksMultipleUsers() public {
        ITIP20 token = _createTIP20WithPolicy();
        
        // Freeze alice and bob
        address[] memory toFreeze = new address[](2);
        toFreeze[0] = alice;
        toFreeze[1] = bob;
        
        vm.prank(owner);
        policyAdmin.freezeMany(toFreeze);
        
        // Alice cannot transfer - use try-catch for precompile
        vm.prank(alice);
        try token.transfer(carl, 100e6) {
            fail("Transfer should have reverted");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), ITIP20.PolicyForbids.selector);
        }
        
        // Bob cannot transfer - use try-catch for precompile
        vm.prank(bob);
        try token.transfer(carl, 100e6) {
            fail("Transfer should have reverted");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), ITIP20.PolicyForbids.selector);
        }
        
        // Carl can still transfer (not frozen)
        vm.prank(carl);
        token.transfer(owner, 100e6);
        assertEq(token.balanceOf(owner), 100e6);
    }

    function test_TIP20_ThawRestoresTransferAbility() public {
        ITIP20 token = _createTIP20WithPolicy();
        
        // Freeze alice
        vm.prank(owner);
        policyAdmin.freeze(alice);
        
        // Verify frozen - use try-catch for precompile
        vm.prank(alice);
        try token.transfer(bob, 100e6) {
            fail("Transfer should have reverted");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), ITIP20.PolicyForbids.selector);
        }
        
        // Thaw alice
        vm.prank(owner);
        policyAdmin.thaw(alice);
        
        // Alice can transfer again
        vm.prank(alice);
        token.transfer(bob, 100e6);
        assertEq(token.balanceOf(bob), 1100e6);
    }

    function test_TIP20_ThawManyRestoresMultipleUsers() public {
        ITIP20 token = _createTIP20WithPolicy();
        
        // Freeze alice and bob
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        
        vm.prank(owner);
        policyAdmin.freezeMany(accounts);
        
        // Both frozen - use try-catch for precompile
        vm.prank(alice);
        try token.transfer(carl, 100e6) {
            fail("Transfer should have reverted");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), ITIP20.PolicyForbids.selector);
        }
        
        vm.prank(bob);
        try token.transfer(carl, 100e6) {
            fail("Transfer should have reverted");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), ITIP20.PolicyForbids.selector);
        }
        
        // Thaw both
        vm.prank(owner);
        policyAdmin.thawMany(accounts);
        
        // Both can transfer now
        vm.prank(alice);
        token.transfer(carl, 100e6);
        assertEq(token.balanceOf(carl), 1100e6);
        
        vm.prank(bob);
        token.transfer(carl, 100e6);
        assertEq(token.balanceOf(carl), 1200e6);
    }

    function test_TIP20_PartialFreezeAndThaw() public {
        ITIP20 token = _createTIP20WithPolicy();
        
        // Freeze alice and bob, carl remains unfrozen
        address[] memory toFreeze = new address[](2);
        toFreeze[0] = alice;
        toFreeze[1] = bob;
        
        vm.prank(owner);
        policyAdmin.freezeMany(toFreeze);
        
        // Carl (unfrozen) can send and receive
        vm.prank(carl);
        token.transfer(owner, 100e6);
        
        // Thaw only alice
        vm.prank(owner);
        policyAdmin.thaw(alice);
        
        // Alice can now transfer
        vm.prank(alice);
        token.transfer(carl, 100e6);
        
        // Bob still frozen - use try-catch for precompile
        vm.prank(bob);
        try token.transfer(carl, 100e6) {
            fail("Transfer should have reverted");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), ITIP20.PolicyForbids.selector);
        }
    }
}
