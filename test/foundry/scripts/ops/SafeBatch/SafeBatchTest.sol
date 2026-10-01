// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SafeDelegateBatch} from "scripts/ops/SafeBatch/SafeDelegateBatch.sol";
import {OftConfigBatch} from "scripts/ops/SafeBatch/OftConfigBatch.sol";

interface ISafe {
    function nonce() external view returns (uint256);
    function getThreshold() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
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

interface IEndpointView {
    function getSendLibrary(address _sender, uint32 _eid) external view returns (address);
    function getReceiveLibrary(address _receiver, uint32 _eid) external view returns (address, bool);
}

interface IOAppView {
    function peers(uint32 _eid) external view returns (bytes32);
    function enforcedOptions(uint32 _eid, uint16 _msgType) external view returns (bytes memory);
}

/// @dev One entry of a Safe Tx Builder payload. Field order is alphabetical because that is how
///      forge encodes a JSON object into a tuple; `operation` and `value` are strings there.
struct PayloadTx {
    bytes data;
    string operation;
    address to;
    string value;
}

interface IUlnView {
    function getAppUlnConfig(address _oapp, uint32 _remoteEid)
        external
        view
        returns (OftConfigBatch.UlnConfig memory);
}

/// @notice Pre-flight harness for a SafeDelegateBatch: runs it through the REAL Safe on a fork as one
///         delegatecall and pins the safety envelope — it executes without reverting (so no route has
///         drifted into LZ_SameValue), it writes storage only to the accounts it declares, it changes
///         only the LayerZero routes it declares (everything else on the chain, the canonical mesh
///         included, stays byte-identical), a replay reverts instead of burning a Safe nonce, and its
///         runtime code holds no opcode that could corrupt the Safe through delegatecall.
///
///         This is campaign tooling: delete the per-campaign suites once their batches have executed,
///         since their pre-state assumptions are true only until then.
abstract contract SafeBatchTest is Test {
    uint8 internal constant OPERATION_DELEGATECALL = 1;

    SafeDelegateBatch internal helper;
    address internal endpoint;
    address internal sendUln;
    address internal receiveUln;

    /// @dev Reads the chain constants off the batch under test.
    function _bind(OftConfigBatch batch) internal {
        helper = batch;
        endpoint = batch.endpoint();
        sendUln = batch.sendUln302();
        receiveUln = batch.receiveUln302();
    }

    /// @dev Accounts this batch may write storage to; its Safe is allowed implicitly.
    function _expectedWriteAccounts() internal virtual returns (address[] memory);

    /// @dev OFTs whose every route is fingerprinted before/after. Empty = skip the route audit
    ///      (batches that touch no LayerZero config).
    function _auditedOfts() internal virtual returns (address[] memory) {
        return new address[](0);
    }

    /// @dev Routes this batch may change, as (oft, eid).
    function _isExpectedRoute(address, uint32) internal virtual returns (bool) {
        return false;
    }

    /// @notice Executes, then proves nothing outside the declared accounts had storage written.
    function test_WritesOnlyToExpectedAccounts() public {
        address[] memory expected = _expectedWriteAccounts();

        vm.startStateDiffRecording();
        assertTrue(_execViaSafe(), "Safe execution failed");
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        for (uint256 i = 0; i < accesses.length; i++) {
            if (accesses[i].reverted) continue;
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; j++) {
                Vm.StorageAccess memory sa = accesses[i].storageAccesses[j];
                if (!sa.isWrite || sa.reverted || sa.previousValue == sa.newValue) continue;
                bool ok = sa.account == helper.safe();
                for (uint256 k = 0; k < expected.length && !ok; k++) {
                    ok = sa.account == expected[k];
                }
                if (!ok) {
                    emit log_named_address("unexpected storage write to", sa.account);
                    fail();
                }
            }
        }
    }

