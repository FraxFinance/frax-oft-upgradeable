// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {OftConfigBatch, IMessageLibManager} from "../OftConfigBatch.sol";
import {HopAdminBatch} from "../HopAdminBatch.sol";

/// @notice One Safe transaction on Blast (chain 81457) for FRA-95 / FRA-56 (proxy OFT set only).
///         Blast was never rewired to the Fraxtal hub and no chain peers it back any more, but its
///         proxy OFTs still peer ten legacy-mesh chains (+ Ethereum on four of them) and carry
///         send/receive libraries, enforced options and DVN config toward thirteen eids, so a send
///         from Blast burns tokens into an unverifiable message.
///
///         Per route (5 OFTs x 13 eids): send library -> BlockedMessageLib, peer -> 0 where set,
///         receive library -> default, enforced options -> 0x0003, ULN app config -> empty on
///         both ULN302 libraries. FPI already has blocked send libraries everywhere except Metis;
///         only its leftover ULN config (and the Metis libraries) are reset.
///         Then the RemoteMintRedeemHop is retired like the RemoteHop already was (the 27-chain
///         legacy hop wind-down executed on Blast; the mint-redeem hop was left running).
///
///         Legacy OFT set (frxUSD 0x909DBdE1… etc., user-held supply): only the spoke-to-spoke send
///         libraries toward Metis and Base-legacy are blocked; the lane into Ethereum-legacy, peers
///         and receive config stay so holders keep their exit (see _blockLegacySpokeLanes). Legacy
///         FPI (0.06 outstanding) is retired outright on all three lanes.
///         Route state was read from Blast on 2026-09-21; the fork test asserts that pre-state so
///         drift fails loudly instead of reverting mid-batch (LZ_SameValue).
contract Batch202609Blast is OftConfigBatch, HopAdminBatch {
    address public constant BLAST_SAFE = 0x33A133020b2C2CD41a24F74033B11EC2fC0bF97a;

    address public constant WFRAX_OFT = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
    address public constant SFRXUSD_OFT = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address public constant SFRXETH_OFT = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
    address public constant FRXUSD_OFT = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address public constant FRXETH_OFT = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
    address public constant FPI_OFT = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;

    /// @dev Legacy V1 mint-redeem hop; the RemoteHop (0xe93Cb38f…) was already wound down.
    address public constant REMOTE_MINT_REDEEM_HOP = 0x85b1714b25f40FD5025423124c076476073180b3;

    uint32 public constant ETHEREUM_EID = 30101;
    uint32 public constant METIS_EID = 30151;
    uint32 public constant BASE_EID = 30184;
    uint32 public constant FRAXTAL_EID = 30255;

    /// @dev FRA-131: spoke of the non-canonical "FPI" mesh (Ethereum adapter 0xE41228… on FRAX collateral),
    ///      retired: Ethereum already blocks that lane both ways, so retire every lane here the same
    ///      way (send blocked, peer cleared, receive blocked).
    address public constant BAD_FPI_OFT = 0xE41228a455700cAF09E551805A8aB37caa39D08c;

    function badFpiEids() public pure returns (uint32[] memory eids) {
        uint32[7] memory fixedEids = [uint32(30101), 30184, 30255, 30151, 30260, 30280, 30274]; // Ethereum, Base, Fraxtal, Metis, Mode, Sei, X-Layer
        eids = new uint32[](7);
        for (uint256 i = 0; i < 7; i++) {
            eids[i] = fixedEids[i];
        }
    }

    function safe() public pure override returns (address) {
        return BLAST_SAFE;
    }

    function chainId() public pure override returns (uint256) {
        return 81457;
    }

    function endpoint() public pure override returns (address) {
        return 0x1a44076050125825900e736c501f859c50fE728c;
    }

    function blockedLibrary() public pure override returns (address) {
        return 0x1ccBf0db9C192d969de57E25B3fF09A25bb1D862;
    }

    function sendUln302() public pure override returns (address) {
        return 0xc1B621b18187F74c8F6D52a6F709Dd2780C09821;
    }

    function receiveUln302() public pure override returns (address) {
        return 0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6;
    }

    /// @dev Legacy-mesh eids every OFT below still peers.
    function peeredEids() public pure returns (uint32[10] memory) {
        return [uint32(30102), 30106, 30109, 30110, 30111, 30184, 30274, 30280, 30332, 30339];
    }

    function _run() internal override {
        address[5] memory ofts = [WFRAX_OFT, SFRXUSD_OFT, SFRXETH_OFT, FRXUSD_OFT, FRXETH_OFT];
        uint32[10] memory peered = peeredEids();
        for (uint256 i = 0; i < ofts.length; i++) {
            for (uint256 j = 0; j < peered.length; j++) {
                _sever(ofts[i], peered[j], true, true);
            }
            // Ethereum: peered by all but WFRAX (whose Ethereum counterpart is a different OFT).
            _sever(ofts[i], ETHEREUM_EID, ofts[i] != WFRAX_OFT, true);
            // Libraries and DVN config were set toward Metis and Fraxtal but peers never were.
            _sever(ofts[i], METIS_EID, false, true);
            _sever(ofts[i], FRAXTAL_EID, false, true);
        }

        // FPI: send libraries already blocked (except Metis), receive libraries default (except
        // Metis), enforced options cleared; only the ULN app config survived the FPI retirement.
        for (uint256 j = 0; j < peered.length; j++) {
            _zeroUlnConfig(FPI_OFT, peered[j]);
        }
        _zeroUlnConfig(FPI_OFT, ETHEREUM_EID);
        _zeroUlnConfig(FPI_OFT, FRAXTAL_EID);
        IMessageLibManager(endpoint()).setSendLibrary(FPI_OFT, METIS_EID, blockedLibrary());
        IMessageLibManager(endpoint()).setReceiveLibrary(FPI_OFT, METIS_EID, address(0), 0);
        _zeroUlnConfig(FPI_OFT, METIS_EID);

        _retireHopRouting(REMOTE_MINT_REDEEM_HOP);

        _blockLegacySpokeLanes(METIS_EID, BASE_EID);
        _retireRoutes(LEGACY_FPI, _eids3(ETHEREUM_EID, METIS_EID, BASE_EID), true);

        _retireRoutes(BAD_FPI_OFT, badFpiEids(), true);
    }
}
