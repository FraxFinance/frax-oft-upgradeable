// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./FixLegacyDVNsInherited.s.sol";
import {IOAppCore} from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppCore.sol";

interface IEndpointV2BlockLib {
    function blockedLibrary() external view returns (address);
    function getSendLibrary(address _sender, uint32 _dstEid) external view returns (address lib);
}

/// @title Step 1: Block send lib for all legacy OFTs
/// @notice Sets the send library to the blocked library for all legacy OFTs on each source chain,
///         preventing any OFT message flow. This must be executed FIRST before DVN config changes.
/// @dev Run per-chain: modify the chainId filter in run() to target a specific source chain.
///      Generates one Safe TX batch JSON per source chain.
contract SetBlockSendLibLegacy is FixLegacyDVNsInherited {
    using stdJson for string;
    using Strings for uint256;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/fix/FixLegacyDVNs/txs/");
        string memory name = string.concat((block.timestamp).toString(), "-1_SetBlockSendLibLegacy-");
        name = string.concat(name, currentOftName, "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function run() public override {
        for (uint256 o = 0; o < legacyOftAddresses.length; o++) {
            currentOftName = legacyOftNames[o];
            for (uint256 i = 0; i < legacyConfigs.length; i++) {
                for (uint256 j = 0; j < legacyChainIds.length; j++) {
                    if (legacyConfigs[i].chainid == legacyChainIds[j]) {
                        blockSendLibsForOft(legacyConfigs[i], legacyOftAddresses[o]);
                    }
                }
            }
        }
    }

    function blockSendLibsForOft(L0Config memory _config, address _oft) public simulateAndWriteTxs(_config) {
        address blockedLibrary = IEndpointV2BlockLib(_config.endpoint).blockedLibrary();

        for (uint256 d = 0; d < legacyChainIds.length; d++) {
            // Skip self
            if (legacyChainIds[d] == _config.chainid) continue;

            L0Config memory dstConfig = findLegacyConfig(legacyChainIds[d]);

            // Skip if peer is not set
            if (!hasPeer(_oft, uint32(dstConfig.eid))) continue;

            // Check if already blocked
            address existingSendLib = IEndpointV2BlockLib(_config.endpoint).getSendLibrary(
                _oft,
                uint32(dstConfig.eid)
            );
            if (existingSendLib == blockedLibrary) continue;

            // Set send lib to blocked library
            bytes memory data = abi.encodeCall(
                IMessageLibManager.setSendLibrary,
                (_oft, uint32(dstConfig.eid), blockedLibrary)
            );
            (bool success,) = _config.endpoint.call(data);
            require(success, "Failed to set blocked send library");

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
