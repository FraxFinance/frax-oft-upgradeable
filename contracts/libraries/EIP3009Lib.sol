pragma solidity ^0.8.0;

import {EIP3009Module} from "contracts/modules/EIP3009Module.sol";
import {SignatureModule} from "contracts/modules/signatureModule/SignatureModule.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

/// @notice EIP-3009 authorization validation.
/// @dev Linked library. Runs via delegatecall: nonces use EIP3009Module's namespaced storage and
///      the EIP-712 digest is rebuilt from the OZ EIP712 slot. Token movement stays in the module.
library EIP3009Lib {
    bytes32 private constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;
    bytes32 private constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;
    bytes32 private constant CANCEL_AUTHORIZATION_TYPEHASH =
        0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;

    /// @dev keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 private constant EIP712_DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev Must equal EIP3009Module.EIP3009ModuleStorageLocation.
    bytes32 private constant EIP3009ModuleStorageLocation =
        0x6607eb842e76408d8b3956685dc6b9da5897a1d9b47edcc993ce266e603fa500;

    /// @dev OZ EIP712Upgradeable storage: keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.EIP712")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant EIP712StorageLocation = 0xa16a46d94261c7517cc8ff89f61c0ce93598e3c849801011dee649a6a557d100;

    struct EIP712Storage {
        bytes32 _hashedName;
        bytes32 _hashedVersion;
        string _name;
        string _version;
    }

    function _getEIP3009ModuleStorage() private pure returns (EIP3009Module.EIP3009ModuleStorage storage $) {
        assembly {
            $.slot := EIP3009ModuleStorageLocation
        }
    }

    function _getEIP712Storage() private pure returns (EIP712Storage storage $) {
        assembly {
            $.slot := EIP712StorageLocation
        }
    }

    function validateTransferAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external {
        // Checks: authorization validity
        if (block.timestamp <= validAfter) revert EIP3009Module.InvalidAuthorization();
        if (block.timestamp >= validBefore) revert EIP3009Module.ExpiredAuthorization();
        _requireUnusedAuthorization({ authorizer: from, nonce: nonce });

        // Checks: valid signature
        _requireIsValidSignatureNow({
            signer: from,
            structHash: keccak256(
                abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
            ),
            signature: signature
        });

        // Effects: mark authorization as used
        _markAuthorizationAsUsed({ authorizer: from, nonce: nonce });
    }

    function validateReceiveAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external {
        // Checks: authorization validity (msg.sender is the original caller under DELEGATECALL)
        if (to != msg.sender) revert EIP3009Module.InvalidPayee({ caller: msg.sender, payee: to });
        if (block.timestamp <= validAfter) revert EIP3009Module.InvalidAuthorization();
        if (block.timestamp >= validBefore) revert EIP3009Module.ExpiredAuthorization();
        _requireUnusedAuthorization({ authorizer: from, nonce: nonce });

        // Checks: valid signature
        _requireIsValidSignatureNow({
            signer: from,
            structHash: keccak256(
                abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
            ),
            signature: signature
        });

        // Effects: mark authorization as used
        _markAuthorizationAsUsed({ authorizer: from, nonce: nonce });
    }

    function cancelAuthorization(address authorizer, bytes32 nonce, bytes memory signature) external {
        _requireUnusedAuthorization({ authorizer: authorizer, nonce: nonce });
        _requireIsValidSignatureNow({
            signer: authorizer,
            structHash: keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce)),
            signature: signature
        });

        _getEIP3009ModuleStorage().isAuthorizationUsed[authorizer][nonce] = true;
        emit EIP3009Module.AuthorizationCanceled({ authorizer: authorizer, nonce: nonce });
    }

    function _requireUnusedAuthorization(address authorizer, bytes32 nonce) private view {
        if (_getEIP3009ModuleStorage().isAuthorizationUsed[authorizer][nonce])
            revert EIP3009Module.UsedOrCanceledAuthorization();
    }

    function _markAuthorizationAsUsed(address authorizer, bytes32 nonce) private {
        _getEIP3009ModuleStorage().isAuthorizationUsed[authorizer][nonce] = true;
        emit EIP3009Module.AuthorizationUsed({ authorizer: authorizer, nonce: nonce });
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
