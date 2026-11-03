// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {OftConfigBatch} from "../OftConfigBatch.sol";

/// @notice One Safe transaction on Sei (chain 1329) for FRA-131: retires the spoke of the non-canonical
///         "FPI" mesh (Ethereum adapter 0xE41228… on FRAX collateral, already dead on the Ethereum side
///         since 2026-08-26) — every lane: send blocked, peer cleared, receive blocked.
contract Batch202609Sei is OftConfigBatch {
    address public constant SAFE = 0x0357D02fc95320b990322d3ff69204c3D251171b;
    address public constant BAD_FPI_OFT = 0xEed9DE5E41b53D1C8fAB8AAB4b0e446F828c1483;

    function safe() public pure override returns (address) {
        return SAFE;
    }

    function chainId() public pure override returns (uint256) {
        return 1329;
    }

    function endpoint() public pure override returns (address) {
        return 0x1a44076050125825900e736c501f859c50fE728c;
    }

    function blockedLibrary() public pure override returns (address) {
        return 0x1ccBf0db9C192d969de57E25B3fF09A25bb1D862;
    }

    function sendUln302() public pure override returns (address) {
        return 0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7;
    }

    function receiveUln302() public pure override returns (address) {
        return 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043;
    }

    function badFpiEids() public pure returns (uint32[] memory eids) {
        uint32[8] memory fixedEids = [uint32(30101), 30184, 30243, 30255, 30151, 30260, 30274, 30168]; // Ethereum, Base, Blast, Fraxtal, Metis, Mode, X-Layer, Solana
        eids = new uint32[](8);
        for (uint256 i = 0; i < 8; i++) {
            eids[i] = fixedEids[i];
        }
    }

    function _run() internal override {
        _retireRoutes(BAD_FPI_OFT, badFpiEids(), true);
    }
}
