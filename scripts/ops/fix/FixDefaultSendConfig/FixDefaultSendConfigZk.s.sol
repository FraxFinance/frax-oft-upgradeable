// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { ExecutorConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";


import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/*
Sets the default config of the SendLib for each EVM chain so that the values are not 0
    - maxMessageSize:
        - EVM: 10,000
        - Solana: 200
        - Aptos/Move: 0
    - executor
*/
// Only send to ZK chains
// forge script scripts/ops/fix/FixDefaultSendConfig/FixDefaultSendConfigZk.s.sol
contract FixDefaultSendConfigZk is DeployFraxOFTProtocol {
    using Strings for uint256;
    uint32 constant EXECUTOR_CONFIG_TYPE = 1;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/fix/FixDefaultSendConfig/txs/");

        string memory name = string.concat(simulateConfig.chainid.toString(), ".json");
        return string.concat(root, name);
    }

    function run() public override {
        // general populate to prevent revert of `_populateConnectedOfts()`
        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            proxyOfts.push(address(0));
        }

        for (uint256 i=0; i<proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid != 2741 && proxyConfigs[i].chainid != 324) {
                continue;
            }
            setDefaultSendConfig(proxyConfigs[i]);
        }
    }

    function setDefaultSendConfig(L0Config memory _config) public simulateAndWriteTxs(_config) {
        // refresh the array
        delete setConfigParams;

        buildAllDefaultSendConfigs(_config);

        address endpoint = _config.endpoint;
        for (uint256 o=0; o<connectedOfts.length; o++) {
            bytes memory data = abi.encodeCall(
                IMessageLibManager.setConfig,
                (
                    connectedOfts[o],
                    _config.sendLib302,
                    setConfigParams
                )
            );
            (bool success, ) = endpoint.call(data);
            require(success, "setConfig failed");
            serializedTxs.push(
                SerializedTx({
                    name: "setDefaultSendConfig",
                    to: endpoint,
                    value: 0,
                    data: data
                })
            );
        }
    }


    function buildAllDefaultSendConfigs(L0Config memory _config) public {
        // set EVM chain config
        for (uint256 p=0; p<proxyConfigs.length; p++) {
            // NOTE: allows setting config where destination == source
            buildDefaultSendConfig({
                _config: _config,
                _dstEid: uint32(proxyConfigs[p].eid),
                _maxMessageSize: uint32(10_000)
            });
        }

        // set Solana chain config
        buildDefaultSendConfig({
            _config: _config,
            _dstEid: uint32(30168), // Solana EID
            _maxMessageSize: uint32(200) 
        });

        // set Aptos/Move chain config
        buildDefaultSendConfig({
            _config: _config,
            _dstEid: uint32(30325), // Movement EID
            _maxMessageSize: uint32(10_000) // TODO
        });
        buildDefaultSendConfig({
            _config: _config,
            _dstEid: uint32(30108), // Aptos EID
            _maxMessageSize: uint32(10_000) // TODO
        });
    }

    function buildDefaultSendConfig(
        L0Config memory _config,
        uint32 _dstEid,
        uint32 _maxMessageSize
    ) public {
        // Only add the default send config if the destination EID is supported by the connected chain
        if (
            !IMessageLibManager(_config.endpoint).isSupportedEid(_dstEid)
        ) return;

        ExecutorConfig memory executorConfig = ExecutorConfig({
            maxMessageSize: _maxMessageSize,
            executor: _config.executor
        });

        setConfigParams.push(
            SetConfigParam({
                eid: _dstEid,
                configType: EXECUTOR_CONFIG_TYPE,
                config: abi.encode(executorConfig)
            })   
        );
    }
}