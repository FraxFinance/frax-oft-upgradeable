// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTAdapterUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTAdapterUpgradeable.sol";
import { SendParam } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

contract FraxOFTAdapterUpgradeable is OFTAdapterUpgradeable {
    constructor(
        address _token,
        address _lzEndpoint
    ) OFTAdapterUpgradeable(_token, _lzEndpoint) {}

    function version() external pure returns (uint256 major, uint256 minor, uint256 patch) {
        major = 1;
        minor = 0;
        patch = 0;
    }

    // Admin

    function initialize(address _delegate) external initializer {
        __OFTCore_init(_delegate);
        __Ownable_init();
        _transferOwnership(_delegate);
    }
}
