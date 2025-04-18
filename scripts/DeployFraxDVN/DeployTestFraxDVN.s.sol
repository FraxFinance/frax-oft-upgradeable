// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0FraxDVNScript.sol";

// forge script ./scripts/DeployFraxDVN/DeployTestFraxDVN.s.sol:DeployTestFraxDVN --rpc-url "https://ethereum-sepolia-rpc.publicnode.com"
contract DeployTestFraxDVN is BaseL0FraxDVNScript {
    function _getNetworkEnv() internal pure override returns (string memory _networkEnv) {
        _networkEnv = ".testnet";
    }
}
