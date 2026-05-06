// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./FixDVNsInherited.s.sol";
import {IOAppCore} from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppCore.sol";

interface IEndpointV2 {
    function blockedLibrary() external view returns (address);

    function getSendLibrary(address _sender, uint32 _dstEid) external view returns (address lib);
}

contract SetBlockSendLib is FixDVNsInherited {
    using stdJson for string;
    using Strings for uint256;
    using OptionsBuilder for bytes;

    function filename() public view override returns (string memory) {
        return filenameForStep("1c_SetBlockSendLibSolana");
    }

    function run() public override {
        for (uint256 i = 0; i < expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid != ETHEREUM_CHAIN_ID && proxyConfigs[i].chainid != FRAXTAL_CHAIN_ID) continue;
            if (!matchesSource(proxyConfigs[i])) continue;
            if (proxyConfigs[i].chainid == 324 || proxyConfigs[i].chainid == 2741) {
                // skip zksync and abstract, they have a separate script
                continue;
            }

            setSendLibs(proxyConfigs[i]);
        }
    }

    function setSendLibs(L0Config memory _config) public simulateAndWriteTxs(_config) {
        address blockedLibrary = IEndpointV2(_config.endpoint).blockedLibrary();

        for (uint256 o = 0; o < connectedOfts.length; o++) {
            address connectedOft = connectedOfts[o];

            for (uint256 i = 0; i < nonEvmConfigs.length; i++) {
                if (nonEvmConfigs[i].chainid != SOLANA_CHAIN_ID) continue; // only consider solana
                if (!matchesNonEvmDestination(_config, nonEvmConfigs[i])) continue;
                // skip if peer is not set
                if (!hasPeer(connectedOft, nonEvmConfigs[i])) {
                    continue;
                }

                address existingSendLibrary =
                    IEndpointV2(_config.endpoint).getSendLibrary(connectedOft, uint32(nonEvmConfigs[i].eid));

                if (existingSendLibrary == blockedLibrary) continue;

                // set the blocked library for the connected OFT
                bytes memory data = abi.encodeCall(
                    IMessageLibManager.setSendLibrary, (connectedOft, uint32(nonEvmConfigs[i].eid), blockedLibrary)
                );
                (bool success,) = _config.endpoint.call(data);
                require(success, "Failed to set send library");
                serializedTxs.push(SerializedTx({name: "SetBlockSendLib", to: _config.endpoint, value: 0, data: data}));
            }
        }
    }

    function hasPeer(address _oft, L0Config memory _dstConfig) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(uint32(_dstConfig.eid));
        return peer != bytes32(0);
    }
}
