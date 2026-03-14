// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/BaseL0Script.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";

// forge script scripts/ops/FraxDVNTest/mainnet/4_MintMockfrxUSD.s.sol --rpc-url https://rpc.frax.com --broadcast
contract MintMockfrxUSD is BaseL0Script {
    address mockfrxUSD = 0x458edF815687e48354909A1a848f2528e1655764;
    address fraxtalOFTWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;

    uint256 amount = 1000e18;

    function run() public broadcastAs(configDeployerPK) {
        FraxOFTMintableUpgradeable(mockfrxUSD).mint(fraxtalOFTWallet, amount);
    }
}
