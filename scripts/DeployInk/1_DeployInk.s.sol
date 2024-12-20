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


    /// @dev skip admin transfer
    function setupSource() public override broadcastAs(configDeployerPK) {
        setupEvms();
        setupNonEvms();

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        // setPriviledgedRoles();
    }
}