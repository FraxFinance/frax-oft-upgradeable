// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {SafeDelegateBatch} from "./SafeDelegateBatch.sol";

/// @dev Legacy V1 hop admin surface (fraxtal-lz-hop RemoteHop / RemoteMintRedeemHop, all onlyOwner).
///      Only the bytes32 setFraxtalHop overload is declared so the selector is unambiguous
///      (0x77958f87, the one the 27-chain legacy hop wind-down used).
interface ILegacyRemoteHop {
    function paused() external view returns (bool);
    function toggleOFTApproval(address _oft, bool _approved) external;
    function setExecutorOptions(uint32 eid, bytes calldata _options) external;
    function setFraxtalHop(bytes32 _fraxtalHop) external;
    function setNumDVNs(uint256 _numDVNs) external;
    function setHopFee(uint256 _hopFee) external;
    function pause(bool _paused) external;
}

/// @dev First-generation HopV2 (fraxtal-lz-hop `HopV2.sol`, AccessControl, DEFAULT_ADMIN_ROLE = chain
///      Safe). Only the bytes32 setRemoteHop overload is declared so the selector is unambiguous.
interface IOldHopV2 {
    function paused() external view returns (bool);
    function pauseOn() external;
    function setRemoteHop(uint32 _eid, bytes32 _remoteHop) external;
    function setApprovedOft(address _oft, bool _isApproved) external;
    function setNumDVNs(uint32 _numDVNs) external;
    function setExecutorOptions(uint32 eid, bytes calldata _options) external;
    function recover(address _target, uint256 _value, bytes calldata _data) external;
}

/// @notice Hop admin recipes for a SafeDelegateBatch (see SafeDelegateBatch.sol): V1 hop retirement,
///         first-generation HopV2 shutdown.
abstract contract HopAdminBatch is SafeDelegateBatch {
    uint32 public constant SOLANA_EID = 30168;

    /// @dev Tail of the 27-chain legacy hop wind-down recipe, shared by RemoteHop and
    ///      RemoteMintRedeemHop (the latter has no OFT approvals or executor options).
    function _retireHopRouting(address _hop) internal {
        ILegacyRemoteHop hop = ILegacyRemoteHop(_hop);
        // Hop setters have no same-value checks, so pin the replay guard here: a re-queued batch
        // must revert (GS013, nonce untouched) instead of silently succeeding.
        require(!hop.paused(), "HopAdminBatch: hop already retired");
        hop.setFraxtalHop(bytes32(0));
        hop.setNumDVNs(0);
        hop.setHopFee(0);
        hop.pause(true);
    }

    /// @dev FRA-102: shut down a first-generation HopV2 the way the V1 spokes were wound down —
    ///      pause, drop the hub/spoke registrations and OFT approvals, zero numDVNs, clear the only
    ///      executor options entry (Solana) where set, and sweep the native balance to the Safe.
    ///      `recover` is a plain call with the full gas stipend, so the Safe can receive directly,
    ///      and the amount is read at execution time so the payload can never go stale.
    function _shutdownOldHopV2(address _hop, uint32[] memory _eids, address[] memory _ofts, bool _clearSolanaExecutorOptions)
        internal
    {
        IOldHopV2 hop = IOldHopV2(_hop);
        require(!hop.paused(), "HopAdminBatch: HopV2 already shut down");
        hop.pauseOn();
        for (uint256 i = 0; i < _eids.length; i++) {
            hop.setRemoteHop(_eids[i], bytes32(0));
        }
        for (uint256 i = 0; i < _ofts.length; i++) {
            hop.setApprovedOft(_ofts[i], false);
        }
        hop.setNumDVNs(0);
        if (_clearSolanaExecutorOptions) hop.setExecutorOptions(SOLANA_EID, "");
        uint256 balance = _hop.balance;
        if (balance != 0) hop.recover(safe(), balance, "");
    }
}
