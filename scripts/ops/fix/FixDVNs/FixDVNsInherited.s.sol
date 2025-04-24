// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

contract FixDVNsInherited is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256[] public chainIds;

    constructor() {
        // Initialize the chainIds array with the desired chain IDs
        chainIds = [
            34443,  // mode
            1329,   // sei
            252,    // fraxtal
            196,    // xlayer
            146,    // sonic
            57073,  // ink
            42161,  // arbitrum
            10,     // optimism
            137,    // polygon
            43114,  // avalanche
            56,     // bsc
            1101,   // polygon zkevm
            1,      // ethereum,
            81457,  // blast
            8453,   // base
            80094,  // berachain
            59144,  // linea
            324,    // abstract
            2741    // zksync
        ];
    }
}