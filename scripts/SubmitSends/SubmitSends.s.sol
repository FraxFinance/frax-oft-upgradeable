// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

contract SubmitSends is BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function setUp() public override {
        super.setUp();
    }

    function run() public {
        submitSends();
    }

    function submitSends() public {
        activeLegacy ? 
            submitSends(legacyOfts) :
            submitSends(proxyOfts);
    }

    function submitSends(
        address[] memory _connectedOfts
    ) public {
        for (uint256 c=0; c<configs.length; c++) {
            // Do not send if the target chain == active chain
            if (configs[c].chainid == activeConfig.chainid) {
                continue;
            }
            for (uint256 o=0; o<_connectedOfts.length; o++) {
                submitSend(configs[c], _connectedOfts[o]);
            }
        }
    }

    /// Similar methods: https://github.com/angg-lz/my-lz-oft/blob/main/tasks/index.ts
    /// https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/OFT.t.sol#L111
    function submitSend(
        L0Config memory _connectedConfig,
        address _connectedOft
    ) public {
        uint256 amount = 1e12;
        require(
            IERC20(_connectedOft).balanceOf(vm.addr(senderDeployerPK)) > amount * 6,
            "Not enough token balance"
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        SendParam memory sendParam = SendParam({
                dstEid: _connectedConfig.eid,
                to: addressToBytes32(vm.addr(senderDeployerPK)),
                amountLD: amount,
                minAmountLD: amount,
                extraOptions: options,
                composeMsg: '',
                oftCmd: '',
        });
        MessagingFee memory fee = FraxOFTUpgradeable(_connectedOft).quoteSend(sendParam, false);
        MessagingReceipt memory msgReceipt;
        OFTReceipt memory oftReceipt;
        (msgReceipt, oftReceipt) = FraxOFTUpgradeable(_connectedOft).send{value: fee.nativeFee}({
            _sendParam: sendParam,
            _fee: fee,
            _refundAddress: payable(vm.addr(senderDeployerPK))
        });
    }
}