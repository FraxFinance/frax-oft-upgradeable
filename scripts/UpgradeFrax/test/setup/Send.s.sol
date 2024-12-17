// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../../../BaseL0Script.sol";

// forge script scripts/UpgradeFrax/test/setup/Send.s.sol --rpc-url https://mainnet.base.org --broadcast
contract Send is BaseL0Script {
    using OptionsBuilder for bytes;

    uint256 amount = 100_000e18;
    address public oft;
    uint32 public dstEid;

    constructor() {
        if (block.chainid == 252) {
            oft = 0x103C430c9Fcaa863EA90386e3d0d5cd53333876e; // fraxtal addr of oft
            dstEid = uint32(30184); // base eid
        } else {
            oft = 0xa536976c9cA36e74Af76037af555eefa632ce469; // base addr of adapter
            dstEid = uint32(30255); // fraxtal eid
        }
    }

    function run() public broadcastAs(configDeployerPK) {
        address token = IOFT(oft).token();

        uint256 allowance = IERC20(token).allowance(vm.addr(configDeployerPK), oft);
        if (allowance < amount) {
            IERC20(token).approve(oft, type(uint256).max);
        }

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
                dstEid: dstEid,
                to: addressToBytes32(vm.addr(configDeployerPK)),
                amountLD: amount,
                minAmountLD: amount,
                extraOptions: options,
                composeMsg: '',
                oftCmd: ''
        });
        MessagingFee memory fee = IOFT(oft).quoteSend(sendParam, false);
        IOFT(oft).send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(vm.addr(configDeployerPK))
        );
    }
}