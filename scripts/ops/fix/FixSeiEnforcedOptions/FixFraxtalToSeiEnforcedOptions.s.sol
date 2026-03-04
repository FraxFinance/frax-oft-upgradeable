// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/**
 * @title FixFraxtalToSeiEnforcedOptions
 * @notice Update enforced options on Fraxtal lockboxes for messages going to Sei
 * @dev Required due to Sei governance proposal #109 increasing SSTORE cost from 20k to 72k gas
 *      https://www.mintscan.io/sei/proposals/109
 * 
 * Run command:
 * forge script scripts/ops/fix/FixSeiEnforcedOptions/FixFraxtalToSeiEnforcedOptions.s.sol --rpc-url https://rpc.frax.com
 */
contract FixFraxtalToSeiEnforcedOptions is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;

    L0Config[] seiConfigAsArray;

    // Sei EID
    uint256 constant SEI_EID = 30280;

    /// @notice Override with higher gas limits to account for Sei's SSTORE cost increase (20k -> 72k)
    function setEvmEnforcedOptions(
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public override {
        // Increased gas: 200k -> 300k for SEND, 250k -> 350k for SEND_AND_CALL
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300_000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(350_000, 0);

        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: _configs,
            _optionsTypeOne: optionsTypeOne,
            _optionsTypeTwo: optionsTypeTwo
        });
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/scripts/ops/fix/FixSeiEnforcedOptions/txs/FixFraxtalToSeiEnforcedOptions.json");
    }

    function run() public override simulateAndWriteTxs(broadcastConfig) {
        // Set up Fraxtal lockboxes as the connected OFTs
        delete proxyOfts;
        proxyOfts.push(fraxtalFraxLockbox);      // WFRAX
        proxyOfts.push(fraxtalSFrxUsdLockbox);   // sfrxUSD
        proxyOfts.push(fraxtalSFrxEthLockbox);   // sfrxETH
        proxyOfts.push(fraxtalFrxUsdLockbox);    // frxUSD
        proxyOfts.push(fraxtalFrxEthLockbox);    // frxETH
        proxyOfts.push(fraxtalFpiLockbox);       // FPI

        // Find Sei config from proxyConfigs
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].eid == SEI_EID) {
                seiConfigAsArray.push(proxyConfigs[i]);
            }
        }
        require(seiConfigAsArray.length == 1, "Sei config not found or duplicated");
        require(seiConfigAsArray[0].eid == SEI_EID, "Did not add correct Sei EID");

        // Set enforced options with higher gas for Sei (uses overridden setEvmEnforcedOptions)
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: seiConfigAsArray
        });
    }
}
