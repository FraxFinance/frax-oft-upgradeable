// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ITIP403Registry } from "contracts/interfaces/ITIP403Registry.sol";
import { ITIP20Factory } from "contracts/interfaces/ITIP20Factory.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { TIP20RolesAuthUpgradeable } from "contracts/modules/tempo/TIP20RolesAuthUpgradeable.sol";
import { ITIP20Frax } from "contracts/interfaces/ITIP20Frax.sol";

/**
 * @title TIP20Module
 * @author Frax Finance
 * @notice Abstract module that adds TIP-20 (Tempo Improvement Proposal 20) compliance to ERC20 tokens
 * @dev This module implements the TIP-20 standard for Tempo Finance integration.
 *      It uses ERC-7201 namespaced storage pattern to avoid storage collisions when
 *      composed with other upgradeable contracts.
 * 
 * Key Features:
 * - Transfer Policy: Enforces TIP-403 transfer policies via the registry precompile
 * - Supply Cap: Configurable maximum supply limit
 * - Quote Token: Hierarchical quote token system for stablecoin pricing
 * - Rewards: Opt-in reward distribution system with immediate payouts
 * - Role-Based Access: Uses TIP20RolesAuthUpgradeable for fine-grained permissions
 * - Memo Support: All transfers, mints, and burns can include an optional memo
 * 
 * Precompile Addresses (Tempo Network):
 * - TIP403 Registry: 0x403c000000000000000000000000000000000000
 * - TIP Fee Manager: 0xfeEC000000000000000000000000000000000000
 * - Stablecoin Exchange: 0xDEc0000000000000000000000000000000000000
 * - TIP20 Factory: 0x20Fc000000000000000000000000000000000000
 * 
 * Storage:
 * - Uses ERC-7201 namespaced storage at slot: 0x3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f00
 * 
 * Integration:
 * - Inheriting contracts must implement: owner(), isPaused(), balanceOf(), totalSupply(),
 *   _transfer(), _mint(), _burn(), _spendAllowance()
 * - Call __TIP20Module_init() in the initializer
 * - Call _beforeTokenTransferTIP20() in _beforeTokenTransfer hook
 */
