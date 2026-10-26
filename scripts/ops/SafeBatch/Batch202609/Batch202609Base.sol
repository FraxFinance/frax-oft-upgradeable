// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {OftConfigBatch} from "../OftConfigBatch.sol";
import {HopAdminBatch} from "../HopAdminBatch.sol";

/// @notice One Safe transaction on Base (chain 8453).
///         1. FRA-102: shuts down BOTH first-generation HopV2 spokes — the one in the fraxtal-lz-hop
///            README (0x22beDD…) and the earlier one the old Fraxtal hub still registers for eid
///            30184 (0x7c5004F6…) — superseded by the hop-v2 RemoteHopV2 0x0000006D38…: pause, drop
///            the Fraxtal hub registration and the six OFT approvals, zero numDVNs, clear the Solana
///            executor options, sweep their ETH to the Safe.
///         2. Legacy OFT set (user-held supply): block the spoke-to-spoke send libraries toward Metis
///            and Blast-legacy; the lane into Ethereum-legacy, peers and receive config stay. Legacy
///            FPI (0.10 outstanding) is retired outright on all three lanes.
contract Batch202609Base is OftConfigBatch, HopAdminBatch {
    address public constant BASE_SAFE = 0xCBfd4Ef00a8cf91Fd1e1Fe97dC05910772c15E53;
    address public constant OLD_HOP_V2 = 0x22beDD55A0D29Eb31e75C70F54fADa7Ca94339B9;
    address public constant OLDER_HOP_V2 = 0x7C5004F64F86728b5d852CeEc7987333114b206d;
    uint32 public constant FRAXTAL_EID = 30255;
    uint32 public constant ETHEREUM_EID = 30101;
    uint32 public constant METIS_EID = 30151;
    uint32 public constant BLAST_EID = 30243;

    /// @dev FRA-131: spoke of the non-canonical "FPI" mesh (Ethereum adapter 0xE41228… on FRAX collateral),
    ///      retired: Ethereum already blocks that lane both ways, so retire every lane here the same
    ///      way (send blocked, peer cleared, receive blocked).
    address public constant BAD_FPI_OFT = 0xE41228a455700cAF09E551805A8aB37caa39D08c;

    function badFpiEids() public pure returns (uint32[] memory eids) {
        uint32[7] memory fixedEids = [uint32(30101), 30243, 30255, 30151, 30260, 30280, 30274]; // Ethereum, Blast, Fraxtal, Metis, Mode, Sei, X-Layer
        eids = new uint32[](7);
        for (uint256 i = 0; i < 7; i++) {
            eids[i] = fixedEids[i];
        }
    }

    function safe() public pure override returns (address) {
        return BASE_SAFE;
    }

    function chainId() public pure override returns (uint256) {
        return 8453;
    }

    function endpoint() public pure override returns (address) {
        return 0x1a44076050125825900e736c501f859c50fE728c;
    }

    function blockedLibrary() public pure override returns (address) {
        return 0x1ccBf0db9C192d969de57E25B3fF09A25bb1D862;
    }

    function sendUln302() public pure override returns (address) {
        return 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2;
    }

    function receiveUln302() public pure override returns (address) {
        return 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf;
    }

    function ofts() public pure returns (address[] memory list) {
        list = new address[](6);
        list[0] = 0x0CEAC003B0d2479BebeC9f4b2EBAd0a803759bbf; // WFRAX
        list[1] = 0x91A3f8a8d7a881fBDfcfEcd7A2Dc92a46DCfa14e; // sfrxUSD
        list[2] = 0x192e0C7Cc9B263D93fa6d472De47bBefe1Fb12bA; // sfrxETH
        list[3] = 0xe5020A6d073a794B6E7f05678707dE47986Fb0b6; // frxUSD
        list[4] = 0x7eb8d1E4E2D0C8b9bEDA7a97b305cF49F3eeE8dA; // frxETH
        list[5] = 0xEEdd3A0DDDF977462A97C1F0eBb89C3fbe8D084B; // FPI
    }

    function _run() internal override {
        uint32[] memory eids = new uint32[](1);
        eids[0] = FRAXTAL_EID;
        _shutdownOldHopV2({_hop: OLD_HOP_V2, _eids: eids, _ofts: ofts(), _clearSolanaExecutorOptions: true});
        _shutdownOldHopV2({_hop: OLDER_HOP_V2, _eids: eids, _ofts: ofts(), _clearSolanaExecutorOptions: true});

        _blockLegacySpokeLanes(METIS_EID, BLAST_EID);
        _retireRoutes(LEGACY_FPI, _eids3(ETHEREUM_EID, METIS_EID, BLAST_EID), true);

        _retireRoutes(BAD_FPI_OFT, badFpiEids(), true);
    }
}
