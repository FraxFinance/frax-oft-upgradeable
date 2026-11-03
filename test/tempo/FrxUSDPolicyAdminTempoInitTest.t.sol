// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";
import { ITIP403Registry } from "tempo-std/interfaces/ITIP403Registry.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { FrxUSDPolicyAdminTempo } from "contracts/frxUsd/FrxUSDPolicyAdminTempo.sol";

/// @dev Pre-fix shape of `initializeWithPolicy` (no validation), kept so the reproductions can still
///      construct the broken states the validation now rejects.
contract UnvalidatedPolicyAdmin is FrxUSDPolicyAdminTempo {
    bytes32 private constant LOC = 0x26bddd9d371485490a0eb07480715865c05a6d3ae02ab4f9213c12782ba8dc00;

    function initializeUnvalidated(address _owner, uint64 _policyId) external initializer {
        __Ownable2Step_init();
        _transferOwnership(_owner);
        assembly {
            sstore(LOC, _policyId)
        }
    }
}

/// @dev Upgrade target used to show a mis-set policyId is recoverable through the proxy.
contract FrxUSDPolicyAdminTempoV2 is FrxUSDPolicyAdminTempo {
    bytes32 private constant LOC = 0x26bddd9d371485490a0eb07480715865c05a6d3ae02ab4f9213c12782ba8dc00;

    function repairPolicyId(uint64 _policyId) external reinitializer(2) {
        assembly {
            sstore(LOC, _policyId)
        }
    }
}

/// @notice What an unvalidated policyId used to allow, and whether it was recoverable. These states
///         can no longer be reached through `initializeWithPolicy`; see the validation suite below.
contract FrxUSDPolicyAdminTempoInitTest is Test {
    address internal constant LIVE_PROXY = 0x766c2BD9C6dDc5BeE9ACd7D4C8ADD5b969952969;
    address internal owner = address(0xA11CE);
    address internal proxyAdmin = address(0xAD801);
    address internal victim = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork(vm.envOr("TEMPO_RPC_URL", string("https://rpc.tempo.xyz")));
        require(block.chainid == 4217, "expected a Tempo fork");
    }

    /// @dev Builds the pre-fix broken state deliberately; `initializeWithPolicy` now rejects all of it.
    function _deploy(uint64 _policyId) internal returns (FrxUSDPolicyAdminTempo p) {
        address impl = address(new UnvalidatedPolicyAdmin());
        p = FrxUSDPolicyAdminTempo(
            address(
                new TransparentUpgradeableProxy(
                    impl,
                    proxyAdmin,
                    abi.encodeCall(UnvalidatedPolicyAdmin.initializeUnvalidated, (owner, _policyId))
                )
            )
        );
    }

    /// @notice The live deployment is correctly configured, so none of this is currently live.
    function test_LiveDeploymentIsBlacklistTypedAndSelfAdministered() public {
        (ITIP403Registry.PolicyType t, address admin) = FrxUSDPolicyAdminTempo(LIVE_PROXY).getPolicyData();
        assertEq(uint8(t), uint8(ITIP403Registry.PolicyType.BLACKLIST), "live policy must be BLACKLIST");
        assertEq(admin, LIVE_PROXY, "live policy must be self-administered");
        assertEq(FrxUSDPolicyAdminTempo(LIVE_PROXY).policyId(), 5);
    }

    /// @notice Confirmed: a WHITELIST-typed policy bricks freeze/thaw.
    function test_WhitelistPolicy_BricksFreezeAndThaw() public {
        uint64 wl = StdPrecompiles.TIP403_REGISTRY.createPolicy(address(this), ITIP403Registry.PolicyType.WHITELIST);
        FrxUSDPolicyAdminTempo p = _deploy(wl);
        // hand admin to the wrapper so only the TYPE is wrong, isolating the cause
        StdPrecompiles.TIP403_REGISTRY.setPolicyAdmin(wl, address(p));

        vm.prank(owner);
        vm.expectRevert();
        p.freeze(victim);

        vm.prank(owner);
        vm.expectRevert();
        p.thaw(victim);
    }

    /// @notice Confirmed: with a WHITELIST policy `isFrozen` does not revert, it inverts.
    ///         An account that was never frozen reports as frozen.
    function test_WhitelistPolicy_IsFrozenSilentlyInverts() public {
        uint64 wl = StdPrecompiles.TIP403_REGISTRY.createPolicy(address(this), ITIP403Registry.PolicyType.WHITELIST);
        FrxUSDPolicyAdminTempo p = _deploy(wl);

        assertTrue(p.isFrozen(victim), "nobody froze this account, yet it reports frozen");
        assertTrue(p.isFrozen(address(0xDEAD)), "every non-whitelisted account reports frozen");
    }

    /// @notice Confirmed: a policy this contract does not administer bricks freeze.
    function test_ForeignAdminPolicy_BricksFreeze() public {
        uint64 bl = StdPrecompiles.TIP403_REGISTRY.createPolicy(address(0xFEE1), ITIP403Registry.PolicyType.BLACKLIST);
        FrxUSDPolicyAdminTempo p = _deploy(bl);

        vm.prank(owner);
        vm.expectRevert();
        p.freeze(victim);
    }

    /// @notice The correction the report says is impossible: the contract is behind a
    ///         TransparentUpgradeableProxy, so the ProxyAdmin can upgradeAndCall into a
    ///         reinitializer that rewrites policyId. Freeze works again afterwards.
    function test_MisSetPolicyId_IsRecoverableByUpgrade() public {
        uint64 wl = StdPrecompiles.TIP403_REGISTRY.createPolicy(address(this), ITIP403Registry.PolicyType.WHITELIST);
        FrxUSDPolicyAdminTempo p = _deploy(wl);

        vm.prank(owner);
        vm.expectRevert();
        p.freeze(victim); // broken as reported

        // a correctly-typed policy, administered by the wrapper
        uint64 good = StdPrecompiles.TIP403_REGISTRY.createPolicy(address(p), ITIP403Registry.PolicyType.BLACKLIST);

        address v2 = address(new FrxUSDPolicyAdminTempoV2());
        vm.prank(proxyAdmin);
        TransparentUpgradeableProxy(payable(address(p))).upgradeToAndCall(
            v2,
            abi.encodeCall(FrxUSDPolicyAdminTempoV2.repairPolicyId, (good))
        );

        assertEq(p.policyId(), good, "policyId repaired");
        vm.prank(owner);
        p.freeze(victim);
        assertTrue(p.isFrozen(victim), "freeze works after the repair");
        vm.prank(owner);
        p.thaw(victim);
        assertFalse(p.isFrozen(victim), "thaw works after the repair");
    }
}

