// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupSourceFraxOFTFraxtalHub.sol";
import { OFTAdapterUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTAdapterUpgradeable.sol";

// forge script scripts/FraxtalHub/2_SetupSourceFraxOFTFraxtalHub/SetupSourceFraxOFTFraxtalHubTempoTestnet.s.sol --rpc-url https://rpc.testnet.tempo.xyz --broadcast
contract SetupSourceFraxOFTFraxtalHubTempoTestnet is SetupSourceFraxOFTFraxtalHub {
    constructor() {
        frxUsdOft = 0x6A678cEfcA10d5bBe4638D27C671CE7d56865037; // frxUSD lockbox on tempo testnet

        proxyOfts.push(frxUsdOft);
    }

    function run() public override {
        require(
            isStringEqual(IERC20Metadata(OFTAdapterUpgradeable(frxUsdOft).token()).symbol(), "frxUSD"),
            "frxUsdOft != frxUSD"
        );
        for (uint256 i = 0; i < testnetConfigs.length; i++) {
            // Set up destinations for Ethereum Sepolia lockboxes only
            if (testnetConfigs[i].chainid == 11155111 || testnetConfigs[i].chainid == broadcastConfig.chainid) {
                tempConfigs.push(testnetConfigs[i]);
            }
        }

        require(tempConfigs.length == 2, "Incorrect tempConfigs array");

        delete testnetConfigs;
        for (uint256 i = 0; i < tempConfigs.length; i++) {
            testnetConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        setupSource();
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        setDVNs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: testnetConfigs });

        setLibs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: testnetConfigs });

        setPriviledgedRoles();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({ _connectedOfts: proxyOfts, _configs: testnetConfigs });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({ _connectedOfts: proxyOfts, _peerOfts: expectedTestnetProxyOfts, _configs: testnetConfigs });
    }

    function getPeerFromArray(address _oft, address[] memory _oftArray) public view override returns (address peer) {
        require(_oftArray.length == 1, "getPeerFromArray index mismatch");
        require(_oft != address(0), "getPeerFromArray() OFT == address(0)");
        /// @dev maintains array of deployFraxOFTUpgradeablesAndProxies(), where proxyOfts is pushed to in the respective order
        if (_oft == frxUsdOft || _oft == proxyFrxUsdOft) {
            peer = _oftArray[0];
        }
    }

    function setPriviledgedRoles() public override {
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;

        /// @dev transfer ownership of OFT
        for (uint256 o = 0; o < proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(0x0990be6dB8c785FBbF9deD8bAEc612A10CaE814b);
            Ownable(proxyOft).transferOwnership(0x0990be6dB8c785FBbF9deD8bAEc612A10CaE814b);
        }

        /// @dev transfer ownership of ProxyAdmin
        Ownable(proxyAdmin).transferOwnership(0x0990be6dB8c785FBbF9deD8bAEc612A10CaE814b);
    }
}
