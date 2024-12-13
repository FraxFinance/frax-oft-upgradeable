// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../../BaseL0Script.sol";

contract Send is BaseL0Script {
    using OptionsBuilder for bytes;

    uint256 amount = 500_000e18;
    address public oft;
    uint32 public dstEid;

    constructor() {
        if (block.chainid == 252) {
            oft = address(0x0); // @todo fraxtal addr of oft
            dstEid = uint32(30184); // base eid
        } else {
            oft = address(0x0); // @todo base addr of adapter
            dstEid = uint32(30255); // fraxtal eid
        }
    }

    function run() public override broadcastAs(configDeployerPK) {
        address token = IOFT(oft).token();

        uint256 allowance = IERC20(token).allowance(vm.addr(configDeployerPK), _connectedOft);
        if (allowance < amount) {
            IERC20(token).approve(_connectedOft, type(uint256).max);
        }
}