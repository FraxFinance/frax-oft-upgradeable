pragma solidity ^0.8.22;
// SPDX-License-Identifier: MIT

import "scripts/BaseL0Script.sol";
import "contracts/MockCustodian.sol";

contract DeployMockCustodian is BaseL0Script {
    address public ethMsig = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;

    function run() public broadcastAs(configDeployerPK) {
        MockCustodian mockCustodian = new MockCustodian(ethMsig);
        console.log(address(mockCustodian));
    }
}