// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SendFraxOFTFraxtalHub.sol";

// forge script scripts/FraxtalHub/4_SendFraxOFTFraxtalHub/SendFraxOFTFraxtalToHyperliquidmock.s.sol --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast

contract SendFraxOFTFraxtalToHyperliquidmock is SendFraxOFTFraxtalHub {
    constructor() {
        wfraxOft = 0x65C042454005de49106a6B0129F4Af56939457da;
        sfrxUsdOft = 0xE1851f6ac161d1911104b19918FB866eF6FEE577;
        sfrxEthOft = 0xb7583B07C12286bb9026A7053B0C44e8f5fa8624;
        frxUsdOft = 0xA444F92734be29E71b8A4762595C9733Ab2C9c47;
        frxEthOft = 0xa5C2889F0E3DA388DF3BF87f8f0B8E56bB863C41;
        fpiOft = 0xC6563942D1AE02Dd6e450847de3753011cA3eee1;

        dstEid = 30367;
        amount = 0.00001 ether;
        senderWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
        recipientWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
    }
}
