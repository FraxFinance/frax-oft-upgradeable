// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SendFraxOFTFraxtalHub.sol";
import { FraxOFTWalletUpgradeableTempo } from "contracts/FraxOFTWalletUpgradeableTempo.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";

// forge script scripts/FraxtalHub/4_SendFraxOFTFraxtalHub/SendFraxOFTTempoToFraxtal.s.sol --rpc-url $TEMPO_RPC_URL --broadcast

contract SendFraxOFTTempoToFraxtal is SendFraxOFTFraxtalHub { 
    constructor() {
        wfraxOft = 0x00000000E9CE0f293D1Ce552768b187eBA8a56D4;
        sfrxUsdOft = 0x00000000fD8C4B8A413A06821456801295921a71;
        sfrxEthOft = 0x00000000883279097A49dB1f2af954EAd0C77E3c;
        frxUsdOft = 0x00000000D61733e7A393A10A5B48c311AbE8f1E5;
        frxEthOft = 0x000000008c3930dCA540bB9B3A5D0ee78FcA9A4c;
        fpiOft = 0x00000000bC4aEF4bA6363a437455Cb1af19e2aEb;

        srcEid = 30410;
        dstEid = 30255;
        amount = 0.0001 ether;
        senderWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
        recipientWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
    }

    /// @dev Tempo pays LZ fees in TIP20 (no msg.value) via FraxOFTWalletUpgradeableTempo.
    function _executeBatchBridge(uint256 _totalFee) internal override {
        FraxOFTWalletUpgradeableTempo _wallet = FraxOFTWalletUpgradeableTempo(senderWallet);
        IERC20 _pathUsd = IERC20(StdTokens.PATH_USD_ADDRESS);

        address FRXUSD_TIP20 = IOFT(frxUsdOft).token();

        address gasToken = FRXUSD_TIP20; // StdTokens.PATH_USD_ADDRESSå

        // _wallet.approveToken(IERC20(FRXUSD_TIP20), frxUsdOft, type(uint256).max);

        // Approve wallet to let each OFT pull PATH_USD for LZ gas fees
        // for (uint256 i; i < ofts.length; i++) {
        //     _wallet.approveToken(IERC20(gasToken), address(ofts[i]), type(uint256).max);
        // }

        // Approve wallet to pull PATH_USD from deployer for the total fee
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);
        // ITIP20(gasToken).approve(senderWallet, type(uint256).max);
        _wallet.batchBridgeWithTIP20FeeFromWallet(sendParams, ofts, refundAddresses);
    }

    /// @dev frxUSD on Tempo is a 6-decimal TIP20 — scale down from 18 decimals.
    ///      Returns a NEW struct to avoid mutating the original (memory structs are pass-by-reference).
    function _getsendParamsForfrxUSD(SendParam memory _sendParam) internal view override returns (SendParam memory) {
        uint256 scaleFactor = 10 ** (18 - IERC20Metadata(IOFT(frxUsdOft).token()).decimals());
        return SendParam({
            dstEid: _sendParam.dstEid,
            to: _sendParam.to,
            amountLD: _sendParam.amountLD / scaleFactor,
            minAmountLD: _sendParam.minAmountLD / scaleFactor,
            extraOptions: _sendParam.extraOptions,
            composeMsg: _sendParam.composeMsg,
            oftCmd: _sendParam.oftCmd
        });
    }
}
