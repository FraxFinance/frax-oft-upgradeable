pragma solidity ^0.8.0;
import {PauseLib} from "contracts/libraries/PauseLib.sol";

/*
  * @title PauseModule
  * @dev Contract module that allows pausing and unpausing of the contract.
  * @dev State transitions are delegated to `PauseLib`.
*/
abstract contract PauseModule {

    struct PauseStorage {
        bool isPaused;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.PauseModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PauseStorageLocation = 0x242e96562e738afaa26e2a4eb34bb6ab09c26cd11226ccf8fbc02da32756d300;

    function _getPauseStorage() private pure returns (PauseStorage storage $) {
        assembly {
            $.slot := PauseStorageLocation
        }
    }

    function _pause() internal virtual {
        PauseLib.pause();
    }

    function _unpause() internal virtual {
        PauseLib.unpause();
    }

    /// @notice Return whether the contract is paused
    /// @return bool True if paused, false otherwise
    function isPaused() public view virtual returns (bool) {
        PauseStorage storage $ = _getPauseStorage();
        return $.isPaused;
    }

    /* ========== EVENTS ========== */
    /// @notice Event Emitted when the contract is paused
    event Paused();

    /// @notice Event Emitted when the contract is unpaused
    event Unpaused();

    /* ========== ERRORS ========== */
    error IsPaused();
    error NotPaused();
}
