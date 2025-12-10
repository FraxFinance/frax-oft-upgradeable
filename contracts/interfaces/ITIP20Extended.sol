// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @title ITIP20Extended - TIP-20 extensions beyond ERC-20
/// @notice A token standard that extends ERC-20 with additional features including transfer policies, memo support, and pause functionality
/// @dev This interface excludes functions already defined in ERC-20 (name, symbol, decimals, 
///      totalSupply, balanceOf, allowance, approve, transfer, transferFrom) and functions
///      already implemented in FrxUSDOFTUpgradeable (pause, unpause)
interface ITIP20Extended {

    // ============ Errors ============

    /// @notice Error when attempting an operation while the contract is paused.
    error ContractPaused();

    /// @notice Error when the spender has insufficient allowance for the requested transfer.
    error InsufficientAllowance();

    /// @notice Error when an account has insufficient balance for the requested operation.
    error InsufficientBalance(uint256 currentBalance, uint256 expectedBalance, address);

    error InvalidAmount();

    /// @notice Error when an invalid currency identifier is provided.
    error InvalidCurrency();

    error InvalidQuoteToken();
    error InvalidBaseToken();
    error InvalidToken();

    /// @notice Error when attempting to transfer to an invalid recipient address.
    error InvalidRecipient();

    error InvalidSupplyCap();
    error NoOptedInSupply();

    /// @notice Error when starting a reward stream with seconds > 0
    error ScheduledRewardsDisabled();

    /// @notice Error when a transfer is blocked by the current transfer policy.
    error PolicyForbids();

    /// @notice Error when attempting to burn from a protected address.
    error ProtectedAddress();

    error SupplyCapExceeded();

    // ============ Events ============

    /// @notice Emitted when tokens are burned.
    /// @param from The address from which tokens were burned.
    /// @param amount The amount of tokens burned.
    event Burn(address indexed from, uint256 amount);

    /// @notice Emitted when tokens are forcibly burned from a blocked account.
    /// @param from The address from which tokens were forcibly burned.
    /// @param amount The amount of tokens burned.
    event BurnBlocked(address indexed from, uint256 amount);

    /// @notice Emitted when tokens are minted.
    /// @param to The address that received the newly minted tokens.
    /// @param amount The amount of tokens minted.
    event Mint(address indexed to, uint256 amount);

    event NextQuoteTokenSet(address indexed updater, ITIP20Extended indexed nextQuoteToken);

    /// @notice Emitted when the contract's pause state changes.
    /// @param updater The address that initiated the pause state change.
    /// @param isPaused The new pause state of the contract.
    event PauseStateUpdate(address indexed updater, bool isPaused);

    event QuoteTokenUpdate(address indexed updater, ITIP20Extended indexed newQuoteToken);
    event RewardRecipientSet(address indexed holder, address indexed recipient);
    event RewardScheduled(address indexed funder, uint64 indexed id, uint256 amount, uint32 durationSeconds);

    /// @notice Emitted when the supply cap is updated.
    /// @param updater The address that initiated the supply cap update.
    /// @param newSupplyCap The new maximum supply limit for the token.
    event SupplyCapUpdate(address indexed updater, uint256 indexed newSupplyCap);

    /// @notice Emitted when the transfer policy is updated.
    /// @param updater The address that initiated the policy update.
    /// @param newPolicyId The new policy identifier that will govern transfers.
    event TransferPolicyUpdate(address indexed updater, uint64 indexed newPolicyId);

    /// @notice Emitted when tokens are transferred with an attached memo.
    /// @param from The address tokens were transferred from.
    /// @param to The address tokens were transferred to.
    /// @param amount The amount of tokens transferred.
    /// @param memo The memo attached to the transfer.
    event TransferWithMemo(address indexed from, address indexed to, uint256 amount, bytes32 indexed memo);

    // ============ Role Constants ============

    /// @notice Returns the role identifier for burning tokens from blocked accounts.
    /// @return The burn blocked role identifier.
    function BURN_BLOCKED_ROLE() external view returns (bytes32);

