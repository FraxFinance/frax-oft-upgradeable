// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SendFraxOFTFraxtalHub.sol";

// forge script scripts/FraxtalHub/4_SendFraxOFTFraxtalHub/SendFraxOFTFraxtalToHyperliquid.s.sol --rpc-url https://rpc.frax.com --broadcast

contract SendFraxOFTFraxtalToHyperliquid is SendFraxOFTFraxtalHub {
    constructor() {
        wfraxOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;

        srcEid = 30255;
        dstEid = 30367;
        amount = 2 ether;
        senderWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
        recipientWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
    }
}
