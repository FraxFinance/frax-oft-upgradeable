// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alPrivateKey, sigUtils.getTypedDataHash(permit));

        vm.prank(bob);
        oft.permit({
            owner: al,
            spender: bob,
            value: 1e18,
            deadline: deadline,
            v: v,
            r: r,
            s: s
        });

        uint256 permitAllowanceAfter = oft.allowance(al, bob);
        assertEq(permitAllowanceAfter, 1e18, "Permit allowance should now be 1e18");
    }
}