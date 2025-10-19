// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FrxUSDOFTUpgradeable } from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";

/// @notice Testnet frxUSD to mint tokens
contract TestnetFrxUSDOFTUpgradeable is FrxUSDOFTUpgradeable {
    constructor(address _lzEndpoint) FrxUSDOFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    /// @notice mint some testnet frxUSD
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }
}