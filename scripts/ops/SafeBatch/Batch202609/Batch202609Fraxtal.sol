// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {OftConfigBatch, IFraxtalHub} from "../OftConfigBatch.sol";
import {HopAdminBatch} from "../HopAdminBatch.sol";

/// @notice One Safe transaction on Fraxtal (chain 252) for everything FRA-81 leaves on the hub.
///         1. FraxtalMintRedeemHop still registers remote hops for five retired chains — Blast,
///            Polygon zkEVM, Scroll, Mode, Berachain — so a compose from any of them would pass the
///            hub gate and die on a severed lane. De-register all five (the legacy FraxtalHop
///            already has them zeroed).
///         2. The six lockboxes carry dormant LayerZero config toward Plasma (30383), Blast (30243)
///            and Metis (30151): explicit ULN send/receive libraries, enforced options and DVN
///            config, with every peer already zero. Reset it (FPI toward Blast is already clean).
///         3. FRA-102: shuts down the first-generation HopV2 hub (fraxtal-lz-hop `HopV2 Mainnet`),
///            superseded by the hop-v2 hub 0x00000000e18aFc20…: pause, drop its Ethereum / Arbitrum /
///            Base spoke registrations and lockbox approvals, zero numDVNs, sweep its FRAX to the Safe.
///         4. FRA-100: Katana lane to 5/5 — Horizen now runs a DVN on Katana, so the five live lockboxes'
///            send and receive ULN config toward Katana (30375) goes from 4 to 5 required DVNs
///            (confirmations unchanged: 5 out, 60 in). Batch202609Katana does the mirror image plus
///            the hops' numDVNs; execute this one FIRST (Fraxtal then pays five DVNs before Katana
///            starts requiring five).
///         Items 1-3 touch no live route: Fraxtal peers none of those eids.
contract Batch202609Fraxtal is OftConfigBatch, HopAdminBatch {
    address public constant FRAXTAL_SAFE = 0x5f25218ed9474b721d6a38c115107428E832fA2E;
    address public constant FRAXTAL_MINT_REDEEM_HOP = 0x3e6a2cBaFD864e09e6DAb9Cf035a0AbEa32bc0BC;
    address public constant OLD_HOP_V2_HUB = 0xe8Cd13de17CeC6FCd9dD5E0a1465Da240f951536;

    address public constant WFRAX_LOCKBOX = 0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A;
    address public constant SFRXUSD_LOCKBOX = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
    address public constant SFRXETH_LOCKBOX = 0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168;
    address public constant FRXUSD_LOCKBOX = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
    address public constant FRXETH_LOCKBOX = 0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604;
    address public constant FPI_LOCKBOX = 0x75c38D46001b0F8108c4136216bd2694982C20FC;

    uint32 public constant ETHEREUM_EID = 30101;
    uint32 public constant ARBITRUM_EID = 30110;
    uint32 public constant BASE_EID = 30184;
    uint32 public constant KATANA_EID = 30375;
    uint64 public constant KATANA_SEND_CONFIRMATIONS = 5;
    uint64 public constant KATANA_RECEIVE_CONFIRMATIONS = 60;
    uint32 public constant PLASMA_EID = 30383;
    uint32 public constant BLAST_EID = 30243;
    uint32 public constant METIS_EID = 30151;
    uint32 public constant POLYGON_ZKEVM_EID = 30158;
    uint32 public constant SCROLL_EID = 30214;
    uint32 public constant MODE_EID = 30260;
    uint32 public constant BERACHAIN_EID = 30362;

    /// @dev FRA-131: spoke of the non-canonical "FPI" mesh (Ethereum adapter 0xE41228… on FRAX collateral),
    ///      retired: Ethereum already blocks that lane both ways, so retire every lane here the same
    ///      way (send blocked, peer cleared, receive blocked).
    address public constant BAD_FPI_OFT = 0xEed9DE5E41b53D1C8fAB8AAB4b0e446F828c1483;

    function badFpiEids() public pure returns (uint32[] memory eids) {
        uint32[8] memory fixedEids = [uint32(30101), 30184, 30243, 30151, 30260, 30280, 30274, 30168]; // Ethereum, Base, Blast, Metis, Mode, Sei, X-Layer, Solana
        eids = new uint32[](8);
        for (uint256 i = 0; i < 8; i++) {
            eids[i] = fixedEids[i];
        }
    }

    function safe() public pure override returns (address) {
        return FRAXTAL_SAFE;
    }

    function chainId() public pure override returns (uint256) {
        return 252;
    }

    function endpoint() public pure override returns (address) {
        return 0x1a44076050125825900e736c501f859c50fE728c;
    }

    function blockedLibrary() public pure override returns (address) {
        return 0x1ccBf0db9C192d969de57E25B3fF09A25bb1D862;
    }

    function sendUln302() public pure override returns (address) {
        return 0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6;
    }

    function receiveUln302() public pure override returns (address) {
        return 0x8bC1e36F015b9902B54b1387A4d733cebc2f5A4e;
    }

    function retiredHubEids() public pure returns (uint32[5] memory) {
        return [BLAST_EID, POLYGON_ZKEVM_EID, SCROLL_EID, MODE_EID, BERACHAIN_EID];
    }

    /// @dev Spokes still registered on the old HopV2 hub.
    function oldHopV2Eids() public pure returns (uint32[] memory eids) {
        eids = new uint32[](3);
        (eids[0], eids[1], eids[2]) = (ETHEREUM_EID, ARBITRUM_EID, BASE_EID);
    }

    /// @dev Fraxtal-side DVNs for the Katana lane, ascending: Frax, Canary, Nethermind, LayerZero, Horizen.
    function katanaDvns() public pure returns (address[] memory dvns) {
        dvns = new address[](5);
        dvns[0] = 0x26cD5aBaDf7eC3f0F02b48314bfcA6b2342cddD4;
        dvns[1] = 0x6398E91001Cc1682bBA103E6B2489Fa5675a5a64;
        dvns[2] = 0xa7b5189bcA84Cd304D8553977c7C614329750d99;
        dvns[3] = 0xcCE466a522984415bC91338c232d98869193D46e;
        dvns[4] = 0xDd7B5E1dB4AaFd5C8EC3b764eFB8ed265Aa5445B;
    }

    function lockboxes() public pure returns (address[] memory list) {
        list = new address[](6);
        (list[0], list[1], list[2]) = (WFRAX_LOCKBOX, SFRXUSD_LOCKBOX, SFRXETH_LOCKBOX);
        (list[3], list[4], list[5]) = (FRXUSD_LOCKBOX, FRXETH_LOCKBOX, FPI_LOCKBOX);
    }

    function _run() internal override {
        uint32[5] memory retired = retiredHubEids();
        for (uint256 i = 0; i < retired.length; i++) {
            IFraxtalHub(FRAXTAL_MINT_REDEEM_HOP).setRemoteHop(retired[i], bytes32(0));
        }

        address[] memory boxes = lockboxes();
        for (uint256 i = 0; i < boxes.length; i++) {
            _sever(boxes[i], PLASMA_EID, false, true);
            _sever(boxes[i], METIS_EID, false, true);
            if (boxes[i] != FPI_LOCKBOX) _sever(boxes[i], BLAST_EID, false, true);
        }

        _shutdownOldHopV2({_hop: OLD_HOP_V2_HUB, _eids: oldHopV2Eids(), _ofts: boxes, _clearSolanaExecutorOptions: false});

        _retireRoutes(BAD_FPI_OFT, badFpiEids(), true);

        address[] memory dvns = katanaDvns();
        for (uint256 i = 0; i < boxes.length; i++) {
            if (boxes[i] == FPI_LOCKBOX) continue; // FPI is retired: its Katana route is already severed
            _setRequiredDvns(boxes[i], KATANA_EID, sendUln302(), KATANA_SEND_CONFIRMATIONS, dvns);
            _setRequiredDvns(boxes[i], KATANA_EID, receiveUln302(), KATANA_RECEIVE_CONFIRMATIONS, dvns);
        }
    }
}
