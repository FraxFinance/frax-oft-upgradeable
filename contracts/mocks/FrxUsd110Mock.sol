pragma solidity ^0.8.22;

import { FrxUSDOFTUpgradeable } from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";

contract FrxUSD110Mock is FrxUSDOFTUpgradeable {
    constructor(address _lzEndpoint) FrxUSDOFTUpgradeable(_lzEndpoint) {
        // _disableInitializers();
    }

    function init(address _delegate) external {
        require(owner() == address(0), "Already initialized");
        __OFT_init(name(), symbol(), _delegate);
        __EIP712_init(name(), version());

        __Ownable_init();
        _transferOwnership(_delegate);
    }

    function mint(address to, uint256 amount) external onlyOwner{
        _mint(to, amount);
    }
}