// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev creates 34443 files with set DVNs for all chains- 

/*
Goal: change _configs from activeConfigArray to all configs as setupSource uses configs.
ie: through non-removal of old arrays (https://github.com/FraxFinance/frax-oft-upgradeable/pull/11),
  the prior DVN configurations were overwritten in setupSource() with invalid activeConfigArray DVN addrs.
*/

contract SetupSolana is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    /// @dev override to alter file save location
    modifier simulateAndWriteTxs(L0Config memory _config) override {
        // Clear out arrays
        delete enforcedOptionsParams;
        delete setConfigParams;
        delete serializedTxs;

        vm.createSelectFork(_config.RPC);
        chainid = _config.chainid;
        vm.startPrank(_config.delegate);
        _;
        vm.stopPrank();

        // create filename and save
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/SetupSolana/txs/");
        string memory filename = string.concat(_config.chainid.toString(), ".json");
        
        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }


    function setUp() public override {
        super.setUp();

        // Load solana as the activeConfig
        L0Config[] memory nonEvmConfigs = abi.decode(json.parseRaw(".Legacy"), (L0Config[]));
        activeConfig = nonEvmConfigs[0];
        activeConfigArray.push(nonEvmConfigs[0]);
    }

    function run() public override {
        // deploySource();
        // setupSource();
        setupDestinations();
    }

    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public override simulateAndWriteTxs(_connectedConfig) {
        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: activeConfigArray
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: configs
        });

        setPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: proxyOfts,
            _configs: configs
        });

    /// @dev additional option added to optionsType2
    function setEnforcedOptions(
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public override {
        // For each peer, default
        // https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/OFT.t.sol#L417
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000, 0).addExecutorComposeOption(0, 0, 0);

        for (uint256 c=0; c<_configs.length; c++) {            
            uint32 eid = uint32(_configs[c].eid);

            // cannot set enforced options to self
            if (chainid == activeConfig.chainid && eid == activeConfig.eid) continue;

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
    }
}
