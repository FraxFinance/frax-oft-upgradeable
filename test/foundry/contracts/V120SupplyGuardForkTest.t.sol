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
///         already in deficit, and that seeding AFTER the upgrade restores exactly the intended
///         headroom.
/// @dev v1.1.0 accumulates `totalTransferTo`/`totalTransferFrom` but never enforces the guard.
///      v1.2.0 begins enforcing against those inherited counters, so an eid where
///      `totalTransferFrom > initialTotalSupply + totalTransferTo` starts reverting on its first
///      inbound message unless the baseline is raised.
///
///      The order matters: v1.1.0's `setInitialTotalSupply` also zeroes both counters, while
///      v1.2.0's writes only the baseline. The seed arithmetic assumes persisting counters, so
///      seeding before the upgrade would wipe the ledger and leave the guard far looser than
///      intended (see `test_V110Setter_ResetsCounters`).
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

    /// @notice Upgrade, then seed with the generator's formula: headroom lands exactly on the
    ///         intended margin because the v1.2.0 setter leaves the counters alone.
    function test_UpgradeThenSeed_RestoresIntendedHeadroom() public {
        uint256 margin = 1_000_000e18; // stands in for the peer's circulating supply
        uint256 from = adapter.totalTransferFrom(DEFICIT_EID);
        uint256 to = adapter.totalTransferTo(DEFICIT_EID);

        _upgrade(_deployV120());

        vm.prank(adapter.owner());
        adapter.setInitialTotalSupply(DEFICIT_EID, from - to + margin);

        // counters untouched by the v1.2.0 setter
        assertEq(adapter.totalTransferFrom(DEFICIT_EID), from, "v1.2.0 setter must not reset transferFrom");
        assertEq(adapter.totalTransferTo(DEFICIT_EID), to, "v1.2.0 setter must not reset transferTo");

        // headroom is precisely the margin we asked for
        uint256 headroom = adapter.initialTotalSupply(DEFICIT_EID) + adapter.totalTransferTo(DEFICIT_EID)
            - adapter.totalTransferFrom(DEFICIT_EID);
        assertEq(headroom, margin, "headroom != intended margin");

        _deliverInbound(1e6);
        _deliverInbound(1e6);
        assertEq(
            adapter.initialTotalSupply(DEFICIT_EID) + adapter.totalTransferTo(DEFICIT_EID)
                - adapter.totalTransferFrom(DEFICIT_EID),
            margin - 2e18,
            "headroom should shrink by exactly the delivered amount"
        );
    }

    /// @notice Surplus case (transferTo > transferFrom): the unified formula must still land
    ///         headroom on peer supply, not peer supply plus the surplus.
    function test_UpgradeThenSeed_SurplusEid_HeadroomEqualsPeerSupply() public {
        uint32 eid = 30101; // Ethereum: Fraxtal has sent it more than it has received back
        uint256 from = adapter.totalTransferFrom(eid);
        uint256 to = adapter.totalTransferTo(eid);
        assertGt(to, from, "precondition: eid should be in surplus");

        uint256 peerSupply = 97_000_000e18; // order of magnitude of Ethereum frxUSD supply
        uint256 needed = from + peerSupply;
        uint256 required = needed > to ? needed - to : 0;
        assertLt(required, peerSupply, "surplus eid must need a baseline BELOW peer supply");

        _upgrade(_deployV120());
        vm.prank(adapter.owner());
        adapter.setInitialTotalSupply(eid, required);

        uint256 headroom = adapter.initialTotalSupply(eid) + adapter.totalTransferTo(eid) - adapter.totalTransferFrom(eid);
        assertEq(headroom, peerSupply, "headroom must equal peer supply, not supply + surplus");
    }

    /// @notice Why seeding must NOT happen before the upgrade: the v1.1.0 setter zeroes both
    ///         counters, so the deficit formula would over-relax the guard by the whole deficit.
    function test_V110Setter_ResetsCounters() public {
        assertEq(adapter.version(), "1.1.0", "fork is not on v1.1.0");
        uint256 from = adapter.totalTransferFrom(DEFICIT_EID);
        uint256 to = adapter.totalTransferTo(DEFICIT_EID);
        assertGt(from, 0, "precondition: live counters are non-zero");

        vm.prank(adapter.owner());
        adapter.setInitialTotalSupply(DEFICIT_EID, from - to + 1_000_000e18);

        assertEq(adapter.totalTransferFrom(DEFICIT_EID), 0, "v1.1.0 setter did not reset transferFrom");
        assertEq(adapter.totalTransferTo(DEFICIT_EID), 0, "v1.1.0 setter did not reset transferTo");
        // With counters wiped, headroom equals the full seed rather than the intended margin.
        assertEq(adapter.initialTotalSupply(DEFICIT_EID), from - to + 1_000_000e18);
        assertGt(adapter.initialTotalSupply(DEFICIT_EID), 1_000_000e18 * 5, "deficit dwarfs the margin here");
    }
}
