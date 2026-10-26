// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {HopAdminBatch} from "../HopAdminBatch.sol";

/// @notice One Safe transaction on Arbitrum (chain 42161) for FRA-102: shuts down the
///         first-generation HopV2 spoke (fraxtal-lz-hop `HopV2 Mainnet`), superseded by the hop-v2
///         RemoteHopV2 0x0000006D38…: pause, drop the Fraxtal hub registration and the six OFT
///         approvals, zero numDVNs, clear the Solana executor options, sweep its ETH to the Safe.
contract Batch202609Arbitrum is HopAdminBatch {
    address public constant ARBITRUM_SAFE = 0x3da490b19F300E7cb2280426C8aD536dB2df445c;
    address public constant OLD_HOP_V2 = 0xf307Ad241E1035062Ed11F444740f108B8D036a6;
    uint32 public constant FRAXTAL_EID = 30255;

    function safe() public pure override returns (address) {
        return ARBITRUM_SAFE;
    }

    function chainId() public pure override returns (uint256) {
        return 42161;
    }

    function ofts() public pure returns (address[] memory list) {
        list = new address[](6);
        list[0] = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a; // WFRAX
        list[1] = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0; // sfrxUSD
        list[2] = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45; // sfrxETH
        list[3] = 0x80Eede496655FB9047dd39d9f418d5483ED600df; // frxUSD
        list[4] = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050; // frxETH
        list[5] = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927; // FPI
    }

    function _run() internal override {
        uint32[] memory eids = new uint32[](1);
        eids[0] = FRAXTAL_EID;
        _shutdownOldHopV2({_hop: OLD_HOP_V2, _eids: eids, _ofts: ofts(), _clearSolanaExecutorOptions: true});
    }
}
