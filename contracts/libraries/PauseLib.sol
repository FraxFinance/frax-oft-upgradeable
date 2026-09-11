pragma solidity ^0.8.0;

import {PauseModule} from "contracts/modules/PauseModule.sol";

/// @notice Pause state transitions.
/// @dev Linked library. Runs via delegatecall against PauseModule's namespaced storage.
library PauseLib {
    /// @dev Must equal PauseModule.PauseStorageLocation.
    bytes32 private constant PauseStorageLocation = 0x242e96562e738afaa26e2a4eb34bb6ab09c26cd11226ccf8fbc02da32756d300;

    function _getPauseStorage() private pure returns (PauseModule.PauseStorage storage $) {
        assembly {
            $.slot := PauseStorageLocation
        }
    }

    function pause() external {
        PauseModule.PauseStorage storage $ = _getPauseStorage();
        if ($.isPaused) revert PauseModule.IsPaused();
        $.isPaused = true;
        emit PauseModule.Paused();
    }

    function unpause() external {
        PauseModule.PauseStorage storage $ = _getPauseStorage();
        if (!$.isPaused) revert PauseModule.NotPaused();
        $.isPaused = false;
        emit PauseModule.Unpaused();
    }
}
