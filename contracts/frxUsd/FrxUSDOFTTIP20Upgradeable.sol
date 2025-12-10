// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {FrxUSDOFTUpgradeable} from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import {ITIP20Extended} from "contracts/interfaces/ITIP20Extended.sol";

/**
 * @title FrxUSDOFTTIP20Upgradeable
 * @dev Extends FrxUSDOFTUpgradeable with TIP-20 compliance using ERC-7201 namespaced storage
 */
contract FrxUSDOFTTIP20Upgradeable is FrxUSDOFTUpgradeable, ITIP20Extended {
    
    // ============ Role Constants ============
    bytes32 public constant BURN_BLOCKED_ROLE = keccak256("BURN_BLOCKED_ROLE");
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant UNPAUSE_ROLE = keccak256("UNPAUSE_ROLE");

    // ============ ERC-7201 Namespaced Storage ============

    struct UserRewardInfo {
        address rewardRecipient;
        uint256 rewardPerToken;
        uint256 rewardBalance;
    }

    /// @custom:storage-location erc7201:frax.storage.FrxUSDOFTTIP20
    struct TIP20Storage {
        uint256 supplyCap;
        uint64 transferPolicyId;
        string currency;
        ITIP20Extended quoteToken;
        ITIP20Extended nextQuoteToken;
        uint256 globalRewardPerToken;
        uint128 optedInSupply;
        mapping(address => UserRewardInfo) userRewardInfo;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.FrxUSDOFTTIP20")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TIP20StorageLocation = 0x9fd7d0c44526e808a04e8633c77b144fb613d422fc75d4d0ebc0c5329184a400;

    function _getTIP20Storage() private pure returns (TIP20Storage storage $) {
        assembly {
            $.slot := TIP20StorageLocation
        }
    }

    // ============ Constructor ============
    constructor(address _lzEndpoint) FrxUSDOFTUpgradeable(_lzEndpoint) {}

    // ============ ITIP20Extended Implementation ============

    /// @inheritdoc ITIP20Extended
    function paused() external view override returns (bool) {
        return isPaused();
    }

    /// @inheritdoc ITIP20Extended
    function currency() external view override returns (string memory) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.currency;
    }

    /// @inheritdoc ITIP20Extended
    function supplyCap() external view override returns (uint256) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.supplyCap;
    }

    /// @inheritdoc ITIP20Extended
    function transferPolicyId() external view override returns (uint64) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.transferPolicyId;
    }

    /// @inheritdoc ITIP20Extended
    function quoteToken() external view override returns (ITIP20Extended) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.quoteToken;
    }

    /// @inheritdoc ITIP20Extended
    function nextQuoteToken() external view override returns (ITIP20Extended) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.nextQuoteToken;
    }

    /// @inheritdoc ITIP20Extended
    function globalRewardPerToken() external view override returns (uint256) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.globalRewardPerToken;
    }

    /// @inheritdoc ITIP20Extended
    function optedInSupply() external view override returns (uint128) {
        TIP20Storage storage $ = _getTIP20Storage();
        return $.optedInSupply;
    }

    /// @inheritdoc ITIP20Extended
    function userRewardInfo(address account) external view override returns (
        address rewardRecipient,
        uint256 rewardPerToken,
        uint256 rewardBalance
    ) {
        TIP20Storage storage $ = _getTIP20Storage();
        UserRewardInfo storage info = $.userRewardInfo[account];
        return (info.rewardRecipient, info.rewardPerToken, info.rewardBalance);
    }

    /// @inheritdoc ITIP20Extended
    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    /// @inheritdoc ITIP20Extended
    function burnBlocked(address from, uint256 amount) external override onlyOwner {
        _burn(from, amount);
        emit BurnBlocked(from, amount);
    }

    /// @inheritdoc ITIP20Extended
    function burnWithMemo(uint256 amount, bytes32 memo) external override {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    /// @inheritdoc ITIP20Extended
    function mint(address to, uint256 amount) external override onlyOwner {
        TIP20Storage storage $ = _getTIP20Storage();
        if ($.supplyCap > 0 && totalSupply() + amount > $.supplyCap) revert SupplyCapExceeded();
        _mint(to, amount);
        emit Mint(to, amount);
    }

    /// @inheritdoc ITIP20Extended
    function mintWithMemo(address to, uint256 amount, bytes32 memo) external override onlyOwner {
        TIP20Storage storage $ = _getTIP20Storage();
        if ($.supplyCap > 0 && totalSupply() + amount > $.supplyCap) revert SupplyCapExceeded();
        _mint(to, amount);
        emit Mint(to, amount);
    }

    /// @inheritdoc ITIP20Extended
    function transferWithMemo(address to, uint256 amount, bytes32 memo) external override {
        _transfer(msg.sender, to, amount);
        emit TransferWithMemo(msg.sender, to, amount, memo);
    }

    /// @inheritdoc ITIP20Extended
    function transferFromWithMemo(address from, address to, uint256 amount, bytes32 memo) external override returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        emit TransferWithMemo(from, to, amount, memo);
        return true;
    }

    /// @inheritdoc ITIP20Extended
    function systemTransferFrom(address from, address to, uint256 amount) external override onlyOwner returns (bool) {
        _transfer(from, to, amount);
        return true;
    }

    /// @inheritdoc ITIP20Extended
    function changeTransferPolicyId(uint64 newPolicyId) external override onlyOwner {
        TIP20Storage storage $ = _getTIP20Storage();
        $.transferPolicyId = newPolicyId;
        emit TransferPolicyUpdate(msg.sender, newPolicyId);
    }

    /// @inheritdoc ITIP20Extended
    function setSupplyCap(uint256 newSupplyCap) external override onlyOwner {
        TIP20Storage storage $ = _getTIP20Storage();
        $.supplyCap = newSupplyCap;
        emit SupplyCapUpdate(msg.sender, newSupplyCap);
    }

    /// @inheritdoc ITIP20Extended
    function setNextQuoteToken(ITIP20Extended newQuoteToken) external override onlyOwner {
        TIP20Storage storage $ = _getTIP20Storage();
        $.nextQuoteToken = newQuoteToken;
        emit NextQuoteTokenSet(msg.sender, newQuoteToken);
    }

    /// @inheritdoc ITIP20Extended
    function completeQuoteTokenUpdate() external override onlyOwner {
        TIP20Storage storage $ = _getTIP20Storage();
        if (address($.nextQuoteToken) == address(0)) revert InvalidQuoteToken();
        $.quoteToken = $.nextQuoteToken;
        $.nextQuoteToken = ITIP20Extended(address(0));
        emit QuoteTokenUpdate(msg.sender, $.quoteToken);
    }

    /// @inheritdoc ITIP20Extended
    function setRewardRecipient(address newRewardRecipient) external override {
        TIP20Storage storage $ = _getTIP20Storage();
        $.userRewardInfo[msg.sender].rewardRecipient = newRewardRecipient;
        emit RewardRecipientSet(msg.sender, newRewardRecipient);
    }

    /// @inheritdoc ITIP20Extended
    function startReward(uint256 amount, uint32 seconds_) external override onlyOwner returns (uint64) {
        TIP20Storage storage $ = _getTIP20Storage();
        if (seconds_ > 0) revert ScheduledRewardsDisabled();
        if ($.optedInSupply == 0) revert NoOptedInSupply();
        emit RewardScheduled(msg.sender, 0, amount, seconds_);
        return 0;
    }

    /// @inheritdoc ITIP20Extended
    function claimRewards() external override returns (uint256 maxAmount) {
        TIP20Storage storage $ = _getTIP20Storage();
        UserRewardInfo storage info = $.userRewardInfo[msg.sender];
        maxAmount = info.rewardBalance;
        info.rewardBalance = 0;
        return maxAmount;
    }

    /// @inheritdoc ITIP20Extended
    function transferFeePreTx(address from, uint256 amount) external override {
        // Fee handling hook - can be extended for specific fee logic
    }

    /// @inheritdoc ITIP20Extended
    function transferFeePostTx(address to, uint256 refund, uint256 actualUsed) external override {
        // Fee handling hook - can be extended for specific fee logic
    }
}