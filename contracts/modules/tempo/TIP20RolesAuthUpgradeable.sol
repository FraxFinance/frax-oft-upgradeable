// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { ITIP20RolesAuth } from "@tempo/interfaces/ITIP20RolesAuth.sol";

/**
 * @title TIP20RolesAuthUpgradeable
 * @author Frax Finance
 * @notice Upgradeable role-based access control module for TIP-20 tokens
 * @dev Implements ITIP20RolesAuth with ERC-7201 namespaced storage for upgrade safety.
 *      Based on Tempo Finance's TIP20RolesAuth but adapted for upgradeable contracts.
 * 
 * Roles:
 * - DEFAULT_ADMIN_ROLE (0x00): Can grant/revoke all roles, manage supply cap, transfer policy, quote token
 * - PAUSE_ROLE: Can pause the contract
 * - UNPAUSE_ROLE: Can unpause the contract
 * - ISSUER_ROLE: Can mint tokens
 * - BURN_BLOCKED_ROLE: Can burn tokens from blocked addresses
 * 
 * Storage:
 * - Uses ERC-7201 namespaced storage at slot: 0x8c4e4e6e5f5c5d5e5f6061626364656667686970717273747576777879000000
 * 
 * Integration:
 * - Call __TIP20RolesAuth_init(_admin) in the initializer to grant all roles to admin
 * - Use onlyRole(ROLE) modifier for access control
 */
abstract contract TIP20RolesAuthUpgradeable is ITIP20RolesAuth {
    /// @notice Role identifier for pausing the contract
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    
    /// @notice Role identifier for unpausing the contract
    bytes32 public constant UNPAUSE_ROLE = keccak256("UNPAUSE_ROLE");
    
    /// @notice Role identifier for minting tokens
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    
    /// @notice Role identifier for burning tokens from blocked addresses
    bytes32 public constant BURN_BLOCKED_ROLE = keccak256("BURN_BLOCKED_ROLE");

    /// @custom:storage-location erc7201:frax.storage.TIP20RolesAuth
    struct TIP20RolesAuthStorage {
        /// @dev Mapping of account => role => hasRole
        mapping(address account => mapping(bytes32 role => bool)) hasRole;
        /// @dev Mapping of role => adminRole (the role that can grant/revoke it)
        mapping(bytes32 role => bytes32 adminRole) roleAdmin;
    }

    /// @dev ERC-7201 storage slot for TIP20RolesAuth
    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.TIP20RolesAuth")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TIP20RolesAuthStorageLocation =
        0x8c4e4e6e5f5c5d5e5f6061626364656667686970717273747576777879000000;

    /// @dev Returns the storage pointer for TIP20RolesAuth
    function _getTIP20RolesAuthStorage() internal pure returns (TIP20RolesAuthStorage storage $) {
        assembly {
            $.slot := TIP20RolesAuthStorageLocation
        }
    }

    /// @dev The default admin role - can grant/revoke all roles with unset admins
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0;
    
    /// @dev A role that can never be granted to anyone (self-administered)
    bytes32 internal constant UNGRANTABLE_ROLE = bytes32(type(uint256).max);

    /// @notice Initialize role-based access control
    /// @dev Grants all roles to the admin address. Should be called in initializer.
    /// @param _admin The address to receive all initial roles
    function __TIP20RolesAuth_init(address _admin) internal {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        // Prevent granting this role by making it self-administered.
        $.roleAdmin[UNGRANTABLE_ROLE] = UNGRANTABLE_ROLE;
        $.hasRole[_admin][DEFAULT_ADMIN_ROLE] = true;
        $.hasRole[_admin][PAUSE_ROLE] = true;
        $.hasRole[_admin][UNPAUSE_ROLE] = true;
        $.hasRole[_admin][ISSUER_ROLE] = true;
        $.hasRole[_admin][BURN_BLOCKED_ROLE] = true;
    }

    /// @notice Modifier to restrict function access to accounts with a specific role
    /// @param role The required role identifier
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

    /// @notice Get the admin role for a specific role
    /// @dev Returns DEFAULT_ADMIN_ROLE if no admin role is set
    /// @param role The role identifier to query
    /// @return The admin role identifier
    function _getRoleAdmin(bytes32 role) internal view returns (bytes32) {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        return $.roleAdmin[role];
    }

    /// @notice Internal function to grant a role without access control
    /// @dev Use this in initializers or internal logic where onlyRole check is not needed
    /// @param role The role identifier to grant
    /// @param account The address to grant the role to
    function _setupRole(bytes32 role, address account) internal {
        TIP20RolesAuthStorage storage $ = _getTIP20RolesAuthStorage();
        $.hasRole[account][role] = true;
        emit RoleMembershipUpdated(role, account, msg.sender, true);
    }
}
