pragma solidity ^0.8.0;

import {EIP712Upgradeable} from "./shared/EIP712Upgradeable.sol";

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @dev Ripped from OZ 4.9.4 ERC20Permit.sol with namespaced storage
abstract contract PermitModule is EIP712Upgradeable {

    using Counters for Counters.Counter;

    //==============================================================================
    // Storage
    //==============================================================================

    // solhint-disable-next-line var-name-mixedcase
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    struct PermitModuleStorage {
        mapping(address => Counters.Counter) nonces;
    }

    // keccak256(abi.encode(uint256(keccak256("frax.storage.PermitModule")) - 1)) & ~bytes32(uint256(0xff))    
    bytes32 private constant PermitModuleStorageLocation = 0xb39b43abb0b115e0a59dece28477e279ee5f8e2fd55fbe200557c3ab864a0300;

    function _getPermitModuleStorage() private pure returns (PermitModuleStorage storage $) {
        assembly {
            $.slot := PermitModuleStorageLocation
        }
    }

    //==============================================================================
    // Functions
    //==============================================================================

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");

        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        require(signer == owner, "ERC20Permit: invalid signature");

        _approve(owner, spender, value);
    }

    function nonces(address owner) public view virtual returns (uint256) {
        PermitModuleStorage storage $ = _getPermitModuleStorage();
        return $.nonces[owner].current();
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _useNonce(address owner) internal virtual returns (uint256 current) {
        PermitModuleStorage storage $ = _getPermitModuleStorage();
        current = $.nonces[owner].current();
        $.nonces[owner].increment();
    }

    //==============================================================================
    // Virtual overriden methods
    //==============================================================================

    function _approve(address owner, address spender, uint256 amount) internal virtual {}
}