pragma solidity ^0.8.0;

import {PermitModule} from "contracts/modules/PermitModule.sol";
import {SignatureModule} from "contracts/modules/signatureModule/SignatureModule.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

/// @notice ERC-2612 permit validation.
/// @dev Linked library. Runs via delegatecall: the nonce uses PermitModule's namespaced storage and
///      the EIP-712 digest is rebuilt from the OZ EIP712 slot. The approval stays in the module.
library PermitLib {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @dev keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 private constant EIP712_DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev Must equal PermitModule.PermitModuleStorageLocation.
    bytes32 private constant PermitModuleStorageLocation =
        0xb39b43abb0b115e0a59dece28477e279ee5f8e2fd55fbe200557c3ab864a0300;

    /// @dev OZ EIP712Upgradeable storage: keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.EIP712")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant EIP712StorageLocation = 0xa16a46d94261c7517cc8ff89f61c0ce93598e3c849801011dee649a6a557d100;

    struct EIP712Storage {
        bytes32 _hashedName;
        bytes32 _hashedVersion;
        string _name;
        string _version;
    }

    function _getPermitModuleStorage() private pure returns (PermitModule.PermitModuleStorage storage $) {
        assembly {
            $.slot := PermitModuleStorageLocation
        }
    }

    function _getEIP712Storage() private pure returns (EIP712Storage storage $) {
        assembly {
            $.slot := EIP712StorageLocation
        }
    }

    function validatePermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    ) external {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");

        _requireIsValidSignatureNow({
            signer: owner,
            structHash: keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline)),
            signature: signature
        });
    }

    function _useNonce(address owner) private returns (uint256 current) {
        PermitModule.PermitModuleStorage storage $ = _getPermitModuleStorage();
        current = $.nonces[owner]._value;
        $.nonces[owner]._value = current + 1;
    }

    /// @dev Mirrors SignatureModule._requireIsValidSignatureNow (EIP712Upgradeable digest +
    ///      OZ SignatureChecker), executing in the token's context under DELEGATECALL.
    function _requireIsValidSignatureNow(address signer, bytes32 structHash, bytes memory signature) private view {
        if (
            !SignatureChecker.isValidSignatureNow({
                signer: signer,
                hash: ECDSAUpgradeable.toTypedDataHash(_domainSeparatorV4(), structHash),
                signature: signature
            }) || signer == address(0)
        ) revert SignatureModule.InvalidSignature();
    }

    function _domainSeparatorV4() private view returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPE_HASH, _EIP712NameHash(), _EIP712VersionHash(), block.chainid, address(this))
        );
    }

    function _EIP712NameHash() private view returns (bytes32) {
        EIP712Storage storage $ = _getEIP712Storage();
        string memory name = $._name;
        if (bytes(name).length > 0) {
            return keccak256(bytes(name));
        } else {
            bytes32 hashedName = $._hashedName;
            if (hashedName != 0) {
                return hashedName;
            } else {
                return keccak256("");
            }
        }
    }

    function _EIP712VersionHash() private view returns (bytes32) {
        EIP712Storage storage $ = _getEIP712Storage();
        string memory version = $._version;
        if (bytes(version).length > 0) {
            return keccak256(bytes(version));
        } else {
            bytes32 hashedVersion = $._hashedVersion;
            if (hashedVersion != 0) {
                return hashedVersion;
            } else {
                return keccak256("");
            }
        }
    }
}
