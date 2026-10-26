// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EIP712Upgradeable} from "contracts/modules/signatureModule/EIP712Upgradeable.sol";

/// @notice EIP-712 domain separator and ERC-5267 metadata.
/// @dev Linked library. Runs via delegatecall against the OZ `openzeppelin.storage.EIP712` slot.
library EIP712Lib {
    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev Must equal EIP712Upgradeable.EIP712StorageLocation.
    bytes32 private constant EIP712StorageLocation = 0xa16a46d94261c7517cc8ff89f61c0ce93598e3c849801011dee649a6a557d100;

    function _getEIP712Storage() private pure returns (EIP712Upgradeable.EIP712Storage storage $) {
        assembly {
            $.slot := EIP712StorageLocation
        }
    }

    function domainSeparatorV4() external view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, _nameHash(), _versionHash(), block.chainid, address(this)));
    }

    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        EIP712Upgradeable.EIP712Storage storage $ = _getEIP712Storage();
        // If the hashed name and version in storage are non-zero, the contract hasn't been properly initialized
        // and the EIP712 domain is not reliable, as it will be missing name and version.
        require($._hashedName == 0 && $._hashedVersion == 0, "EIP712: Uninitialized");

        return (
            hex"0f", // 01111
            $._name,
            $._version,
            block.chainid,
            address(this),
            bytes32(0),
            new uint256[](0)
        );
    }

    function _nameHash() private view returns (bytes32) {
        EIP712Upgradeable.EIP712Storage storage $ = _getEIP712Storage();
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

    function _versionHash() private view returns (bytes32) {
        EIP712Upgradeable.EIP712Storage storage $ = _getEIP712Storage();
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
