// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../../FraxtalHub/3_SetupDestinationFraxOFTFraxtalHub/SetupDestinationFraxOFTFraxtalHub.sol";

// forge script scripts/SepoliaHub/3_SetupDestinationFraxOFTSepoliaHub/SetupDestinationFraxOFTSepoliaHubTempoTestnet.s.sol --rpc-url https://ethereum-sepolia-rpc.publicnode.com --broadcast
contract SetupDestinationFraxOFTSepoliaTempoTestnet is SetupDestinationFraxOFTFraxtalHub {
    constructor() {
        frxUsdOft = 0x16FBfCF4970D4550791faF75AE9BaecE75C85A27; // frxUSD lockbox on tempo testnet

        proxyOfts.push(frxUsdOft);
    }

    function run() public override {
        // require(
        //     OFTUpgradeable(frxUsdOft).isPeer(40161, addressToBytes32(ethSepoliaFrxUsdLockbox)),
        //     "frxusdoft is not connected to sepolia"
        // );

        for (uint256 i; i < testnetConfigs.length; i++) {
            // Set up destinations for Tempo testnet lockboxes only
            if (testnetConfigs[i].chainid == 42431 || testnetConfigs[i].chainid == broadcastConfig.chainid) {
                tempConfigs.push(testnetConfigs[i]);
            }
        }

        require(tempConfigs.length == 2, "Incorrect tempConfigs array");

        delete testnetConfigs;
        for (uint256 i = 0; i < tempConfigs.length; i++) {
            testnetConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        setupDestinations();
    }

    function setupProxyDestinations() public override {
        setupDestination({ _connectedConfig: broadcastConfig });
    }

    function setupDestination(L0Config memory _connectedConfig) public override broadcastAs(configDeployerPK) {
        // store for later referencing
        simulateConfig = broadcastConfig;

        _populateConnectedOfts();

        setEvmEnforcedOptions({ _connectedOfts: connectedOfts, _configs: testnetConfigs });

        setEvmPeers({ _connectedOfts: connectedOfts, _peerOfts: proxyOfts, _configs: testnetConfigs });

        setDVNs({ _connectedConfig: _connectedConfig, _connectedOfts: connectedOfts, _configs: testnetConfigs });

        setLibs({ _connectedConfig: _connectedConfig, _connectedOfts: connectedOfts, _configs: testnetConfigs });
    }

    function getPeerFromArray(address _oft, address[] memory _oftArray) public view override returns (address peer) {
        require(_oftArray.length == 1, "getPeerFromArray index mismatch");
        require(_oft != address(0), "getPeerFromArray() OFT == address(0)");
        /// @dev maintains array of deployFraxOFTUpgradeablesAndProxies(), where proxyOfts is pushed to in the respective order
        if (_oft == frxUsdOft || _oft == proxyFrxUsdOft) {
            peer = _oftArray[0];
        }
    }

    function pushSerializedTx(string memory _name, address _to, uint256 _value, bytes memory _data) public override {}
}
