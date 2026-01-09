// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @title ITIP20Factory
/// @notice Minimal interface for TIP-20 factory token validation
interface ITIP20Factory {
    /// @notice Check if an address is a registered TIP-20 token
    /// @param token The address to check
    /// @return bool True if the address is a TIP-20 token, false otherwise
    function isTIP20(address token) external view returns (bool);
}
