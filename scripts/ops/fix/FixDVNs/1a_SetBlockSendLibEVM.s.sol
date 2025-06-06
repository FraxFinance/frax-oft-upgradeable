// pragma solidity ^0.8.19;

import "./FixDVNsInherited.s.sol";
import {IOAppCore} from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppCore.sol";

interface IEndpointV2 {
    function blockedLibrary() external view returns (address);
}

contract SetBlockSendLib is FixDVNsInherited {
    using stdJson for string;
    using Strings for uint256;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/fix/FixDVNs/txs/");
        string memory name = string.concat((block.timestamp).toString(), "-1a_SetBlockSendLibEVM-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function run() public override {
        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        for (uint256 i=0; i<proxyConfigs.length; i++) {
            for (uint256 j=0; j<chainIds.length; j++) {
                if (chainIds[j] == 324 || chainIds[j] == 2741) {
                    // skip zksync and abstract, they have a separate script
                    continue;
                }

                if (proxyConfigs[i].chainid == chainIds[j]) {
                    setSendLibs(proxyConfigs[i]);
                }
            }
        }
    }

    function setSendLibs(L0Config memory _config) public simulateAndWriteTxs(_config) {

        address blockedLibrary = IEndpointV2(_config.endpoint).blockedLibrary();

        for (uint256 o=0; o<connectedOfts.length; o++) {
            address connectedOft = connectedOfts[o];
            
            // loop through proxy configs, find the proxy config with the given chainID
            for (uint256 i=0; i<proxyConfigs.length; i++) {
                for (uint256 j=0; j<chainIds.length; j++) {
                    // only set chains as desired, not equal to the same chain
                    if (
                        proxyConfigs[i].chainid != chainIds[j]
                        || proxyConfigs[i].chainid == _config.chainid
                    ) continue;

                    // skip if peer is not set
                    if (!hasPeer(connectedOft, proxyConfigs[i])) {
                        continue;
                    }

                    // set the blocked library for the connected OFT
                    bytes memory data = abi.encodeCall(
                        IMessageLibManager.setSendLibrary,
                        (
                            connectedOft,
                            uint32(proxyConfigs[i].eid),
                            blockedLibrary
                        )
                    );
                    (bool success, ) = _config.endpoint.call(data);
                    require(success, "Failed to set send library");
                    serializedTxs.push(
                        SerializedTx({
                            name: "SetBlockSendLib",
                            to: _config.endpoint,
                            value: 0,
                            data: data
                        })
                    );
                }
            }
        }
    }

    function hasPeer(address _oft, L0Config memory _dstConfig) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(uint32(_dstConfig.eid));
        return peer != bytes32(0);
    }
}