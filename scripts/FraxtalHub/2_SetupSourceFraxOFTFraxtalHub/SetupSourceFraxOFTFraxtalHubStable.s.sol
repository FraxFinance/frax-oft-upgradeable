// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupSourceFraxOFTFraxtalHub.sol";

// forge script scripts/FraxtalHub/2_SetupSourceFraxOFTFraxtalHub/SetupSourceFraxOFTFraxtalHubStable.s.sol --rpc-url https://rpc.stable.xyz --broadcast
contract SetupSourceFraxOFTFraxtalHubStable is SetupSourceFraxOFTFraxtalHub {
    constructor() {
        wfraxOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;

        proxyOfts.push(wfraxOft);
        proxyOfts.push(sfrxUsdOft);
        proxyOfts.push(sfrxEthOft);
        proxyOfts.push(frxUsdOft);
        proxyOfts.push(frxEthOft);
        proxyOfts.push(fpiOft);
    }
}