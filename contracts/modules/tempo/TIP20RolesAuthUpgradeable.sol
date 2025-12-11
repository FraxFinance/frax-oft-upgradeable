// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { ITIP20RolesAuth } from "@tempo/interfaces/ITIP20RolesAuth.sol";

/**
 * @title TIP20RolesAuthUpgradeable
 * @notice Upgradeable role-based access control for TIP-20 tokens using ERC-7201 namespaced storage
 * @dev Based on TIP20RolesAuth but adapted for upgradeable contracts with isolated storage
 */
abstract contract TIP20RolesAuthUpgradeable is ITIP20RolesAuth {
    /// @custom:storage-location erc7201:frax.storage.TIP20RolesAuth
    struct TIP20RolesAuthStorage {
        mapping(address account => mapping(bytes32 role => bool)) hasRole;
        mapping(bytes32 role => bytes32 adminRole) roleAdmin;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.TIP20RolesAuth")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TIP20RolesAuthStorageLocation = 
        0x8c4e4e6e5f5c5d5e5f6061626364656667686970717273747576777879000000;

    function _getTIP20RolesAuthStorage() internal pure returns (TIP20RolesAuthStorage storage $) {
        assembly {
            $.slot := TIP20RolesAuthStorageLocation
        }
    }

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0; // Roles with unset admins will yield this role as admin.
    bytes32 internal constant UNGRANTABLE_ROLE = bytes32(type(uint256).max); // Can never be granted to anyone.

    function __TIP20RolesAuth_init() internal {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        // Prevent granting this role by making it self-administered.
        $.roleAdmin[UNGRANTABLE_ROLE] = UNGRANTABLE_ROLE;
    }

    modifier onlyRole(bytes32 role) {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        if (!$.hasRole[msg.sender][role]) revert Unauthorized();
        _;
    }

    /// @notice Check if an account has a specific role
    /// @param account The address to check
    /// @param role The role identifier
    /// @return bool True if the account has the role
    function hasRole(address account, bytes32 role) external view returns (bool) {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        return $.hasRole[account][role];
    }

    /// @notice Grant a role to an account
    /// @param role The role identifier to grant
    /// @param account The address to grant the role to
    function grantRole(bytes32 role, address account) external onlyRole(_getRoleAdmin(role)) {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        $.hasRole[account][role] = true;
        emit RoleMembershipUpdated(role, account, msg.sender, true);
    }

    /// @notice Revoke a role from an account
    /// @param role The role identifier to revoke
    /// @param account The address to revoke the role from
    function revokeRole(bytes32 role, address account) external virtual onlyRole(_getRoleAdmin(role)) {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        $.hasRole[account][role] = false;
        emit RoleMembershipUpdated(role, account, msg.sender, false);
    }

    /// @notice Renounce a role for the caller
    /// @param role The role identifier to renounce
    function renounceRole(bytes32 role) external virtual onlyRole(role) {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        $.hasRole[msg.sender][role] = false;
        emit RoleMembershipUpdated(role, msg.sender, msg.sender, false);
    }

    /// @notice Set the admin role for a specific role
    /// @param role The role identifier
    /// @param adminRole The admin role identifier that can grant/revoke the role
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external virtual onlyRole(_getRoleAdmin(role)) {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        $.roleAdmin[role] = adminRole;
        emit RoleAdminUpdated(role, adminRole, msg.sender);
    }

    function _getRoleAdmin(bytes32 role) internal view returns (bytes32) {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        return $.roleAdmin[role];
    }

    function _setupRole(bytes32 role, address account) internal {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        $.hasRole[account][role] = true;
        emit RoleMembershipUpdated(role, account, msg.sender, true);
    }
}
