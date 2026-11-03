// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @title FixLegacyDVNsInherited
/// @notice Base contract for legacy OFT DVN upgrade scripts.
///         Legacy OFTs live on 4 chains: Ethereum (1), Metis (1088), Blast (81457), Base (8453).
///         All 6 legacy OFTs share the same address across all 4 chains.
///         Metis does NOT have a Frax DVN, so it stays at 2/2 (Horizen + L0).
contract FixLegacyDVNsInherited is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    /// @notice The 4 legacy chain IDs
    uint256[] public legacyChainIds;

    /// @notice The 6 legacy OFT addresses (same on all chains)
    address[] public legacyOftAddresses;

    /// @notice The 6 legacy OFT names (parallel to legacyOftAddresses)
    string[] public legacyOftNames;

    /// @notice Currently processing OFT name (set before simulateAndWriteTxs calls)
    string public currentOftName;

    /// @notice Legacy chain IDs that get the Frax DVN upgrade (excludes Metis)
    uint256[] public fraxDvnChainIds;

    constructor() {
        // Legacy chains
        legacyChainIds.push(1);     // Ethereum
        legacyChainIds.push(1088);  // Metis
        legacyChainIds.push(81457); // Blast
        legacyChainIds.push(8453);  // Base

        // 6 legacy OFTs (same address on all 4 chains)
        legacyOftAddresses.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // LFRAX
        legacyOftAddresses.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX
        legacyOftAddresses.push(0xF010a7c8877043681D59AD125EbF575633505942); // frxETH
        legacyOftAddresses.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sfrxETH
        legacyOftAddresses.push(0x23432452B720C80553458496D4D9d7C5003280d0); // FRAX
        legacyOftAddresses.push(0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d); // FPI

        // Parallel names array
        legacyOftNames.push("LFRAX");
        legacyOftNames.push("sFRAX");
        legacyOftNames.push("frxETH");
        legacyOftNames.push("sfrxETH");
        legacyOftNames.push("FRAX");
        legacyOftNames.push("FPI");

        // Chains that will get 3/3 DVN (Frax DVN added) — Metis excluded
        fraxDvnChainIds.push(1);     // Ethereum
        fraxDvnChainIds.push(81457); // Blast
        fraxDvnChainIds.push(8453);  // Base
    }

    /// @notice Find legacy L0Config by chain ID from legacyConfigs array
    function findLegacyConfig(uint256 _chainId) internal view returns (L0Config memory) {
        for (uint256 i = 0; i < legacyConfigs.length; i++) {
            if (legacyConfigs[i].chainid == _chainId) {
                return legacyConfigs[i];
            }
        }
        revert(string.concat("Legacy config not found for chainId: ", _chainId.toString()));
    }

    /// @notice Check if a chain has Frax DVN support
    function hasFraxDvn(uint256 _chainId) internal view returns (bool) {
        for (uint256 i = 0; i < fraxDvnChainIds.length; i++) {
            if (fraxDvnChainIds[i] == _chainId) return true;
        }
        return false;
    }

    function hasPeer(address _oft, uint32 _eid) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(_eid);
        return peer != bytes32(0);
    }
}
