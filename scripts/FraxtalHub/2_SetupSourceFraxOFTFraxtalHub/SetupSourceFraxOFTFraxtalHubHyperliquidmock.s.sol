// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupSourceFraxOFTFraxtalHub.sol";

// forge script scripts/FraxtalHub/2_SetupSourceFraxOFTFraxtalHub/SetupSourceFraxOFTFraxtalHubHyperliquidmock.s.sol --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast
contract SetupSourceFraxOFTFraxtalHubHyperliquidmock is SetupSourceFraxOFTFraxtalHub {
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

    function setPriviledgedRoles() public override {
        proxyAdmin = 0xB4D6a05F58E1671C4ECd5D6544C83954B44Fb8d5;

        /// @dev transfer ownership of OFT
        for (uint256 o = 0; o < proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(0x8d8290d49e88D16d81C6aDf6C8774eD88762274A);
            Ownable(proxyOft).transferOwnership(0x8d8290d49e88D16d81C6aDf6C8774eD88762274A);
        }

        /// @dev transfer ownership of ProxyAdmin
        Ownable(proxyAdmin).transferOwnership(0x8d8290d49e88D16d81C6aDf6C8774eD88762274A);
    }
}
