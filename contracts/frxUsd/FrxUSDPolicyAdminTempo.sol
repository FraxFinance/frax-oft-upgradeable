// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ITIP403Registry } from "tempo-std/interfaces/ITIP403Registry.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";

/**
 * @title FrxUSDPolicyAdminTempo
 * @author Frax Finance
 * @notice Admin wrapper contract for managing freeze/thaw operations via TIP-403 Registry on Tempo
 * @dev This contract provides a simplified interface for managing blacklist-based freeze/thaw
 *      operations using the TIP-403 Registry precompile on Tempo Network.
 */
contract FrxUSDPolicyAdminTempo is Ownable2StepUpgradeable {
    /* ========== ERC-7201 NAMESPACED STORAGE ========== */

    /// @custom:storage-location erc7201:frax.storage.FrxUSDPolicyAdminTempo
    struct PolicyAdminStorage {
        uint64 policyId;
        mapping(address => bool) freezers;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.FrxUSDPolicyAdminTempo")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant POLICY_ADMIN_STORAGE_LOCATION = 
        0x26bddd9d371485490a0eb07480715865c05a6d3ae02ab4f9213c12782ba8dc00;

    function _getPolicyAdminStorage() private pure returns (PolicyAdminStorage storage $) {
        assembly {
            $.slot := POLICY_ADMIN_STORAGE_LOCATION
        }
    }

    /* ========== EVENTS ========== */

    /// @notice Emitted when a freezer is added
    /// @param account The account being added as a freezer
    event AddFreezer(address indexed account);

    /// @notice Emitted when a freezer is removed
    /// @param account The account being removed as a freezer
    event RemoveFreezer(address indexed account);

    /// @notice Emitted when an account is frozen
    /// @param account The account being frozen
    event AccountFrozen(address indexed account);

    /// @notice Emitted when an account is thawed (unfrozen)
    /// @param account The account being thawed
    event AccountThawed(address indexed account);

    /// @notice Emitted when the policy ID is set
    /// @param policyId The new policy ID
    event PolicyIdSet(uint64 indexed policyId);

    /* ========== ERRORS ========== */

    /// @notice Error thrown when caller is not an authorized freezer
    error NotFreezer();

    /// @notice Error thrown when account is already a freezer
    error AlreadyFreezer();

    /// @notice Error thrown when array lengths do not match
    error ArrayLengthMismatch();

    /// @notice Error thrown when policy ID is not set
    error PolicyIdNotSet();

    /* ========== CONSTRUCTOR ========== */

    /// @notice Constructor disables initializers for upgradeable pattern
    constructor() {
        _disableInitializers();
    }

    /* ========== INITIALIZATION ========== */

    /// @notice Initializes the contract with owner and creates a blacklist policy
    /// @param _owner The initial owner of the contract
    /// @dev Creates a BLACKLIST policy in TIP-403 Registry with this contract as admin
    function initialize(address _owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(_owner);
        
        PolicyAdminStorage storage $ = _getPolicyAdminStorage();
        
        // Create a blacklist policy with this contract as the admin
        $.policyId = StdPrecompiles.TIP403_REGISTRY.createPolicy(address(this), ITIP403Registry.PolicyType.BLACKLIST);
        
        emit PolicyIdSet($.policyId);
    }

    /// @notice Initializes with an existing policy ID
    /// @param _owner The initial owner of the contract
    /// @param _policyId The existing TIP-403 policy ID to use
    /// @dev Use this if a policy has already been created
    function initializeWithPolicy(address _owner, uint64 _policyId) external initializer {
        __Ownable2Step_init();
        _transferOwnership(_owner);
        
        PolicyAdminStorage storage $ = _getPolicyAdminStorage();
        $.policyId = _policyId;
        
        emit PolicyIdSet(_policyId);
    }

    /* ========== MODIFIERS ========== */

    /// @notice Modifier to restrict access to freezers or owner
    modifier onlyFreezerOrOwner() {
        if (!_getPolicyAdminStorage().freezers[msg.sender] && msg.sender != owner()) revert NotFreezer();
        _;
    }

    /// @notice Modifier to ensure policy ID is set
    modifier policyExists() {
        if (_getPolicyAdminStorage().policyId == 0) revert PolicyIdNotSet();
        _;
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice External admin gated function to add a freezer role to an account
    /// @param account The account to be added as a freezer
    /// @dev Only callable by owner
    function addFreezer(address account) external onlyOwner {
        PolicyAdminStorage storage $ = _getPolicyAdminStorage();
        if ($.freezers[account]) revert AlreadyFreezer();
        $.freezers[account] = true;
        emit AddFreezer(account);
    }

    /// @notice External admin gated function to remove a freezer role from an account
    /// @param account The account to be removed as a freezer
    /// @dev Only callable by owner
    function removeFreezer(address account) external onlyOwner {
        PolicyAdminStorage storage $ = _getPolicyAdminStorage();
        if (!$.freezers[account]) revert NotFreezer();
        $.freezers[account] = false;
        emit RemoveFreezer(account);
    }

    /// @notice External function to freeze an account by adding it to the blacklist
    /// @param account The account to be frozen
    /// @dev Only callable by freezers or owner
    /// @dev Adds the account to the TIP-403 blacklist policy
    function freeze(address account) external onlyFreezerOrOwner policyExists {
        StdPrecompiles.TIP403_REGISTRY.modifyPolicyBlacklist(_getPolicyAdminStorage().policyId, account, true);
        emit AccountFrozen(account);
    }

    /// @notice External function to batch freeze multiple accounts
    /// @param accounts Array of accounts to be frozen
    /// @dev Only callable by freezers or owner
    function freezeMany(address[] calldata accounts) external onlyFreezerOrOwner policyExists {
        uint64 _policyId = _getPolicyAdminStorage().policyId;
        uint256 len = accounts.length;
        for (uint256 i; i < len; ++i) {
            StdPrecompiles.TIP403_REGISTRY.modifyPolicyBlacklist(_policyId, accounts[i], true);
            emit AccountFrozen(accounts[i]);
        }
    }

    /// @notice External admin gated function to unfreeze an account
    /// @param account The account to be thawed (unfrozen)
    /// @dev Only callable by owner
    /// @dev Removes the account from the TIP-403 blacklist policy
    function thaw(address account) external onlyOwner policyExists {
        StdPrecompiles.TIP403_REGISTRY.modifyPolicyBlacklist(_getPolicyAdminStorage().policyId, account, false);
        emit AccountThawed(account);
    }

    /// @notice External admin gated function to batch unfreeze multiple accounts
    /// @param accounts Array of accounts to be thawed (unfrozen)
    /// @dev Only callable by owner
    function thawMany(address[] calldata accounts) external onlyOwner policyExists {
        uint64 _policyId = _getPolicyAdminStorage().policyId;
        uint256 len = accounts.length;
        for (uint256 i; i < len; ++i) {
            StdPrecompiles.TIP403_REGISTRY.modifyPolicyBlacklist(_policyId, accounts[i], false);
            emit AccountThawed(accounts[i]);
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Returns the TIP-403 policy ID
    /// @return The policy ID used for freeze/thaw operations
    function policyId() external view returns (uint64) {
        return _getPolicyAdminStorage().policyId;
    }

    /// @notice Check if an account is frozen (on the blacklist)
    /// @param account The account to check
    /// @return bool True if the account is frozen, false otherwise
    /// @dev Uses TIP-403 isAuthorized - returns false if frozen (blacklisted)
    function isFrozen(address account) external view returns (bool) {
        uint64 _policyId = _getPolicyAdminStorage().policyId;
        if (_policyId == 0) return false;
        // In a blacklist policy, isAuthorized returns false if the account is blacklisted
        return !StdPrecompiles.TIP403_REGISTRY.isAuthorized(_policyId, account);
    }

    /// @notice Check if an account is an authorized freezer
    /// @param account The account to check
    /// @return bool True if the account is a freezer, false otherwise
    function isFreezer(address account) external view returns (bool) {
        return _getPolicyAdminStorage().freezers[account];
    }

    /// @notice Check if an account is an authorized freezer (alias for public mapping access)
    /// @param account The account to check
    /// @return bool True if the account is a freezer, false otherwise
    function freezers(address account) external view returns (bool) {
        return _getPolicyAdminStorage().freezers[account];
    }

    /// @notice Get the TIP-403 policy data
    /// @return policyType The type of the policy (should be BLACKLIST)
    /// @return admin The admin address of the policy
    function getPolicyData() external view returns (ITIP403Registry.PolicyType policyType, address admin) {
        return StdPrecompiles.TIP403_REGISTRY.policyData(_getPolicyAdminStorage().policyId);
    }

    /// @notice Set a new policy admin in the TIP-403 Registry
    /// @param newAdmin The new admin address for the policy
    /// @dev Only callable by owner, transfers policy admin to new address
    function setPolicyAdmin(address newAdmin) external onlyOwner policyExists {
        StdPrecompiles.TIP403_REGISTRY.setPolicyAdmin(_getPolicyAdminStorage().policyId, newAdmin);
    }

    /// @notice Returns the contract version
    /// @return The version string
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
