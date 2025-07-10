pragma solidity ^0.8.0;

import { DeployFraxOFTProtocol } from "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

contract FixRemoveMesh is DeployFraxOFTProtocol {

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "scripts/ops/fix/FixRemoveMesh/txs/FixRemoveMesh-");
        
        string memory name = string.concat(simulateConfig.chainid.toString(), ".json");
        
        return string.concat(root, name);
    }

    function run() public override {
        removeMesh();
    }

    function removeMesh() public {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            L0Config memory config = proxyConfigs[i];
            if (config.chainid == 252) continue; // Skip fraxtal- maintain all connections
            removeMesh(config);
        }
    }

    function removeMesh(L0Config memory _config) simulateAndWriteTxs(_config) public {
        address blockedLibrary = IEndpointV2(_config.endpoint).blockedLibrary();
        
        // for each oft
        for (uint256 o=0; o<connectedOfts.length; o++ )[
            address connectedOft = connectedOfts[o];

            // loop through non-evm configs to ensure there are no connections
            for (uint256 i=0; i<nonEvmConfigs.length; i++) {
                // skip if the config is fraxtal / ethereum as we want to maintain those connections
                if (_config.chainid == 1 || _config.chainid == 252) continue;

                // get the existing send library- note that this will return the send lib if not set (aka default value)
                address existingSendLibrary = IEndpointV2(_config.endpoint).getSendLibrary(
                    connectedOft,
                    uint32(proxyConfigs[i].eid)
                );
                // skip if the existing send library is already blocked 
                if (existingSendLibrary == blockedLibrary) continue;

                bytes memory data = abi.encodeCall(
                    IMessageLibManager.setSendLibrary,
                    (
                        connectedOft,
                        uint32(dstConfig.eid),
                        blockedLibrary
                    )
                );
                (bool success, ) = _config.endpoint.call(data);
                require(success, "Failed to set send library to blocked library");

                serializedTxs.push(
                    SerializedTx({
                        name: "block send lib",
                        to: _config.endpoint,
                        data: data,
                        value: 0
                    })
                );
            }

            // loop through all possible evm connections
            for (uint256 i=0; i<proxyConfigs.length; i++) {
                // check if there is a peer / send library set
                L0Config memory dstConfig = proxyConfigs[i];
                if (dstConfig.chainid == 252) continue; // Skip fraxtal- maintain connection

                // skip if no peer- no need to block sends
                if (!hasPeer(connectedOft, dstConfig)) continue;

                // get the existing send library- note that this will return the send lib if not set (aka default value)
                address existingSendLibrary = IEndpointV2(_config.endpoint).getSendLibrary(
                    connectedOft,
                    uint32(proxyConfigs[i].eid)
                );
                // skip if the existing send library is already blocked 
                if (existingSendLibrary == blockedLibrary) continue;

                bytes memory data = abi.encodeCall(
                    IMessageLibManager.setSendLibrary,
                    (
                        connectedOft,
                        uint32(dstConfig.eid),
                        blockedLibrary
                    )
                );
                (bool success, ) = _config.endpoint.call(data);
                require(success, "Failed to set send library to blocked library");

                serializedTxs.push(
                    SerializedTx({
                        name: "block send lib",
                        to: _config.endpoint,
                        data: data,
                        value: 0
                    })
                );
            ]
        }
    }

    function hasPeer(address _oft, L0Config memory _dstConfig) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(uint32(_dstConfig.eid));
        return peer != bytes32(0);
    }

}