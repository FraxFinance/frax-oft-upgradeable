// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupDestinationFraxOFTFraxtalHub.sol";

// forge script scripts/FraxtalHub/3_SetupDestinationFraxOFTFraxtalHub/SetupDestinationFraxOFTFraxtalHubTempo.s.sol --rpc-url $TEMPO_RPC_URL --ffi
contract SetupDestinationFraxOFTFraxtalHubTempo is SetupDestinationFraxOFTFraxtalHub {
    constructor() {
        wfraxOft = 0x00000000E9CE0f293D1Ce552768b187eBA8a56D4;
        sfrxUsdOft = 0x00000000fD8C4B8A413A06821456801295921a71;
        sfrxEthOft = 0x00000000883279097A49dB1f2af954EAd0C77E3c;
        frxUsdOft = 0x00000000D61733e7A393A10A5B48c311AbE8f1E5;
        frxEthOft = 0x000000008c3930dCA540bB9B3A5D0ee78FcA9A4c;
        fpiOft = 0x00000000bC4aEF4bA6363a437455Cb1af19e2aEb;

        proxyOfts.push(wfraxOft);
        proxyOfts.push(sfrxUsdOft);
        proxyOfts.push(sfrxEthOft);
        proxyOfts.push(frxUsdOft);
        proxyOfts.push(frxEthOft);
        proxyOfts.push(fpiOft);
    }

    function getFileExtension() internal pure override returns (string memory) {
        return "";
    }
}
