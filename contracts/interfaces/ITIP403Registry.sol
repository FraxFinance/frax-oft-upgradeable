// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @title ITIP403Registry
/// @notice Minimal interface for TIP-403 registry authorization checks
interface ITIP403Registry {
    /// @notice Check if an address is authorized under a specific policy
    /// @param policyId The policy identifier
    /// @param account The address to check authorization for
    /// @return bool True if the address is authorized, false otherwise
    function isAuthorized(uint64 policyId, address account) external view returns (bool);
}
