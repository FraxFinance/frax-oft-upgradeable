// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

/*
TODO
- Automatically verify contracts
- Deployment on non-evm / non-pre-deterministic chains
    - Would need to modify from expectedProxyOFTs to proxyOFTs
*/


contract DeployFraxOFTProtocol is BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function version() public virtual override pure returns (uint256, uint256, uint256) {
        return (1, 2, 0);
    }

    function setUp() public virtual override {
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
                _connectedOfts: expectedProxyOfts
            });
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public virtual simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: activeConfigArray
        });

        setEvmPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: expectedProxyOfts,
            _configs: activeConfigArray
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: activeConfigArray
        });
    }

    function setupSource() public virtual broadcastAs(configDeployerPK) {
        // TODO: this will break if proxyOFT addrs are not the pre-determined addrs verified in postDeployChecks()
        setupEvms();
        setupNonEvms();

        setDVNs({
            _connectedConfig: activeConfig,
            _connectedOfts: expectedProxyOfts,
            _configs: allConfigs
        });

        setPriviledgedRoles();
    }

    function setupEvms() public virtual {
        setEvmEnforcedOptions({
            _connectedOfts: expectedProxyOfts,
            _configs: evmConfigs
        });

        /// @dev legacy, non-upgradeable OFTs
        setEvmPeers({
            _connectedOfts: expectedProxyOfts,
            _peerOfts: legacyOfts,
            _configs: legacyConfigs
        });
        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: expectedProxyOfts,
            _peerOfts: expectedProxyOfts,
            _configs: proxyConfigs
        });
    }

    function setupNonEvms() public virtual {
        setSolanaEnforcedOptions();
        
        /// @dev: additional enforced options for non-evms set here

        setNonEvmPeers({
            _connectedOfts: expectedProxyOfts
        });
    }

    function preDeployChecks() public virtual view {
        for (uint256 e=0; e<allConfigs.length; e++) {
            uint256 eid = allConfigs[e].eid;    
            // source and dest eid cannot be same
            if (eid == activeConfig.eid) continue;
            require(
                IMessageLibManager(activeConfig.endpoint).isSupportedEid(uint32(allConfigs[e].eid)),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
    }

    function postDeployChecks() public virtual view {
        // Ensure OFTs are their expected pre-determined address.  If not, there's a chance the deployer nonce shifted,
        // the EVM has differing logic, or we are not on an EVM compatable chain.
        // TODO: support for non-evm addresses
        // TODO: validate that differing OFT addrs does not impact assumed setup functions.
        require(fxsOft == expectedProxyOfts[0], "Invalid FXS OFT");
        require(sFraxOft == expectedProxyOfts[1], "Invalid sFRAX OFT");
        require(sfrxEthOft == expectedProxyOfts[2], "Invalid sfrxETH OFT");
        require(fraxOft == expectedProxyOfts[3], "Invalid FRAX OFT");
        require(frxEthOft == expectedProxyOfts[4], "Invalid frxETH OFT");
        require(fpiOft == expectedProxyOfts[5], "Invalid FPI OFT");
        require(proxyOfts.length == numOfts, "OFT array lengths different");
    }

    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(oftDeployerPK) public virtual {

        // Proxy admin (0x223a681fc5c5522c85C96157c0efA18cd6c5405c)
        proxyAdmin = address(new ProxyAdmin(vm.addr(configDeployerPK)));

        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250)
        implementationMock = address(new ImplementationMock());

        // / @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d
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

        // Deploy sfrxETH
        (,sfrxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Staked Frax Ether",
            _symbol: "sfrxETH"
        });

        // Deploy FRAX
        (,fraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax",
            _symbol: "FRAX"
        });

        // Deploy frxETH
        (,frxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Ether",
            _symbol: "frxETH"
        });

        // Deploy FPI
        (,fpiOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Price Index",
            _symbol: "FPI"
        });
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
        // TODO: will need to look at these instead of expectedProxyOFTs if the deployed addrs are different than expected
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
        // TODO: fix loop to correct length
        for (uint256 o=0; o<expectedProxyOfts.length; o++) {
            address proxyOft = expectedProxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(activeConfig.delegate);
            Ownable(proxyOft).transferOwnership(activeConfig.delegate);
        }

        /// @dev transfer ownership of ProxyAdmin
        Ownable(proxyAdmin).transferOwnership(activeConfig.delegate);
    }

    /// @dev _connectedOfts refers to the OFTs of the RPC we are currently connected to
    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public virtual {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            for (uint256 c=0; c<_configs.length; c++) {
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(_peerOfts[o])
                });
            }
        }
    }

    /// @dev Non-evm OFTs require their own unique peer address
    function setNonEvmPeers(
        address[] memory _connectedOfts
    ) public virtual {
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            for (uint256 c=0; c<nonEvmPeersArrays.length; c++) {
                setPeer({
                    _config: activeConfig,
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: nonEvmPeersArrays[c][o]
                });
            }
        }
    }

    function setPeer(
        L0Config memory _config,
        address _connectedOft,
        bytes32 _peerOftAsBytes32
    ) public virtual {
        uint32 eid = uint32(_config.eid);

        // cannot set peer to self
        if (chainid == activeConfig.chainid && eid == activeConfig.eid) return;

        bytes memory data = abi.encodeCall(
            IOAppCore.setPeer,
            (
                eid, _peerOftAsBytes32
            )
        );
        (bool success, ) = _connectedOft.call(data);
        require(success, "Unable to setPeer");
        serializedTxs.push(
            SerializedTx({
                name: "setPeer",
                to: _connectedOft,
                value: 0,
                data: data
            })
        );
    }

    function setEvmEnforcedOptions(
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public virtual {
        // For each peer, default
        // https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/OFT.t.sol#L417
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000, 0);

        _setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: _configs,
            _optionsTypeOne: optionsTypeOne,
            _optionsTypeTwo: optionsTypeTwo
        });
    }

    function setSolanaEnforcedOptions() public virtual {
        uint32 eid = uint32(nonEvmConfigs[0].eid);

        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);

        delete enforcedOptionsParams;
        enforcedOptionsParams.push(EnforcedOptionParam(eid, 1, optionsTypeOne));
        enforcedOptionsParams.push(EnforcedOptionParam(eid, 2, optionsTypeTwo));

        _setEnforcedOptions({
            _connectedOfts: expectedProxyOfts,
            _configs: new L0Config[](0),
            _optionsTypeOne: "",
            _optionsTypeTwo: ""
        });
    }

    function _setEnforcedOptions(
        address[] memory _connectedOfts,
        L0Config[] memory _configs,
        bytes memory _optionsTypeOne,
        bytes memory _optionsTypeTwo
    ) public virtual {
        for (uint256 c=0; c<_configs.length; c++) {            
            uint32 eid = uint32(_configs[c].eid);

            // cannot set enforced options to self
            if (chainid == activeConfig.chainid && eid == activeConfig.eid) continue;

            enforcedOptionsParams.push(EnforcedOptionParam(eid, 1, _optionsTypeOne));
            enforcedOptionsParams.push(EnforcedOptionParam(eid, 2, _optionsTypeTwo));
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
        if (uint160(_connectedConfig.dvnHorizen) < uint160(_connectedConfig.dvnL0)) {
            requiredDVNs[0] = _connectedConfig.dvnHorizen;
            requiredDVNs[1] = _connectedConfig.dvnL0;
        } else {
            requiredDVNs[0] = _connectedConfig.dvnL0;
            requiredDVNs[1] = _connectedConfig.dvnHorizen;
        }
        ulnConfig.requiredDVNs = requiredDVNs;

        // push allConfigs
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
