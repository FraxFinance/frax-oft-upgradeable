// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {OftConfigBatch} from "../OftConfigBatch.sol";
import {HopAdminBatch, ILegacyRemoteHop} from "../HopAdminBatch.sol";

/// @notice One Safe transaction on Plasma (chain 9745) for FRA-81 / the Plasma sub-issue.
///         1. Severs the Fraxtal (eid 30255) route on all six Plasma OFTs, which still peer the
///            Fraxtal lockboxes even though Fraxtal dropped its Plasma peers on 2025-12-31 (36 calls).
///         2. Retires the four legacy V1 hops the Safe owns (two deploy sets from the unmerged
///            fraxtal-lz-hop `ops/plasma-hub` branch, never registered on the Fraxtal hubs) with
///            the recipe the 27-chain legacy hop wind-down applied to every other spoke: drop OFT
///            approvals, clear executor options, zero fraxtalHop / numDVNs / hopFee, pause.
///            recoverETH is omitted: all four hold 0 XPL.
contract Batch202609Plasma is OftConfigBatch, HopAdminBatch {
    address public constant PLASMA_SAFE = 0x7d99C7737751b044DF4fA10aeEFA31532dd11DBE;
    uint32 public constant FRAXTAL_EID = 30255;

    address public constant WFRAX_OFT = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
    address public constant SFRXUSD_OFT = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address public constant SFRXETH_OFT = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
    address public constant FRXUSD_OFT = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address public constant FRXETH_OFT = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
    address public constant FPI_OFT = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;

    // Legacy V1 hops: 2025-10-06 deploy (the pair in the Linear ticket) and the 2025-12-03 redeploy.
    address public constant REMOTE_HOP_2025_10 = 0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2;
    address public constant REMOTE_MINT_REDEEM_HOP_2025_10 = 0xb85A8FDa7F5e52E32fa5582847CFfFee9456a5Dc;
    address public constant REMOTE_HOP_2025_12 = 0x7c3915dde9058b3271A490B68d1315FDF4C60fbd;
    address public constant REMOTE_MINT_REDEEM_HOP_2025_12 = 0x3d94797D3d1A40d94bf41A2E2aaAA15ecac71E45;

    function safe() public pure override returns (address) {
        return PLASMA_SAFE;
    }

    function chainId() public pure override returns (uint256) {
        return 9745;
    }

    function endpoint() public pure override returns (address) {
        return 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    }

    function blockedLibrary() public pure override returns (address) {
        return 0xC1cE56B2099cA68720592583C7984CAb4B6d7E7a;
    }

    function sendUln302() public pure override returns (address) {
        return 0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7;
    }

    function receiveUln302() public pure override returns (address) {
        return 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043;
    }

    function _run() internal override {
        address[6] memory ofts = [WFRAX_OFT, SFRXUSD_OFT, SFRXETH_OFT, FRXUSD_OFT, FRXETH_OFT, FPI_OFT];
        for (uint256 i = 0; i < ofts.length; i++) {
            _sever({_oft: ofts[i], _eid: FRAXTAL_EID, _clearPeer: true, _clearEnforcedOptions: true});
        }

        _retireRemoteHop({_hop: REMOTE_HOP_2025_10, _clearSolanaExecutorOptions: false});
        _retireRemoteHop({_hop: REMOTE_HOP_2025_12, _clearSolanaExecutorOptions: true});
        _retireHopRouting(REMOTE_MINT_REDEEM_HOP_2025_10);
        _retireHopRouting(REMOTE_MINT_REDEEM_HOP_2025_12);
    }

    function _retireRemoteHop(address _hop, bool _clearSolanaExecutorOptions) internal {
        ILegacyRemoteHop hop = ILegacyRemoteHop(_hop);
        hop.toggleOFTApproval(FRXUSD_OFT, false);
        hop.toggleOFTApproval(SFRXUSD_OFT, false);
        hop.toggleOFTApproval(FRXETH_OFT, false);
        hop.toggleOFTApproval(SFRXETH_OFT, false);
        hop.toggleOFTApproval(WFRAX_OFT, false);
        hop.toggleOFTApproval(FPI_OFT, false);
        if (_clearSolanaExecutorOptions) hop.setExecutorOptions(SOLANA_EID, "");
        _retireHopRouting(_hop);
    }
}