    /// @notice Executes, then proves every route it did not declare — the canonical mesh included —
    ///         is byte-identical: peer, send library, receive library, enforced options, ULN config.
    function test_ChangesOnlyExpectedRoutes() public {
        address[] memory ofts = _auditedOfts();
        if (ofts.length == 0) return;
        uint32[] memory eids = _meshEids();

        bytes32[][] memory before = new bytes32[][](ofts.length);
        for (uint256 i = 0; i < ofts.length; i++) {
            before[i] = new bytes32[](eids.length);
            for (uint256 j = 0; j < eids.length; j++) {
                before[i][j] = _routeFingerprint(ofts[i], eids[j]);
            }
        }

        assertTrue(_execViaSafe(), "Safe execution failed");

        uint256 changed;
        for (uint256 i = 0; i < ofts.length; i++) {
            for (uint256 j = 0; j < eids.length; j++) {
                if (_routeFingerprint(ofts[i], eids[j]) == before[i][j]) continue;
                changed++;
                if (!_isExpectedRoute(ofts[i], eids[j])) {
                    emit log_named_address("unexpected route change on OFT", ofts[i]);
                    emit log_named_uint("  eid", eids[j]);
                    fail();
                }
            }
        }
        assertTrue(changed > 0, "batch changed no route at all");
        emit log_named_uint("routes changed (all declared)", changed);
    }

    /// @notice A re-queued batch reverts (GS013, safeTxGas == 0) instead of consuming a Safe nonce.
    ///         Batches that deliberately tolerate a re-run override this — see the Katana suite.
    function test_SecondExecutionRevertsInsteadOfConsumingNonce() public virtual {
        assertTrue(_execViaSafe(), "first execution failed");
        ISafe safe = ISafe(helper.safe());
        uint256 nonceAfterFirst = safe.nonce();
        (bytes memory data, bytes memory signatures, address executor) = _prepareSafeTx();
        vm.expectRevert(bytes("GS013"));
        vm.prank(executor);
        safe.execTransaction(
            address(helper), 0, data, OPERATION_DELEGATECALL, 0, 0, 0, address(0), payable(address(0)), signatures
        );
        assertEq(safe.nonce(), nonceAfterFirst, "nonce consumed by a failed replay");
    }

    /// @notice The delegatecall-safety invariant: the batch cannot touch the Safe's own storage.
    function test_NoStorageOrDangerousOpcodesInExecutableCode() public {
        bytes memory code = address(helper).code;
        uint256 cborLength = (uint256(uint8(code[code.length - 2])) << 8) | uint256(uint8(code[code.length - 1]));
        uint256 executableEnd = code.length - 2 - cborLength;
        for (uint256 i; i < executableEnd; i++) {
            uint8 op = uint8(code[i]);
            assertTrue(op != 0x54 && op != 0x55, "SLOAD/SSTORE in delegatecall target");
            assertTrue(op != 0x5c && op != 0x5d, "TLOAD/TSTORE in delegatecall target");
            assertTrue(op != 0xf0 && op != 0xf5, "CREATE in delegatecall target");
            assertTrue(op != 0xf2 && op != 0xf4, "CALLCODE/DELEGATECALL in delegatecall target");
            assertTrue(op != 0xff, "SELFDESTRUCT in delegatecall target");
            if (op >= 0x60 && op <= 0x7f) i += op - 0x5f; // skip PUSH data
        }
    }

    /// @notice Where a Safe Transaction Service refuses `operation = 1` (Blast and Sei: they trust
    ///         only MultiSendCallOnly, which cannot delegatecall inward), the batch ships instead as
    ///         ordinary Tx Builder payloads extracted from it by DeprecateFromSafeBatch.s.sol. This proves the
    ///         two are the same operation: run the payloads as plain calls from the Safe, run the
    ///         batch as a delegatecall from the same pre-state, and require that every storage slot
    ///         either path leaves changed is the same slot holding the same value.
    ///
    ///         The Safe's own storage is excluded — one route burns one nonce, the other burns as
    ///         many as it has payloads, which is the whole difference between them.
    function test_PlainCallBatchesMatchTheDelegatecall() public {
        string[] memory files = _plainCallFiles();
        if (files.length == 0) return;
        emit log_named_uint("payload files", files.length);

        // Both folds live in memory: vm.revertTo below restores this contract's storage too, so
        // anything recorded on the way there would be erased before the comparison.
        uint256 snapshot = vm.snapshot();

        vm.startStateDiffRecording();
        uint256 sent = _sendPlainCalls(files);
        Writes memory plain = _fold(vm.stopAndReturnStateDiff());
        emit log_named_uint("plain calls executed", sent);

        assertTrue(vm.revertTo(snapshot), "could not restore the pre-state");

        vm.startStateDiffRecording();
        assertTrue(_execViaSafe(), "Safe execution failed");
        Writes memory delegated = _fold(vm.stopAndReturnStateDiff());

        uint256 changed = _assertSameNetWrites(plain, delegated, "plain calls");
        _assertSameNetWrites(delegated, plain, "the delegatecall");
        assertTrue(changed > 0, "the payloads changed nothing");
        emit log_named_uint("storage slots changed identically by both routes", changed);
    }

