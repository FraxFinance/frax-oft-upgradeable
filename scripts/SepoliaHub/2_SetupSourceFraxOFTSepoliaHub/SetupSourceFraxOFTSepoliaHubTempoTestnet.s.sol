// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../../FraxtalHub/2_SetupSourceFraxOFTFraxtalHub/SetupSourceFraxOFTFraxtalHub.sol";
import { OFTAdapterUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTAdapterUpgradeable.sol";

// forge script scripts/SepoliaHub/2_SetupSourceFraxOFTSepoliaHub/SetupSourceFraxOFTSepoliaHubTempoTestnet.s.sol --rpc-url https://rpc.moderato.tempo.xyz --broadcast
contract SetupSourceFraxOFTSepoliaHubTempoTestnet is SetupSourceFraxOFTFraxtalHub {
    constructor() {
        frxUsdOft = 0x16FBfCF4970D4550791faF75AE9BaecE75C85A27; // frxUSD lockbox on tempo testnet

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
        proxyAdmin = 0x394E4F810Bde9Eb786018Def607951021c470051;

        /// @dev transfer ownership of OFT
        for (uint256 o = 0; o < proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(0x1d434906Aa520E592fAB2b82406BEfF859be8e82);
            Ownable(proxyOft).transferOwnership(0x1d434906Aa520E592fAB2b82406BEfF859be8e82);
        }

        /// @dev transfer ownership of ProxyAdmin
        Ownable(proxyAdmin).transferOwnership(0x1d434906Aa520E592fAB2b82406BEfF859be8e82);
    }
}
