// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupSourceFraxOFTFraxtalHub.sol";
import { OFTAdapterUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTAdapterUpgradeable.sol";

// forge script scripts/FraxtalHub/2_SetupSourceFraxOFTFraxtalHub/SetupSourceFraxOFTFraxtalHubTempo.s.sol --rpc-url $TEMPO_RPC_URL --gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc --broadcast
contract SetupSourceFraxOFTFraxtalHubTempo is SetupSourceFraxOFTFraxtalHub {
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

    /// @notice Use --sender / --gcp instead of a raw private key.
    modifier broadcastAs(uint256) override {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    /// @notice frxUSD on Tempo is an OFTAdapter wrapping TIP20 — validate via underlying token.
    function _validateFrxUsdAddr() internal view override {
        require(
            isStringEqual(IERC20Metadata(OFTAdapterUpgradeable(frxUsdOft).token()).symbol(), "frxUSD"),
            "frxUsdOft != frxUSD"
        );
    }
}
