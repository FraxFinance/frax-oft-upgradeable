// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

contract L0Constants {

    address[] public expectedProxyOfts;
    address[] public fraxtalLockboxes;
    address[] public ethLockboxes;
    address[] public connectedOfts;
    address[] public ethLockboxesLegacy;

    // Semi Pre-deterministic upgradeable addresses 
    address public proxyFrxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address public proxySFrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address public proxyFrxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
    address public proxySFrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
    address public proxyFxsOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
    address public proxyFpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;

    address public fraxtalFrxUsdLockbox = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
    address public fraxtalSFrxUsdLockbox = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
    address public fraxtalFrxEthLockbox = 0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604;
    address public fraxtalSFrxEthLockbox = 0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168;
    address public fraxtalFxsLockbox = 0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A;
    address public fraxtalFpiLockbox = 0x75c38D46001b0F8108c4136216bd2694982C20FC;

    address public ethFrxUsdLockbox = 0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0;
    address public ethSFrxUsdLockbox = 0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126;
    address public ethFrxEthLockbox = 0xF010a7c8877043681D59AD125EbF575633505942;
    address public ethSFrxEthLockbox = 0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A;
    address public ethFxsLockbox = 0x23432452B720C80553458496D4D9d7C5003280d0; // TODO - upgrade 
    address public ethFpiLockbox = 0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d;

    address public ethFraxLockboxLegacy = 0x909DBdE1eBE906Af95660033e478D59EFe831fED;
    address public ethSFraxLockboxLegacy = 0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E;

    constructor() {
        // array of semi-pre-determined upgradeable OFTs
        /// @dev: this array maintains the same token order as proxyOfts
        expectedProxyOfts.push(proxyFxsOft);
        expectedProxyOfts.push(proxySFrxUsdOft);
        expectedProxyOfts.push(proxySFrxEthOft);
        expectedProxyOfts.push(proxyFrxUsdOft);
        expectedProxyOfts.push(proxyFrxEthOft);
        expectedProxyOfts.push(proxyFpiOft);

        fraxtalLockboxes.push(fraxtalFxsLockbox);
        fraxtalLockboxes.push(fraxtalSFrxUsdLockbox);
        fraxtalLockboxes.push(fraxtalSFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalFrxUsdLockbox);
        fraxtalLockboxes.push(fraxtalFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalFpiLockbox);

        ethLockboxes.push(ethFxsLockbox);
        ethLockboxes.push(ethSFrxUsdLockbox);
        ethLockboxes.push(ethSFrxEthLockbox);
        ethLockboxes.push(ethFrxUsdLockbox);
        ethLockboxes.push(ethFrxEthLockbox);
        ethLockboxes.push(ethFpiLockbox);

        connectedOfts = new address[](expectedProxyOfts.length);

        ethLockboxesLegacy.push(ethFraxLockboxLegacy);
        ethLockboxesLegacy.push(ethSFraxLockboxLegacy);
    }
}