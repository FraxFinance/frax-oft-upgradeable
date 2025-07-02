pragma solidity ^0.8.0;

import "scripts/ops/UpgradeToMint/1_UpgradeAdapter.s.sol";
import "frax-std/FraxTest.sol";

contract UpgradeAdapterTest is DUpgradeAdapter, FraxTest {
    using OptionsBuilder for bytes;

    address bob = vm.addr(0xb0b);

    function setUp() public override {
        deal(bob, 100e18);

        super.setUp();
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 252) {
                broadcastConfig = proxyConfigs[i];
                break;
            }
        }
        require(broadcastConfig.chainid == 252, "Fraxtal config not found");
    }

    function test_UpgradeAdapters() external {
        run();

        validateUpgrade(frxUsd, fraxtalFrxUsdLockbox);
        validateUpgrade(sfrxUsd, fraxtalSFrxUsdLockbox);
        validateUpgrade(wfrax, fraxtalFraxLockbox);
        validateUpgrade(fpi, fraxtalFpiLockbox);
    }

    function validateUpgrade(address token, address lockbox) internal {
        testRecover(token, lockbox);
        testSend(token, lockbox);
        testReceive(token, lockbox);
    }

    function testRecover(address token, address lockbox) internal {
        // recover tokens to delegate
        uint256 balanceDelegateBefore = IERC20(token).balanceOf(broadcastConfig.delegate);
        uint256 balanceLockbox = IERC20(token).balanceOf(lockbox);

        FraxOFTMintableAdapterUpgradeable(lockbox).recover();

        assertEq(
            IERC20(token).balanceOf(broadcastConfig.delegate),
            balanceDelegateBefore + balanceLockbox,
            "Recover failed"
        );
        assertEq(
            IERC20(token).balanceOf(lockbox),
            0,
            "Lockbox balance should be zero after recover"
        );
    }

    function testSend(address token, address lockbox) internal {
        uint256 amount = 1e18;
        deal(token, bob, amount);
        uint256 balanceBobBefore = IERC20(token).balanceOf(bob);
        uint256 totalSupplyBefore = IERC20(token).totalSupply();
        
        vm.startPrank(bob);

        IERC20(token).approve(lockbox, amount);
        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
            dstEid: 30101,
            to: addressToBytes32(broadcastConfig.delegate),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: '',
            oftCmd: ''
        });
        MessagingFee memory fee = IOFT(lockbox).quoteSend(sendParam, false);
        IOFT(lockbox).send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(bob)
        );

        vm.stopPrank();

        assertEq(
            IERC20(token).balanceOf(bob),
            balanceBobBefore - amount,
            "Bob's balance should decrease after send"
        );
        assertEq(
            IERC20(token).totalSupply(),
            totalSupplyBefore - amount,
            "Total supply should decrease after send"
        );
    }

    function testReceive(address token, address lockbox) internal {
        uint256 amount = 1e18;
        uint256 balanceBobBefore = IERC20(token).balanceOf(bob);
        uint256 totalSupplyBefore = IERC20(token).totalSupply();

        
    }
}
