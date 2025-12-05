// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SendFraxOFTFraxtalHub.sol";

// forge script scripts/FraxtalHub/4_SendFraxOFTFraxtalHub/SendFraxOFTMonadToFraxtal.s.sol --rpc-url https://rpc.monad.xyz --broadcast
contract SendFraxOFTMonadToFraxtal is SendFraxOFTFraxtalHub {
    constructor() {
        wfraxOft = 0x29aCC7c504665A5EA95344796f784095f0cfcC58;
        sfrxUsdOft = 0x137643F7b2C189173867b3391f6629caB46F0F1a;
        sfrxEthOft = 0x3B4cf37A3335F21c945a40088404c715525fCb29;
        frxUsdOft = 0x58E3ee6accd124642dDB5d3f91928816Be8D8ed3;
        frxEthOft = 0x288F9D76019469bfEb56BB77d86aFa2bF563B75B;
        fpiOft = 0xBa554F7A47f0792b9fa41A1256d4cf628Bb1D028;

        srcEid = 30390;
        dstEid = 30255;
        amount = 0.0001 ether;
        senderWallet = 0x8F37D9F5404067d4bAEc77e42956A198d1858080;
        recipientWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
    }
}
