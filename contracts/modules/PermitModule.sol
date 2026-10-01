pragma solidity ^0.8.0;

import {SignatureModule} from "./signatureModule/SignatureModule.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {PermitLib} from "contracts/libraries/PermitLib.sol";

/// @dev Ripped from OZ 4.9.4 ERC20Permit.sol with namespaced storage and support of ERC1271 signatures
/// @dev Permit validation is delegated to `PermitLib`; `_approve` is implemented by the token.
abstract contract PermitModule is SignatureModule {

    using Counters for Counters.Counter;

    //==============================================================================
    // Storage
    //==============================================================================

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
        permit({
            owner: owner,
            spender: spender,
            value: value,
            deadline: deadline,
            signature: abi.encodePacked(r, s, v)
        });
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    ) public virtual {
        // Checks + effects (deadline, signature, nonce) in the linked library
        PermitLib.validatePermit(owner, spender, value, deadline, signature);

        _approve(owner, spender, value);
    }

    function nonces(address owner) public view virtual returns (uint256) {
        PermitModuleStorage storage $ = _getPermitModuleStorage();
        return $.nonces[owner].current();
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    //==============================================================================
    // Virtual overriden methods
    //==============================================================================

    function _approve(address owner, address spender, uint256 amount) internal virtual {}
}
