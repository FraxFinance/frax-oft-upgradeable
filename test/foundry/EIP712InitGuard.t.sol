// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { ImplementationMock } from "contracts/mocks/ImplementationMock.sol";

import { TransparentUpgradeableProxy, ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @dev Derived contract that exposes the EIP-712 initializers outside any initializer context,
///      the surface the `onlyInitializing` guard exists to close.
contract EIP712InitExposed is FraxOFTUpgradeable {
    constructor(address _lzEndpoint) FraxOFTUpgradeable(_lzEndpoint) {}

    function exposedEIP712Init(string memory _name, string memory _version) external {
        __EIP712_init(_name, _version);
    }

    function exposedEIP712InitUnchained(string memory _name, string memory _version) external {
        __EIP712_init_unchained(_name, _version);
    }
}

/// @dev EIP-712 initializer guard (audit finding ZELLIC-SA8P5Q): __EIP712_init and __EIP712_init_unchained run
///      only inside an initializer/reinitializer context, so derived code cannot rewrite the signing domain.
contract EIP712InitGuardTest is Test {
    address constant ENDPOINT = address(0x1a44076050125825900e736c501f859c50fE728c);
    address owner = makeAddr("owner");
    address proxy;
    FraxOFTUpgradeable oft;

    function setUp() external {
        // The OApp initializer calls endpoint.setDelegate(); fake the endpoint so no fork is needed.
        vm.etch(ENDPOINT, hex"00");
        vm.mockCall(ENDPOINT, abi.encodeWithSignature("setDelegate(address)"), "");

        address implementation = address(new FraxOFTUpgradeable(ENDPOINT));
        proxy = address(new TransparentUpgradeableProxy(address(new ImplementationMock()), owner, ""));
        vm.prank(owner);
        ITransparentUpgradeableProxy(proxy).upgradeToAndCall(
            implementation,
            abi.encodeWithSelector(FraxOFTUpgradeable.initialize.selector, "Mock Frax Token", "mFRAX", owner)
        );
        oft = FraxOFTUpgradeable(proxy);
    }

    /// @dev reinitializer(3) path: __EIP712_init ran inside an initializer context and set the domain.
    function test_initialize_setsEip712Domain() external {
        (, string memory name, string memory version,,,,) = oft.eip712Domain();
        assertEq(name, "Mock Frax Token");
        assertEq(version, oft.version());
    }

    /// @dev reinitializer(4) path: initializeV120 re-runs __EIP712_init inside an initializer context.
    function test_initializeV120_succeedsInsideReinitializer() external {
        address implementation = address(new FraxOFTUpgradeable(ENDPOINT));
        vm.prank(owner);
        ITransparentUpgradeableProxy(proxy).upgradeToAndCall(
            implementation,
            abi.encodeWithSelector(FraxOFTUpgradeable.initializeV120.selector)
        );
        (, string memory name, string memory version,,,,) = oft.eip712Domain();
        assertEq(name, "Mock Frax Token");
        assertEq(version, "1.2.0");
        assertEq(oft.DOMAIN_SEPARATOR(), _domainSeparator(name, version));
    }

    /// @dev Outside an initializer context the helpers must revert and leave the domain untouched.
    function test_exposedInit_revertsOutsideInitializer() external {
        bytes32 before = oft.DOMAIN_SEPARATOR();
        address exposed = address(new EIP712InitExposed(ENDPOINT));
        vm.prank(owner);
        ITransparentUpgradeableProxy(proxy).upgradeTo(exposed);

        vm.expectRevert("Initializable: contract is not initializing");
        EIP712InitExposed(proxy).exposedEIP712Init("Evil", "9");
        vm.expectRevert("Initializable: contract is not initializing");
        EIP712InitExposed(proxy).exposedEIP712InitUnchained("Evil", "9");

        assertEq(oft.DOMAIN_SEPARATOR(), before);
    }

    /// @dev Same on the bare implementation (constructor ran _disableInitializers).
    function test_exposedInit_revertsOnImplementation() external {
        EIP712InitExposed impl = new EIP712InitExposed(ENDPOINT);
        vm.expectRevert("Initializable: contract is not initializing");
        impl.exposedEIP712Init("Evil", "9");
    }

    function _domainSeparator(string memory name, string memory version) internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)), keccak256(bytes(version)), block.chainid, proxy
        ));
    }
}
