// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

/*
TODO
- Deployment handling on non-pre-deterministic chains
*/

contract DeployFraxOFTProtocol is BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function version() public virtual override pure returns (uint256, uint256, uint256) {
        return (1, 2, 8);
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

    function setupProxyDestinations() public virtual {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // skip if destination == source
            if (proxyConfigs[i].eid == broadcastConfig.eid) continue;
            setupDestination({
                _connectedConfig: proxyConfigs[i]
            });
        }
    }

    function setupLegacyDestinations() public virtual {
        // DEPRECATED
    }

    function setupDestination(
        L0Config memory _connectedConfig
    ) public virtual simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: broadcastConfigArray
        });

        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: expectedProxyOfts,
            _configs: broadcastConfigArray 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: proxyOfts,
            _configs: broadcastConfigArray
        });

        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: proxyOfts,
            _configs: broadcastConfigArray
        });
    }

    function setupSource() public virtual broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        setPriviledgedRoles();
    }

    function setupEvms() public virtual {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: evmConfigs
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: proxyOfts,
            _configs: proxyConfigs
        });
    }

    function setupNonEvms() public virtual {
        require(proxyOfts.length == 6, "Error: non-evm setup will be incorrect");

        setSolanaEnforcedOptions({
            _connectedOfts: proxyOfts
        });

        // TODO: should be connectedOfts after merging with master
        setAptosEnforcedOptions({
            _connectedOfts: proxyOfts
        });
        
        /// @dev: additional enforced options for non-evms set here

        setNonEvmPeers({
            _connectedOfts: proxyOfts
        });
    }

    function preDeployChecks() public virtual view {
        for (uint256 e=0; e<allConfigs.length; e++) {
            uint256 eid = allConfigs[e].eid;    
            // source and dest eid cannot be same
            if (eid == broadcastConfig.eid) continue;
            require(
                IMessageLibManager(broadcastConfig.endpoint).isSupportedEid(uint32(allConfigs[e].eid)),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
    }

    function postDeployChecks() internal virtual view {
        // Ensure OFTs are their expected pre-determined address.  If not, there's a chance the deployer nonce shifted,
        // the EVM has differing logic, or we are not on an EVM compatable chain.
        require(fxsOft == expectedProxyOfts[0], "Invalid FXS OFT");
        require(sfrxUsdOft == expectedProxyOfts[1], "Invalid sFRAX OFT");
        require(sfrxEthOft == expectedProxyOfts[2], "Invalid sfrxETH OFT");
        require(frxUsdOft == expectedProxyOfts[3], "Invalid FRAX OFT");
        require(frxEthOft == expectedProxyOfts[4], "Invalid frxETH OFT");
        require(fpiOft == expectedProxyOfts[5], "Invalid FPI OFT");
        require(proxyOfts.length == numOfts, "OFT array lengths different");
    }

    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(oftDeployerPK) public virtual {

        // Proxy admin (0x223a681fc5c5522c85C96157c0efA18cd6c5405c)
        proxyAdmin = address(new FraxProxyAdmin(vm.addr(configDeployerPK)));

        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250)
        implementationMock = address(new ImplementationMock());

        // / @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d
        // Deploy FXS
        (,fxsOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Share",
            _symbol: "FXS"
        });

        // Deploy sfrxUSD
        (,sfrxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Staked Frax USD",
            _symbol: "sfrxUSD"
        });

        // Deploy sfrxETH
        (,sfrxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Staked Frax Ether",
            _symbol: "sfrxETH"
        });

        // Deploy frxUSD
        (,frxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax USD",
            _symbol: "frxUSD"
        });

        // Deploy frxETH
        (,frxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Ether",
            _symbol: "frxETH"
        });

        // Deploy broken FPI
        deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax Price Index",
            _symbol: "Mock FPI"
        });
        // pop off pushed proxy addr as it's the broken FPI
        proxyOfts.pop();

        // Deploy correct FPI
        (, fpiOft) = deployFraxOFTUpgradeableAndProxy({
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
            abi.encode(broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));

        /// @dev: broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
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
            address(FraxOFTUpgradeable(proxy).endpoint()) == broadcastConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }


    function setPriviledgedRoles() public virtual {
        /// @dev transfer ownership of OFT
        for (uint256 o=0; o<proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(broadcastConfig.delegate);
            Ownable(proxyOft).transferOwnership(broadcastConfig.delegate);
        }

        /// @dev transfer ownership of ProxyAdmin
        Ownable(proxyAdmin).transferOwnership(broadcastConfig.delegate);
    }

    /// @dev _connectedOfts refers to the OFTs of the RPC we are currently connected to
    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public virtual {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        require(frxUsdOft != address(0) && sfrxUsdOft != address(0), "(s)frxUSD ofts are null");

        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address peerOft = _peerOfts[o];

            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {

                // for fraxtal destination, override OFT address of (s)frxUSD to the standalone lockbox
                if (_configs[c].chainid == 252) {
                    if (_connectedOfts[o] == frxUsdOft) {
                        peerOft = fraxtalFrxUsdLockbox;
                    } else if (_connectedOfts[o] == sfrxUsdOft) {
                        peerOft = fraxtalSFrxUsdLockbox;
                    } else if (_connectedOfts[o] == frxEthOft) {
                        peerOft = fraxtalFrxEthLockbox;
                    } else if (_connectedOfts[o] == sfrxEthOft) {
                        peerOft = fraxtalSFrxEthLockbox;
                    } else if (_connectedOfts[o] == fxsOft) {
                        peerOft = fraxtalFxsLockbox;
                    } else if (_connectedOfts[o] == fpiOft) {
                        peerOft = fraxtalFpiLockbox;
                    } else {
                        require(0==1, "unidentified oft to fraxtal");
                    }
                } else {
                    // Non-fraxtal destination: use the predeterministic address
                    if (_connectedOfts[o] == frxUsdOft) {
                        peerOft = frxUsdOft;
                    } else if (_connectedOfts[o] == sfrxUsdOft) {
                        peerOft = sfrxUsdOft;
                    } else if (_connectedOfts[o] == frxEthOft) {
                        peerOft = frxEthOft;
                    } else if (_connectedOfts[o] == sfrxEthOft) {
                        peerOft = sfrxEthOft;
                    } else if (_connectedOfts[o] == fxsOft) {
                        peerOft = fxsOft;
                    } else if (_connectedOfts[o] == fpiOft) {
                        peerOft = fpiOft;
                    } else {
                        require(0==1, "unidentified oft to pre-determined peer");
                    }
                }

                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }

    /// @dev Non-evm OFTs require their own unique peer address
    function setNonEvmPeers(
        address[] memory _connectedOfts
    ) public virtual {
        // Set the peer per OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // For each non-evm
            for (uint256 c=0; c<nonEvmPeersArrays.length; c++) {
                setPeer({
                    _config: nonEvmConfigs[c],
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
        // cannot set peer to self
        if (block.chainid == _config.chainid) return;

        bytes memory data = abi.encodeCall(
            IOAppCore.setPeer,
            (
                uint32(_config.eid), _peerOftAsBytes32
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

        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: _configs,
            _optionsTypeOne: optionsTypeOne,
            _optionsTypeTwo: optionsTypeTwo
        });
    }

    function setSolanaEnforcedOptions(
        address[] memory _connectedOfts
    ) public virtual {
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);

        L0Config[] memory configs = new L0Config[](1);
        configs[0] = nonEvmConfigs[0]; // mapped to solana

        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: configs,
            _optionsTypeOne: optionsTypeOne,
            _optionsTypeTwo: optionsTypeTwo
        });
    }

    function setAptosEnforcedOptions(
        address[] memory _connectedOfts
    ) public virtual {
        // TODO: change these, [200_000, 2_500_000] is solana config
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);

        L0Config[] memory configs = new L0Config[](1);
        configs[0] = nonEvmConfigs[1]; // mapped to Aptos

        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: configs,
            _optionsTypeOne: optionsTypeOne,
            _optionsTypeTwo: optionsTypeTwo
        });
    }


    function setEnforcedOptions(
        address[] memory _connectedOfts,
        L0Config[] memory _configs,
        bytes memory _optionsTypeOne,
        bytes memory _optionsTypeTwo
    ) public virtual {
        // clear out any pre-existing enforced options params
        delete enforcedOptionParams;

        // Build enforced options for each chain
        for (uint256 c=0; c<_configs.length; c++) {            
            // cannot set enforced options to self
            if (block.chainid == _configs[c].chainid) continue;

            enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 1, _optionsTypeOne));
            enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 2, _optionsTypeTwo));
        }

        for (uint256 o=0; o<_connectedOfts.length; o++) {
            setEnforcedOption({
                _connectedOft: _connectedOfts[o]
            });
        }
    }

    function setEnforcedOption(
        address _connectedOft
    ) public {
        bytes memory data = abi.encodeCall(
            IOAppOptionsType3.setEnforcedOptions,
            (
                enforcedOptionParams
            )
        );
        (bool success, ) = _connectedOft.call(data);
        require(success, "Unable to setEnforcedOptions");
        serializedTxs.push(
            SerializedTx({
                name: "setEnforcedOptions",
                to: _connectedOft,
                value: 0,
                data: data
            })
        );
    }

    function setDVNs(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts,
        L0Config[] memory _configs 
    ) public virtual {
        UlnConfig memory ulnConfig;
        ulnConfig.requiredDVNCount = 2;
        address[] memory requiredDVNs = new address[](2);

        // skip setting up DVN if the address is null
        if (_connectedConfig.dvnHorizen == address(0)) return;

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
            // cannot set enforced options to self
            if (block.chainid == _configs[c].chainid) continue;

            setConfigParams.push(
                SetConfigParam({
                    eid: uint32(_configs[c].eid),
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

    function setLibs(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts,
        L0Config[] memory _configs 
    ) public virtual {
        // for each oft
        for (uint256 o=0; o < _connectedOfts.length; o++) {
            // for each destination
            for (uint256 c=0; c < _configs.length; c++) {
                setLib({
                    _connectedConfig: _connectedConfig,
                    _connectedOft: _connectedOfts[o],
                    _config: _configs[c]
                });
            }
        }
    }

    function setLib(
        L0Config memory _connectedConfig,
        address _connectedOft,
        L0Config memory _config
    ) public virtual {
        // skip if the connected and target are the same
        if (_connectedConfig.eid == _config.eid) return;

        // set sendLib to default if not already set
        address lib = IMessageLibManager(_connectedConfig.endpoint).getSendLibrary({
            _sender: _connectedOft,
            _eid: uint32(_config.eid)
        });
        bool isDefault = IMessageLibManager(_connectedConfig.endpoint).isDefaultSendLibrary({
            _sender: _connectedOft,
            _eid: uint32(_config.eid)
        });
        if (lib != _connectedConfig.sendLib302 || isDefault) {
            bytes memory data = abi.encodeCall(
                IMessageLibManager.setSendLibrary,
                (
                    _connectedOft, uint32(_config.eid), _connectedConfig.sendLib302
                )
            );
            (bool success,) = _connectedConfig.endpoint.call(data);
            require(success, "Unable to call setSendLibrary");
            serializedTxs.push(
                SerializedTx({
                    name: "setSendLibrary",
                    to: _connectedConfig.endpoint,
                    value: 0,
                    data: data
                })
            );
        }

        // set receiveLib to default if not already set
        (lib, isDefault) = IMessageLibManager(_connectedConfig.endpoint).getReceiveLibrary({
            _receiver: _connectedOft,
            _eid: uint32(_config.eid)
        });
        if (lib != _connectedConfig.receiveLib302 || isDefault) {
            bytes memory data = abi.encodeCall(
                IMessageLibManager.setReceiveLibrary,
                (
                    _connectedOft, uint32(_config.eid), _connectedConfig.receiveLib302, 0
                )
            );
            (bool success,) = _connectedConfig.endpoint.call(data);
            require(success, "Unable to call setReceiveLibrary");
            serializedTxs.push(
                SerializedTx({
                    name: "setReceiveLibrary",
                    to: _connectedConfig.endpoint,
                    value: 0,
                    data: data
                })
            );
        }
    }
}
