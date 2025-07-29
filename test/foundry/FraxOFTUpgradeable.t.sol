// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

import {EIP3009Module} from "contracts/modules/EIP3009Module.sol";
import {SigUtils} from "./utils/SigUtils.sol";
import "frax-std/FraxTest.sol";


contract FraxOFTUpgradeableTest is FraxTest {

    SigUtils sigUtils;
    FraxOFTUpgradeable oft;
    uint256 alPrivateKey = 0x41;
    address al = vm.addr(alPrivateKey);
    address bob = vm.addr(0xb0b);
    address owner = vm.addr(0x12345);

    function setUp() external {
        vm.createSelectFork("https://rpc.frax.com");
        oft = FraxOFTUpgradeable(deployMockFraxOFT());
        sigUtils = new SigUtils(oft.DOMAIN_SEPARATOR());

        deal(address(oft), al, 100e18);
        deal(address(oft), bob, 100e18);
    }

    /// @notice ripped from DeployFraxOFTProtocol.deployFraxOFTUPgradeablesAndProxies()
    function deployMockFraxOFT() internal returns (address) {
        address proxyAdmin = address(new FraxProxyAdmin(owner));
        address implementationMock = address(new ImplementationMock());
        address implementation = address(new FraxOFTUpgradeable(0x1a44076050125825900e736c501f859c50fE728c)); // from L0Config.252.endpoint
        address proxy = address(new TransparentUpgradeableProxy(implementationMock, owner, ""));
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTUpgradeable.initialize.selector,
            "Mock Frax Token",
            "mFRAX",
            owner
        );
        vm.startPrank(owner);
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);
        vm.stopPrank();
        return (proxy);
    }

    function test_Permit_succeeds() external {
        /// al permits to bob
        uint256 permitAllowanceBefore = oft.allowance(al, bob);
        assertEq(permitAllowanceBefore, 0, "Permit allowance should be 0 beforehand");

        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = oft.nonces(al);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: al,
            spender: bob,
            value: 1e18,
            nonce: nonce,
            deadline: deadline
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alPrivateKey, sigUtils.getPermitTypedDataHash(permit));

        vm.prank(bob);
        oft.permit({
            owner: permit.owner,
            spender: permit.spender,
            value: permit.value,
            deadline: permit.deadline,
            v: v,
            r: r,
            s: s
        });

        uint256 permitAllowanceAfter = oft.allowance(al, bob);
        assertEq(permitAllowanceAfter, 1e18, "Permit allowance should now be 1e18");
    }

    function test_TransferWithAuthorization_succeeds() external {
        uint256 balanceBefore = oft.balanceOf(bob);
        assertEq(balanceBefore, 100e18, "Bob's balance should be 100e18 before transfer");

        // al authorized bob to transfer 1e18 from al to bob
        uint256 value = 1e18;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = bytes32(abi.encode(1));
        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            from: al,
            to: bob,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alPrivateKey, sigUtils.getTransferWithAuthorizationTypedDataHash(authorization));

        vm.prank(bob);
        oft.transferWithAuthorization({
            from: al,
            to: bob,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        uint256 balanceAfter = oft.balanceOf(bob);
        assertEq(balanceAfter, balanceBefore + value, "Bob's balance should now be 101e18");
    }

    function test_ReceiveWithAuthorization_succeeds() external {
        uint256 balanceBefore = oft.balanceOf(bob);
        assertEq(balanceBefore, 100e18, "Bob's balance should be 100e18 before transfer");

        // al authorized bob to transfer 1e18 from al to bob
        uint256 value = 1e18;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = bytes32(abi.encode(1));
        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            from: al,
            to: bob,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alPrivateKey, sigUtils.getReceiveWithAuthorizationTypedDataHash(authorization));

        vm.prank(bob);
        oft.receiveWithAuthorization({
            from: al,
            to: bob,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        uint256 balanceAfter = oft.balanceOf(bob);
        assertEq(balanceAfter, balanceBefore + value, "Bob's balance should now be 101e18");
    }

    function test_CancelAuthorization_succeeds() external {
        // al authorizes bob to transfer 1e18 from al to bob
        uint256 value = 1e18;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = bytes32(abi.encode(1));
        SigUtils.CancelAuthorization memory cancelAuthorization = SigUtils.CancelAuthorization({
            authorizer: al,
            nonce: nonce
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alPrivateKey, sigUtils.getCancelAuthorizationTypedDataHash(cancelAuthorization));

        // al cancels the authorization
        vm.prank(al);
        oft.cancelAuthorization({
            authorizer: al,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            from: al,
            to: bob,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce
        });
        (v, r, s) = vm.sign(alPrivateKey, sigUtils.getTransferWithAuthorizationTypedDataHash(authorization));

        // try to transfer with authorization should fail
        vm.expectRevert(EIP3009Module.UsedOrCanceledAuthorization.selector);
        vm.prank(bob);
        oft.transferWithAuthorization({
            from: al,
            to: bob,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });
    }
}