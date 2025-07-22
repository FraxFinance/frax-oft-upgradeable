// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTAdapterUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTAdapterUpgradeable.sol";
import { SupplyTrackingModule } from "./modules/SupplyTrackingModule.sol";

interface IERC20PermitPermissionedOptiMintable {
    function minter_burn_from(address, uint256) external;
    function minter_mint(address, uint256) external;
}

contract FraxOFTMintableAdapterUpgradeable is OFTAdapterUpgradeable, SupplyTrackingModule {
    constructor(
        address _token,
        address _lzEndpoint
    ) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    function version() external pure returns (uint256 major, uint256 minor, uint256 patch) {
        major = 1;
        minor = 1;
        patch = 0;
    }

    /// @notice Recover all tokens to owner
    /// @dev added in v1.1.0
    function recover() external {
        uint256 balance = innerToken.balanceOf(address(this));
        if (balance == 0) return;

        innerToken.transfer(owner(), balance);
    }

    /// @dev overrides OFTAdapterUpgradeable.sol to burn the tokens from the sender/track supply
    /// @dev added in v1.1.0
    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        _addToTotalSupply(_dstEid, amountSentLD);
        _addToTotalTransferTo(_dstEid, amountSentLD);

        IERC20PermitPermissionedOptiMintable(address(innerToken)).minter_burn_from(msg.sender, amountSentLD);
    }

    /// @dev overrides OFTAdapterUpgradeable to mint the tokens to the sender/track supply
    /// @dev added in v1.1.0
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal override returns (uint256 amountReceivedLD) {

        _subtractFromTotalSupply(_srcEid, _amountLD);
        _addToTotalTransferFrom(_srcEid, _amountLD);

        IERC20PermitPermissionedOptiMintable(address(innerToken)).minter_mint(_to, _amountLD);
        return _amountLD;
    }

    /// @notice Set the total supply and transfer amounts for a specific chain
    /// @param _eid The target chain EID
    /// @param _totalSupply The total supply of the OFT on the target chain
    /// @param _totalTransferFrom The total amount transferred from the target chain
    /// @param _totalTransferTo The total amount transferred to the target chain
    /// @dev Only callable by the owner
    /// @dev added in v1.1.0
    function setTotals(
        uint32 _eid,
        uint256 _totalSupply,
        uint256 _totalTransferFrom,
        uint256 _totalTransferTo
    ) external onlyOwner {
        _setTotals(_eid, _totalSupply, _totalTransferFrom, _totalTransferTo);
    }

    /// @notice Set the total supply for a specific chain
    /// @param _eid The target chain EID
    /// @param _totalSupply The total supply of the OFT on the target chain
    /// @dev Only callable by the owner
    /// @dev added in v1.1.0
    function setTotalSupply(uint32 _eid, uint256 _totalSupply) external onlyOwner {
        _setTotalSupply(_eid, _totalSupply);
    }
}
