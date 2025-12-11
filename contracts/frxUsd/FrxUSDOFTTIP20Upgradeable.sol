// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTUpgradeable.sol";
import { FreezeThawModule } from "contracts/modules/FreezeThawModule.sol";
import { PauseModule } from "contracts/modules/PauseModule.sol";
import { EIP3009Module } from "contracts/modules/EIP3009Module.sol";
import { PermitModule } from "contracts/modules/PermitModule.sol";
import { SendParam } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { TIP403Registry } from "@tempo/TIP403Registry.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { TIP20RolesAuth } from "@tempo/abstracts/TIP20RolesAuth.sol";
import { TIP20Factory } from "@tempo/TIP20Factory.sol";
import { AccessControlDefaultAdminRulesUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlDefaultAdminRulesUpgradeable.sol";

/**
 * @title FrxUSDOFTTIP20Upgradeable
 * @dev Extends FrxUSDOFTUpgradeable with TIP-20 compliance
 */
contract FrxUSDOFTTIP20Upgradeable is
    OFTUpgradeable,
    EIP3009Module,
    PermitModule,
    FreezeThawModule,
    PauseModule,
    ITIP20,
    AccessControlDefaultAdminRulesUpgradeable
{
    TIP403Registry internal constant TIP403_REGISTRY = TIP403Registry(0x403c000000000000000000000000000000000000);

    address internal constant TIP_FEE_MANAGER_ADDRESS = 0xfeEC000000000000000000000000000000000000;
    address internal constant STABLECOIN_EXCHANGE_ADDRESS = 0xDEc0000000000000000000000000000000000000;

    address internal constant FACTORY = 0x20Fc000000000000000000000000000000000000;

    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant UNPAUSE_ROLE = keccak256("UNPAUSE_ROLE");
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant BURN_BLOCKED_ROLE = keccak256("BURN_BLOCKED_ROLE");

    uint256 internal constant ACC_PRECISION = 1e18;

    struct UserRewardInfo {
        address rewardRecipient;
        uint256 rewardPerToken;
        uint256 rewardBalance;
    }

    /// @custom:storage-location erc7201:frax.storage.TIP20
    struct TIP20Storage {
        uint256 supplyCap;
        uint64 transferPolicyId;
        string currency;
        ITIP20 quoteToken;
        ITIP20 nextQuoteToken;
        uint256 globalRewardPerToken;
        uint128 optedInSupply;
        mapping(address => UserRewardInfo) userRewardInfo;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.TIP20")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TIP20StorageLocation = 0x9fd7d0c44526e808a04e8633c77b144fb613d422fc75d4d0ebc0c5329184a400;

    function _getTIP20Storage() internal pure returns (TIP20Storage storage $) {
        assembly {
            $.slot := TIP20StorageLocation
        }
    }

    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    function version() public pure returns (string memory) {
        return "1.1.0";
    }

    /// @dev overrides state where previous OFT versions were named the legacy "FRAX"
    function name() public pure override returns (string memory) {
        return "Frax USD";
    }

    /// @dev overrides state where previous OFT versions were named the legacy "FRAX"
    function symbol() public pure override returns (string memory) {
        return "frxUSD";
    }

    // Admin

    /// @dev This method is called specifically when deploying a new OFT
    function initialize(
        address _delegate,
        string memory _currency,
        ITIP20 _quoteToken,
        address _admin,
        uint48 _initialDelay
    ) external initializer {
        __OFT_init(name(), symbol(), _delegate);
        __EIP712_init(name(), version());

        __Ownable_init();
        _transferOwnership(_delegate);
        __AccessControlDefaultAdminRules_init(_initialDelay, _admin);
        _setupRole(PAUSE_ROLE, _admin);
        _setupRole(UNPAUSE_ROLE, _admin);
        _setupRole(ISSUER_ROLE, _admin);
        _setupRole(BURN_BLOCKED_ROLE, _admin);

        TIP20Storage storage $ = _getTIP20Storage();
        $.transferPolicyId = 1; // "Always-allow" policy by default
        $.supplyCap = type(uint128).max; // Default to cap at uint128.max
        $.currency = _currency;
        $.quoteToken = _quoteToken;
        $.nextQuoteToken = _quoteToken;

        hasRole[_admin][DEFAULT_ADMIN_ROLE] = true; // Grant admin role to first admin.
    }

    /// @notice External admin gated function to add a freezer role to an account
    /// @param account The account to be added as a freezer
    /// @dev Added in v1.1.0
    function addFreezer(address account) external onlyOwner {
        _addFreezer(account);
    }

    /// @notice External admin gated function to remove a freezer role from an account
    /// @param account The account to be removed as a freezer
    /// @dev Added in v1.1.0
    function removeFreezer(address account) external onlyOwner {
        _removeFreezer(account);
    }

    /// @notice External admin gated function to unfreeze a set of accounts
    /// @param accounts Array of accounts to be unfrozen
    /// @dev Added in v1.1.0
    function thawMany(address[] memory accounts) external onlyOwner {
        _thawMany(accounts);
    }

    /// @notice External admin gated function to unfreeze an account
    /// @param account The account to be unfrozen
    /// @dev Added in v1.1.0
    function thaw(address account) external onlyOwner {
        _thaw(account);
    }

    /// @notice External admin gated function to batch freeze a set of accounts
    /// @param accounts Array of accounts to be frozen
    /// @dev Added in v1.1.0
    function freezeMany(address[] memory accounts) external {
        if (!isFreezer(msg.sender) && msg.sender != owner()) revert NotFreezer();
        _freezeMany(accounts);
    }

    /// @notice External admin gated function to freeze a given account
    /// @param account The account to be
    /// @dev Added in v1.1.0
    function freeze(address account) external {
        if (!isFreezer(msg.sender) && msg.sender != owner()) revert NotFreezer();
        _freeze(account);
    }

    /// @notice External admin gated function to batch burn balance from a set of accounts
    /// @param accounts Array of accounts whose balances will be burned
    /// @param amounts Array of amounts corresponding to the balances to be burned
    /// @dev Added in v1.1.0
    /// @dev if `amount` == 0, entire balance will be burned
    function burnMany(address[] memory accounts, uint256[] memory amounts) external onlyOwner {
        uint lenOwner = accounts.length;
        if (accounts.length != amounts.length) revert ArrayMisMatch();
        for (uint i; i < lenOwner; ++i) {
            if (amounts[i] == 0) amounts[i] = balanceOf(accounts[i]);
            _burn(accounts[i], amounts[i]);
        }
    }

    /// @notice External admin gated function to burn balance from a given account
    /// @param account  The account whose balance will be burned
    /// @param amount The amount of balance to burn
    /// @dev Added in v1.1.0
    /// @dev if `amount` == 0, entire balance will be burned
    function burn(address account, uint256 amount) external onlyRole(ISSUER_ROLE) {
        if (amount == 0) amount = balanceOf(account);
        _burn(account, amount);
        emit Burn(msg.sender, amount);
    }

    /// @notice External admin gated pause function
    /// @dev Added in v1.1.0
    function pause() external onlyRole(PAUSE_ROLE) {
        _pause();
        emit PauseStateUpdate(msg.sender, true);
    }

    /// @notice External admin gated unpause function
    /// @dev Added in v1.1.0
    function unpause() external onlyRole(UNPAUSE_ROLE) {
        _unpause();
        emit PauseStateUpdate(msg.sender, false);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        TIP20Storage storage $ = _getTIP20Storage();
        if (msg.sender != owner()) {
            if (isPaused()) revert ContractPaused();
            if ((uint160(to) >> 64) == 0x20c000000000000000000000) revert InvalidRecipient();
            if (
                !TIP403_REGISTRY.isAuthorized($.transferPolicyId, from) ||
                !TIP403_REGISTRY.isAuthorized($.transferPolicyId, to)
            ) revert PolicyForbids();
            if (isFrozen(to) || isFrozen(from) || isFrozen(msg.sender)) revert BeforeTokenTransferBlocked();
        }
        if (amount > balanceOf(from)) {
            revert InsufficientBalance(balanceOf(from), amount, address(this));
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
        super._beforeTokenTransfer(from, to, amount);
    }

    // Helper views

    function toLD(uint64 _amountSD) external view returns (uint256 amountLD) {
        return _toLD(_amountSD);
    }

    function toSD(uint256 _amountLD) external view returns (uint64 amountSD) {
        return _toSD(_amountLD);
    }

    function removeDust(uint256 _amountLD) public view returns (uint256 amountLD) {
        return _removeDust(_amountLD);
    }

    function debitView(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) external view returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        /// @dev: _dstEid is unused in _debitView
        return _debitView(_amountLD, _minAmountLD, _dstEid);
    }

    function buildMsgAndOptions(
        SendParam calldata _sendParam,
        uint256 _amountLD
    ) external view returns (bytes memory message, bytes memory options) {
        return _buildMsgAndOptions(_sendParam, _amountLD);
    }

    //==============================================================================
    // Overrides
    //==============================================================================

    /// @dev supports EIP3009
    function _transfer(address from, address to, uint256 amount) internal override(EIP3009Module, ERC20Upgradeable) {
        return ERC20Upgradeable._transfer(from, to, amount);
    }

    /// @dev supports EIP2612
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal override(PermitModule, ERC20Upgradeable) {
        return ERC20Upgradeable._approve(owner, spender, amount);
    }

    /* ========== ERRORS ========== */
    error ArrayMisMatch();
    error BeforeTokenTransferBlocked();

    // ============ ITIP20 Implementation ============

    function decimals() public pure returns (uint8) {
        return 6;
    }

    /// @inheritdoc ITIP20
    function currency() external view override returns (string memory) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.currency;
    }

    /// @inheritdoc ITIP20
    function supplyCap() external view override returns (uint256) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.supplyCap;
    }

    /// @inheritdoc ITIP20
    function transferPolicyId() external view override returns (uint64) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.transferPolicyId;
    }

    /// @inheritdoc ITIP20
    function quoteToken() external view override returns (ITIP20) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.quoteToken;
    }

    /// @inheritdoc ITIP20
    function nextQuoteToken() external view override returns (ITIP20) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.nextQuoteToken;
    }

    /// @inheritdoc ITIP20
    function globalRewardPerToken() external view override returns (uint256) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.globalRewardPerToken;
    }

    /// @inheritdoc ITIP20
    function optedInSupply() external view override returns (uint128) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.optedInSupply;
    }

    /// @inheritdoc ITIP20
    function userRewardInfo(
        address account
    ) external view override returns (address rewardRecipient, uint256 rewardPerToken, uint256 rewardBalance) {
        TIP20Storage storage $ = _getTIP20Storage();
        UserRewardInfo storage info = $.userRewardInfo[account];
        return (info.rewardRecipient, info.rewardPerToken, info.rewardBalance);
    }

    /// @inheritdoc ITIP20
    function changeTransferPolicyId(uint64 newPolicyId) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        TIP20Storage storage $ = _getTIP20Storage();
        $.transferPolicyId = newPolicyId;
        emit TransferPolicyUpdate(msg.sender, newPolicyId);
    }

    /// @inheritdoc ITIP20
    function setSupplyCap(uint256 newSupplyCap) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newSupplyCap < totalSupply()) revert InvalidSupplyCap();
        if (newSupplyCap > type(uint128).max) revert SupplyCapExceeded();
        TIP20Storage storage $ = _getTIP20Storage();
        $.supplyCap = newSupplyCap;
        emit SupplyCapUpdate(msg.sender, newSupplyCap);
    }

    /// @inheritdoc ITIP20
    function setNextQuoteToken(ITIP20 newQuoteToken) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        TIP20Storage storage $ = _getTIP20Storage();
        // sets next quote token, to put the DEX for that pair into place-only mode
        // does not check for loops; that is checked in completeQuoteTokenUpdate
        if (!TIP20Factory(FACTORY).isTIP20(address(newQuoteToken))) {
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

    /// @inheritdoc ITIP20
    function completeQuoteTokenUpdate() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        TIP20Storage storage $ = _getTIP20Storage();
        // check that this does not create a loop, by looping through quote token until we reach the root
        ITIP20 current = $.nextQuoteToken;
        while (address(current) != address(0)) {
            if (current == this) revert InvalidQuoteToken();
            current = current.quoteToken();
        }

        $.quoteToken = $.nextQuoteToken;
        emit QuoteTokenUpdate(msg.sender, $.nextQuoteToken);
    }

    /// @inheritdoc ITIP20
    function setRewardRecipient(address newRewardRecipient) external override {
        if (isPaused()) revert ContractPaused();
        TIP20Storage storage $ = _getTIP20Storage();
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

    /// @inheritdoc ITIP20
    function startReward(uint256 amount, uint32 seconds_) external override returns (uint64) {
        if (isPaused()) revert ContractPaused();
        TIP20Storage storage $ = _getTIP20Storage();

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

    /// @inheritdoc ITIP20
    function claimRewards() external override returns (uint256 maxAmount) {
        if (isPaused()) revert ContractPaused();
        TIP20Storage storage $ = _getTIP20Storage();
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

    /// @inheritdoc ITIP20
    function transferFeePreTx(address from, uint256 amount) external override {
        TIP20Storage storage $ = _getTIP20Storage();
        require(msg.sender == TIP_FEE_MANAGER_ADDRESS);
        require(from != address(0));

        if (amount > balanceOf(from)) {
            revert InsufficientBalance(balanceOf[from], amount, address(this));
        }

        address fromsRewardRecipient = _updateRewardsAndGetRecipient(from);
        if (fromsRewardRecipient != address(0)) {
            $.optedInSupply -= uint128(amount);
        }
        _transfer(from, TIP_FEE_MANAGER_ADDRESS, amount);
    }

    /// @inheritdoc ITIP20
    function transferFeePostTx(address to, uint256 refund, uint256 actualUsed) external override {
        TIP20Storage storage $ = _getTIP20Storage();
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
        // TODO : verify event s as per TIP20 standard
        emit Transfer(to, TIP_FEE_MANAGER_ADDRESS, actualUsed);
    }

    /// @inheritdoc ITIP20
    function paused() external view override returns (bool) {
        return isPaused();
    }

    /// @inheritdoc ITIP20
    function burn(uint256 amount) external override onlyRole(ISSUER_ROLE) {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    /// @inheritdoc ITIP20
    function burnBlocked(address from, uint256 amount) external override onlyRole(BURN_BLOCKED_ROLE) {
        TIP20Storage storage $ = _getTIP20Storage();
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

    /// @inheritdoc ITIP20
    function burnWithMemo(uint256 amount, bytes32 memo) external override onlyRole(ISSUER_ROLE) {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
        emit TransferWithMemo(msg.sender, address(0), amount, memo);
    }

    /// @inheritdoc ITIP20
    function mint(address to, uint256 amount) external override onlyRole(ISSUER_ROLE) {
        TIP20Storage storage $ = _getTIP20Storage();
        _mint(to, amount);
        emit Mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal override {
        TIP20Storage storage $ = _getTIP20Storage();
        if (!TIP403_REGISTRY.isAuthorized($.transferPolicyId, to)) revert PolicyForbids();
        if (totalSupply() + amount > $.supplyCap) revert SupplyCapExceeded(); // Catches overflow.

        // Handle reward accounting for opted-in receiver
        address tosRewardRecipient = _updateRewardsAndGetRecipient(to);
        if (tosRewardRecipient != address(0)) {
            $.optedInSupply += uint128(amount);
        }

        super._mint(to, amount);
    }

    /// @inheritdoc ITIP20
    function mintWithMemo(address to, uint256 amount, bytes32 memo) external override onlyRole(ISSUER_ROLE) {
        TIP20Storage storage $ = _getTIP20Storage();
        _mint(to, amount);
        emit Mint(to, amount);
        emit TransferWithMemo(address(0), to, amount, memo);
    }

    /// @inheritdoc ITIP20
    function transferWithMemo(address to, uint256 amount, bytes32 memo) external override {
        transfer(to, amount);
        emit TransferWithMemo(msg.sender, to, amount, memo);
    }

    /// @inheritdoc ITIP20
    function transferFromWithMemo(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) external override returns (bool) {
        transferFrom(from, to, amount);
        emit TransferWithMemo(from, to, amount, memo);
        return true;
    }

    /// @inheritdoc ERC20Upgradeable
    function _spendAllowance(address owner, address spender, uint256 amount) internal override {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (amount > currentAllowance) revert InsufficientAllowance();
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /// @inheritdoc ITIP20
    function systemTransferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(msg.sender == TIP_FEE_MANAGER_ADDRESS);
        _transfer(from, to, amount);
        return true;
    }

    function _updateRewardsAndGetRecipient(address user) internal returns (address rewardRecipient) {
        TIP20Storage storage $ = _getTIP20Storage();
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
