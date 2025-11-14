// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupSourceFraxOFTFraxtalHub.sol";

// Note.Following transactions were not executed during SetupSourceFraxOFTFraxtalHubPlasma
// 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050 - frxETH - owner and delegate
// 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927 - fpi - owner and delegate
// 0x90581eca9469d8d7f5d3b60f4715027adfcf7927 - fpi - config 3 receiveUln302
// 0x223a681fc5c5522c85c96157c0efa18cd6c5405c - proxyAdmin - transferOwnership

// forge script scripts/FraxtalHub/2_SetupSourceFraxOFTFraxtalHub/SetupSourceFraxOFTFraxtalHubPlasmaFix.s.sol --rpc-url https://rpc.plasma.to --broadcast
contract SetupSourceFraxOFTFraxtalHubPlasmaFix is SetupSourceFraxOFTFraxtalHub {
    constructor() {
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;

        proxyOfts.push(frxEthOft);
        proxyOfts.push(fpiOft);
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        setDVNs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: proxyConfigs });
        setPriviledgedRoles();
    }

    function _validateAddrs() internal view override {
        require(isStringEqual(IERC20Metadata(frxEthOft).symbol(), "frxETH"), "frxEthOft != frxETH");
        require(isStringEqual(IERC20Metadata(fpiOft).symbol(), "FPI"), "fpiOft != FPI");
    }
}
