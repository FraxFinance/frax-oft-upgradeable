// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTUpgradeable.sol";
import { FreezeThawModule } from "contracts/modules/FreezeThawModule.sol";
import { PauseModule } from "contracts/modules/PauseModule.sol";
import { EIP3009Module } from "contracts/modules/EIP3009Module.sol";
import { PermitModule } from "contracts/modules/PermitModule.sol";
import { TIP20Module } from "contracts/modules/tempo/TIP20Module.sol";
import { SendParam } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";
import { ITIP20Frax } from "contracts/interfaces/ITIP20Frax.sol";

/**
 * @title FrxUSDOFTTIP20Upgradeable
 * @author Frax Finance
 * @notice LayerZero OFT token with TIP-20 compliance for Tempo Finance integration
 * @dev This contract combines LayerZero's Omnichain Fungible Token (OFT) functionality 
 *      with TIP-20 (Tempo Improvement Proposal 20) compliance using a modular architecture.
 * 
 * Architecture:
 * - Inherits OFTUpgradeable for cross-chain token transfers via LayerZero
 * - Composes EIP3009Module for gasless transfers (transferWithAuthorization)
 * - Composes PermitModule for gasless approvals (EIP-2612)
 * - Composes FreezeThawModule for account freezing/thawing
 * - Composes PauseModule for emergency pause functionality
 * - Composes TIP20Module for Tempo Finance TIP-20 compliance
 * 
 * TIP-20 Features:
 * - Transfer policy enforcement via TIP-403 Registry
 * - Supply cap management
 * - Quote token hierarchy for stablecoin pricing
 * - Reward distribution system for opted-in users
 * - Role-based access control (PAUSE_ROLE, UNPAUSE_ROLE, ISSUER_ROLE, BURN_BLOCKED_ROLE)
 * - Memo-enabled transfers, mints, and burns
 * 
 * Storage:
 * - Uses ERC-7201 namespaced storage pattern to avoid storage collisions
 * - TIP20Module storage at slot: 0x3f4e...3f00
 * - TIP20RolesAuth storage at slot: 0x8c4e...0000
 */
