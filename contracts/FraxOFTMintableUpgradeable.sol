// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTUpgradeable } from "./FraxOFTUpgradeable.sol";

/**
 * This contract is for deploying test OFTs.
 * NOT FOR PRODUCTION
 */
contract FraxOFTMintableUpgradeable is FraxOFTUpgradeable {
    constructor(address _lzEndpoint) FraxOFTUpgradeable(_lzEndpoint) {}

    function mint(address _account, uint256 _amount) external onlyOwner {
        _mint(_account, _amount);
    }
}
