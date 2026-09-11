pragma solidity ^0.8.0;

import {FreezeThawModule} from "contracts/modules/FreezeThawModule.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice Freeze/thaw set mutations.
/// @dev Linked library. Runs via delegatecall against FreezeThawModule's namespaced storage.
///      Membership reads stay in the module — a delegatecall costs more than the lookup.
library FreezeThawLib {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Must equal FreezeThawModule.FreezeThawStorageLocation.
    bytes32 private constant FreezeThawStorageLocation = 0xf6192aebe04228448ed4fd2802d59c009f5324cdd6a110c65bd318373b6e1d00;

    function _getFreezeThawStorage() private pure returns (FreezeThawModule.FreezeThawStorage storage $) {
        assembly {
            $.slot := FreezeThawStorageLocation
        }
    }

    function freeze(address account) public {
        FreezeThawModule.FreezeThawStorage storage $ = _getFreezeThawStorage();
        $.frozen.add(account);
        emit FreezeThawModule.AccountFrozen(account);
    }

    function thaw(address account) public {
        FreezeThawModule.FreezeThawStorage storage $ = _getFreezeThawStorage();
        $.frozen.remove(account);
        emit FreezeThawModule.AccountThawed(account);
    }

    function freezeMany(address[] calldata accounts) external {
        uint256 len = accounts.length;
        for (uint256 i; i < len; ++i) {
            freeze(accounts[i]);
        }
    }

    function thawMany(address[] calldata accounts) external {
        uint256 len = accounts.length;
        for (uint256 i; i < len; ++i) {
            thaw(accounts[i]);
        }
    }

    function addFreezer(address account) external {
        FreezeThawModule.FreezeThawStorage storage $ = _getFreezeThawStorage();
        if (!$.freezers.add(account)) revert FreezeThawModule.AlreadyFreezer();
        emit FreezeThawModule.AddFreezer(account);
    }

    function removeFreezer(address account) external {
        FreezeThawModule.FreezeThawStorage storage $ = _getFreezeThawStorage();
        if (!$.freezers.remove(account)) revert FreezeThawModule.NotFreezer();
        emit FreezeThawModule.RemoveFreezer(account);
    }




    function frozenList() external view returns (address[] memory) {
        FreezeThawModule.FreezeThawStorage storage $ = _getFreezeThawStorage();
        return $.frozen.values();
    }

    function freezersList() external view returns (address[] memory) {
        FreezeThawModule.FreezeThawStorage storage $ = _getFreezeThawStorage();
        return $.freezers.values();
    }
}
