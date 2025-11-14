pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

interface IOAppCoreUpgradeable {
    function peers(uint32 _eid) external view returns (bytes32);
    function setPeer(uint32 _eid, bytes32 _peer) external;
}

/// For each chain, if the peer is not fraxtal, remove it
// forge script scripts/ops/RemovePeers/RemovePeers.s.sol --ffi
contract RemovePeers is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();

        return string(
            abi.encodePacked(
                root,
                "/scripts/ops/RemovePeers/txs/RemovePeers-",
                simulateConfig.chainid.toString(),
                ".json"
            )
        );
    }

    function run() public override {
        // for proxy chains
        for (uint256 c=0; c<proxyConfigs.length; c++) {
            if (proxyConfigs[c].chainid == 252) continue; // skip fraxtal
            // skip deprecated/undeployed chains
            if (
                proxyConfigs[c].chainid == 3637 || // botanix
                proxyConfigs[c].chainid == 1101 || // polygon zkevm
                proxyConfigs[c].chainid == 81457 // blast
            ) continue;
            removeAllPeers(proxyConfigs[c]);
        }
    }

    function removeAllPeers(L0Config memory _config) simulateAndWriteTxs(_config) public {
        for (uint256 i=0; i<connectedOfts.length; i++) {
            removeOftPeers(connectedOfts[i]);
        }
    }

    function removeOftPeers(address _oft) public {
        for (uint256 i=0; i<allConfigs.length; i++) {

            // skip fraxtal
            if (allConfigs[i].chainid == 252) {
                continue;
            }
            
            // exception: ethereum should be connected to solana, aptos, movement- skip those peer checks
            if (simulateConfig.chainid == 1) {
                if (
                    allConfigs[i].eid == 30168 || // solana
                    allConfigs[i].eid == 30325 || // movement
                    allConfigs[i].eid == 30108 // aptos
                ) {
                    continue;
                }
            }

            bytes32 peer = IOAppCoreUpgradeable(_oft).peers(uint32(allConfigs[i].eid));
            
            // if peer is set, remove it
            if (peer != bytes32(0)) {
                bytes memory data = abi.encodeCall(
                    IOAppCoreUpgradeable.setPeer,
                    (uint32(allConfigs[i].eid), bytes32(0))
                );
                (bool success, ) = _oft.call(data);
                require(success, "RemovePeers: setPeer failed");
                serializedTxs.push(
                    SerializedTx({
                        name: "SetPeer",
                        to: _oft,
                        value: 0,
                        data: data
                    })
                );
            }
        }
    }
}