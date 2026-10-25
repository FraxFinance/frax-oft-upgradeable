// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "frax-std/FraxTest.sol";

import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";
import { FraxProxyAdmin } from "contracts/FraxProxyAdmin.sol";
import { ImplementationMock } from "contracts/mocks/ImplementationMock.sol";

import { IOFT, SendParam, MessagingFee } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { ProxyAdmin, TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/ProxyAdmin.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Recipient guard (audit finding ZELLIC-4AVT21): a recipient that decodes to address(0), or that is
///      not a left-padded 20-byte address for an EVM-shaped peer, is rejected on the send path (quoteSend
///      and send share _buildMsgAndOptions) and on the receive path (_lzReceive).
contract RecipientGuardSourceAndReceiveTest is FraxTest {
    using OptionsBuilder for bytes;

    address constant ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    uint32 constant ETH_EID = 30101;
    uint32 constant SOL_EID = 30168;
    bytes32 constant ETH_PEER = bytes32(uint256(uint160(0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0)));
    bytes32 constant SOL_PEER = 0x5e208a73d5bb1c78e9dbf53badd7299afd6bee9acacdcd4fd668833e53c538ad;
    /// @dev arbitrary 32-byte Solana account: high 96 bits set, low 160 bits nonzero
    bytes32 constant SOL_RECIPIENT = 0xa1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90;
    /// @dev live Fraxtal frxUSD OFT: its send config (DVNs + executor) is copied onto the mock, because the
    ///      endpoint's DEFAULT required DVN on Fraxtal is a sentinel (0xdEaD for 30101, a reverting stub for 30168)
    address constant LIVE_FRXUSD_OFT = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address constant SEND_LIB_302 = 0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6;
    uint32 constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 constant CONFIG_TYPE_ULN = 2;

    FraxOFTUpgradeable oft;
    address owner = vm.addr(0x12345);
    address al = vm.addr(0x41);
    address bob = vm.addr(0xb0b);

    bytes4 internal INVALID_RECIPIENT = IOFT.InvalidRecipient.selector;

    function setUp() external {
        vm.createSelectFork("https://rpc.frax.com", 23542154);
        oft = FraxOFTUpgradeable(deployMockFraxOFT());

        vm.startPrank(owner);
        oft.setPeer(ETH_EID, ETH_PEER);
        oft.setPeer(SOL_EID, SOL_PEER);
        vm.stopPrank();

        _copyLiveSendConfig(ETH_EID);
        _copyLiveSendConfig(SOL_EID);

        deal(address(oft), al, 100e18);
        vm.deal(al, 10 ether);
    }

    /// @notice ripped from FraxOFTUpgradeable.t.sol / DeployFraxOFTProtocol.deployFraxOFTUpgradeablesAndProxies()
    function deployMockFraxOFT() internal returns (address) {
        address proxyAdmin = address(new FraxProxyAdmin(owner));
        address implementationMock = address(new ImplementationMock());
        address implementation = address(new FraxOFTUpgradeable(ENDPOINT));
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
        return proxy;
    }

    /// @dev owner is the mock's endpoint delegate (set by initialize), so it may call setConfig for it
    function _copyLiveSendConfig(uint32 _eid) internal {
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(ENDPOINT);
        SetConfigParam[] memory params = new SetConfigParam[](2);
        params[0] = SetConfigParam(_eid, CONFIG_TYPE_EXECUTOR, ep.getConfig(LIVE_FRXUSD_OFT, SEND_LIB_302, _eid, CONFIG_TYPE_EXECUTOR));
        params[1] = SetConfigParam(_eid, CONFIG_TYPE_ULN, ep.getConfig(LIVE_FRXUSD_OFT, SEND_LIB_302, _eid, CONFIG_TYPE_ULN));
        vm.startPrank(owner);
        ep.setSendLibrary(address(oft), _eid, SEND_LIB_302);
        ep.setConfig(address(oft), SEND_LIB_302, params);
        vm.stopPrank();
    }

    function _sendParam(uint32 _dstEid, bytes32 _to, uint256 _amount) internal pure returns (SendParam memory) {
        return SendParam({
            dstEid: _dstEid,
            to: _to,
            amountLD: _amount,
            minAmountLD: _amount,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0),
            composeMsg: "",
            oftCmd: ""
        });
    }

    function _oftMessage(bytes32 _sendTo, uint64 _amountSD) internal pure returns (bytes memory) {
        return abi.encodePacked(_sendTo, _amountSD); // 40 bytes, non-compose
    }

    //==============================================================================
    // A. Source side: quoteSend / send
    //==============================================================================

    function test_A_quoteSend_zeroRecipient_reverts() external {
        vm.expectRevert(abi.encodeWithSelector(INVALID_RECIPIENT));
        oft.quoteSend(_sendParam(ETH_EID, bytes32(0), 1e18), false);
    }

    function test_A_quoteSend_highBitsOnlyRecipient_reverts() external {
        // low 160 bits are zero, so this decodes to address(0) on an EVM destination
        vm.expectRevert(abi.encodeWithSelector(INVALID_RECIPIENT));
        oft.quoteSend(_sendParam(ETH_EID, bytes32(uint256(1) << 160), 1e18), false);
    }

    function test_A_quoteSend_solanaShapedRecipient_toEvmPeer_reverts() external {
        // peers(30101) is EVM-shaped (high 96 bits zero) so a 32-byte recipient is rejected
        assertEq(uint256(oft.peers(ETH_EID)) >> 160, 0, "ETH peer must be EVM-shaped");
        vm.expectRevert(abi.encodeWithSelector(INVALID_RECIPIENT));
        oft.quoteSend(_sendParam(ETH_EID, SOL_PEER, 1e18), false);
    }

    function test_A_quoteSend_validRecipient_toEvmPeer_quotes() external {
        MessagingFee memory fee = oft.quoteSend(_sendParam(ETH_EID, bytes32(uint256(uint160(bob))), 1e18), false);
        assertGt(fee.nativeFee, 0, "nativeFee should be nonzero for Fraxtal -> Ethereum");
        assertEq(fee.lzTokenFee, 0);
        console.log("Fraxtal -> Ethereum nativeFee (wei of FRAX):", fee.nativeFee);
    }

    /// @dev Solana peer has high bits set, so a 32-byte recipient passes the guard; the
    ///      remaining path is the live Fraxtal endpoint's quote for eid 30168.
    function test_A_quoteSend_solanaShapedRecipient_toSolanaPeer_passesGuard() external {
        assertTrue(uint256(oft.peers(SOL_EID)) >> 160 != 0, "SOL peer must be 32-byte shaped");
        MessagingFee memory fee = oft.quoteSend(_sendParam(SOL_EID, SOL_RECIPIENT, 1e18), false);
        assertGt(fee.nativeFee, 0, "nativeFee should be nonzero for Fraxtal -> Solana");
        console.log("Fraxtal -> Solana nativeFee (wei of FRAX):", fee.nativeFee);
    }

    /// @dev Same guard, exercised through the external view wrapper so the assertion does not
    ///      depend on the endpoint having a send library / executor config for eid 30168.
    function test_A_buildMsgAndOptions_solanaShapedRecipient_toSolanaPeer_passesGuard() external {
        (bytes memory message, ) = oft.buildMsgAndOptions(_sendParam(SOL_EID, SOL_RECIPIENT, 1e18), 1e18);
        assertEq(message.length, 40, "non-compose OFT message is 40 bytes");
        assertEq(bytes32(message), SOL_RECIPIENT, "sendTo must be the full 32-byte recipient");
    }

    function test_A_buildMsgAndOptions_zeroRecipient_reverts() external {
        vm.expectRevert(abi.encodeWithSelector(INVALID_RECIPIENT));
        oft.buildMsgAndOptions(_sendParam(ETH_EID, bytes32(0), 1e18), 1e18);
    }

    function test_A_send_zeroRecipient_reverts_beforeAnyBalanceChange() external {
        // quote with a valid recipient so msg.value is a real fee
        MessagingFee memory fee = oft.quoteSend(_sendParam(ETH_EID, bytes32(uint256(uint160(bob))), 1e18), false);
        assertGt(fee.nativeFee, 0);

        uint256 alTokensBefore = oft.balanceOf(al);
        uint256 supplyBefore = oft.totalSupply();
        uint256 alNativeBefore = al.balance;
        assertEq(alTokensBefore, 100e18);

        vm.prank(al);
        vm.expectRevert(abi.encodeWithSelector(INVALID_RECIPIENT));
        oft.send{ value: fee.nativeFee }(_sendParam(ETH_EID, bytes32(0), 1e18), fee, al);

        assertEq(oft.balanceOf(al), alTokensBefore, "no tokens burned");
        assertEq(oft.totalSupply(), supplyBefore, "supply unchanged");
        assertEq(al.balance, alNativeBefore, "no native spent");
    }

    /// @dev control: the same send with a valid recipient goes through the live endpoint
    function test_A_send_validRecipient_succeeds() external {
        SendParam memory sp = _sendParam(ETH_EID, bytes32(uint256(uint160(bob))), 1e18);
        MessagingFee memory fee = oft.quoteSend(sp, false);

        uint256 alTokensBefore = oft.balanceOf(al);
        vm.prank(al);
        oft.send{ value: fee.nativeFee }(sp, fee, al);
        assertEq(oft.balanceOf(al), alTokensBefore - 1e18, "1e18 burned on send");
    }

    //==============================================================================
    // B. Receive side: lzReceive from the endpoint
    //==============================================================================

    function _lzReceiveFromEth(bytes32 _sendTo, uint64 _amountSD) internal {
        vm.prank(ENDPOINT);
        oft.lzReceive(
            Origin({ srcEid: ETH_EID, sender: ETH_PEER, nonce: 1 }),
            bytes32("g"),
            _oftMessage(_sendTo, _amountSD),
            address(0),
            ""
        );
    }

    function test_B_lzReceive_zeroRecipient_reverts() external {
        uint256 supplyBefore = oft.totalSupply();
        vm.prank(ENDPOINT);
        vm.expectRevert(abi.encodeWithSelector(INVALID_RECIPIENT));
        oft.lzReceive(
            Origin({ srcEid: ETH_EID, sender: ETH_PEER, nonce: 1 }),
            bytes32("g"),
            _oftMessage(bytes32(0), 1e6),
            address(0),
            ""
        );
        assertEq(oft.totalSupply(), supplyBefore, "nothing minted");
    }

    function test_B_lzReceive_highBitsRecipient_reverts() external {
        bytes32 dirty = bytes32(uint256(1) << 200) | bytes32(uint256(uint160(bob)));
        assertEq(address(uint160(uint256(dirty))), bob, "low 160 bits are bob");
        uint256 bobBefore = oft.balanceOf(bob);
        vm.prank(ENDPOINT);
        vm.expectRevert(abi.encodeWithSelector(INVALID_RECIPIENT));
        oft.lzReceive(
            Origin({ srcEid: ETH_EID, sender: ETH_PEER, nonce: 1 }),
            bytes32("g"),
            _oftMessage(dirty, 1e6),
            address(0),
            ""
        );
        assertEq(oft.balanceOf(bob), bobBefore, "nothing minted to bob");
    }

    function test_B_lzReceive_validRecipient_mints() external {
        uint256 bobBefore = oft.balanceOf(bob);
        uint256 supplyBefore = oft.totalSupply();
        _lzReceiveFromEth(bytes32(uint256(uint160(bob))), 1e6);
        assertEq(oft.balanceOf(bob), bobBefore + 1e18, "bob credited 1e6 SD * 1e12 = 1e18 LD");
        assertEq(oft.totalSupply(), supplyBefore + 1e18);
    }

    /// @dev sanity: the endpoint/peer checks of the fork's OAppReceiver still run first
    function test_B_lzReceive_notEndpoint_reverts() external {
        vm.prank(al);
        vm.expectRevert();
        oft.lzReceive(
            Origin({ srcEid: ETH_EID, sender: ETH_PEER, nonce: 1 }),
            bytes32("g"),
            _oftMessage(bytes32(uint256(uint160(bob))), 1e6),
            address(0),
            ""
        );
    }
}