abstract contract TIP20Module is ITIP20Frax, TIP20RolesAuthUpgradeable, IERC20Upgradeable {
    ITIP403Registry internal constant TIP403_REGISTRY = ITIP403Registry(0x403c000000000000000000000000000000000000);

    address internal constant TIP_FEE_MANAGER_ADDRESS = 0xfeEC000000000000000000000000000000000000;
    address internal constant STABLECOIN_EXCHANGE_ADDRESS = 0xDEc0000000000000000000000000000000000000;

    address internal constant FACTORY = 0x20Fc000000000000000000000000000000000000;

    uint256 internal constant ACC_PRECISION = 1e18;

    struct UserRewardInfo {
        address rewardRecipient;
        uint256 rewardPerToken;
        uint256 rewardBalance;
    }

    /// @custom:storage-location erc7201:frax.storage.TIP20Module
    struct TIP20ModuleStorage {
        uint256 supplyCap;
        uint64 transferPolicyId;
        string currency;
        ITIP20 quoteToken;
        ITIP20 nextQuoteToken;
        uint256 globalRewardPerToken;
        uint128 optedInSupply;
        mapping(address => UserRewardInfo) userRewardInfo;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.TIP20Module")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TIP20ModuleStorageLocation =
        0x3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f4e3f00;

    function _getTIP20ModuleStorage() internal pure returns (TIP20ModuleStorage storage $) {
        assembly {
            $.slot := TIP20ModuleStorageLocation
        }
    }

    // ============ Abstract functions that must be implemented by inheriting contract ============

    /// @notice Returns the owner address for access control
    /// @dev Must be implemented to return the contract owner (e.g., from OwnableUpgradeable)
    /// @return The owner address
    function owner() public view virtual returns (address);

    /// @notice Returns whether the contract is paused
    /// @dev Must be implemented to return pause state (e.g., from PauseModule)
    /// @return True if the contract is paused
    function isPaused() public view virtual returns (bool);

    /// @notice Returns the balance of an account
    /// @dev Must be implemented to return token balance (e.g., from ERC20Upgradeable)
    /// @param account The address to query
    /// @return The token balance
    function balanceOf(address account) public view virtual returns (uint256);

    /// @notice Returns the total token supply
    /// @dev Must be implemented to return total supply (e.g., from ERC20Upgradeable)
    /// @return The total supply
    function totalSupply() public view virtual returns (uint256);

    /// @notice Internal transfer function
    /// @dev Must be implemented to perform token transfer (e.g., from ERC20Upgradeable)
    /// @param from The sender address
    /// @param to The recipient address
    /// @param amount The transfer amount
    function _transfer(address from, address to, uint256 amount) internal virtual;

    /// @notice Internal mint function
    /// @dev Must be implemented to mint tokens (e.g., from ERC20Upgradeable)
    /// @param to The recipient address
    /// @param amount The mint amount
    function _mint(address to, uint256 amount) internal virtual;

    /// @notice Internal burn function
    /// @dev Must be implemented to burn tokens (e.g., from ERC20Upgradeable)
    /// @param from The address to burn from
    /// @param amount The burn amount
    function _burn(address from, uint256 amount) internal virtual;

    /// @notice Internal spend allowance function
    /// @dev Must be implemented to deduct allowance (e.g., from ERC20Upgradeable)
    ///      Used by transferFromWithMemo to enforce allowance checks
    /// @param owner The token owner
    /// @param spender The spender address
    /// @param value The amount to deduct from allowance
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual;

    // ============ Initialization ============

    /// @notice Initialize TIP-20 module storage
    /// @param _currency The currency string (e.g., "USD")
    /// @param _quoteToken The initial quote token
    /// @param _admin The admin address that gets all roles
    function __TIP20Module_init(string memory _currency, ITIP20 _quoteToken, address _admin) internal {
        __TIP20RolesAuth_init(_admin);

        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        $.transferPolicyId = 1; // "Always-allow" policy by default
        $.supplyCap = type(uint128).max; // Default to cap at uint128.max
        $.currency = _currency;
        $.quoteToken = _quoteToken;
        $.nextQuoteToken = _quoteToken;
    }

    // ============ TIP-20 Before Token Transfer Hook ============

    /// @notice Hook that must be called before token transfers
    /// @dev This should be integrated into _beforeTokenTransfer in the inheriting contract
    function _beforeTokenTransferTIP20(address from, address to, uint256 amount) internal {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();

        if (msg.sender != owner()) {
            if (isPaused()) revert ContractPaused();
            if ((uint160(to) >> 64) == 0x20c000000000000000000000) revert InvalidRecipient();
            if (
                !TIP403_REGISTRY.isAuthorized($.transferPolicyId, from) ||
                !TIP403_REGISTRY.isAuthorized($.transferPolicyId, to)
            ) revert PolicyForbids();
        }

        // Handle reward accounting for opted-in sender
        address fromsRewardRecipient = _updateRewardsAndGetRecipient(from);

        // Handle reward accounting for opted-in receiver (but not when burning)
        address tosRewardRecipient = _updateRewardsAndGetRecipient(to);

        if (fromsRewardRecipient != address(0)) {
            if (tosRewardRecipient == address(0)) {
                $.optedInSupply -= uint128(amount);
            }
        } else if (tosRewardRecipient != address(0)) {
            $.optedInSupply += uint128(amount);
        }
    }

    // ============ ITIP20 View Functions ============

    /// @inheritdoc ITIP20Frax
    function currency() external view override returns (string memory) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        return $.currency;
    }

    /// @inheritdoc ITIP20Frax
    function supplyCap() external view override returns (uint256) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        return $.supplyCap;
    }

    /// @inheritdoc ITIP20Frax
    function transferPolicyId() external view override returns (uint64) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        return $.transferPolicyId;
    }

    /// @inheritdoc ITIP20Frax
    function quoteToken() external view override returns (ITIP20) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        return $.quoteToken;
    }

    /// @inheritdoc ITIP20Frax
    function nextQuoteToken() external view override returns (ITIP20) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        return $.nextQuoteToken;
    }

    /// @inheritdoc ITIP20Frax
    function globalRewardPerToken() external view override returns (uint256) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        return $.globalRewardPerToken;
    }

    /// @inheritdoc ITIP20Frax
    function optedInSupply() external view override returns (uint128) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        return $.optedInSupply;
    }

    /// @inheritdoc ITIP20Frax
    function userRewardInfo(
        address account
    ) external view override returns (address rewardRecipient, uint256 rewardPerToken, uint256 rewardBalance) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        UserRewardInfo storage info = $.userRewardInfo[account];
        return (info.rewardRecipient, info.rewardPerToken, info.rewardBalance);
    }

    /// @inheritdoc ITIP20Frax
    function paused() external view override returns (bool) {
        return isPaused();
    }

    // ============ ITIP20 Admin Functions ============

    /// @inheritdoc ITIP20Frax
    function changeTransferPolicyId(uint64 newPolicyId) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        $.transferPolicyId = newPolicyId;
        emit TransferPolicyUpdate(msg.sender, newPolicyId);
    }

    /// @inheritdoc ITIP20Frax
    function setSupplyCap(uint256 newSupplyCap) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newSupplyCap < totalSupply()) revert InvalidSupplyCap();
        if (newSupplyCap > type(uint128).max) revert SupplyCapExceeded();
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        $.supplyCap = newSupplyCap;
        emit SupplyCapUpdate(msg.sender, newSupplyCap);
    }

    /// @inheritdoc ITIP20Frax
    function setNextQuoteToken(ITIP20 newQuoteToken) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        // sets next quote token, to put the DEX for that pair into place-only mode
        // does not check for loops; that is checked in completeQuoteTokenUpdate
        if (!ITIP20Factory(FACTORY).isTIP20(address(newQuoteToken))) {
            revert InvalidQuoteToken();
        }

        // If this token represents USD, enforce USD quote token
        if (keccak256(bytes($.currency)) == keccak256(bytes("USD"))) {
            if (keccak256(bytes(newQuoteToken.currency())) != keccak256(bytes("USD"))) {
                revert InvalidQuoteToken();
            }
        }

        $.nextQuoteToken = newQuoteToken;
        emit NextQuoteTokenSet(msg.sender, newQuoteToken);
    }

    /// @inheritdoc ITIP20Frax
    function completeQuoteTokenUpdate() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        // check that this does not create a loop, by looping through quote token until we reach the root
        ITIP20 current = $.nextQuoteToken;
        while (address(current) != address(0)) {
            if (address(current) == address(this)) revert InvalidQuoteToken();
            current = current.quoteToken();
        }

        $.quoteToken = $.nextQuoteToken;
        emit QuoteTokenUpdate(msg.sender, $.nextQuoteToken);
    }

    // ============ ITIP20 User Functions ============

    /// @inheritdoc ITIP20Frax
    function setRewardRecipient(address newRewardRecipient) external override {
        if (isPaused()) revert ContractPaused();
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        // Check TIP-403 authorization
        if (newRewardRecipient != address(0)) {
            if (
                !TIP403_REGISTRY.isAuthorized($.transferPolicyId, msg.sender) ||
                !TIP403_REGISTRY.isAuthorized($.transferPolicyId, newRewardRecipient)
            ) revert PolicyForbids();
        }

        address oldRewardRecipient = _updateRewardsAndGetRecipient(msg.sender);
        if (oldRewardRecipient != address(0)) {
            if (newRewardRecipient == address(0)) {
                $.optedInSupply -= uint128(balanceOf(msg.sender));
            }
        } else if (newRewardRecipient != address(0)) {
            $.optedInSupply += uint128(balanceOf(msg.sender));
        }
        $.userRewardInfo[msg.sender].rewardRecipient = newRewardRecipient;

        emit RewardRecipientSet(msg.sender, newRewardRecipient);
    }

    /// @inheritdoc ITIP20Frax
    function startReward(uint256 amount, uint32 seconds_) external override returns (uint64) {
        if (isPaused()) revert ContractPaused();
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();

        if (amount == 0) revert InvalidAmount();
        if (!TIP403_REGISTRY.isAuthorized($.transferPolicyId, msg.sender)) {
            revert PolicyForbids();
        }

        // Transfer tokens from sender to this contract
        _transfer(msg.sender, address(this), amount);

        if (seconds_ == 0) {
            // Immediate payout
            if ($.optedInSupply == 0) {
                revert NoOptedInSupply();
            }
            uint256 deltaRPT = (amount * ACC_PRECISION) / $.optedInSupply;
            $.globalRewardPerToken += deltaRPT;
            emit RewardScheduled(msg.sender, 0, amount, 0);
            return 0;
        } else {
            // Scheduled/streaming rewards are disabled post-Moderato
            revert ScheduledRewardsDisabled();
        }
    }

    /// @inheritdoc ITIP20Frax
    function claimRewards() external override returns (uint256 maxAmount) {
        if (isPaused()) revert ContractPaused();
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        if (!TIP403_REGISTRY.isAuthorized($.transferPolicyId, msg.sender)) revert PolicyForbids();

        _updateRewardsAndGetRecipient(msg.sender);

        uint256 amount = $.userRewardInfo[msg.sender].rewardBalance;
        uint256 selfBalance = balanceOf(address(this));
        maxAmount = (selfBalance > amount ? amount : selfBalance);
        $.userRewardInfo[msg.sender].rewardBalance -= maxAmount;

        _transfer(address(this), msg.sender, maxAmount);
        if ($.userRewardInfo[msg.sender].rewardRecipient != address(0)) {
            $.optedInSupply += uint128(maxAmount);
        }

        emit Transfer(address(this), msg.sender, maxAmount);
    }

    /// @inheritdoc ITIP20Frax
    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    /// @inheritdoc ITIP20Frax
    function burnBlocked(address from, uint256 amount) external override onlyRole(BURN_BLOCKED_ROLE) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        // Prevent burning from protected precompile addresses
        if (from == TIP_FEE_MANAGER_ADDRESS || from == STABLECOIN_EXCHANGE_ADDRESS) {
            revert ProtectedAddress();
        }

        // Only allow burning from addresses that are blocked from transferring.
        if (TIP403_REGISTRY.isAuthorized($.transferPolicyId, from)) {
            revert PolicyForbids();
        }
        _burn(from, amount);
        emit BurnBlocked(from, amount);
    }

    /// @inheritdoc ITIP20Frax
    function burnWithMemo(uint256 amount, bytes32 memo) external override {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
        emit TransferWithMemo(msg.sender, address(0), amount, memo);
    }

    /// @inheritdoc ITIP20Frax
    function mint(address to, uint256 amount) external override onlyRole(ISSUER_ROLE) {
        _mintTIP20(to, amount);
        emit Mint(to, amount);
    }

    /// @inheritdoc ITIP20Frax
    function mintWithMemo(address to, uint256 amount, bytes32 memo) external override onlyRole(ISSUER_ROLE) {
        _mintTIP20(to, amount);
        emit Mint(to, amount);
        emit TransferWithMemo(address(0), to, amount, memo);
    }

    /// @inheritdoc ITIP20Frax
    function transferWithMemo(address to, uint256 amount, bytes32 memo) external override {
        _transfer(msg.sender, to, amount);
        emit TransferWithMemo(msg.sender, to, amount, memo);
    }

    /// @inheritdoc ITIP20Frax
    function transferFromWithMemo(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) external override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        emit TransferWithMemo(from, to, amount, memo);
        return true;
    }

    /// @inheritdoc ITIP20Frax
    function systemTransferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(msg.sender == TIP_FEE_MANAGER_ADDRESS);
        _transfer(from, to, amount);
        return true;
    }

    // ============ TIP-20 Fee Hooks ============

    /// @inheritdoc ITIP20Frax
    function transferFeePreTx(address from, uint256 amount) external override {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        require(msg.sender == TIP_FEE_MANAGER_ADDRESS);
        require(from != address(0));

        if (amount > balanceOf(from)) {
            revert InsufficientBalance(balanceOf(from), amount, address(this));
        }

        address fromsRewardRecipient = _updateRewardsAndGetRecipient(from);
        if (fromsRewardRecipient != address(0)) {
            $.optedInSupply -= uint128(amount);
        }
        _transfer(from, TIP_FEE_MANAGER_ADDRESS, amount);
    }

    /// @inheritdoc ITIP20Frax
    function transferFeePostTx(address to, uint256 refund, uint256 actualUsed) external override {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        require(msg.sender == TIP_FEE_MANAGER_ADDRESS);
        require(to != address(0));

        uint256 feeManagerBalance = balanceOf(TIP_FEE_MANAGER_ADDRESS);
        if (refund > feeManagerBalance) {
            revert InsufficientBalance(feeManagerBalance, refund, address(this));
        }

        address tosRewardRecipient = _updateRewardsAndGetRecipient(to);
        if (tosRewardRecipient != address(0)) {
            $.optedInSupply += uint128(refund);
        }

        _transfer(TIP_FEE_MANAGER_ADDRESS, to, refund);
        // TODO : verify events as per TIP20 standard
        emit Transfer(to, TIP_FEE_MANAGER_ADDRESS, actualUsed);
    }

    // ============ Internal Helper Functions ============

    /// @notice Internal mint function with TIP-20 checks
    function _mintTIP20(address to, uint256 amount) internal {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        if (!TIP403_REGISTRY.isAuthorized($.transferPolicyId, to)) revert PolicyForbids();
        if (totalSupply() + amount > $.supplyCap) revert SupplyCapExceeded(); // Catches overflow.

        // Handle reward accounting for opted-in receiver
        address tosRewardRecipient = _updateRewardsAndGetRecipient(to);
        if (tosRewardRecipient != address(0)) {
            $.optedInSupply += uint128(amount);
        }

        _mint(to, amount);
    }

    /// @notice Update rewards and get the reward recipient for a user
    function _updateRewardsAndGetRecipient(address user) internal returns (address rewardRecipient) {
        TIP20ModuleStorage storage $ = _getTIP20ModuleStorage();
        rewardRecipient = $.userRewardInfo[user].rewardRecipient;
        uint256 cachedGlobalRewardPerToken = $.globalRewardPerToken;
        uint256 rewardPerTokenDelta = cachedGlobalRewardPerToken - $.userRewardInfo[user].rewardPerToken;

        if (rewardPerTokenDelta != 0) {
            // No rewards to update if not opted-in
            if (rewardRecipient != address(0)) {
                // Balance to update
                uint256 reward = (uint256(balanceOf(user)) * (rewardPerTokenDelta)) / ACC_PRECISION;

                $.userRewardInfo[rewardRecipient].rewardBalance += reward;
            }
            $.userRewardInfo[user].rewardPerToken = cachedGlobalRewardPerToken;
        }
    }
}
