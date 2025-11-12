pragma solidity ^0.8.0;

abstract contract MinterModule {

    //==============================================================================
    // Storage
    //==============================================================================

    struct MinterModuleStorage {
        address[] minters_array;
        mapping(address => bool) minters;
        uint256 totalMinted;
        uint256 totalBurned;
    }

    // keccak256(abi.encode(uint256(keccak256("frax.storage.MinterModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MinterModuleStorageLocation = 0x7a20b3b4fafc14b62295555dcdd80cd62ae312ce9abdfc5568be6a1913cbf700;

    function _getMinterModuleStorage() private pure returns(MinterModuleStorage storage $) {
        assembly {
            $.slot := MinterModuleStorageLocation
        }
    }

    /// @notice A modifier that only allows a minters to call
    modifier onlyMinters() {
        MinterModuleStorage storage $ = _getMinterModuleStorage();
        if (!$.minters[msg.sender]) revert OnlyMinter();
        _;
    }

    /// @notice Adds a minter
    /// @param minter_address Address of minter to add
    function _addMinter(address minter_address) internal {
        MinterModuleStorage storage $ = _getMinterModuleStorage();
        if ($.minters[minter_address]) revert AlreadyExists();
        $.minters[minter_address] = true;
        $.minters_array.push(minter_address);
        emit MinterAdded(minter_address);
    }

    /// @notice Removes a non-bridge minter
    /// @param minter_address Address of minter to remove
    function _removeMinter(address minter_address) internal {
        MinterModuleStorage storage $ = _getMinterModuleStorage();
        if (!$.minters[minter_address]) revert AddressNonexistant();
        delete $.minters[minter_address];
        for (uint256 i = 0; i < $.minters_array.length; i++) {
            if ($.minters_array[i] == minter_address) {
                $.minters_array[i] = address(0); // This will leave a null in the array and keep the indices the same
                break;
            }
        }
        emit MinterRemoved(minter_address);
    }

    /// @notice Used by minters to mint new tokens
    /// @param m_address Address of the account to mint to
    /// @param m_amount Amount of tokens to mint
    function _minter_mint(address m_address, uint256 m_amount) internal {
        MinterModuleStorage storage $ = _getMinterModuleStorage();
        _mint(m_address, m_amount);
        $.totalMinted += m_amount;
        emit TokenMinterMinted(msg.sender, m_address, m_amount);
    }

    /// @notice Used by minters to burn tokens
    /// @param b_address Address of the account to burn from
    /// @param b_amount Amount of tokens to burn
    function _minter_burn_from(address b_address, uint256 b_amount) internal {
        MinterModuleStorage storage $ = _getMinterModuleStorage();
        _burnFrom(b_address, b_amount);
        $.totalBurned += b_amount;
        emit TokenMinterBurned(b_address, msg.sender, b_amount);
    }

    /// @notice Destroys a `value` amount of tokens from `account`, deducting from
    ///         the caller's allowance.
    /// @param account Account to burn tokens from 
    /// @param value the amount to burn from account caller must have allowance
    function _burnFrom(address account, uint256 value) internal {
        _spendAllowance(account, msg.sender, value);
        _burn(account, value);
    }


    //==============================================================================
    // Overridden methods
    //==============================================================================

    function _mint(address,uint256) internal virtual;

    function _burn(address,uint256) internal virtual;

    function _spendAllowance(address,address,uint256) internal virtual;
    
    //==============================================================================
    // Views
    //==============================================================================

    function minters(address _address) external view returns(bool) {
        MinterModuleStorage storage $ = _getMinterModuleStorage();
        return $.minters[_address];
    }

    function minters_array(uint256 _idx) external view returns(address) {
        MinterModuleStorage storage $ = _getMinterModuleStorage();
        return $.minters_array[_idx];
    }

    function totalMinted() external view returns(uint256) {
        MinterModuleStorage storage $ = _getMinterModuleStorage();
        return $.totalMinted;
    }

    function totalBurned() external view returns(uint256) {
        MinterModuleStorage storage $ = _getMinterModuleStorage();
        return $.totalBurned;
    }

    //==============================================================================
    // Events
    //==============================================================================

    /// @notice Emitted when a non-bridge minter is added
    /// @param minter_address Address of the new minter
    event MinterAdded(address minter_address);

    /// @notice Emitted when a non-bridge minter is removed
    /// @param minter_address Address of the removed minter
    event MinterRemoved(address minter_address);

    /// @notice Emitted when a non-bridge minter mints tokens
    /// @param from The minter doing the minting
    /// @param to The account that gets the newly minted tokens
    /// @param amount Amount of tokens minted
    event TokenMinterMinted(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when a non-bridge minter burns tokens
    /// @param from The account whose tokens are burned
    /// @param to The minter doing the burning
    /// @param amount Amount of tokens burned
    event TokenMinterBurned(address indexed from, address indexed to, uint256 amount);

    //==============================================================================
    // Errors
    //==============================================================================
    
    error OnlyMinter();
    error ZeroAddress();
    error AlreadyExists();
    error AddressNonexistant();
}