/// @dev Live Ethereum sfrxETH lock adapter: sfrxETH is Solmate-based and transfers to address(0) without
///      reverting, so the current implementation pays a zero recipient out to address(0). After upgrading the
///      proxy to the implementation in this repo the same delivery reverts and the packet stays retryable.
contract RecipientGuardSfrxEthBurnTest is FraxTest {
    address constant ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant ADAPTER = 0xbBc424e58ED38dd911309611ae2d7A23014Bd960; // live sfrxETH lock adapter proxy
    address constant PROXY_ADMIN = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
    address constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    uint32 constant FRAXTAL_EID = 30255;
    bytes32 constant FRAXTAL_PEER = 0x000000000000000000000000999dfabe3b1cc2ef66eb032eea42fea329bba168;
    /// @dev EIP-1967 admin slot
    bytes32 constant EIP1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 constant EIP1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    bytes4 internal INVALID_RECIPIENT = IOFT.InvalidRecipient.selector;

    FraxOFTAdapterUpgradeable adapter = FraxOFTAdapterUpgradeable(ADAPTER);
    IERC20 sfrxETH = IERC20(SFRXETH);
    address bob = vm.addr(0xb0b);

    function setUp() external {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com", 26257473);
        assertEq(address(uint160(uint256(vm.load(ADAPTER, EIP1967_ADMIN_SLOT)))), PROXY_ADMIN, "admin slot");
        assertEq(adapter.peers(FRAXTAL_EID), FRAXTAL_PEER, "live Fraxtal peer");
        assertEq(address(adapter.endpoint()), ENDPOINT, "live endpoint");
        assertEq(adapter.decimalConversionRate(), 1e12, "rate");
        assertEq(adapter.token(), SFRXETH, "inner token");
    }

    function _deliver(bytes32 _sendTo, uint64 _amountSD) internal {
        vm.prank(ENDPOINT);
        adapter.lzReceive(
            Origin({ srcEid: FRAXTAL_EID, sender: FRAXTAL_PEER, nonce: 1 }),
            bytes32("g"),
            abi.encodePacked(_sendTo, _amountSD),
            address(0),
            ""
        );
    }

    function _deliverExpectInvalidRecipient(bytes32 _sendTo, uint64 _amountSD) internal {
        vm.prank(ENDPOINT);
        vm.expectRevert(abi.encodeWithSelector(INVALID_RECIPIENT));
        adapter.lzReceive(
            Origin({ srcEid: FRAXTAL_EID, sender: FRAXTAL_PEER, nonce: 1 }),
            bytes32("g"),
            abi.encodePacked(_sendTo, _amountSD),
            address(0),
            ""
        );
    }

    function _upgradeToPatchedImpl() internal returns (address impl) {
        impl = address(new FraxOFTAdapterUpgradeable(SFRXETH, ENDPOINT));
        address proxyAdminOwner = ProxyAdmin(PROXY_ADMIN).owner();
        console.log("ProxyAdmin owner:", proxyAdminOwner);
        vm.prank(proxyAdminOwner);
        ProxyAdmin(PROXY_ADMIN).upgrade(TransparentUpgradeableProxy(payable(ADAPTER)), impl);
        assertEq(address(uint160(uint256(vm.load(ADAPTER, EIP1967_IMPL_SLOT)))), impl, "impl slot updated");
        assertEq(adapter.version(), "1.2.0");
        // immutables carried by the new implementation must match the live one
        assertEq(adapter.decimalConversionRate(), 1e12);
        assertEq(adapter.token(), SFRXETH);
        assertEq(address(adapter.endpoint()), ENDPOINT);
        // storage (ERC-7201 namespaces) survives the upgrade
        assertEq(adapter.peers(FRAXTAL_EID), FRAXTAL_PEER);
    }

    /// @notice LIVE behaviour: a zero recipient is paid out to address(0) without reverting.
    function test_C_live_zeroRecipient_silentlyBurns() external {
        uint256 zeroBefore = sfrxETH.balanceOf(address(0));
        uint256 adapterBefore = sfrxETH.balanceOf(ADAPTER);
        console.log("sfrxETH.balanceOf(address(0)) before:", zeroBefore);
        console.log("sfrxETH.balanceOf(adapter)    before:", adapterBefore);

        _deliver(bytes32(0), 1e6); // must NOT revert on the live v1.0.0 implementation

        uint256 zeroAfter = sfrxETH.balanceOf(address(0));
        uint256 adapterAfter = sfrxETH.balanceOf(ADAPTER);
        console.log("sfrxETH.balanceOf(address(0)) after: ", zeroAfter);
        console.log("sfrxETH.balanceOf(adapter)    after: ", adapterAfter);
        assertEq(zeroAfter, zeroBefore + 1e18, "1e6 SD * 1e12 = 1e18 sfrxETH sent to address(0)");
        assertEq(adapterAfter, adapterBefore - 1e18, "adapter lost 1e18 sfrxETH");
    }

    /// @notice LIVE behaviour: a recipient with dirty high bits is paid to the truncated address.
    function test_C_live_highBitsRecipient_truncatesSilently() external {
        bytes32 dirty = bytes32(uint256(1) << 200) | bytes32(uint256(uint160(bob)));
        uint256 bobBefore = sfrxETH.balanceOf(bob);
        _deliver(dirty, 1e6);
        assertEq(sfrxETH.balanceOf(bob), bobBefore + 1e18, "live impl silently truncates to bob");
    }

    /// @notice After the upgrade a zero recipient reverts and a valid one is still paid.
    function test_C_upgraded_zeroRecipient_reverts_validRecipientReceives() external {
        // 1. reproduce the burn on the live implementation first
        uint256 zeroStart = sfrxETH.balanceOf(address(0));
        _deliver(bytes32(0), 1e6);
        assertEq(sfrxETH.balanceOf(address(0)), zeroStart + 1e18, "pre-upgrade burn reproduced");

        // 2. upgrade through the live ProxyAdmin
        address impl = _upgradeToPatchedImpl();
        console.log("new implementation:", impl);

        // 3. zero recipient now reverts, nothing moves
        uint256 zeroBefore = sfrxETH.balanceOf(address(0));
        uint256 adapterBefore = sfrxETH.balanceOf(ADAPTER);
        _deliverExpectInvalidRecipient(bytes32(0), 1e6);
        assertEq(sfrxETH.balanceOf(address(0)), zeroBefore, "no burn after upgrade");
        assertEq(sfrxETH.balanceOf(ADAPTER), adapterBefore, "adapter untouched after upgrade");

        // 4. dirty high bits also revert
        bytes32 dirty = bytes32(uint256(1) << 200) | bytes32(uint256(uint160(bob)));
        _deliverExpectInvalidRecipient(dirty, 1e6);
        assertEq(sfrxETH.balanceOf(bob), 0, "bob not credited from dirty recipient");

        // 5. a left-padded recipient still receives
        _deliver(bytes32(uint256(uint160(bob))), 1e6);
        assertEq(sfrxETH.balanceOf(bob), 1e18, "bob received 1e18 sfrxETH");
        assertEq(sfrxETH.balanceOf(ADAPTER), adapterBefore - 1e18, "adapter paid bob");
    }
}
