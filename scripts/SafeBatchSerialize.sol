// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VmSafe} from "forge-std/Vm.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

struct SerializedTx {
    string name;
    address to;
    uint256 value;
    bytes data;
}

contract SafeTxUtil is Script {
    using stdJson for string;

    /// @notice Builds the Safe batch JSON exactly the same way `writeTxs` does, but using
    ///         pure-Solidity string concatenation instead of `vm.serialize*` / `vm.writeJson`.
    ///         This is the fallback path used when running under `forge --zksync`, where the
    ///         `vm.serialize*` cheatcodes revert (zksolc-era foundry_zksync_core emits
    ///         "Invalid opcode, Not enough gas" on `vm.serializeString`), so no file is ever
    ///         written. Instead we print the JSON to the console so the operator can save it
    ///         to the expected filename manually.
    function logTxsJson(SerializedTx[] memory txs, string memory path) public {
        string memory json = _buildTxsJson(txs);
        console.log("============================================================");
        console.log("zksync fallback: vm.writeJson unavailable. Copy JSON below.");
        console.log("Target file path:");
        console.log(path);
        console.log("------------------------------------------------------------");
        console.log(json);
        console.log("============================================================");
    }

    /// @dev Pure-Solidity reimplementation of the JSON that `writeTxs` produces, so the
    ///      manually-saved file is byte-compatible with the normal output.
    function _buildTxsJson(SerializedTx[] memory txs) internal view returns (string memory) {
        // transactions array
        string memory txsStr = "[";
        for (uint256 i = 0; i < txs.length; i++) {
            if (i != 0) txsStr = string.concat(txsStr, ",");
            txsStr = string.concat(
                txsStr,
                '{"data":"', _bytesToHex(txs[i].data), '",',
                '"operation":"0",',
                '"to":"', _addressToChecksumHexString(txs[i].to), '",',
                '"value":"', Strings.toString(txs[i].value), '"}'
            );
        }
        txsStr = string.concat(txsStr, "]");

        return string.concat(
            '{',
            '"chainId":', Strings.toString(block.chainid), ',',
            '"createdAt":', Strings.toString(block.timestamp * 1000), ',',
            '"meta":{"description":"","name":"Transactions Batch"},',
            '"transactions":', txsStr, ',',
            '"version":"1.0"',
            '}'
        );
    }

    /// @dev Lowercase hex encoding of bytes with 0x prefix, e.g. 0xdeadbeef.
    function _bytesToHex(bytes memory b) internal pure returns (string memory) {
        bytes16 hexChars = "0123456789abcdef";
        bytes memory out = new bytes(2 + b.length * 2);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i = 0; i < b.length; i++) {
            out[2 + i * 2] = hexChars[uint8(b[i]) >> 4];
            out[2 + i * 2 + 1] = hexChars[uint8(b[i]) & 0x0f];
        }
        return string(out);
    }

    /// @dev EIP-55 checksummed hex string for an address. Matches the casing that
    ///      `vm.serializeAddress` writes and that existing JSON files use.
    function _addressToChecksumHexString(address a) internal pure returns (string memory) {
        bytes16 hexChars = "0123456789abcdef";

        // 40 lowercase hex chars without 0x prefix
        bytes memory lower = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            uint8 byteVal = uint8(uint160(a) >> (8 * (19 - i)));
            lower[2 * i] = hexChars[byteVal >> 4];
            lower[2 * i + 1] = hexChars[byteVal & 0x0f];
        }

        // EIP-55: hash the lowercase hex string (no 0x prefix)
        bytes32 hash = keccak256(lower);

        bytes memory out = new bytes(42);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i = 0; i < 40; i++) {
            uint8 hashNibble = uint8(hash[i / 2]);
            if (i % 2 == 0) hashNibble >>= 4;
            else hashNibble &= 0x0f;

            if (lower[i] >= "a" && lower[i] <= "f" && hashNibble >= 8) {
                out[2 + i] = bytes1(uint8(lower[i]) - 32); // uppercase
            } else {
                out[2 + i] = lower[i];
            }
        }
        return string(out);
    }

    function writeTxs(SerializedTx[] memory txs, string memory path) public {
        // Escape hatch for hosts where the JSON cheatcodes are unavailable: builds the same
        // document with plain string concatenation and logs it for extract-console-safe-json.py
        // instead of calling vm.serialize*/vm.writeJson/vm.ffi. Verified to produce output
        // semantically identical to the cheatcode path (see extract-console-safe-json.py).
        //
        // NOTE: this does NOT make `forge --zksync` work. That reverts for a separate reason
        // still undiagnosed -- console.log and string.concat were both proven fine under
        // --zksync, and execution never reaches this function. ZKsync Era (324) and Abstract
        // (2741) are generated by generate-unforkable-batches.py over plain eth_calls instead.
        if (vm.envOr("SAFE_TX_CONSOLE_JSON", false)) {
            _logTxsJson(txs, path);
            return;
        }

        string memory json = "json";
        // Default values
        vm.serializeString(json, "version", "1.0");
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeUint(json, "createdAt", block.timestamp * 1000);

        string memory serializedTxs = "[";
        for (uint i = 0; i < txs.length; i++) {
            if (i != 0) {
                serializedTxs = string.concat(serializedTxs, ",");
            }

            string memory transaction = "tx";
            vm.serializeAddress(transaction, "to", txs[i].to);
            vm.serializeString(
                transaction,
                "value",
                Strings.toString(txs[i].value)
            );
            vm.serializeString(transaction, "operation", "0");
            string memory serializedTx = vm.serializeBytes(
                transaction,
                "data",
                txs[i].data
            );

            serializedTxs = string.concat(serializedTxs, serializedTx);
        }
        serializedTxs = string.concat(serializedTxs, "]");

        string memory meta = "meta";
        vm.serializeString(meta, "name", "Transactions Batch");
        string memory serializedMeta = vm.serializeString(
            meta,
            "description",
            ""
        );

        vm.serializeString(json, "transactions", serializedTxs);
        string memory finalJson = vm.serializeString(
            json,
            "meta",
            serializedMeta
        );

        vm.writeJson({json: finalJson, path: path});

        string[] memory commands = new string[](4);
        // re-used commands to find-replace
        commands[0] = "sed";
        commands[1] = "-i";
        commands[3] = path;

        // Remove all backslashes
        commands[2] = "s/\\\\//g";
        vm.ffi(commands);

        // Replace `"[` with `[`]
        commands[2] = 's/\\"\\[/\\[/g';
        vm.ffi(commands);

        // Replace `]"` with `]`
        commands[2] = 's/\\]\\"/\\]/g';
        vm.ffi(commands);
    }

    /// @dev Emits the same Safe batch document as the cheatcode path, built purely with string
    ///      concatenation so it survives `forge --zksync`. Only console.log is used; vm.toString
    ///      is avoided too, since it is a cheatcode and the point here is to depend on none of
    ///      them. Field types match the cheatcode output exactly (chainId/createdAt numeric,
    ///      version/value/operation strings) so both paths produce interchangeable files.
    function _logTxsJson(SerializedTx[] memory txs, string memory path) internal view {
        string memory body = string.concat(
            '{"version":"1.0","chainId":',
            Strings.toString(block.chainid),
            ',"createdAt":',
            Strings.toString(block.timestamp * 1000),
            ',"meta":{"name":"Transactions Batch","description":""},"transactions":['
        );

        for (uint256 i = 0; i < txs.length; i++) {
            if (i != 0) {
                body = string.concat(body, ",");
            }
            body = string.concat(
                body,
                '{"to":"',
                Strings.toHexString(uint160(txs[i].to), 20),
                '","value":"',
                Strings.toString(txs[i].value),
                '","operation":"0","data":"',
                _bytesToHex(txs[i].data),
                '"}'
            );
        }

        body = string.concat(body, "]}");

        console.log(string.concat("SAFE_TX_JSON_BEGIN ", path));
        console.log(body);
        console.log("SAFE_TX_JSON_END");
    }

}