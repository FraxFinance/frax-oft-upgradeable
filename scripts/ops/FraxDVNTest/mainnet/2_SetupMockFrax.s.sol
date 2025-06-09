// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { Constant } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/test/util/Constant.sol";

struct UlnConfig {
    uint64 confirmations;
    // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
    uint8 requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNThreshold; // (0, optionalDVNCount]
    address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
    address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
}

contract SetupMockFrax is DeployFraxOFTProtocol {
    constructor() {
        delete connectedOfts;
        connectedOfts.push(sepoliaOFT);
        proxyOfts.push(arbSepoliaOFT);
    }

    function _validateAndPopulateMainnetOfts() internal override {
        // check to prevent array mismatch.  This will trigger when, for example, managing peers of 2 of 6 OFTs as
        // this method asumes we're managing all 6 OFTs
        require(proxyOfts.length == 6, "proxyOfts.length != 6");

        /// @dev order maintained through L0Constants.sol `constructor()` and DeployFraxOFTProtocol.s.sol `deployFraxOFTUpgradeablesAndProxies()`
        if (simulateConfig.chainid == 1) {
            connectedOfts[0] = ethLockboxes[0];
            connectedOfts[1] = ethLockboxes[1];
            connectedOfts[2] = ethLockboxes[2];
            connectedOfts[3] = ethLockboxes[3];
            connectedOfts[4] = ethLockboxes[4];
            connectedOfts[5] = ethLockboxes[5];
        } else if (simulateConfig.chainid == 252) {
            // TODO: modify this readme to "Fraxtal Lockboxes"
            // https://github.com/FraxFinance/frax-oft-upgradeable?tab=readme-ov-file#fraxtal-standalone-frxusdsfrxusd-lockboxes
            connectedOfts[0] = fraxtalLockboxes[0];
            connectedOfts[1] = fraxtalLockboxes[1];
            connectedOfts[2] = fraxtalLockboxes[2];
            connectedOfts[3] = fraxtalLockboxes[3];
            connectedOfts[4] = fraxtalLockboxes[4];
            connectedOfts[5] = fraxtalLockboxes[5];
        } else if (simulateConfig.chainid == 8453) {
            connectedOfts[0] = baseProxyOfts[0];
            connectedOfts[1] = baseProxyOfts[1];
            connectedOfts[2] = baseProxyOfts[2];
            connectedOfts[3] = baseProxyOfts[3];
            connectedOfts[4] = baseProxyOfts[4];
            connectedOfts[5] = baseProxyOfts[5];
        } else if (simulateConfig.chainid == 59144) {
            connectedOfts[0] = lineaProxyOfts[0];
            connectedOfts[1] = lineaProxyOfts[1];
            connectedOfts[2] = lineaProxyOfts[2];
            connectedOfts[3] = lineaProxyOfts[3];
            connectedOfts[4] = lineaProxyOfts[4];
            connectedOfts[5] = lineaProxyOfts[5];
        } else if (simulateConfig.chainid == 8453) {
            connectedOfts[0] = baseProxyOfts[0];
            connectedOfts[1] = baseProxyOfts[1];
            connectedOfts[2] = baseProxyOfts[2];
            connectedOfts[3] = baseProxyOfts[3];
            connectedOfts[4] = baseProxyOfts[4];
            connectedOfts[5] = baseProxyOfts[5];
        } else if (simulateConfig.chainid == 2741 || simulateConfig.chainid == 324) {
            connectedOfts[0] = zkEraProxyOfts[0];
            connectedOfts[1] = zkEraProxyOfts[1];
            connectedOfts[2] = zkEraProxyOfts[2];
            connectedOfts[3] = zkEraProxyOfts[3];
            connectedOfts[4] = zkEraProxyOfts[4];
            connectedOfts[5] = zkEraProxyOfts[5];
        } else {
            // https://github.com/FraxFinance/frax-oft-upgradeable?tab=readme-ov-file#proxy-upgradeable-ofts
            connectedOfts[0] = expectedProxyOfts[0];
            connectedOfts[1] = expectedProxyOfts[1];
            connectedOfts[2] = expectedProxyOfts[2];
            connectedOfts[3] = expectedProxyOfts[3];
            connectedOfts[4] = expectedProxyOfts[4];
            connectedOfts[5] = expectedProxyOfts[5];
        }
    }

    function run() public override {
        setupSource();
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();

        /// @dev configures legacy configs as well
        setDVNs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: allConfigs });

        setLibs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: allConfigs });

        // setPriviledgedRoles();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({ _connectedOfts: proxyOfts, _configs: proxyConfigs });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({ _connectedOfts: proxyOfts, _peerOfts: connectedOfts, _configs: proxyConfigs });
    }

    function setEnforcedOptions(
        address[] memory _connectedOfts,
        L0Config[] memory _configs,
        bytes memory _optionsTypeOne,
        bytes memory _optionsTypeTwo
    ) public override {
        // clear out any pre-existing enforced options params
        delete enforcedOptionParams;

        // Build enforced options for each chain
        for (uint256 c = 0; c < _configs.length; c++) {
            // destination peer should only be set
            if (_configs[c].eid != sepoliaPeerId) continue;
            // cannot set enforced options to self
            if (block.chainid == _configs[c].chainid) continue;

            enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 1, _optionsTypeOne));
            enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 2, _optionsTypeTwo));
        }

        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            setEnforcedOption({ _connectedOft: _connectedOfts[o] });
        }
    }

    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "connectedOfts.length != _peerOfts.length");
        // For each OFT
        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            // Set the config per chain
            for (uint256 c = 0; c < _configs.length; c++) {
                // destination peer should only be set
                if (_configs[c].eid != sepoliaPeerId) continue;
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(_peerOfts[o])
                });
            }
        }
    }

    function setDVNs(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public override {
        UlnConfig memory ulnConfig;
        ulnConfig.requiredDVNCount = 2;
        address[] memory requiredDVNs = new address[](2);

        // skip setting up DVN if the address is null
        if (_connectedConfig.dvnHorizen == address(0)) return;

        // sort in ascending order (as spec'd in UlnConfig)
        if (uint160(_connectedConfig.dvnHorizen) < uint160(_connectedConfig.dvnL0)) {
            requiredDVNs[0] = _connectedConfig.dvnHorizen;
            requiredDVNs[1] = _connectedConfig.dvnL0;
        } else {
            requiredDVNs[0] = _connectedConfig.dvnL0;
            requiredDVNs[1] = _connectedConfig.dvnHorizen;
        }
        ulnConfig.requiredDVNs = requiredDVNs;

        // push allConfigs
        for (uint256 c = 0; c < _configs.length; c++) {
            // only set config for destination
            if (_configs[c].eid != sepoliaPeerId) continue;
            // cannot set enforced options to self
            if (block.chainid == _configs[c].chainid) continue;

            setConfigParams.push(
                SetConfigParam({
                    eid: uint32(_configs[c].eid),
                    configType: Constant.CONFIG_TYPE_ULN,
                    config: abi.encode(ulnConfig)
                })
            );
        }

        // Submit txs to set DVN
        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            address endpoint = _connectedConfig.endpoint;

            // receiveLib
            bytes memory data = abi.encodeCall(
                IMessageLibManager.setConfig,
                (_connectedOfts[o], _connectedConfig.receiveLib302, setConfigParams)
            );
            (bool success, ) = endpoint.call(data);
            require(success, "Unable to setConfig for receiveLib");
            serializedTxs.push(SerializedTx({ name: "setConfig for receiveLib", to: endpoint, value: 0, data: data }));

            // sendLib
            data = abi.encodeCall(
                IMessageLibManager.setConfig,
                (_connectedOfts[o], _connectedConfig.sendLib302, setConfigParams)
            );
            (success, ) = endpoint.call(data);
            require(success, "Unable to setConfig for sendLib");
            serializedTxs.push(SerializedTx({ name: "setConfig for sendLib", to: endpoint, value: 0, data: data }));
        }
    }

    function setLibs(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public override {
        // for each oft
        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            // for each destination
            for (uint256 c = 0; c < _configs.length; c++) {
                // only set config for destination
                if (_configs[c].eid != sepoliaPeerId) continue;
                setLib({ _connectedConfig: _connectedConfig, _connectedOft: _connectedOfts[o], _config: _configs[c] });
            }
        }
    }

    function setPriviledgedRoles() public override {}
}
