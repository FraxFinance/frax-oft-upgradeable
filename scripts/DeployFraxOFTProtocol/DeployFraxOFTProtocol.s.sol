// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

/*
TODO
- Setup frxETH, FPI with L0 mainnet adapter & legacies
- Automatically verify contracts
- Deployment on non-evm / non-pre-deterministic chains
*/


contract DeployFraxOFTProtocol is BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function version() public virtual pure returns (uint256, uint256, uint256) {
        return (1, 0, 3);
    }

    function setUp() public override {
        super.setUp();
    }

    function run() public virtual {
        deploySource();
        setupSource();
        setupDestinations();
    }

    function deploySource() public virtual {
        preDeployChecks();
        deployFraxOFTUpgradeablesAndProxies();
        postDeployChecks();
    }

    function setupDestinations() public virtual {
        setupLegacyDestinations();
        setupProxyDestinations();
    }

    function setupLegacyDestinations() public virtual {
        for (uint256 i=0; i<legacyConfigs.length; i++) {
            setupDestination({
                _connectedConfig: legacyConfigs[i],
                _connectedOfts: legacyOfts
            });
        }
    }

    function setupProxyDestinations() public virtual {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // skip if destination == source
            if (proxyConfigs[i].eid == activeConfig.eid) continue;
            setupDestination({
                _connectedConfig: proxyConfigs[i],
                _connectedOfts: proxyOfts
            });
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public virtual simulateAndWriteTxs(_connectedConfig) {
        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: activeConfigArray
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: activeConfigArray
        });

        setPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: proxyOfts,
            _configs: activeConfigArray
        });
    }

    function setupSource() public virtual broadcastAs(configDeployerPK) {
        // TODO: this will break if proxyOFT addrs are not the pre-determined addrs verified in postDeployChecks()
        setEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: configs
        });

        setDVNs({
            _connectedConfig: activeConfig,
            _connectedOfts: proxyOfts,
            _configs: configs
        });

        /// @dev legacy, non-upgradeable OFTs
        setPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: legacyOfts,
            _configs: legacyConfigs
        });
        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setPriviledgedRoles();
    }

    function preDeployChecks() public virtual view {
        for (uint256 e=0; e<configs.length; e++) {
            uint256 eid = configs[e].eid;    
            // source and dest eid cannot be same
            if (eid == activeConfig.eid) continue;
            require(
                IMessageLibManager(activeConfig.endpoint).isSupportedEid(uint32(configs[e].eid)),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
    }

    function postDeployChecks() public virtual view {
        // Ensure OFTs are their expected pre-determined address.  If not, there's a chance the deployer nonce shifted,
        // the EVM has differing logic, or we are not on an EVM compatable chain.
        // TODO: support for non-evm addresses
        // TODO: validate that differing OFT addrs does not impact assumed setup functions.
        require(fxsOft == 0x64445f0aecC51E94aD52d8AC56b7190e764E561a);
        require(sFraxOft == 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0);
        require(sfrxEthOft == 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45);
        require(fraxOft == 0x80Eede496655FB9047dd39d9f418d5483ED600df);
        require(proxyOfts.length == numOfts);
    }

    // TODO: missing ecosystem tokens (FPI, etc.)
    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(oftDeployerPK) public virtual {

        // Proxy admin
        proxyAdmin = address(new ProxyAdmin(vm.addr(configDeployerPK)));

        // Implementation mock
        implementationMock = address(new ImplementationMock());

        /// @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d
        // Deploy FXS
        (,fxsOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Share",
            _symbol: "FXS"
        });

        // Deploy sFRAX
        (,sFraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Staked Frax",
            _symbol: "sFRAX"
        });

        // sfrxETH
        (,sfrxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Staked Frax Ether",
            _symbol: "sfrxETH"
        });

        // Deploy FRAX
        (,fraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax",
            _symbol: "FRAX"
        });

        // Deploy FPI
    }

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    ///     With state checks
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public virtual returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(FraxOFTUpgradeable).creationCode),
            abi.encode(activeConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));

        /// @dev: activeConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTUpgradeable.initialize.selector,
            _name,
            _symbol,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);
        proxyOfts.push(proxy);

        // State checks
        require(
            isStringEqual(FraxOFTUpgradeable(proxy).name(), _name),
            "OFT name incorrect"
        );
        require(
            isStringEqual(FraxOFTUpgradeable(proxy).symbol(), _symbol),
            "OFT symbol incorrect"
        );
        require(
            address(FraxOFTUpgradeable(proxy).endpoint()) == activeConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(activeConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }


    function setPriviledgedRoles() public virtual {
        /// @dev transfer ownership of OFT
        for (uint256 o=0; o<numOfts; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(activeConfig.delegate);
            Ownable(proxyOft).transferOwnership(activeConfig.delegate);
        }

        /// @dev transfer ownership of ProxyAdmin
        Ownable(proxyAdmin).transferOwnership(activeConfig.delegate);
    }

    /// @dev _connectedOfts refers to the OFTs of the RPC we are currently connected to
    function setPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public virtual {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address connectedOft = _connectedOfts[o];
            address peerOft = _peerOfts[o];
            for (uint256 c=0; c<_configs.length; c++) {
                uint32 eid = uint32(_configs[c].eid);

                // cannot set peer to self
                if (chainid == activeConfig.chainid && eid == activeConfig.eid) continue;

                bytes memory data = abi.encodeCall(
                    IOAppCore.setPeer,
                    (
                        eid, addressToBytes32(peerOft)
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

    function setEnforcedOptions(
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public virtual {
        // For each peer, default
        // https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/OFT.t.sol#L417
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000, 0);

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

    function setDVNs(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts,
        L0Config[] memory _configs 
    ) public virtual {
        UlnConfig memory ulnConfig;
        ulnConfig.requiredDVNCount = 2;
        address[] memory requiredDVNs = new address[](2);

        // sort in ascending order (as spec'd in UlnConfig)
        if (uint160(_connectedConfig.dvnHorizon) < uint160(_connectedConfig.dvnL0)) {
            requiredDVNs[0] = _connectedConfig.dvnHorizon;
            requiredDVNs[1] = _connectedConfig.dvnL0;
        } else {
            requiredDVNs[0] = _connectedConfig.dvnL0;
            requiredDVNs[1] = _connectedConfig.dvnHorizon;
        }
        ulnConfig.requiredDVNs = requiredDVNs;

        // push configs
        for (uint256 c=0; c<_configs.length; c++) {
            uint32 eid = uint32(_configs[c].eid);

            // cannot set enforced options to self
            if (chainid == activeConfig.chainid && eid == activeConfig.eid) continue;

            setConfigParams.push(
                SetConfigParam({
                    eid: eid,
                    configType: Constant.CONFIG_TYPE_ULN,
                    config: abi.encode(ulnConfig)                    
                })
            );
        }

        // Submit txs to set DVN
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address endpoint = _connectedConfig.endpoint;
            
            // receiveLib
            bytes memory data = abi.encodeCall(
                IMessageLibManager.setConfig,
                (
                    _connectedOfts[o],
                    _connectedConfig.receiveLib302,
                    setConfigParams
                )
            );
            (bool success, ) = endpoint.call(data);
            require(success, "Unable to setConfig for receiveLib");
            serializedTxs.push(
                SerializedTx({
                    name: "setConfig for receiveLib",
                    to: endpoint,
                    value: 0,
                    data: data
                })
            );

            // sendLib
            data = abi.encodeCall(
                IMessageLibManager.setConfig,
                (
                    _connectedOfts[o],
                    _connectedConfig.sendLib302,
                    setConfigParams
                )
            );
            (success, ) = endpoint.call(data);
            require(success, "Unable to setConfig for sendLib");
            serializedTxs.push(
                SerializedTx({
                    name: "setConfig for sendLib",
                    to: endpoint,
                    value: 0,
                    data: data
                })
            );
        }
    }
}
