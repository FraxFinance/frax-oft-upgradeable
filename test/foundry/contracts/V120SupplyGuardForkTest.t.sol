// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { FraxOFTMintableAdapterUpgradeable } from "contracts/FraxOFTMintableAdapterUpgradeable.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

interface IAdapterView {
    function token() external view returns (address);
    function endpoint() external view returns (address);
    function owner() external view returns (address);
    function version() external view returns (string memory);
    function peers(uint32 eid) external view returns (bytes32);
    function initialTotalSupply(uint32 eid) external view returns (uint256);
    function totalTransferFrom(uint32 eid) external view returns (uint256);
    function totalTransferTo(uint32 eid) external view returns (uint256);
    function setInitialTotalSupply(uint32 eid, uint256 amount) external;
    function lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) external payable;
}

interface IProxyAdminLike {
    function owner() external view returns (address);
    function upgrade(address proxy, address implementation) external;
}

/// @notice Fork proof that the v1.2.0 supply guard behaves as intended on a chain whose ledger is
///         already in deficit, and that seeding beforehand is what keeps inbound transfers alive.
/// @dev v1.1.0 accumulates `totalTransferTo`/`totalTransferFrom` but never enforces the guard.
///      v1.2.0 begins enforcing against those inherited counters, so an eid where
///      `totalTransferFrom > initialTotalSupply + totalTransferTo` starts reverting on its first
///      inbound message unless the baseline is raised first.
///
///      Requires network access: the suite forks Fraxtal (override with FRAXTAL_RPC_URL).
///      Run: forge test --match-path test/foundry/contracts/V120SupplyGuardForkTest.t.sol
contract V120SupplyGuardForkTest is Test {
    // Fraxtal frxUSD mintable adapter and the eid whose ledger is already underwater.
    address internal constant ADAPTER = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
    address internal constant PROXY_ADMIN = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
    uint32 internal constant DEFICIT_EID = 30184; // Base

    address internal constant RECIPIENT = address(0xF00D);

    IAdapterView internal adapter = IAdapterView(ADAPTER);

    function setUp() public {
        vm.createSelectFork(vm.envOr("FRAXTAL_RPC_URL", string("https://rpc.frax.com")));
        require(block.chainid == 252, "expected a Fraxtal fork");
    }

    function _deployV120() internal returns (address) {
        return address(new FraxOFTMintableAdapterUpgradeable(adapter.token(), adapter.endpoint()));
    }

    function _upgrade(address implementation) internal {
        vm.prank(IProxyAdminLike(PROXY_ADMIN).owner());
        IProxyAdminLike(PROXY_ADMIN).upgrade(ADAPTER, implementation);
        assertEq(adapter.version(), "1.2.0", "upgrade did not take");
    }

    /// @dev Delivers an inbound OFT message as the endpoint, which is what drives `_credit`.
    ///      The origin/endpoint reads are hoisted so a `vm.expectRevert` binds to `lzReceive`
    ///      itself rather than to a preceding view call.
    function _deliverInbound(uint64 amountSD) internal {
        (address endpoint, Origin memory origin, bytes memory message) = _prepareInbound(amountSD);
        vm.prank(endpoint);
        adapter.lzReceive(origin, bytes32("guid"), message, address(0), "");
    }

    function _prepareInbound(uint64 amountSD)
        internal
        view
        returns (address endpoint, Origin memory origin, bytes memory message)
    {
        endpoint = adapter.endpoint();
        origin = Origin({ srcEid: DEFICIT_EID, sender: adapter.peers(DEFICIT_EID), nonce: 1 });
        message = abi.encodePacked(bytes32(uint256(uint160(RECIPIENT))), amountSD);
    }

    /// @notice The precondition: this eid's ledger is already in deficit on the live chain.
    function test_LedgerIsAlreadyInDeficit() public {
        uint256 initial = adapter.initialTotalSupply(DEFICIT_EID);
        uint256 from = adapter.totalTransferFrom(DEFICIT_EID);
        uint256 to = adapter.totalTransferTo(DEFICIT_EID);

        console.log("initialTotalSupply", initial);
        console.log("totalTransferFrom ", from);
        console.log("totalTransferTo   ", to);

        assertGt(from, initial + to, "eid is not in deficit; pick another or refresh the fork");
        assertTrue(adapter.peers(DEFICIT_EID) != bytes32(0), "eid is not a live peer");
    }

    /// @notice Upgrading without seeding turns a working inbound path into a reverting one.
    function test_UpgradeWithoutSeeding_BlocksInbound() public {
        _deliverInbound(1e6); // pre-upgrade: v1.1.0 tracks but does not enforce
        _upgrade(_deployV120());

        (address endpoint, Origin memory origin, bytes memory message) = _prepareInbound(1e6);
        vm.prank(endpoint);
        vm.expectRevert(); // TotalTransferFromExceedsInitialTotalSupply
        adapter.lzReceive(origin, bytes32("guid"), message, address(0), "");
    }

    /// @notice Seeding first — as `SeedSupplyLedger` emits — keeps the path open across the upgrade.
    function test_SeedThenUpgrade_KeepsInboundAlive() public {
        uint256 from = adapter.totalTransferFrom(DEFICIT_EID);
        uint256 to = adapter.totalTransferTo(DEFICIT_EID);
        // Same formula the generator uses: cover the deficit, leaving headroom for real flow.
        uint256 required = from - to + 1_000_000e18;

        vm.prank(adapter.owner());
        adapter.setInitialTotalSupply(DEFICIT_EID, required);

        _upgrade(_deployV120());

        _deliverInbound(1e6);
        _deliverInbound(1e6);

        assertGt(
            adapter.initialTotalSupply(DEFICIT_EID) + adapter.totalTransferTo(DEFICIT_EID),
            adapter.totalTransferFrom(DEFICIT_EID),
            "guard should still have headroom"
        );
    }

    /// @notice The seed setter already exists on v1.1.0, which is what makes seed-before-upgrade
    ///         possible and removes any freeze window.
    function test_SeedSetterExistsPreUpgrade() public {
        assertEq(adapter.version(), "1.1.0", "fork is not on v1.1.0");
        vm.prank(adapter.owner());
        adapter.setInitialTotalSupply(DEFICIT_EID, 123);
        assertEq(adapter.initialTotalSupply(DEFICIT_EID), 123, "v1.1.0 cannot be seeded");
    }
}
