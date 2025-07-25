// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/BaseL0Script.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";

// fraxtal : forge script scripts/ops/FraxDVNTest/mainnet/7_SendFraxAssets.s.sol --rpc-url https://rpc.frax.com --broadcast
// plumephoenix : forge script scripts/ops/FraxDVNTest/mainnet/7_SendFraxAssets.s.sol --rpc-url https://rpc.plume.org --broadcast

contract SendFraxAssets is BaseL0Script {
    SendParam[] public sendParams;
    IOFT[] public ofts;
    address[] public redundAddresses;

    function run() public broadcastAs(configDeployerPK) {
        uint256 _totalEthFee;
        uint256 amount = 0.00001 ether;
        address senderWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
        address recipientWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
        SendParam memory _sendParam = SendParam({
            dstEid: uint32(30255),
            to: addressToBytes32(recipientWallet),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        sendParams.push(_sendParam);
        sendParams.push(_sendParam);
        sendParams.push(_sendParam);
        sendParams.push(_sendParam);
        sendParams.push(_sendParam);
        sendParams.push(_sendParam);

        if (broadcastConfig.eid == 30255) {
            ofts.push(IOFT(fraxtalFrxUsdLockbox));
            ofts.push(IOFT(fraxtalSFrxUsdLockbox));
            ofts.push(IOFT(fraxtalFrxEthLockbox));
            ofts.push(IOFT(fraxtalSFrxEthLockbox));
            ofts.push(IOFT(fraxtalFraxLockbox));
            ofts.push(IOFT(fraxtalFpiLockbox));
            MessagingFee memory _fee = IOFT(fraxtalFrxUsdLockbox).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            _fee = IOFT(fraxtalSFrxUsdLockbox).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            _fee = IOFT(fraxtalFrxEthLockbox).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            _fee = IOFT(fraxtalSFrxEthLockbox).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            _fee = IOFT(fraxtalFraxLockbox).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            _fee = IOFT(fraxtalFpiLockbox).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
        } else {
            ofts.push(IOFT(proxyFrxUsdOft));
            ofts.push(IOFT(proxySFrxUsdOft));
            ofts.push(IOFT(proxyFrxEthOft));
            ofts.push(IOFT(proxySFrxEthOft));
            ofts.push(IOFT(proxyFraxOft));
            ofts.push(IOFT(proxyFpiOft));
            MessagingFee memory _fee = IOFT(proxyFrxUsdOft).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            _fee = IOFT(proxySFrxUsdOft).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            _fee = IOFT(proxyFrxEthOft).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            _fee = IOFT(proxySFrxEthOft).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            _fee = IOFT(proxyFraxOft).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            _fee = IOFT(proxyFpiOft).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
        }

        redundAddresses.push(senderWallet);
        redundAddresses.push(senderWallet);
        redundAddresses.push(senderWallet);
        redundAddresses.push(senderWallet);
        redundAddresses.push(senderWallet);
        redundAddresses.push(senderWallet);

        FraxOFTWalletUpgradeable(senderWallet).batchBridgeWithEthFeeFromWallet{ value: _totalEthFee }(
            sendParams,
            ofts,
            redundAddresses
        );
    }
}
