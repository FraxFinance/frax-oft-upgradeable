// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev creates 34443 files with set DVNs for all chains- 

/*
Goal: change _configs from broadcastConfigArray to all configs as setupSource uses configs.
ie: through non-removal of old arrays (https://github.com/FraxFinance/frax-oft-upgradeable/pull/11),
  the prior DVN configurations were overwritten in setupSource() with invalid broadcastConfigArray DVN addrs.
*/

contract SetupSolana is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    bytes32[] solanaPeers;

    function version() public virtual override pure returns (uint256, uint256, uint256) {
        return (1, 0, 1);
    }

    /// @dev comments out requirements at end and setting of broadcastConfig
    function loadJsonConfig() public override {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/L0Config.json");
        json = vm.readFile(path);
        
        // load and write to persistent storage

        // legacy
        L0Config[] memory legacyConfigs_ = abi.decode(json.parseRaw(".Legacy"), (L0Config[]));
        for (uint256 i=0; i<legacyConfigs_.length; i++) {
            L0Config memory config_ = legacyConfigs_[i];
            // if (config_.chainid == chainid) {
            //     broadcastConfig = config_;
            //     broadcastConfigArray.push(config_);
            //     activeLegacy = true;
            // }
            legacyConfigs.push(config_);
            configs.push(config_);
        }

        // proxy (active deployment loaded as broadcastConfig)
        L0Config[] memory proxyConfigs_ = abi.decode(json.parseRaw(".Proxy"), (L0Config[]));
        for (uint256 i=0; i<proxyConfigs_.length; i++) {
            L0Config memory config_ = proxyConfigs_[i];
            // if (config_.chainid == chainid) {
            //     broadcastConfig = config_;
            //     broadcastConfigArray.push(config_);
            //     activeLegacy = false;
            // }
            proxyConfigs.push(config_);
            configs.push(config_);
        }
        // require(broadcastConfig.chainid != 0, "L0Config for source not loaded");
        // require(broadcastConfigArray.length == 1, "broadcastConfigArray does not equal 1");
    }

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/SetupSolana/txs/");
        string memory name = string.concat(simulateConfig.chainid.toString(), ".json");

        return string.concat(root, name);
    }


    function setUp() public override {
        super.setUp();

        // Load solana as the broadcastConfig
        L0Config[] memory nonEvmConfigs = abi.decode(json.parseRaw(".Non-EVM"), (L0Config[]));
        broadcastConfig = nonEvmConfigs[0];
        broadcastConfigArray.push(nonEvmConfigs[0]);

        // push bytes32 token addrs in the same order as deployFraxOFTUpgradeblesAndProxies()
        solanaPeers.push(0x402e86d1cfd2cde4fac63aa8d9892eca6d3c0e08e8335622124332a95df6c10c); // fxs
        solanaPeers.push(0x206fdd7d0be90d8ff93f6f7f4bd4d8b42ca8977317da0b7d2861299e3c589dd8); // sFrax
        solanaPeers.push(0x6a7942e4eb4938d5490d8187183d01123f515025f4244670aff7f8ecd2250d50); // sfrxEth
        solanaPeers.push(0x656d91ab3d464c05cd1345ce21c78e36140a36491e102fbb08c58af73aafe89b); // frax
        solanaPeers.push(0x94791ba0aae2b57460c63d36346392d849b22f39fd3eafad5bc82d01e352dde6); // frxEth
        solanaPeers.push(0x9876880bee04a9020e619b1be124ee307e03ca94bab4f32a7a22cfd2ccee3927); // fpi
    }

    function run() public override {
        // deploySource();
        // setupSource();
        setupDestinations();
    }

    /// @dev modified setPeers `_peerOfts`
    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public override simulateAndWriteTxs(_connectedConfig) {
        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: broadcastConfigArray
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: broadcastConfigArray
        });

        setPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: solanaPeers,
            _configs: broadcastConfigArray
        });
    }

    /// @dev modified optionsTypes
    function setEnforcedOptions(
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public override {
        // For each peer, default
        // https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/OFT.t.sol#L417
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);

        for (uint256 c=0; c<_configs.length; c++) {            
            uint32 eid = uint32(_configs[c].eid);

            // cannot set enforced options to self
            if (block.chainid == _configs[c].chainid) continue;

            enforcedOptionsParams.push(EnforcedOptionParam(eid, 1, optionsTypeOne));
            enforcedOptionsParams.push(EnforcedOptionParam(eid, 2, optionsTypeTwo));
        }

        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address connectedOft = _connectedOfts[o];
            bytes memory data = abi.encodeCall(
                IOAppOptionsType3.setEnforcedOptions,
                (
                    enforcedOptionsParams
                )
            );
            (bool success, ) = connectedOft.call(data);
            require(success, "Unable to setEnforcedOptions");
            serializedTxs.push(
                SerializedTx({
                    name: "setEnforcedOptions",
                    to: connectedOft,
                    value: 0,
                    data: data
                })
            );
        }
    }

    /// @dev _peerOfts modified from address to bytes32
    function setPeers(
        address[] memory _connectedOfts,
        bytes32[] memory _peerOfts,
        L0Config[] memory _configs
    ) public virtual {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address connectedOft = _connectedOfts[o];
            bytes32 peerOft = _peerOfts[o];
            for (uint256 c=0; c<_configs.length; c++) {
                uint32 eid = uint32(_configs[c].eid);

                // cannot set peer to self
                if (block.chainid == _configs[c].chainid) continue;

                bytes memory data = abi.encodeCall(
                    IOAppCore.setPeer,
                    (
                        eid, peerOft
                    )
                );
                (bool success, ) = connectedOft.call(data);
                require(success, "Unable to setPeer");
                serializedTxs.push(
                    SerializedTx({
                        name: "setPeer",
                        to: connectedOft,
                        value: 0,
                        data: data
                    })
                );
            }
        }
    }
}
