// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {OftConfigBatch} from "../OftConfigBatch.sol";
import {ILegacyRemoteHop} from "../HopAdminBatch.sol";

/// @notice One Safe transaction on Ethereum (chain 1) for FRA-56, run by the OFT admin Safe that is
///         the LayerZero delegate of every current lockbox.
///         The current lockboxes no longer peer Blast (30243) or Metis (30151) but sfrxUSD, sfrxETH,
///         frxUSD and frxETH still carry explicit ULN send/receive libraries, enforced options and
///         2-DVN config toward both, and FPI toward Metis. Reset them.
///         frxUSD is owned by a different Safe (0xfFFffF4F…, 4/7), so its two enforced-option
///         entries are left as they are: the Safe here is only its delegate. They are inert — the
///         route has no peer and its send library becomes BlockedMessageLib in this same call.
///
///         FRA-131: the non-canonical "FPI" adapter 0xE41228… (FRAX collateral, 30.06 FRAX held, no
///         recovery function) was retired toward its seven EVM spokes on 2026-08-26 (peers cleared,
///         send + receive blocked). Solana (30168, 0.00002 FPI outstanding) is its last live lane:
///         retire it the same way.
///
///         FRA-96: the legacy V1 RemoteHop 0x3ad4dC23… is paused but its 27-chain wind-down batch was
///         never executed on Ethereum (manual-queue chain): finish it — drop the six lockbox approvals
///         and the Solana executor options, zero fraxtalHop / numDVNs / hopFee. It holds no ETH.
///         The V1 RemoteMintRedeemHop 0x99B5587a… stays live: it is in daily use and has no successor.
///
///         Legacy mesh: FPI is retired outright (dust supply on the spokes) — the legacy FPI adapter
///         0x6Eca253b… already has its send libraries blocked, so clear its Metis / Base / Blast peers
///         and block receive. The other five legacy OFTs (frxUSD 0x909DBdE1… etc.) keep their
///         receive-only exit lanes untouched.
contract Batch202609Ethereum is OftConfigBatch {
    address public constant OFT_ADMIN_SAFE = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;

    address public constant SFRXUSD_LOCKBOX = 0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126;
    address public constant SFRXETH_LOCKBOX = 0xbBc424e58ED38dd911309611ae2d7A23014Bd960;
    address public constant FRXUSD_LOCKBOX = 0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0;
    address public constant FRXETH_LOCKBOX = 0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6;
    address public constant FPI_LOCKBOX = 0x9033BAD7aA130a2466060A2dA71fAe2219781B4b;

    /// @dev Non-canonical FPI OFT adapter (FixDeployFpi replaced it in Sep 2024).
    address public constant BAD_FPI_ADAPTER = 0xE41228a455700cAF09E551805A8aB37caa39D08c;
    /// @dev Legacy V1 RemoteHop (paused, wind-down never executed here).
    address public constant LEGACY_REMOTE_HOP = 0x3ad4dC2319394bB4BE99A0e4aE2AbF7bCEbD648E;
    address public constant WFRAX_LOCKBOX = 0x04ACaF8D2865c0714F79da09645C13FD2888977f;

    uint32 public constant BLAST_EID = 30243;
    uint32 public constant METIS_EID = 30151;
    uint32 public constant BASE_EID = 30184;
    uint32 public constant SOLANA_EID = 30168;

    function safe() public pure override returns (address) {
        return OFT_ADMIN_SAFE;
    }

    function chainId() public pure override returns (uint256) {
        return 1;
    }

    function endpoint() public pure override returns (address) {
        return 0x1a44076050125825900e736c501f859c50fE728c;
    }

    function blockedLibrary() public pure override returns (address) {
        return 0x1ccBf0db9C192d969de57E25B3fF09A25bb1D862;
    }

    function sendUln302() public pure override returns (address) {
        return 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    }

    function receiveUln302() public pure override returns (address) {
        return 0xc02Ab410f0734EFa3F14628780e6e695156024C2;
    }

    function _run() internal override {
        address[3] memory owned = [SFRXUSD_LOCKBOX, SFRXETH_LOCKBOX, FRXETH_LOCKBOX];
        for (uint256 i = 0; i < owned.length; i++) {
            _sever(owned[i], BLAST_EID, false, true);
            _sever(owned[i], METIS_EID, false, true);
        }
        _sever(FRXUSD_LOCKBOX, BLAST_EID, false, false);
        _sever(FRXUSD_LOCKBOX, METIS_EID, false, false);
        _sever(FPI_LOCKBOX, METIS_EID, false, true);

        uint32[] memory solana = new uint32[](1);
        solana[0] = SOLANA_EID;
        _retireRoutes(BAD_FPI_ADAPTER, solana, true);

        _retireRoutes(LEGACY_FPI, _eids3(METIS_EID, BASE_EID, BLAST_EID), false);

        // Finish the V1 RemoteHop wind-down (already paused, so no pause call and no replay guard
        // from _retireHopRouting; a replay reverts earlier on LZ_SameValue anyway).
        ILegacyRemoteHop hop = ILegacyRemoteHop(LEGACY_REMOTE_HOP);
        address[6] memory lockboxes = [WFRAX_LOCKBOX, SFRXUSD_LOCKBOX, SFRXETH_LOCKBOX, FRXUSD_LOCKBOX, FRXETH_LOCKBOX, FPI_LOCKBOX];
        for (uint256 i = 0; i < lockboxes.length; i++) {
            hop.toggleOFTApproval(lockboxes[i], false);
        }
        hop.setExecutorOptions(SOLANA_EID, "");
        hop.setFraxtalHop(bytes32(0));
        hop.setNumDVNs(0);
        hop.setHopFee(0);
    }
}
