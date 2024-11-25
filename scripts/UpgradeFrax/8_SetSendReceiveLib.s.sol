// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IMessageLibManager } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";

/// @dev On ethereum, reset the peers of FRAX / sFRAX to prevent bridging.  Additionally, reset the peers of FRAX / sFRAX
///        on destination chains to prevent bridging
// forge script scripts/UpgradeFrax/8_SetSendReceiveLib.s.sol --rpc-url https://rpc.frax.com
contract SetSendReceiveLib is DeployFraxOFTProtocol {
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
        root = string.concat(root, "/scripts/UpgradeFrax/txs/");
        string memory filename = string.concat("8_SetSendReceiveLib-", _config.chainid.toString());
        filename = string.concat(filename, ".json");

        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }


    /// @dev skip deployment, set oft addrs to only FRAX/sFRAX
    function run() public override {
        delete legacyOfts;
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        legacyOfts.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sFRAX

        delete proxyOfts;
        proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // FRAX
        proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sFRAX

        setLibs();
    }

    function setLibs() public {
        // For legacy chains, unblock legacy paths
        for (uint256 c=0; c<legacyConfigs.length; c++) {
            setLib(legacyOfts, legacyConfigs, legacyConfigs[c]);
        }
        // For proxy chains, unblock proxy paths
        for (uint256 c=0; c<proxyConfigs.length; c++) {
            setLib(proxyOfts, proxyConfigs, proxyConfigs[c]);
        }
    }

    function setLib(
        address[] memory _connectedOfts,
        L0Config[] memory _peerConfigs,
        L0Config memory _config
    ) simulateAndWriteTxs(_config) public {

        // for both FRAX/sFRAX
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address connectedOft = _connectedOfts[o];
            
            // For each destination
            for (uint256 c=0; c<_peerConfigs.length; c++) {
                uint32 eid = uint32(_peerConfigs[c].eid);

                // skip setting sendLib for self
                if (_config.eid == eid) continue;

                // Set sendLib to default

                bytes memory data = abi.encodeCall(
                    IMessageLibManager.setSendLibrary,
                    (
                        connectedOft, eid, _config.sendLib302
                    )
                );
                (bool success,) = _config.endpoint.call(data);
                require(success, "Unable to call setSendLib");
                serializedTxs.push(
                    SerializedTx({
                        name: "setSendLib",
                        to: _config.endpoint,
                        value: 0,
                        data: data
                    })
                );

                // Set receiveLib to default

                data = abi.encodeCall(
                    IMessageLibManager.setReceiveLibrary,
                    (
                        connectedOft, eid, _config.receiveLib302, 0
                    )
                );
                (success,) = _config.endpoint.call(data);
                require(success, "Unable to cal setReceiveLib");
                serializedTxs.push(
                    SerializedTx({
                        name: "setReceiveLib",
                        to: _config.endpoint,
                        value: 0,
                        data: data
                    })
                );
            }
        }
    }
}