    /// @dev Directory of Tx Builder payloads this batch must be equivalent to. Empty = no check.
    ///      Every file in it is executed; the payloads are one route each and independent, so the
    ///      order they come back in cannot change the result.
    function _plainCallDir() internal virtual returns (string memory) {
        return "";
    }

    function _plainCallFiles() internal virtual returns (string[] memory files) {
        string memory dir = _plainCallDir();
        if (bytes(dir).length == 0) return new string[](0);

        Vm.DirEntry[] memory entries = vm.readDir(dir);
        files = new string[](entries.length);
        uint256 n;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].isDir) continue;
            files[n++] = entries[i].path;
        }
        assembly {
            mstore(files, n)
        }
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = i + 1; j < n; j++) {
                if (keccak256(bytes(files[j])) != keccak256(bytes(files[i])) && _lessThan(files[j], files[i])) {
                    (files[i], files[j]) = (files[j], files[i]);
                }
            }
        }
    }

    function _lessThan(string memory a, string memory b) private pure returns (bool) {
        bytes memory x = bytes(a);
        bytes memory y = bytes(b);
        uint256 shorter = x.length < y.length ? x.length : y.length;
        for (uint256 i = 0; i < shorter; i++) {
            if (x[i] != y[i]) return uint8(x[i]) < uint8(y[i]);
        }
        return x.length < y.length;
    }

    function _sendPlainCalls(string[] memory files) private returns (uint256 sent) {
        for (uint256 f = 0; f < files.length; f++) {
            // Decoding `.transactions` as a tuple array rather than `.transactions[*].to`: the
            // wildcard collapses to a scalar when a payload holds exactly one transaction, and
            // one route per file means plenty of them do.
            string memory json = vm.readFile(files[f]);
            PayloadTx[] memory txs = abi.decode(vm.parseJson(json, ".transactions"), (PayloadTx[]));
            for (uint256 i = 0; i < txs.length; i++) {
                assertEq(txs[i].operation, "0", "payload transaction is not a CALL");
                assertEq(txs[i].value, "0", "payload transaction sends value");
                vm.prank(helper.safe());
                (bool ok,) = txs[i].to.call(txs[i].data);
                if (!ok) {
                    emit log_named_string("payload call reverted in", files[f]);
                    emit log_named_uint("  index", i);
                    fail();
                }
                sent++;
            }
        }
    }

    /// @dev Net effect of a run: per (account, slot), the value before the first write and after the
    ///      last one. A slot written and written back nets out and is not a change to the chain.
    struct Writes {
        bytes32[] keys;
        bytes32[] prev;
        bytes32[] last;
        uint256 n;
    }

    function _fold(Vm.AccountAccess[] memory accesses) private view returns (Writes memory w) {
        uint256 cap;
        for (uint256 i = 0; i < accesses.length; i++) {
            cap += accesses[i].storageAccesses.length;
        }
        w.keys = new bytes32[](cap);
        w.prev = new bytes32[](cap);
        w.last = new bytes32[](cap);

        for (uint256 i = 0; i < accesses.length; i++) {
            if (accesses[i].reverted) continue;
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; j++) {
                Vm.StorageAccess memory sa = accesses[i].storageAccesses[j];
                if (!sa.isWrite || sa.reverted || sa.account == helper.safe()) continue;
                bytes32 key = keccak256(abi.encode(sa.account, sa.slot));
                uint256 at = _find(w, key);
                if (at == type(uint256).max) {
                    w.keys[w.n] = key;
                    w.prev[w.n] = sa.previousValue;
                    at = w.n++;
                }
                w.last[at] = sa.newValue;
            }
        }
    }

    function _find(Writes memory w, bytes32 key) private pure returns (uint256) {
        for (uint256 i = 0; i < w.n; i++) {
            if (w.keys[i] == key) return i;
        }
        return type(uint256).max;
    }

    /// @dev Every slot `a` really changed, `b` left holding the same value. Returns the count.
    function _assertSameNetWrites(Writes memory a, Writes memory b, string memory label)
        private
        returns (uint256 changed)
    {
        for (uint256 i = 0; i < a.n; i++) {
            if (a.prev[i] == a.last[i]) continue;
            changed++;
            uint256 at = _find(b, a.keys[i]);
            if (at == type(uint256).max || b.last[at] != a.last[i]) {
                emit log_named_string("a storage slot changed only by", label);
                emit log_named_bytes32("  slot key", a.keys[i]);
                emit log_named_bytes32("  it wrote", a.last[i]);
                emit log_named_bytes32("  the other route left", at == type(uint256).max ? a.prev[i] : b.last[at]);
                fail();
            }
        }
    }

    function _execViaSafe() internal returns (bool) {
        (bytes memory data, bytes memory signatures, address executor) = _prepareSafeTx();
        vm.prank(executor);
        return ISafe(helper.safe()).execTransaction(
            address(helper), 0, data, OPERATION_DELEGATECALL, 0, 0, 0, address(0), payable(address(0)), signatures
        );
    }

    /// @dev Threshold owners pre-approve the hash and sign with the v == 1 "approved hash" type,
    ///      which is what the Safe UI submits once each hardware wallet has confirmed.
    function _prepareSafeTx() internal returns (bytes memory data, bytes memory signatures, address executor) {
        ISafe safe = ISafe(helper.safe());
        data = abi.encodeCall(SafeDelegateBatch.execute, ());
        bytes32 txHash = safe.getTransactionHash(
            address(helper), 0, data, OPERATION_DELEGATECALL, 0, 0, 0, address(0), address(0), safe.nonce()
        );
        address[] memory owners = safe.getOwners();
        for (uint256 i = 0; i < owners.length; i++) {
            for (uint256 j = i + 1; j < owners.length; j++) {
                if (owners[j] < owners[i]) (owners[i], owners[j]) = (owners[j], owners[i]);
            }
        }
        for (uint256 i = 0; i < safe.getThreshold(); i++) {
            vm.prank(owners[i]);
            safe.approveHash(txHash);
            signatures = abi.encodePacked(signatures, bytes32(uint256(uint160(owners[i]))), bytes32(0), uint8(1));
        }
        executor = owners[0];
    }

    /// @dev Every eid in the Frax mesh: the proxy chains, the legacy four and the non-EVM three.
    function _meshEids() internal pure returns (uint32[] memory eids) {
        uint32[33] memory list = [
            uint32(30101), 30102, 30106, 30108, 30109, 30110, 30111, 30151, 30158, 30165, 30168,
            30183, 30184, 30211, 30214, 30243, 30255, 30260, 30274, 30280, 30319, 30320, 30324,
            30325, 30332, 30339, 30362, 30367, 30370, 30375, 30380, 30383, 30390
        ];
        eids = new uint32[](list.length);
        for (uint256 i = 0; i < list.length; i++) {
            eids[i] = list[i];
        }
    }

    function _routeFingerprint(address oft, uint32 eid) internal view returns (bytes32) {
        bytes32 peer;
        try IOAppView(oft).peers(eid) returns (bytes32 p) {
            peer = p;
        } catch {}
        address sendLib;
        try IEndpointView(endpoint).getSendLibrary(oft, eid) returns (address l) {
            sendLib = l;
        } catch {}
        address recvLib;
        bool recvDefault;
        try IEndpointView(endpoint).getReceiveLibrary(oft, eid) returns (address l, bool d) {
            (recvLib, recvDefault) = (l, d);
        } catch {}
        bytes memory eo1;
        bytes memory eo2;
        try IOAppView(oft).enforcedOptions(eid, 1) returns (bytes memory e) {
            eo1 = e;
        } catch {}
        try IOAppView(oft).enforcedOptions(eid, 2) returns (bytes memory e) {
            eo2 = e;
        } catch {}
        bytes memory ulnSend;
        bytes memory ulnRecv;
        try IUlnView(sendUln).getAppUlnConfig(oft, eid) returns (OftConfigBatch.UlnConfig memory c) {
            ulnSend = abi.encode(c);
        } catch {}
        try IUlnView(receiveUln).getAppUlnConfig(oft, eid) returns (OftConfigBatch.UlnConfig memory c) {
            ulnRecv = abi.encode(c);
        } catch {}
        return keccak256(abi.encode(peer, sendLib, recvLib, recvDefault, eo1, eo2, ulnSend, ulnRecv));
    }
}
