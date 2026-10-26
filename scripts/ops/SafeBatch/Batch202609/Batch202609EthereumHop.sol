// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {HopAdminBatch} from "../HopAdminBatch.sol";

/// @notice One Safe transaction on Ethereum (chain 1) for FRA-102, run by the Hop Safe (0x6cCF3F2C…,
///         DEFAULT_ADMIN of the old hop — a different Safe from the OFT admin that runs
///         Batch202609Ethereum, hence a second contract on this chain). Shuts down the
///         first-generation HopV2 spoke (fraxtal-lz-hop `HopV2 Mainnet`), superseded by the hop-v2
///         RemoteHopV2 0x0000006D38…: pause, drop the Fraxtal hub registration and the six lockbox
///         approvals, zero numDVNs, clear the Solana executor options, sweep its ETH to the Safe.
contract Batch202609EthereumHop is HopAdminBatch {
    address public constant HOP_SAFE = 0x6cCF3F2Ca29591F90ADB403D67E4dcB49cEcC634;
    address public constant OLD_HOP_V2 = 0xFd3B410b82a00B2651b42A13837204c5e3D92e27;
    uint32 public constant FRAXTAL_EID = 30255;

    function safe() public pure override returns (address) {
        return HOP_SAFE;
    }

    function chainId() public pure override returns (uint256) {
        return 1;
    }

    function lockboxes() public pure returns (address[] memory list) {
        list = new address[](6);
        list[0] = 0x04ACaF8D2865c0714F79da09645C13FD2888977f; // WFRAX
        list[1] = 0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126; // sfrxUSD
        list[2] = 0xbBc424e58ED38dd911309611ae2d7A23014Bd960; // sfrxETH
        list[3] = 0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0; // frxUSD
        list[4] = 0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6; // frxETH
        list[5] = 0x9033BAD7aA130a2466060A2dA71fAe2219781B4b; // FPI
    }

    function _run() internal override {
        uint32[] memory eids = new uint32[](1);
        eids[0] = FRAXTAL_EID;
        _shutdownOldHopV2({_hop: OLD_HOP_V2, _eids: eids, _ofts: lockboxes(), _clearSolanaExecutorOptions: true});
    }
}
