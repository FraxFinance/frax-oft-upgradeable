// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { OFTUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTUpgradeable.sol";

// Setup destination with a hub model vs. a spoke model where the only peer is Fraxtal
abstract contract SetupDestinationFraxOFTFraxtalHub is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;

    function run() public override {
        require(
            OFTUpgradeable(wfraxOft).isPeer(30255, addressToBytes32(fraxtalFraxLockbox)),
            "fraxtal is not connected to wfraxOft"
        );
        require(
            OFTUpgradeable(sfrxUsdOft).isPeer(30255, addressToBytes32(fraxtalSFrxUsdLockbox)),
            "fraxtal is not connected to sfrxusdoft"
        );
        require(
            OFTUpgradeable(sfrxEthOft).isPeer(30255, addressToBytes32(fraxtalSFrxEthLockbox)),
            "fraxtal is not connected to sfrxethoft"
        );
        require(
            OFTUpgradeable(frxUsdOft).isPeer(30255, addressToBytes32(fraxtalFrxUsdLockbox)),
            "frxusdoft is not connected to fraxtal"
        );
        require(
            OFTUpgradeable(frxEthOft).isPeer(30255, addressToBytes32(fraxtalFrxEthLockbox)),
            "frxethoft is not connected to fraxtal"
        );
        require(
            OFTUpgradeable(fpiOft).isPeer(30255, addressToBytes32(fraxtalFpiLockbox)),
            "frxethoft is not connected to fraxtal"
        );

        for (uint256 i; i < proxyConfigs.length; i++) {
            // Set up destinations for Fraxtal lockboxes only
            if (proxyConfigs[i].chainid == 252 || proxyConfigs[i].chainid == broadcastConfig.chainid) {
                tempConfigs.push(proxyConfigs[i]);
            }
        }

        require(tempConfigs.length == 2, "Incorrect tempConfigs array");

        delete proxyConfigs;
        for (uint256 i = 0; i < tempConfigs.length; i++) {
            proxyConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        setupDestinations();
    }
}