    /// @notice Returns the role identifier for issuing tokens.
    /// @return The issuer role identifier.
    function ISSUER_ROLE() external view returns (bytes32);

    /// @notice Returns the role identifier for pausing the contract.
    /// @return The pause role identifier.
    function PAUSE_ROLE() external view returns (bytes32);

    /// @notice Returns the role identifier for unpausing the contract.
    /// @return The unpause role identifier.
    function UNPAUSE_ROLE() external view returns (bytes32);

    // ============ View Functions ============

    function currency() external view returns (string memory);

    function globalRewardPerToken() external view returns (uint256);

    function nextQuoteToken() external view returns (ITIP20Extended);

    function optedInSupply() external view returns (uint128);

    /// @notice Returns whether the contract is currently paused.
    /// @return True if the contract is paused, false otherwise.
    function paused() external view returns (bool);

    function quoteToken() external view returns (ITIP20Extended);

    /// @notice Returns the maximum supply cap for the token.
    /// @return The supply cap amount.
    function supplyCap() external view returns (uint256);

    /// @notice Returns the current transfer policy identifier.
    /// @return The active transfer policy ID.
    function transferPolicyId() external view returns (uint64);

    function userRewardInfo(address account) external view returns (
        address rewardRecipient,
        uint256 rewardPerToken,
        uint256 rewardBalance
    );

    // ============ Burn Functions ============

    /// @notice Burns tokens from the caller's balance.
    /// @param amount The amount of tokens to burn.
    function burn(uint256 amount) external;

    /// @notice Burns tokens from a blocked account (admin function).
    /// @param from The address to burn tokens from.
    /// @param amount The amount of tokens to burn.
    function burnBlocked(address from, uint256 amount) external;

    /// @notice Burns tokens from the caller's balance with an attached memo.
    /// @param amount The amount of tokens to burn.
    /// @param memo The memo to attach to the burn operation.
    function burnWithMemo(uint256 amount, bytes32 memo) external;

    // ============ Mint Functions ============

    /// @notice Mints new tokens to a specified address.
    /// @param to The address to mint tokens to.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) external;

    /// @notice Mints new tokens to a specified address with an attached memo.
    /// @param to The address to mint tokens to.
    /// @param amount The amount of tokens to mint.
    /// @param memo The memo to attach to the mint operation.
    function mintWithMemo(address to, uint256 amount, bytes32 memo) external;

    // ============ Transfer Functions with Memo ============

    /// @notice Transfers tokens with an attached memo.
    /// @param to The address to transfer tokens to.
    /// @param amount The amount of tokens to transfer.
    /// @param memo The memo to attach to the transfer.
    function transferWithMemo(address to, uint256 amount, bytes32 memo) external;

    /// @notice Transfers tokens from one address to another with a memo using allowance.
    /// @param from The address to transfer tokens from.
    /// @param to The address to transfer tokens to.
    /// @param amount The amount of tokens to transfer.
    /// @param memo The memo to attach to the transfer.
    /// @return success True if the transfer was successful.
    function transferFromWithMemo(address from, address to, uint256 amount, bytes32 memo) external returns (bool);

    function systemTransferFrom(address from, address to, uint256 amount) external returns (bool);

    // ============ Policy & Config Functions ============

    /// @notice Changes the transfer policy identifier.
    /// @param newPolicyId The new policy identifier to set.
    function changeTransferPolicyId(uint64 newPolicyId) external;

    function setSupplyCap(uint256 newSupplyCap) external;

    function setNextQuoteToken(ITIP20Extended newQuoteToken) external;

    function completeQuoteTokenUpdate() external;

    // ============ Reward Functions ============

    function setRewardRecipient(address newRewardRecipient) external;

    function startReward(uint256 amount, uint32 seconds_) external returns (uint64);

    function claimRewards() external returns (uint256 maxAmount);

    // ============ Fee Functions ============

    function transferFeePreTx(address from, uint256 amount) external;

    function transferFeePostTx(address to, uint256 refund, uint256 actualUsed) external;
}
