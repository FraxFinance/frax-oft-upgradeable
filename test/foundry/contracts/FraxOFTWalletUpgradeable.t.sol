// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { FraxOFTWalletUpgradeable, IHopV2, MismatchedArrayLengths } from "contracts/FraxOFTWalletUpgradeable.sol";
import { UpgradeWalletBridges } from "scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol";

/// @notice Arbitrum fork test: runs the real upgrade script against the live dev wallet proxy, then
///         exercises every bridge path the upgraded wallet exposes - direct `IOFT.send` and HopV2,
///         single and multi-OFT, from-wallet and from-sender.
/// forge test --match-path test/foundry/contracts/FraxOFTWalletUpgradeable.t.sol -vvv
/// Optional env: ARBITRUM_RPC_URL, ARBITRUM_FORK_BLOCK (0/unset = latest)
contract FraxOFTWalletUpgradeableForkTest is Test {
    bytes32 internal constant EIP1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant EIP1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address internal constant WALLET = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
    address internal constant HOP_V2 = 0x0000006D38568b00B457580b734e0076C62de659; // RemoteHopV2 (Arbitrum)

    address internal constant FRXUSD_OFT = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address internal constant SFRXUSD_OFT = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address internal constant FRAX_OFT = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;

    uint32 internal constant FRAXTAL_EID = 30255;
    uint32 internal constant BASE_EID = 30184;

    uint256 internal constant AMOUNT = 1e18; // dust-free for 18-decimal OFTs (6 shared decimals)

    /// @dev Packed so tests stay clear of stack-too-deep (legacy codegen, no via-ir).
    struct HopBatch {
        address[] ofts;
        uint32[] dstEids;
        bytes32[] recipients;
        uint256[] amounts;
        uint128[] dstGases;
        bytes[] datas;
    }

    FraxOFTWalletUpgradeable internal wallet = FraxOFTWalletUpgradeable(WALLET);

    address internal owner;
    address internal ownerBefore;
    address internal pendingOwnerBefore;
    address internal adminBefore;
    address internal implementationBefore;
    uint256 internal walletEthBefore;

    address internal alice = makeAddr("alice");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        string memory rpc = vm.envOr("ARBITRUM_RPC_URL", string("https://arb1.arbitrum.io/rpc"));
        uint256 forkBlock = vm.envOr("ARBITRUM_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, forkBlock);

        ownerBefore = wallet.owner();
        pendingOwnerBefore = wallet.pendingOwner();
        adminBefore = _load(EIP1967_ADMIN_SLOT);
        implementationBefore = _load(EIP1967_IMPLEMENTATION_SLOT);

        // Upgrade exactly the way the ops script will
        UpgradeWalletBridges script = new UpgradeWalletBridges();
        script.setUp();
        script.upgradeChain(block.chainid);

        owner = wallet.owner();
        walletEthBefore = WALLET.balance;
        vm.deal(owner, 10 ether);

        vm.label(WALLET, "FraxOFTWallet");
        vm.label(HOP_V2, "RemoteHopV2");
        vm.label(FRXUSD_OFT, "frxUSD OFT");
        vm.label(SFRXUSD_OFT, "sfrxUSD OFT");
        vm.label(FRAX_OFT, "FRAX OFT");
    }

    // ─── Upgrade ─────────────────────────────────────────────────────────

    function test_upgrade_preservesProxyState() public view {
        assertTrue(_load(EIP1967_IMPLEMENTATION_SLOT) != implementationBefore, "implementation not changed");
        assertEq(_load(EIP1967_ADMIN_SLOT), adminBefore, "admin changed");
        assertEq(wallet.owner(), ownerBefore, "owner changed");
        assertEq(wallet.pendingOwner(), pendingOwnerBefore, "pendingOwner changed");
    }

    function test_upgrade_cannotReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        wallet.initialize(alice);
    }

    function test_onlyOwner() public {
        SendParam memory sp = _sendParam(FRAXTAL_EID, AMOUNT);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        wallet.bridgeWithEthFeeFromWallet(sp, IOFT(FRXUSD_OFT), alice);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        wallet.hopV2WithEthFeeFromWallet(HOP_V2, FRXUSD_OFT, BASE_EID, _b32(recipient), AMOUNT, 0, "");
    }

    // ─── Direct OFT send (no hop) ────────────────────────────────────────

    function test_bridgeWithEthFeeFromWallet() public {
        deal(FRXUSD_OFT, WALLET, AMOUNT);
        SendParam memory sp = _sendParam(FRAXTAL_EID, AMOUNT);
        uint256 fee = IOFT(FRXUSD_OFT).quoteSend(sp, false).nativeFee;

        vm.prank(owner);
        wallet.bridgeWithEthFeeFromWallet{ value: fee }(sp, IOFT(FRXUSD_OFT), owner);

        assertEq(IERC20(FRXUSD_OFT).balanceOf(WALLET), 0, "wallet still holds frxUSD");
        assertEq(WALLET.balance, walletEthBefore, "fee not consumed exactly");
    }

    /// @dev The wallet's core purpose: push several OFTs through the mesh in one tx.
    function test_batchBridgeWithEthFeeFromWallet_multipleOfts() public {
        IOFT[] memory ofts = _ofts();
        SendParam[] memory sps = new SendParam[](ofts.length);
        address[] memory refunds = new address[](ofts.length);
        uint256 totalFee;
        for (uint256 i; i < ofts.length; i++) {
            deal(address(ofts[i]), WALLET, AMOUNT);
            sps[i] = _sendParam(FRAXTAL_EID, AMOUNT);
            refunds[i] = owner;
            totalFee += ofts[i].quoteSend(sps[i], false).nativeFee;
        }

        vm.prank(owner);
        wallet.batchBridgeWithEthFeeFromWallet{ value: totalFee }(sps, ofts, refunds);

        for (uint256 i; i < ofts.length; i++) {
            assertEq(IERC20(address(ofts[i])).balanceOf(WALLET), 0, "wallet still holds OFT");
        }
        assertEq(WALLET.balance, walletEthBefore, "fees not consumed exactly");
    }

    function test_batchBridgeWithEthFeeFromSender_multipleOfts() public {
        IOFT[] memory ofts = _ofts();
        SendParam[] memory sps = new SendParam[](ofts.length);
        address[] memory senders = new address[](ofts.length);
        IERC20[] memory tokens = new IERC20[](ofts.length);
        address[] memory refunds = new address[](ofts.length);
        uint256 totalFee;
        for (uint256 i; i < ofts.length; i++) {
            deal(address(ofts[i]), alice, AMOUNT);
            vm.prank(alice);
            IERC20(address(ofts[i])).approve(WALLET, AMOUNT);
            sps[i] = _sendParam(FRAXTAL_EID, AMOUNT);
            senders[i] = alice;
            tokens[i] = IERC20(address(ofts[i]));
            refunds[i] = owner;
            totalFee += ofts[i].quoteSend(sps[i], false).nativeFee;
        }

        vm.prank(owner);
        wallet.batchBridgeWithEthFeeFromSender{ value: totalFee }(sps, senders, tokens, ofts, refunds);

        for (uint256 i; i < ofts.length; i++) {
            assertEq(IERC20(address(ofts[i])).balanceOf(alice), 0, "sender still holds OFT");
            assertEq(IERC20(address(ofts[i])).balanceOf(WALLET), 0, "wallet still holds OFT");
        }
    }

    /// @dev Regression: master used `&&` between length checks, so this passed validation.
    function test_batchBridge_revertsOnMismatchedLengths() public {
        SendParam[] memory sps = new SendParam[](2);
        IOFT[] memory ofts = new IOFT[](2);
        address[] memory refunds = new address[](1);

        vm.expectRevert(MismatchedArrayLengths.selector);
        vm.prank(owner);
        wallet.batchBridgeWithEthFeeFromWallet(sps, ofts, refunds);
    }

    // ─── HopV2 ───────────────────────────────────────────────────────────

    function test_hopV2WithEthFeeFromWallet_toFraxtal() public {
        _hopFromWallet(FRXUSD_OFT, FRAXTAL_EID);
    }

    function test_hopV2WithEthFeeFromWallet_toBaseViaFraxtal() public {
        _hopFromWallet(FRXUSD_OFT, BASE_EID);
    }

    function test_hopV2WithEthFeeFromSender_toBaseViaFraxtal() public {
        deal(SFRXUSD_OFT, alice, AMOUNT);
        vm.prank(alice);
        IERC20(SFRXUSD_OFT).approve(WALLET, AMOUNT);
        uint256 fee = _quoteHop(SFRXUSD_OFT, BASE_EID, AMOUNT);

        vm.prank(owner);
        wallet.hopV2WithEthFeeFromSender{ value: fee }(
            HOP_V2, SFRXUSD_OFT, IERC20(SFRXUSD_OFT), alice, BASE_EID, _b32(recipient), AMOUNT, 0, ""
        );

        assertEq(IERC20(SFRXUSD_OFT).balanceOf(alice), 0, "sender still holds sfrxUSD");
        assertEq(IERC20(SFRXUSD_OFT).balanceOf(WALLET), 0, "wallet still holds sfrxUSD");
        assertEq(WALLET.balance, walletEthBefore, "fee not consumed exactly");
    }

    function test_batchHopV2WithEthFeeFromWallet_multipleOfts() public {
        HopBatch memory b = _hopBatch();
        uint256 totalFee;
        for (uint256 i; i < b.ofts.length; i++) {
            deal(b.ofts[i], WALLET, AMOUNT);
            totalFee += _quoteHop(b.ofts[i], b.dstEids[i], AMOUNT);
        }

        vm.prank(owner);
        wallet.batchHopV2WithEthFeeFromWallet{ value: totalFee }(
            HOP_V2, b.ofts, b.dstEids, b.recipients, b.amounts, b.dstGases, b.datas
        );

        for (uint256 i; i < b.ofts.length; i++) {
            assertEq(IERC20(b.ofts[i]).balanceOf(WALLET), 0, "wallet still holds OFT");
        }
        assertEq(WALLET.balance, walletEthBefore, "fees not consumed exactly");
    }

    function test_batchHopV2WithEthFeeFromSender_multipleOfts() public {
        HopBatch memory b = _hopBatch();
        address[] memory senders = new address[](b.ofts.length);
        IERC20[] memory tokens = new IERC20[](b.ofts.length);
        uint256 totalFee;
        for (uint256 i; i < b.ofts.length; i++) {
            deal(b.ofts[i], alice, AMOUNT);
            vm.prank(alice);
            IERC20(b.ofts[i]).approve(WALLET, AMOUNT);
            senders[i] = alice;
            tokens[i] = IERC20(b.ofts[i]);
            totalFee += _quoteHop(b.ofts[i], b.dstEids[i], AMOUNT);
        }

        vm.prank(owner);
        wallet.batchHopV2WithEthFeeFromSender{ value: totalFee }(
            HOP_V2, senders, tokens, b.ofts, b.dstEids, b.recipients, b.amounts, b.dstGases, b.datas
        );

        for (uint256 i; i < b.ofts.length; i++) {
            assertEq(IERC20(b.ofts[i]).balanceOf(alice), 0, "sender still holds OFT");
            assertEq(IERC20(b.ofts[i]).balanceOf(WALLET), 0, "wallet still holds OFT");
        }
    }

    function test_batchHopV2_revertsWhenMsgValueTooLow() public {
        HopBatch memory b = _hopBatch();
        uint256 totalFee;
        for (uint256 i; i < b.ofts.length; i++) {
            deal(b.ofts[i], WALLET, AMOUNT);
            totalFee += _quoteHop(b.ofts[i], b.dstEids[i], AMOUNT);
        }

        vm.expectRevert("Insufficient ETH for fees");
        vm.prank(owner);
        wallet.batchHopV2WithEthFeeFromWallet{ value: totalFee - 1 }(
            HOP_V2, b.ofts, b.dstEids, b.recipients, b.amounts, b.dstGases, b.datas
        );
    }

    function test_batchHopV2_revertsOnMismatchedLengths() public {
        HopBatch memory b = _hopBatch();
        b.datas = new bytes[](1);

        vm.expectRevert(MismatchedArrayLengths.selector);
        vm.prank(owner);
        wallet.batchHopV2WithEthFeeFromWallet(HOP_V2, b.ofts, b.dstEids, b.recipients, b.amounts, b.dstGases, b.datas);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    function _hopFromWallet(address _oft, uint32 _dstEid) internal {
        deal(_oft, WALLET, AMOUNT);
        uint256 fee = _quoteHop(_oft, _dstEid, AMOUNT);

        vm.prank(owner);
        wallet.hopV2WithEthFeeFromWallet{ value: fee }(HOP_V2, _oft, _dstEid, _b32(recipient), AMOUNT, 0, "");

        assertEq(IERC20(_oft).balanceOf(WALLET), 0, "wallet still holds OFT");
        assertEq(WALLET.balance, walletEthBefore, "fee not consumed exactly");
    }

    /// @dev HopV2.quote encodes msg.sender into the hop message, so quote as the wallet.
    function _quoteHop(address _oft, uint32 _dstEid, uint256 _amount) internal returns (uint256 fee) {
        vm.prank(WALLET);
        fee = IHopV2(HOP_V2).quote(_oft, _dstEid, _b32(recipient), _amount, 0, "");
    }

    function _hopBatch() internal view returns (HopBatch memory b) {
        b.ofts = new address[](3);
        b.ofts[0] = FRXUSD_OFT;
        b.ofts[1] = SFRXUSD_OFT;
        b.ofts[2] = FRAX_OFT;

        b.dstEids = new uint32[](3);
        b.dstEids[0] = BASE_EID; // spoke -> Fraxtal -> spoke
        b.dstEids[1] = FRAXTAL_EID; // spoke -> hub
        b.dstEids[2] = BASE_EID;

        b.recipients = new bytes32[](3);
        b.amounts = new uint256[](3);
        for (uint256 i; i < 3; i++) {
            b.recipients[i] = _b32(recipient);
            b.amounts[i] = AMOUNT;
        }
        b.dstGases = new uint128[](3);
        b.datas = new bytes[](3);
    }

    function _ofts() internal pure returns (IOFT[] memory ofts) {
        ofts = new IOFT[](3);
        ofts[0] = IOFT(FRXUSD_OFT);
        ofts[1] = IOFT(SFRXUSD_OFT);
        ofts[2] = IOFT(FRAX_OFT);
    }

    function _sendParam(uint32 _dstEid, uint256 _amount) internal view returns (SendParam memory) {
        return SendParam({
            dstEid: _dstEid,
            to: _b32(recipient),
            amountLD: _amount,
            minAmountLD: _amount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
    }

    function _b32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function _load(bytes32 _slot) internal view returns (address) {
        return address(uint160(uint256(vm.load(WALLET, _slot))));
    }
}
