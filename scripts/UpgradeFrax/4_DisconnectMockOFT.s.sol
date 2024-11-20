// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { OFTUpgradeableMock } from "contracts/mocks/OFTUpgradeableMock.sol";

/// @dev deploy upgradeable mock OFTs and mint lockbox supply to the fraxtal msig
// forge script scripts/UpgradeFrax/4_DisconnectMockOFT.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract DisconnectMockOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    address deployer = 0xb0E1650A9760e0f383174af042091fc544b8356f;
    address fraxMockOft = address(0); // TODO
    address sFraxMockOft = address(0); // TODO

    /// @dev override to only use FRAX, sFRAX as peer. Set the mock addresses as proxy (destination) addresses
    function setUp() public virtual override {
        chainid = block.chainid;
        loadJsonConfig();

        delete legacyOfts;
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        legacyOfts.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sFRAX

        delete proxyOfts;
        proxyOfts.push(fraxMockOft);
        proxyOfts.push(sFraxMockOft);
    }

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
        string memory filename = string.concat("4_DisconnectMockOFT-", _config.chainid.toString());
        filename = string.concat(filename, ".json");

        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }

    /// @dev skip deployment and destination setting- only setup ethereum peers
    function run() public override {
        // deploySource();
        setupSource();
        // setupDestinations();
    }

    /// @dev Remove the fraxtal peer
        function setupSource() public override simulateAndWriteTxs(activeConfig) {
        // setEnforcedOptions({
        //     _connectedOfts: proxyOfts,
        //     _configs: configs
        // });

        // setDVNs({
        //     _connectedConfig: activeConfig,
        //     _connectedOfts: proxyOfts,
        //     _configs: configs
        // });

        // setPeers({
        //     _connectedOfts: proxyOfts,
        //     _peerOfts: legacyOfts,
        //     _configs: legacyConfigs
        // });

        setPeers({
            // _connectedOfts: proxyOfts,
            _connectedOfts: legacyOfts,
            _peerOfts: proxyOfts,
            _configs: proxyConfigs
        });

        // setPriviledgedRoles();
    }

    /// @dev override solely fraxtal peer address with address(0)
    function setPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address connectedOft = _connectedOfts[o];
            address peerOft = _peerOfts[o];
            for (uint256 c=0; c<_configs.length; c++) {
                uint32 eid = uint32(_configs[c].eid);

                // cannot set peer to self
                if (chainid == activeConfig.chainid && eid == activeConfig.eid) continue;
                
                /// @dev skip if not fraxtal eid
                if (eid != uint32(30255)) continue;

                bytes memory data = abi.encodeCall(
                    IOAppCore.setPeer,
                    (
                        // eid, addressToBytes32(peerOft)
                        eid, addressToBytes32(address(0))
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