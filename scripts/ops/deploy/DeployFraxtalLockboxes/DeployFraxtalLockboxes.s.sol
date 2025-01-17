// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev deploys (s)frxETH/FXS/FPI lockboxes on fraxtal and wires them to proxy OFTs
contract DeployFraxtalLockboxes is DeployFraxOFTProtocol {

    address wfrxEth = 0xfc00000000000000000000000000000000000006;
    address sfrxEth = 0xfc00000000000000000000000000000000000005;
    address fxs = 0xfc00000000000000000000000000000000000002;
    address fpi = 0xfc00000000000000000000000000000000000003;

    function run() public override {
        // TODO: overwrite expectedProxyOFTs to [frxETH, sfrxETH, fxs, fpi] to match proxyOfts
    }

    function postDeployChecks() public override pure {
        require(address(0) == address(0));
    }

    // Deploy (s)frxETH/FXS/FPI
    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(senderDeployerPK) public override {
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
    }
}