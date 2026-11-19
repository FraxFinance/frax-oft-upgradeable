// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/BaseL0Script.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";
import { FraxOFTWalletUpgradeableTempo } from "contracts/FraxOFTWalletUpgradeableTempo.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";

// fraxtal : forge script scripts/ops/FraxDVNTest/mainnet/7_SendFraxAssets.s.sol --rpc-url https://rpc.frax.com --broadcast
// plumephoenix : forge script scripts/ops/FraxDVNTest/mainnet/7_SendFraxAssets.s.sol --rpc-url https://rpc.plume.org --broadcast
// katana : forge script scripts/ops/FraxDVNTest/mainnet/7_SendFraxAssets.s.sol --rpc-url https://rpc.katana.network --broadcast
// aurora : forge script scripts/ops/FraxDVNTest/mainnet/7_SendFraxAssets.s.sol --rpc-url https://mainnet.aurora.dev --broadcast
// scroll : forge script scripts/ops/FraxDVNTest/mainnet/7_SendFraxAssets.s.sol --rpc-url https://rpc.scroll.io --broadcast
// sei : forge script scripts/ops/FraxDVNTest/mainnet/7_SendFraxAssets.s.sol --rpc-url https://sei.drpc.org --broadcast

contract SendFraxAssets is BaseL0Script {
    SendParam[] public sendParams;
    IOFT[] public ofts;
    address[] public refundAddresses;

    function run() public broadcastAs(configDeployerPK) {
        uint256 _totalEthFee;
        uint256 amount = 0.00001 ether;
        address senderWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630; //0x4a767e2ef83577225522Ef8Ed71056c6E3acB216
        address recipientWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630; //0x4a767e2ef83577225522Ef8Ed71056c6E3acB216;// 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
        SendParam memory _sendParam = SendParam({
            dstEid: uint32(30255),
            to: addressToBytes32(recipientWallet),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        simulateConfig.chainid = block.chainid;
        _validateAndPopulateMainnetOfts();

        // Only tokens still active in the mesh (L0Constants.activeTokens), in Token slot order. Chains keep the
        // addresses of retired tokens (e.g. FPI) in `connectedOfts`, but those OFTs have no peers, so sending
        // one would revert the whole batch.
        for (uint256 i; i < activeTokens.length; i++) {
            address oft = connectedOfts[uint256(activeTokens[i])];
            if (oft == address(0)) continue;
            sendParams.push(_sendParam);
            ofts.push(IOFT(oft));
            refundAddresses.push(senderWallet);
            _totalEthFee += IOFT(oft).quoteSend(_sendParam, false).nativeFee;
        }

        if (broadcastConfig.eid == 30410) {
            // Tempo: approve wallet to pull TIP20 gas token, then bridge
            StdPrecompiles.TIP_FEE_MANAGER.setUserToken(StdTokens.PATH_USD_ADDRESS);
            ITIP20(StdTokens.PATH_USD_ADDRESS).approve(senderWallet, _totalEthFee);
            FraxOFTWalletUpgradeableTempo(senderWallet).batchBridgeWithTIP20FeeFromWallet(
                sendParams,
                ofts,
                refundAddresses
            );
        } else {
            // All other chains: pays ETH
            FraxOFTWalletUpgradeable(senderWallet).batchBridgeWithEthFeeFromWallet{ value: _totalEthFee }(
                sendParams,
                ofts,
                refundAddresses
            );
        }
    }
}
