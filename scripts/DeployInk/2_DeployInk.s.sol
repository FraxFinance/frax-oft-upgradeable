// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Deploy to ink and maintain control of proxyAdmin until msig is setup
// forge script scripts/DeployInk/1_DeployInk.s.sol --rpc-url https://rpc-gel.inkonchain.com --verify --verifier blockscout --verifier-url https://explorer.inkonchain.com/api/
contract DeployInk is DeployFraxOFTProtocol {

    // Remove solana config as the chain is not yet supported
    function setUp() public override {
        super.setUp();

        // Solana is the last config added to all configs, therefore we can pop() to remove
        allConfigs.pop();
    }

    // override fraxtal frxUSD, sfrxUSD with standalone lockboxes
    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                address peerOft = _peerOfts[o];
                // for fraxtal
                if (_configs[c].chainid == 252) {
                    if (_connectedOfts[o] == 0x80Eede496655FB9047dd39d9f418d5483ED600df) {
                        // standalone frxUSD lockbox
                        peerOft = address(0);
                    } else if (_connectedOfts[o] == 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0) {
                        peerOft = address(0);
                    }
                }
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(/*_peerOfts[o]*/ peerOft)
                });
            }
        }
    }
}