/// @notice The validation added to `initializeWithPolicy`: every mis-configuration the report
///         describes is now rejected at init, and the correct two-step flow still works.
contract FrxUSDPolicyAdminTempoValidationTest is Test {
    address internal owner = address(0xA11CE);
    address internal proxyAdmin = address(0xAD801);
    address internal victim = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork(vm.envOr("TEMPO_RPC_URL", string("https://rpc.tempo.xyz")));
    }

    function _proxyUninitialized() internal returns (address) {
        address impl = address(new FrxUSDPolicyAdminTempo());
        return address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    }

    function test_RejectsZeroAndUnknownPolicyId() public {
        FrxUSDPolicyAdminTempo p = FrxUSDPolicyAdminTempo(_proxyUninitialized());
        vm.expectRevert(FrxUSDPolicyAdminTempo.InvalidPolicyId.selector);
        p.initializeWithPolicy(owner, 0);

        uint64 unknown = StdPrecompiles.TIP403_REGISTRY.policyIdCounter() + 1_000;
        vm.expectRevert(FrxUSDPolicyAdminTempo.InvalidPolicyId.selector);
        p.initializeWithPolicy(owner, unknown);
    }

    function test_RejectsWhitelistTypedPolicy() public {
        address proxy = _proxyUninitialized();
        uint64 wl = StdPrecompiles.TIP403_REGISTRY.createPolicy(proxy, ITIP403Registry.PolicyType.WHITELIST);
        vm.expectRevert(FrxUSDPolicyAdminTempo.InvalidPolicyType.selector);
        FrxUSDPolicyAdminTempo(proxy).initializeWithPolicy(owner, wl);
    }

    function test_RejectsPolicyThisContractDoesNotAdminister() public {
        address proxy = _proxyUninitialized();
        uint64 bl = StdPrecompiles.TIP403_REGISTRY.createPolicy(address(0xFEE1), ITIP403Registry.PolicyType.BLACKLIST);
        vm.expectRevert(FrxUSDPolicyAdminTempo.NotPolicyAdmin.selector);
        FrxUSDPolicyAdminTempo(proxy).initializeWithPolicy(owner, bl);
    }

    function test_AcceptsCorrectlyConfiguredPolicyAndFreezeWorks() public {
        address proxy = _proxyUninitialized();
        uint64 bl = StdPrecompiles.TIP403_REGISTRY.createPolicy(proxy, ITIP403Registry.PolicyType.BLACKLIST);
        FrxUSDPolicyAdminTempo p = FrxUSDPolicyAdminTempo(proxy);
        p.initializeWithPolicy(owner, bl);

        assertEq(p.policyId(), bl);
        assertEq(p.owner(), owner);
        assertFalse(p.isFrozen(victim));
        vm.prank(owner);
        p.freeze(victim);
        assertTrue(p.isFrozen(victim), "freeze works on a validated policy");
    }

    /// @notice `initialize()` (the path our deployment actually uses) is unaffected.
    function test_PlainInitializeStillSelfProvisionsABlacklistPolicy() public {
        address impl = address(new FrxUSDPolicyAdminTempo());
        FrxUSDPolicyAdminTempo p = FrxUSDPolicyAdminTempo(
            address(
                new TransparentUpgradeableProxy(
                    impl, proxyAdmin, abi.encodeCall(FrxUSDPolicyAdminTempo.initialize, (owner))
                )
            )
        );
        (ITIP403Registry.PolicyType t, address admin) = p.getPolicyData();
        assertEq(uint8(t), uint8(ITIP403Registry.PolicyType.BLACKLIST));
        assertEq(admin, address(p));
        vm.prank(owner);
        p.freeze(victim);
        assertTrue(p.isFrozen(victim));
    }
}
