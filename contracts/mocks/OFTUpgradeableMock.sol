// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTUpgradeable } from "../FraxOFTUpgradeable.sol";

interface IEndpoint {
    function delegates(address _oapp) external view returns (address);
}

contract OFTUpgradeableMock is FraxOFTUpgradeable {
    constructor(address _lzEndpoint) FraxOFTUpgradeable(_lzEndpoint) {}

    function mint(address _to, uint256 _amount) public {
        require(msg.sender == IEndpoint(address(endpoint)).delegates(address(this)));
        _mint(_to, _amount);
    }
}