contract FrxUSDOFTTIP20Upgradeable is 
    OFTUpgradeable, 
    EIP3009Module, 
    PermitModule, 
    FreezeThawModule, 
    PauseModule,
    TIP20Module 
{
    /// @notice Constructor sets the LayerZero endpoint and disables initializers
    /// @param _lzEndpoint The LayerZero endpoint address for cross-chain messaging
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    /// @notice Returns the contract version
    /// @return The version string "1.1.0"
    function version() public pure returns (string memory) {
        return "1.1.0";
    }

    /// @notice Returns the token name
    /// @dev Overrides ERC20 storage to return hardcoded value for consistency across chains
    /// @return The token name "Frax USD"
    function name() public pure override(ERC20Upgradeable, ITIP20Frax) returns (string memory) {
        return "Frax USD";
    }

    /// @notice Returns the token symbol
    /// @dev Overrides ERC20 storage to return hardcoded value for consistency across chains
    /// @return The token symbol "frxUSD"
    function symbol() public pure override(ERC20Upgradeable, ITIP20Frax) returns (string memory) {
        return "frxUSD";
    }

    /// @notice Returns the token decimals
    /// @dev Returns 6 decimals as per TIP-20 specification
    /// @return The number of decimals (6)
    function decimals() public pure override(ERC20Upgradeable, ITIP20Frax) returns (uint8) {
        return 6;
    }

    // ============ Override functions from multiple inheritance ============

    /// @dev Override owner() to satisfy multiple inheritance
    function owner() public view override(OwnableUpgradeable, TIP20Module) returns (address) {
        return OwnableUpgradeable.owner();
    }

    /// @dev Override isPaused() to satisfy multiple inheritance
    function isPaused() public view override(PauseModule, TIP20Module) returns (bool) {
        return PauseModule.isPaused();
    }

    /// @dev Override balanceOf() to satisfy multiple inheritance
    function balanceOf(address account) public view override(ERC20Upgradeable, TIP20Module) returns (uint256) {
        return ERC20Upgradeable.balanceOf(account);
    }

    /// @dev Override totalSupply() to satisfy multiple inheritance
    function totalSupply() public view override(ERC20Upgradeable, TIP20Module) returns (uint256) {
        return ERC20Upgradeable.totalSupply();
    }

    // ============ Initialization ============

    /// @notice Initialize the contract with TIP-20 parameters
    /// @param _delegate The delegate address for OFT
    /// @param _currency The currency string (e.g., "USD")
    /// @param _quoteToken The initial quote token
    /// @param _admin The admin address that receives all roles
    function initialize(
        address _delegate,
        string memory _currency,
        ITIP20 _quoteToken,
        address _admin
    ) external initializer {
        // Initialize base OFT and ownership
        __OFT_init(name(), symbol(), _delegate);
        __EIP712_init(name(), version());
        __Ownable_init();
        _transferOwnership(_delegate);
        
        // Initialize TIP-20 module
        __TIP20Module_init(_currency, _quoteToken, _admin);
    }

    // ============ Admin Functions (from FrxUSDOFTUpgradeable) ============

    /// @notice External admin gated function to add a freezer role to an account
    function addFreezer(address account) external onlyOwner {
        _addFreezer(account);
    }

    /// @notice External admin gated function to remove a freezer role from an account
    function removeFreezer(address account) external onlyOwner {
        _removeFreezer(account);
    }

    /// @notice External admin gated function to unfreeze a set of accounts
    function thawMany(address[] memory accounts) external onlyOwner {
        _thawMany(accounts);
    }

    /// @notice External admin gated function to unfreeze an account
    function thaw(address account) external onlyOwner {
        _thaw(account);
    }

    /// @notice External admin gated function to batch freeze a set of accounts
    function freezeMany(address[] memory accounts) external {
        if (!isFreezer(msg.sender) && msg.sender != owner()) revert NotFreezer();
        _freezeMany(accounts);
    }

    /// @notice External admin gated function to freeze a given account
    function freeze(address account) external {
        if (!isFreezer(msg.sender) && msg.sender != owner()) revert NotFreezer();
        _freeze(account);
    }

    /// @notice External admin gated function to batch burn balance from a set of accounts
    function burnMany(address[] memory accounts, uint256[] memory amounts) external onlyOwner {
        uint lenOwner = accounts.length;
        if (accounts.length != amounts.length) revert ArrayMisMatch();
        for (uint i; i < lenOwner; ++i) {
            if (amounts[i] == 0) amounts[i] = balanceOf(accounts[i]);
            _burn(accounts[i], amounts[i]);
        }
    }

    /// @notice Admin burn from an account (requires ISSUER_ROLE for TIP-20)
    /// @param account The account to burn from
    /// @param amount The amount to burn (0 = burn entire balance)
    function burn(address account, uint256 amount) external onlyRole(ISSUER_ROLE) {
        if (amount == 0) amount = balanceOf(account);
        _burn(account, amount);
        emit Burn(msg.sender, amount);
    }

    /// @notice Admin pause function (requires PAUSE_ROLE for TIP-20)
    function pause() external onlyRole(PAUSE_ROLE) {
        _pause();
        emit PauseStateUpdate(msg.sender, true);
    }

    /// @notice Admin unpause function (requires UNPAUSE_ROLE for TIP-20)
    function unpause() external onlyRole(UNPAUSE_ROLE) {
        _unpause();
        emit PauseStateUpdate(msg.sender, false);
    }

    // ============ Integrate TIP-20 Hooks into Token Transfer ============

    /// @dev Override _beforeTokenTransfer to integrate both base checks and TIP-20 checks
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Skip balance check for mints (from == address(0))
        if (from != address(0) && amount > balanceOf(from)) {
            revert InsufficientBalance(balanceOf(from), amount, address(this));
        }

        // Call TIP-20 hook for reward accounting and policy checks
        _beforeTokenTransferTIP20(from, to, amount);
        
        // Call parent hook for freeze/thaw and pause checks
        if (msg.sender != owner()) {
            if (
                isPaused() ||
                isFrozen(to) || isFrozen(from) || isFrozen(msg.sender)
            ) revert BeforeTokenTransferBlocked();
        }
        
        super._beforeTokenTransfer(from, to, amount);
    }

    // ============ Helper Views (from FrxUSDOFTUpgradeable) ============

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
        return _debitView(_amountLD, _minAmountLD, _dstEid);
    }

    function buildMsgAndOptions(
        SendParam calldata _sendParam,
        uint256 _amountLD
    ) external view returns (bytes memory message, bytes memory options) {
        return _buildMsgAndOptions(_sendParam, _amountLD);
    }

    // ============ Internal Overrides for Multiple Inheritance ============

    /// @dev Override _mint to call ERC20 mint (TIP-20 checks are done in TIP20Module.mint/mintWithMemo)
    function _mint(address to, uint256 amount) internal override(ERC20Upgradeable, TIP20Module) {
        ERC20Upgradeable._mint(to, amount);
    }

    /// @dev supports EIP3009
    function _transfer(address from, address to, uint256 amount) 
        internal 
        override(EIP3009Module, ERC20Upgradeable, TIP20Module) 
    {
        ERC20Upgradeable._transfer(from, to, amount);
    }

    /// @dev Override _burn to satisfy multiple inheritance
    function _burn(address from, uint256 amount) 
        internal 
        override(ERC20Upgradeable, TIP20Module) 
    {
        ERC20Upgradeable._burn(from, amount);
    }

    /// @dev supports EIP2612
    function _approve(address _owner, address _spender, uint256 _amount) 
        internal 
        override(PermitModule, ERC20Upgradeable) 
    {
        return ERC20Upgradeable._approve(_owner, _spender, _amount);
    }

    /// @dev Override _spendAllowance to satisfy multiple inheritance
    function _spendAllowance(address owner, address spender, uint256 value) 
        internal 
        override(ERC20Upgradeable, TIP20Module) 
    {
        ERC20Upgradeable._spendAllowance(owner, spender, value);
    }

    // ============ Errors ============

    error ArrayMisMatch();
    error BeforeTokenTransferBlocked();
}
