// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

contract SubmitSends is BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function version() public pure override returns (uint256, uint256, uint256) {
        return (1, 1, 1);
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
            submitSends(expectedProxyOfts);
    }

    function submitSends(
        address[] memory _connectedOfts
    ) public {
        for (uint256 c=0; c<allConfigs.length; c++) {
            // Do not send if the target chain == active chain
            if (allConfigs[c].chainid == activeConfig.chainid) {
                continue;
            }
            for (uint256 o=0; o<_connectedOfts.length; o++) {
                submitSend(allConfigs[c], _connectedOfts[o]);
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

        // TODO: remove after testing
        // send over sfrxEth, sFrax, frxEth
        // if (_connectedOft != 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0 && _connectedOft != 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45 && _connectedOft != 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050) return;
        // send legacy fpi
        if (_connectedOft != 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927) return;
        // skip sending to solana
        if (_connectedConfig.eid == 30168) return;
        // only send to proxy eids
        // if (_connectedConfig.eid != 30260 && _connectedConfig.eid != 30280 && _connectedConfig.eid != 30255 && _connectedConfig.eid !=  30274) return;

        require(
            IERC20(oftToken).balanceOf(vm.addr(senderDeployerPK)) > allConfigs.length,
            "Not enough token balance"
        );

        uint256 allowance = IERC20(oftToken).allowance(vm.addr(senderDeployerPK), _connectedOft);
        if (allowance < amount) {
            IERC20(oftToken).approve(_connectedOft, type(uint256).max);
        }

        // bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300_000, 0);
        bytes memory options = OptionsBuilder.newOptions();
        bytes32 to;
        if (_connectedConfig.eid == 30168) {
            to = 0x382cf2ab7863c0f8cdedff8ef6ad1b02f835ddc8aea86c8f0ed5fc6fa8f765b0; // phantom wallet 4nHaq4EiQZVnDhPAnK1zZEd3qKJVwzBuyTdrbBvvvUS3
        } else {
            to = addressToBytes32(vm.addr(senderDeployerPK));
        }
        SendParam memory sendParam = SendParam({
                dstEid: uint32(_connectedConfig.eid),
                to: to,
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