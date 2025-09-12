// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupDestinationFraxOFTFraxtalHub.sol";

// forge script scripts/FraxtalHub/3_SetupDestinationFraxOFTFraxtalHub/SetupDestinationFraxOFTFraxtalHubHyperliquidmock.s.sol --rpc-url https://rpc.hyperliquid.xyz/evm
contract SetupDestinationFraxOFTFraxtalHubHyperliquidmock is SetupDestinationFraxOFTFraxtalHub {
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

    function run() public override {
        delete fraxtalLockboxes;
        fraxtalFraxLockbox = 0xBC54454844815FFD8229D1f617EFa554D2d68F63; // wfrax
        fraxtalSFrxUsdLockbox = 0x6ff6b416B574Ebc51c8ddDf0B32b82Af3bD08888; // sfrxusd
        fraxtalSFrxEthLockbox = 0x16cEA656B1ad3cAAEf01894794373E48B77faAeF; // sfrxeth
        fraxtalFrxUsdLockbox = 0x1c3Fe45704D8b5B09c145356A6DFD570ab264CDB; // frxusd
        fraxtalFrxEthLockbox = 0xfD34516A516c4F76a5d5B3F9Da562F5731Ac42AF; // frxeth
        fraxtalFpiLockbox = 0xC149f946e3EE35766A7250B6FF619D9Cf198EbF0; // fpi
        fraxtalLockboxes.push(fraxtalFraxLockbox);
        fraxtalLockboxes.push(fraxtalSFrxUsdLockbox);
        fraxtalLockboxes.push(fraxtalSFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalFrxUsdLockbox);
        fraxtalLockboxes.push(fraxtalFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalFpiLockbox);
        super.run();
    }

    function setupDestinations() public override {
        for (uint256 i; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 252) {
                proxyConfigs[i].delegate = 0xAcE0Fd98cfaEd46526cdB1458F2e6a2b1f15f784;
            }
        }
        super.setupDestinations();
    }

    function filename() public view override returns (string memory) {
        string memory name = super.filename();
        return string.concat(name, "-mock");
    }

    function getFileExtension() internal pure override returns (string memory) {
        return "";
    }
}
