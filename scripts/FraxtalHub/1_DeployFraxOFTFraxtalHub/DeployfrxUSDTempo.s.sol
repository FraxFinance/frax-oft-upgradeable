// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../../BaseL0Script.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";

// forge script ./scripts/FraxtalHub/1_DeployFraxOFTFraxtalHub/DeployfrxUSDTempo.s.sol --rpc-url https://rpc.testnet.tempo.xyz --broadcast
contract DeployfrxUSDTempo is BaseL0Script {
    function setUp() public override {}

    function run() public broadcastAs(oftDeployerPK) {
        ITIP20 token = ITIP20(
            StdPrecompiles.TIP20_FACTORY.createToken(
                "Frax USD",
                "frxUSD",
                "USD",
                StdTokens.PATH_USD,
                vm.addr(configDeployerPK)
            )
        );
    }
}
