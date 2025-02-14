// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Used to setup a single destination to Aptos, for example BSC <> Aptos
// forge script scripts/ops/SetupAptos/SetupAptosSingle.s.sol --rpc-url https://bsc-dataseed.bnbchain.org
contract SetupAptosSingle is DeployFraxOFTProtocol {

    L0Config[] public aptosConfigArray;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/SetupAptos/txs/");
        string memory name = string.concat(simulateConfig.chainid.toString(), ".json");

        return string.concat(root, name);
    }

    function run() public override {
        for (uint256 i=0; i<nonEvmConfigs.length; i++) {
            if (nonEvmConfigs[i].eid == 30108) {
                aptosConfigArray.push(nonEvmConfgis[i]);
            }
        }
        require(aptosConfigArray.length == 1, "Aptos config not added");
        require(aptosConfigArray[0].eid == 30108, "Not aptos config");

        setupAptosDestinations();
    }

    function setupAptosDestinations() public virtual {
        setupAptosDestination(broadcastConfig);
    }

    function setupAptosDestination(L0Config memory _simulateConfig) simulateAndWriteTxs(_simulateConfig) public {
        /// @dev connectedOfts are set in BaseL0Script.simulateAndWriteTxs()

        setAptosEnforcedOptions({
            _connectedOfts: connectedOfts
        });

        setAptosPeers({
            _connectedConfig: _simulateConfig,
            _connectedOfts: connectedOfts
        });

        setDVNs({
            _connectedConfig: _simulateConfig,
            _connectedOfts: connectedOfts,
            _configs: aptosConfigArray
        });
    }

    function setAptosEnforcedOptions(
        address[] memory _connectedOfts
    ) public {
        // TODO: change these, [200_000, 2_500_000] is solana config
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);

        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: aptosConfigArray,
            _optionsTypeOne: optionsTypeOne,
            _optionsTypeTwo: optionsTypeTwo
        });
    }

    function setAptosPeers(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public {
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // aptos is nonEvmPeersArrays[1] from BaseL0Script.loadJsonConfig()
            setPeer({
                _config: _connectedConfig,
                _connectedOft: _connectedOfts[o],
                _peerOftAsBytes32: nonEvmPeersArrays[1][o]
            });
        }
    }
}