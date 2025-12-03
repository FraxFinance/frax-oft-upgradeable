// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupSourceFraxOFTFraxtalHub.sol";

// forge script scripts/FraxtalHub/2_SetupSourceFraxOFTFraxtalHub/SetupSourceFraxOFTFraxtalHubMonad.s.sol --rpc-url https://rpc.monad.xyz --broadcast
contract SetupSourceFraxOFTFraxtalHubMonad is SetupSourceFraxOFTFraxtalHub {
    constructor() {
        wfraxOft = 0x29acc7c504665a5ea95344796f784095f0cfcc58;
        sfrxUsdOft = 0x137643f7b2c189173867b3391f6629cab46f0f1a;
        sfrxEthOft = 0x3b4cf37a3335f21c945a40088404c715525fcb29;
        frxUsdOft = 0x58e3ee6accd124642ddb5d3f91928816be8d8ed3;
        frxEthOft = 0x288f9d76019469bfeb56bb77d86afa2bf563b75b;
        fpiOft = 0xba554f7a47f0792b9fa41a1256d4cf628bb1d028;

        proxyOfts.push(wfraxOft);
        proxyOfts.push(sfrxUsdOft);
        proxyOfts.push(sfrxEthOft);
        proxyOfts.push(frxUsdOft);
        proxyOfts.push(frxEthOft);
        proxyOfts.push(fpiOft);
    }
}