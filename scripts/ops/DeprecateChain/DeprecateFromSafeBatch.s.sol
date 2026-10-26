// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

import "./DeprecateOFTBase.s.sol";
import {SafeDelegateBatch} from "scripts/ops/SafeBatch/SafeDelegateBatch.sol";
import {IMessageLibManager as IBatchLibManager} from "scripts/ops/SafeBatch/OftConfigBatch.sol";

interface ISafeExec {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function nonce() external view returns (uint256);
    function approveHash(bytes32 hashToApprove) external;
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
}

interface ISymbol {
    function symbol() external view returns (string memory);
}

/// @notice Third iteration strategy alongside DeprecateChain (all tokens, one chain) and
///         DeprecateToken (all chains, one token): **all the work a deployed SafeDelegateBatch
///         does**, written out as this directory's usual per-token, per-peer Safe batches.
///
///         Why it exists: a batch contract is one Safe transaction of four bytes, which is the
///         cheapest thing to sign — but some Safe Transaction Services refuse `operation = 1`
///         outright (Blast and Sei trust only MultiSendCallOnly, which cannot delegatecall inward),
///         and a hardware wallet that cannot stream a large EIP-712 message cannot sign a big
///         MultiSend either. Splitting one route per file solves both: ordinary calls, and each
///         file is the same size as every other Deprecate-* batch this directory has produced.
///
///         The calls are not re-derived from chain state the way DeprecateOFTBase derives them.
///         They are recorded off the deployed, verified batch by replaying it on a fork through the
///         real Safe and keeping every call the Safe itself makes — so the payloads cannot drift
///         from the contract that was reviewed, and they cover the things L0Config knows nothing
///         about (the legacy OFT set, the non-canonical FPI mesh, a V1 hop's admin calls).
///
///         Usage:
///           BATCH=0xebd44fa2… forge script scripts/ops/DeprecateChain/DeprecateFromSafeBatch.s.sol \
///             --ffi --rpc-url https://rpc.blast.io
///
///         Env:
///           BATCH  the deployed SafeDelegateBatch to replay (required; must be pinned to this chain)
///           DIR    output folder under txs/ (default: batch-<chainid>)
///
///         Writes txs/<DIR>/Deprecate-<thisChain>-<peerChain>-<LABEL>.json, one per (token, peer),
///         plus Deprecate-<thisChain>-admin-<LABEL>.json for calls that belong to no route.
///         Each file is independently executable: a route's calls never span two files, and every
///         call closes a route, so any subset leaves the chain more closed than it was, never less.
contract DeprecateFromSafeBatch is DeprecateOFTBase {
    using Strings for uint256;

    uint8 internal constant OPERATION_DELEGATECALL = 1;

    bytes4 internal constant SET_SEND_LIBRARY = IBatchLibManager.setSendLibrary.selector;
    bytes4 internal constant SET_RECEIVE_LIBRARY = IBatchLibManager.setReceiveLibrary.selector;
    bytes4 internal constant SET_CONFIG = IBatchLibManager.setConfig.selector;
    bytes4 internal constant SET_PEER = bytes4(keccak256("setPeer(uint32,bytes32)"));
    bytes4 internal constant SET_ENFORCED_OPTIONS = bytes4(keccak256("setEnforcedOptions((uint32,uint16,bytes)[])"));

    /// @dev Filled per file before `filename()` is read.
    address public currentSubject;
    uint32 public currentEid;

    /// @dev Distinct subjects across the whole batch, and the label each file uses for them.
    address[] public subjects;
    string[] public subjectLabels;

    function outputDir() public view override returns (string memory) {
        return string.concat(
            vm.projectRoot(),
            "/scripts/ops/DeprecateChain/txs/",
            vm.envOr("DIR", string.concat("batch-", block.chainid.toString())),
            "/"
        );
    }

    /// @dev Same shape as DeprecateOFTBase.filename(), but the token part is resolved from the
    ///      subject contract rather than from a canonical token index — this batch also touches the
    ///      legacy OFT set and two non-canonical FPI adapters, several of which share a symbol.
    function filename() public view override returns (string memory) {
        return string.concat(
            outputDir(), "Deprecate-", block.chainid.toString(), "-", _peerPart(), "-", _labelOf(currentSubject), ".json"
        );
    }

    function run() public override {
        SafeDelegateBatch batch = SafeDelegateBatch(vm.envAddress("BATCH"));
        require(batch.chainId() == block.chainid, "batch is pinned to another chain");
        address safe = batch.safe();

        SerializedTx[] memory calls = _record(batch, safe);
        console.log("recorded calls:", calls.length);

        address[] memory subject = new address[](calls.length);
        uint32[] memory eid = new uint32[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (subject[i], eid[i]) = _routeOf(calls[i]);
            _rememberSubject(subject[i]);
        }
        _labelSubjects();

        vm.createDir(outputDir(), true);
        uint256 written;
        for (uint256 i = 0; i < calls.length; i++) {
            if (_firstIndexOf(subject, eid, subject[i], eid[i]) != i) continue; // already written

            uint256 n;
            for (uint256 j = i; j < calls.length; j++) {
                if (subject[j] == subject[i] && eid[j] == eid[i]) n++;
            }
            SerializedTx[] memory group = new SerializedTx[](n);
            uint256 k;
            for (uint256 j = i; j < calls.length; j++) {
                if (subject[j] == subject[i] && eid[j] == eid[i]) group[k++] = calls[j];
            }

            currentSubject = subject[i];
            currentEid = eid[i];
            _writeBatch(group, filename());
            written++;
        }
        console.log("files written:", written);
    }

    /// @dev Streams one Safe Tx Builder batch with cheatcodes alone — same document, field for
    ///      field, as `SafeTxUtil.writeTxs`. Deploying SafeTxUtil mid-script reverts on some forks
    ///      (seen on Base and Fraxtal) and its in-memory JSON building cannot pay the memory gas for
    ///      a large admin group, and this needs neither a CREATE nor the memory.
    function _writeBatch(SerializedTx[] memory txs, string memory path) internal {
        vm.writeFile(
            path,
            string.concat(
                '{"chainId":', block.chainid.toString(),
                ',"createdAt":', (block.timestamp * 1000).toString(),
                ',"meta":{"description":"","name":"Transactions Batch"},"transactions":['
            )
        );
        for (uint256 i = 0; i < txs.length; i++) {
            vm.writeLine(
                path,
                string.concat(
                    '{"data":"', vm.toString(txs[i].data),
                    '","operation":"0","to":"', vm.toString(txs[i].to),
                    '","value":"', txs[i].value.toString(),
                    i + 1 == txs.length ? '"}' : '"},'
                )
            );
        }
        vm.writeLine(path, '],"version":"1.0"}');
    }

    // -------------------------------------------------------------------------------------------
    // recording
    // -------------------------------------------------------------------------------------------

    /// @dev Runs the batch through the real Safe and keeps every call the Safe itself made. Inside a
    ///      delegatecall the batch runs as the Safe, so those have `accessor == safe` — exactly the
    ///      list a plain-call batch has to reproduce.
    function _record(SafeDelegateBatch batch, address safe) internal returns (SerializedTx[] memory) {
        ISafeExec s = ISafeExec(safe);
        bytes memory data = abi.encodeCall(SafeDelegateBatch.execute, ());
        bytes32 txHash = s.getTransactionHash(
            address(batch), 0, data, OPERATION_DELEGATECALL, 0, 0, 0, address(0), address(0), s.nonce()
        );

        address[] memory owners = s.getOwners();
        for (uint256 i = 0; i < owners.length; i++) {
            for (uint256 j = i + 1; j < owners.length; j++) {
                if (owners[j] < owners[i]) (owners[i], owners[j]) = (owners[j], owners[i]);
            }
        }
        bytes memory signatures;
        for (uint256 i = 0; i < s.getThreshold(); i++) {
            vm.prank(owners[i]);
            s.approveHash(txHash);
            signatures = abi.encodePacked(signatures, bytes32(uint256(uint160(owners[i]))), bytes32(0), uint8(1));
        }

        vm.startStateDiffRecording();
        vm.prank(owners[0]);
        bool ok = s.execTransaction(
            address(batch), 0, data, OPERATION_DELEGATECALL, 0, 0, 0, address(0), payable(address(0)), signatures
        );
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        require(ok, "batch reverted on the fork");

        uint256 count;
        for (uint256 i = 0; i < accesses.length; i++) {
            if (_isSafeCall(accesses[i], safe)) count++;
        }
        SerializedTx[] memory calls = new SerializedTx[](count);
        uint256 k;
        for (uint256 i = 0; i < accesses.length; i++) {
            if (!_isSafeCall(accesses[i], safe)) continue;
            calls[k] = SerializedTx({
                name: "call",
                to: accesses[i].account,
                value: accesses[i].value,
                data: accesses[i].data
            });
            k++;
        }
        return calls;
    }

    function _isSafeCall(VmSafe.AccountAccess memory access, address safe) internal pure returns (bool) {
        return access.kind == VmSafe.AccountAccessKind.Call && access.accessor == safe && !access.reverted
            && access.data.length >= 4 && access.account != safe;
    }

    // -------------------------------------------------------------------------------------------
    // routing a call to its (token, peer) file
    // -------------------------------------------------------------------------------------------

    /// @dev Which OApp and which remote eid a call belongs to. A call carrying more than one eid
    ///      would have to span two files, so this refuses rather than guessing — the batches here
    ///      write one eid per `setConfig` / `setEnforcedOptions` call.
    function _routeOf(SerializedTx memory call) internal pure returns (address subject, uint32 eid) {
        bytes4 selector = bytes4(call.data);
        bytes memory args = _args(call.data);

        if (selector == SET_SEND_LIBRARY) {
            (subject, eid,) = abi.decode(args, (address, uint32, address));
        } else if (selector == SET_RECEIVE_LIBRARY) {
            (subject, eid,,) = abi.decode(args, (address, uint32, address, uint256));
        } else if (selector == SET_CONFIG) {
            IBatchLibManager.SetConfigParam[] memory params;
            (subject,, params) = abi.decode(args, (address, address, IBatchLibManager.SetConfigParam[]));
            require(params.length > 0, "setConfig with no params");
            eid = params[0].eid;
            for (uint256 i = 1; i < params.length; i++) {
                require(params[i].eid == eid, "setConfig spans several eids");
            }
        } else if (selector == SET_ENFORCED_OPTIONS) {
            EnforcedOptionParam[] memory params = abi.decode(args, (EnforcedOptionParam[]));
            require(params.length > 0, "setEnforcedOptions with no params");
            (subject, eid) = (call.to, params[0].eid);
            for (uint256 i = 1; i < params.length; i++) {
                require(params[i].eid == eid, "setEnforcedOptions spans several eids");
            }
        } else if (selector == SET_PEER) {
            (eid,) = abi.decode(args, (uint32, bytes32));
            subject = call.to;
        } else {
            // Admin calls on a hop or similar: no route, so they share one per-contract file.
            subject = call.to;
            eid = 0;
        }
    }

    function _args(bytes memory data) internal pure returns (bytes memory args) {
        args = new bytes(data.length - 4);
        for (uint256 i = 4; i < data.length; i++) {
            args[i - 4] = data[i];
        }
    }

    function _firstIndexOf(address[] memory subject, uint32[] memory eid, address wantSubject, uint32 wantEid)
        internal
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < subject.length; i++) {
            if (subject[i] == wantSubject && eid[i] == wantEid) return i;
        }
        revert("unreachable");
    }

    // -------------------------------------------------------------------------------------------
    // naming
    // -------------------------------------------------------------------------------------------

    /// @dev The peer half of the filename: the peer's chain id where L0Config knows it, else the
    ///      eid itself, and "admin" for calls that belong to no route.
    function _peerPart() internal view returns (string memory) {
        if (currentEid == 0) return "admin";
        uint256 chainid = _chainIdForEid(currentEid);
        return chainid == 0 ? string.concat("eid", uint256(currentEid).toString()) : chainid.toString();
    }

    function _chainIdForEid(uint32 eid) internal view returns (uint256) {
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].eid == eid) return proxyConfigs[i].chainid;
        }
        for (uint256 i = 0; i < legacyConfigs.length; i++) {
            if (legacyConfigs[i].eid == eid) return legacyConfigs[i].chainid;
        }
        for (uint256 i = 0; i < nonEvmConfigs.length; i++) {
            if (nonEvmConfigs[i].eid == eid) return nonEvmConfigs[i].chainid;
        }
        // Chains dropped from L0Config when they left the mesh still appear in these batches, since
        // the point is to clean up what was left pointing at them.
        if (eid == 30260) return 34443; // Mode
        return 0;
    }

    function _rememberSubject(address subject) internal {
        for (uint256 i = 0; i < subjects.length; i++) {
            if (subjects[i] == subject) return;
        }
        subjects.push(subject);
    }

    /// @dev Labels are the contract's own `symbol()` plus the head of its address. The symbol alone
    ///      would be a trap: a chain can hold several contracts answering "FPI" or "frxUSD" — the
    ///      canonical OFT, the legacy adapter, the non-canonical mesh's adapter — and only some of
    ///      them are being touched. The address says which one this file is for, including against
    ///      contracts that appear nowhere in the batch.
    function _labelSubjects() internal {
        for (uint256 i = 0; i < subjects.length; i++) {
            string memory symbol = _symbolOf(subjects[i]);
            subjectLabels.push(
                bytes(symbol).length == 0
                    ? _shortAddress(subjects[i])
                    : string.concat(symbol, "-", _shortAddress(subjects[i]))
            );
        }
    }

    function _labelOf(address subject) internal view returns (string memory) {
        for (uint256 i = 0; i < subjects.length; i++) {
            if (subjects[i] == subject) return subjectLabels[i];
        }
        revert("unlabelled subject");
    }

    /// @dev Empty when the contract has no symbol — a hop, for instance — leaving the address to
    ///      name the file on its own.
    function _symbolOf(address subject) internal view returns (string memory) {
        try ISymbol(subject).symbol() returns (string memory symbol) {
            bytes memory raw = bytes(symbol);
            bytes memory out = new bytes(raw.length);
            uint256 n;
            for (uint256 i = 0; i < raw.length; i++) {
                uint8 c = uint8(raw[i]);
                if (c >= 0x61 && c <= 0x7a) c -= 32; // lowercase -> uppercase
                bool keep = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a);
                if (keep) out[n++] = bytes1(c);
            }
            if (n > 0) {
                assembly {
                    mstore(out, n)
                }
                return string(out);
            }
        } catch {}
        return "";
    }

    /// @dev First four bytes of the address, lowercase hex, no prefix.
    function _shortAddress(address subject) internal pure returns (string memory) {
        bytes16 hexChars = "0123456789abcdef";
        bytes memory out = new bytes(8);
        for (uint256 i = 0; i < 4; i++) {
            uint8 b = uint8(uint160(subject) >> (8 * (19 - i)));
            out[i * 2] = hexChars[b >> 4];
            out[i * 2 + 1] = hexChars[b & 0x0f];
        }
        return string(out);
    }
}
