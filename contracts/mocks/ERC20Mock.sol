// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts-4.8.1/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts-4.8.1/access/Ownable.sol";

contract ERC20Mock is Ownable, ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}