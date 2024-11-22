// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

contract SendMockOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    address public mFraxOft = address(0); // TODO
    address public mSFraxOft = address(0); // TODO
    address public ethMsig = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;

    /// @dev override to alter file save location
    modifier simulateAndWriteTxs(L0Config memory _config) override {
        // Clear out arrays
        delete enforcedOptionsParams;
        delete setConfigParams;
        delete serializedTxs;

        vm.createSelectFork(_config.RPC);
        chainid = _config.chainid;
        vm.startPrank(_config.delegate);
        _;
        vm.stopPrank();

        // create filename and save
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/UpgradeFrax/txs/");
        string memory filename = string.concat("3_SendMockOFT-", _config.chainid.toString());
        filename = string.concat(filename, ".json");

        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }

    function run() public override {
        submitSends();
    }

    function submitSends() public simulateAndWriteTxs(activeConfig) {
        submitSend(mFraxOft);
        submitSend(mSFraxOft);
    }

    function submitSend(address _oft) public {
        uint256 amount = IERC20(_oft).balanceOf(activeConfig.delegate);

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
                dstEid: uint32(30101), // Ethereum
                to: addressToBytes32(ethMsig),
                amountLD: amount,
                minAmountLD: amount,
                extraOptions: options,
                composeMsg: '',
                oftCmd: ''
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        bytes memory data = abi.encodeCall(
            IOFT.send,
            (
                sendParam, fee, activeConfig.delegate
            )
        );
        (bool success, ) = _oft.call{value: fee.nativeFee}(data);
        require(success, "Failed send");
        serializedTxs.push(
            SerializedTx({
                name: "sendMockOFT",
                to: _oft,
                value: fee.nativeFee,
                data: data
            })
        );
    }
}