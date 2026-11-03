// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupSourceFraxOFTFraxtalHub.sol";

// forge script scripts/FraxtalHub/2_SetupSourceFraxOFTFraxtalHub/SetupSourceFraxOFTFraxtalHubRobinhood.s.sol --rpc-url https://rpc.mainnet.chain.robinhood.com --gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc --broadcast
contract SetupSourceFraxOFTFraxtalHubRobinhood is SetupSourceFraxOFTFraxtalHub {
    constructor() {
        wfraxOft = 0x00000000E9CE0f293D1Ce552768b187eBA8a56D4;
        sfrxUsdOft = 0x00000000fD8C4B8A413A06821456801295921a71;
        sfrxEthOft = 0x00000000883279097A49dB1f2af954EAd0C77E3c;
        frxUsdOft = 0x00000000D61733e7A393A10A5B48c311AbE8f1E5;
        frxEthOft = 0x000000008c3930dCA540bB9B3A5D0ee78FcA9A4c;

        proxyOfts.push(wfraxOft);
        proxyOfts.push(sfrxUsdOft);
        proxyOfts.push(sfrxEthOft);
        proxyOfts.push(frxUsdOft);
        proxyOfts.push(frxEthOft);
    }

    /// @notice Use --sender / --gcp instead of a raw private key (the GCP deployer owns the
    ///         OFTs from step 1 and must sign step 2 until setPriviledgedRoles hands off).
    modifier broadcastAs(uint256) override {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }
}
