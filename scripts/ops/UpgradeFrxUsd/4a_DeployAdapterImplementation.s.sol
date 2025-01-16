// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";

// Deploy the frxUSD and sfrxUSD adapters
/*
source .env && forge script scripts/UpgradeFrax/4a_DeployAdapterImplementation.s.sol --rpc-url https://rpc.frax.com \
    --verifier-url $FRAXSCAN_API_URL --etherscan-api-key $FRAXSCAN_API_KEY --broadcast --verify
*/
contract DeployAdapterImplementation is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    address public frxUsdImplementation;
    address public sfrxUsdImplementation;
    address public frxUsd = 0xFc00000000000000000000000000000000000001;
    address public sfrxUsd = 0xfc00000000000000000000000000000000000008;
    address public endpoint = 0x1a44076050125825900e736c501f859c50fE728c;

    function run() public override {
        deployImplementations();
    }

    function deployImplementations() internal broadcastAs(configDeployerPK) {
        frxUsdImplementation = address(new FraxOFTAdapterUpgradeable(frxUsd, endpoint));
        console.log("frxUsd implementation @ ", frxUsdImplementation);
        sfrxUsdImplementation = address(new FraxOFTAdapterUpgradeable(sfrxUsd, endpoint));
        console.log("sfrxUsd implementation @ ", sfrxUsdImplementation);
    }
}