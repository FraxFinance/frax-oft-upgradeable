// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

contract SubmitSends is BaseL0Script {
    function setUp() public override {
        super.setUp();
    }

    function run() public {

    }

    function submitSends() public {
        for (uint256 i=0; i<configs.length; i++) {
            submitSend(configs[i])
        }
    }

    function submitSend(L0Config memory _config) public {
        
    }
}