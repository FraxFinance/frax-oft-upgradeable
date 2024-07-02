// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

contract SubmitSends is BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function version() public pure override returns (uint256, uint256, uint256) {
        return (1, 0, 1);
    }

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
    ) public broadcastAs(senderDeployerPK) {
        uint256 amount = 1e14;
        address oftToken = IOFT(_connectedOft).token();
        require(
            IERC20(oftToken).balanceOf(vm.addr(senderDeployerPK)) > amount * 6,
            "Not enough token balance"
        );

        uint256 allowance = IERC20(oftToken).allowance(vm.addr(senderDeployerPK), _connectedOft);
        if (allowance < amount) {
            IERC20(oftToken).approve(_connectedOft, type(uint256).max);
        }

        // bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300_000, 0);
        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
                dstEid: uint32(_connectedConfig.eid),
                to: addressToBytes32(vm.addr(senderDeployerPK)),
                amountLD: amount,
                minAmountLD: amount,
                extraOptions: options,
                composeMsg: '',
                oftCmd: ''
        });
        MessagingFee memory fee = IOFT(_connectedOft).quoteSend(sendParam, false);
        IOFT(_connectedOft).send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(vm.addr(senderDeployerPK))
        );
    }
}