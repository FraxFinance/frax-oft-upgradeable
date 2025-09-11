// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupDestinationFraxOFTFraxtalHub.sol";

// forge script scripts/FraxtalHub/3_SetupDestinationFraxOFTFraxtalHub/SetupDestinationFraxOFTFraxtalHubHyperliquid.s.sol --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast
contract SetupDestinationFraxOFTFraxtalHubHyperliquid is SetupDestinationFraxOFTFraxtalHub {
    constructor() {
        wfraxOft = 0x65C042454005de49106a6B0129F4Af56939457da;
        sfrxUsdOft = 0xE1851f6ac161d1911104b19918FB866eF6FEE577;
        sfrxEthOft = 0xb7583B07C12286bb9026A7053B0C44e8f5fa8624;
        frxUsdOft = 0xA444F92734be29E71b8A4762595C9733Ab2C9c47;
        frxEthOft = 0xa5C2889F0E3DA388DF3BF87f8f0B8E56bB863C41;
        fpiOft = 0xC6563942D1AE02Dd6e450847de3753011cA3eee1;

        proxyOfts.push(wfraxOft);
        proxyOfts.push(sfrxUsdOft);
        proxyOfts.push(sfrxEthOft);
        proxyOfts.push(frxUsdOft);
        proxyOfts.push(frxEthOft);
        proxyOfts.push(fpiOft);
    }
}
