// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTAdapterUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTAdapterUpgradeable.sol";

interface IERC20PermitPermissionedOptiMintable {
    function minter_burn_from(address, uint256) external;
    function minter_mint(address, uint256) external;
}

contract FraxOFTMintableAdapterUpgradeable is OFTAdapterUpgradeable {
    constructor(
        address _token,
        address _lzEndpoint
    ) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    function version() external pure returns (uint256 major, uint256 minor, uint256 patch) {
        major = 1;
        minor = 0;
        patch = 0;
    }

    /// @notice Recover all tokens to owner
    function recover() external {
        uint256 balance = innerToken.balanceOf(address(this));
        if (balance == 0) return;

        innerToken.transfer(owner(), balance);
    }

    /// @dev overrides OFTAdapterUpgradeable.sol to burn the tokens from the sender
    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        IERC20PermitPermissionedOptiMintable(address(innerToken)).minter_burn_from(msg.sender, amountSentLD);
    }

    /// @dev overrides OFTAdapterUpgradeable to mint the tokens to the sender
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /* _srcEid */
    ) internal override returns (uint256 amountReceivedLD) {
        IERC20PermitPermissionedOptiMintable(address(innerToken)).minter_mint(_to, _amountLD);
        return _amountLD;
    }

}
