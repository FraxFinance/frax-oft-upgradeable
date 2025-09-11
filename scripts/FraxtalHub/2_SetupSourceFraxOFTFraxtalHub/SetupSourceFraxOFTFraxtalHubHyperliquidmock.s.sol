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

    function setPriviledgedRoles() public override {
        proxyAdmin = broadcastConfig.proxyAdmin;

        // TODO : remove nextline once mock frax OFTs setup is done
        proxyAdmin = 0xB4D6a05F58E1671C4ECd5D6544C83954B44Fb8d5;

        if (proxyAdmin == address(0)) revert("ProxyAdmin cannot be zero address");

        // TODO : remove next loop once mock frax OFTs setup is done
        /// @dev transfer ownership of OFT
        for (uint256 o = 0; o < proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(0x8d8290d49e88D16d81C6aDf6C8774eD88762274A);
            Ownable(proxyOft).transferOwnership(0x8d8290d49e88D16d81C6aDf6C8774eD88762274A);
        }

        // TODO : remove nextline once mock frax OFTs setup is done
        /// @dev transfer ownership of ProxyAdmin
        Ownable(proxyAdmin).transferOwnership(0x8d8290d49e88D16d81C6aDf6C8774eD88762274A);

        // TODO : uncomment next line once mock OFTs setup is done
        // super.setPriviledgedRoles();
    }
}
