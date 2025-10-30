// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

// forge script scripts/SubmitSends/SubmitSend.s.sol --broadcast --rpc-url https://eth-sepolia.public.blastapi.io
contract SubmitSend is BaseL0Script {
    using OptionsBuilder for bytes;

    uint256 amount = 100_000e18;
    address public oft = 0x29a5134D3B22F47AD52e0A22A63247363e9F35c2; // frxUSD
    uint32 public dstEid = 40231; // arb sep
    address to = vm.addr(senderDeployerPK);

    function run() public broadcastAs(senderDeployerPK) {
        address token = IOFT(oft).token();

        uint256 allowance = IERC20(token).allowance(vm.addr(senderDeployerPK), oft);
        if (allowance < amount) {
            IERC20(token).approve(oft, type(uint256).max);
        }

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
                dstEid: dstEid,
                to: addressToBytes32(vm.addr(senderDeployerPK)),
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
            payable(vm.addr(senderDeployerPK))
        );
    }
}