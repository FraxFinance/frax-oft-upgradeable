// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

import { SetDVNs } from "scripts/DeployFraxOFTProtocol/inherited/SetDVNs.s.sol";

/*
TODO
- Deployment handling on non-pre-deterministic chains
*/

contract DeployFraxOFTProtocol is SetDVNs, BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    /// @dev Nick's method CREATE2 deployer (keyless deployment, available on all EVM chains)
    address public constant NICK_CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev Google Cloud deployer address (passed via --sender on CLI)
    address public constant GCS_DEPLOYER = 0x54F9b12743A7DeeC0ea48721683cbebedC6E17bC;

    function version() public virtual override pure returns (uint256, uint256, uint256) {
        return (1, 3, 1);
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
            _connectedOfts: connectedOfts,
            _configs: broadcastConfigArray
        });

        setEvmPeers({
            _connectedOfts: connectedOfts,
            _peerOfts: proxyOfts,
            _configs: broadcastConfigArray 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: connectedOfts,
            _configs: broadcastConfigArray
        });

        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: connectedOfts,
            _configs: broadcastConfigArray
        });
    }

    function setupSource() public virtual {
        vm.startBroadcast();

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

        vm.stopBroadcast();
    }

    function setupEvms() public virtual {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: expectedProxyOfts,
            _configs: proxyConfigs
        });
    }

    function setupNonEvms() public virtual {
        require(proxyOfts.length == 6, "Error: non-evm setup will be incorrect");

        setSolanaEnforcedOptions({
            _connectedOfts: proxyOfts
        });

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
            uint32 eid = uint32(allConfigs[e].eid);
            require(
                IMessageLibManager(broadcastConfig.endpoint).isSupportedEid(eid),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
    }

    function postDeployChecks() internal virtual view {
        require(proxyOfts.length == 6, "Did not deploy all 6 OFTs");
    }

    function deployFraxOFTUpgradeablesAndProxies() public virtual {
        vm.startBroadcast();

        // Proxy admin — deployed deterministically via Nick's CREATE2
        proxyAdmin = deployCreate2({
            _salt: "FraxProxyAdmin",
            _initCode: abi.encodePacked(
                type(FraxProxyAdmin).creationCode,
                abi.encode(msg.sender)
            )
        });
        require(msg.sender == GCS_DEPLOYER, "Must pass --sender with GCS deployer address");

        // Implementation mock — deployed deterministically via Nick's CREATE2
        implementationMock = deployCreate2({
            _salt: "ImplementationMock",
            _initCode: type(ImplementationMock).creationCode
        });

        // / @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d
        // Deploy WFRAX
        (,wfraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Wrapped Frax",
            _symbol: "WFRAX"
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
        (,frxUsdOft) = deployFrxUsdOFTUpgradeableAndProxy();

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

        vm.stopBroadcast();
    }

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    ///     With state checks
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public virtual returns (address implementation, address proxy) {
        implementation = address(new FraxOFTUpgradeable(broadcastConfig.endpoint)); 

        /// @dev: broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTUpgradeable.initialize.selector,
            _name,
            _symbol,
            msg.sender
        );

        /// @dev: deploy deterministic proxy via Nick's CREATE2
        proxy = deployCreate2({
            _salt: _symbol,
            _initCode: abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(implementationMock, msg.sender, "")
            )
        });

        // Upgrade to real implementation and initialize
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });

        // Transfer admin to proxyAdmin
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
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == msg.sender,
            "Endpoint delegate incorrect"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == msg.sender,
            "OFT owner incorrect"
        );
    }

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    ///     With state checks
    function deployFrxUsdOFTUpgradeableAndProxy() public virtual returns (address implementation, address proxy) {
        implementation = address(new FrxUSDOFTUpgradeable(broadcastConfig.endpoint)); 

        /// @dev: broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FrxUSDOFTUpgradeable.initialize.selector,
            msg.sender
        );

        /// @dev: deploy deterministic proxy via Nick's CREATE2
        proxy = deployCreate2({
            _salt: "frxUSD",
            _initCode: abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(implementationMock, msg.sender, "")
            )
        });

        // Upgrade to real implementation and initialize
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });

        // Transfer admin to proxyAdmin
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        proxyOfts.push(proxy);

        // State checks
        require(
            isStringEqual(FraxOFTUpgradeable(proxy).name(), "Frax USD"),
            "OFT name incorrect"
        );
        require(
            isStringEqual(FraxOFTUpgradeable(proxy).symbol(), "frxUSD"),
            "OFT symbol incorrect"
        );
        require(
            address(FraxOFTUpgradeable(proxy).endpoint()) == broadcastConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == msg.sender,
            "Endpoint delegate incorrect"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == msg.sender,
            "OFT owner incorrect"
        );
    }

    function setPriviledgedRoles() public virtual {
        if (broadcastConfig.delegate == address(0)) revert("Delegate cannot be zero address");
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
        require(_connectedOfts.length == _peerOfts.length, "connectedOfts.length != _peerOfts.length");
        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                address peerOft = determinePeer({
                    _chainid: _configs[c].chainid,
                    _oft: _peerOfts[o],
                    _peerOfts: _peerOfts
                });
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }

    // Overwrite the peer where necessary
    // Conditional statement allows for overwriting peer whether (for example, frxUSD):
    //  (1) frxUsdOft is set through deployFraxOFTUpgradeableAndProxy() (allows for non-predetermined addrs)
    //  (2) connectedOft is the predetermined frxUsd OFT addr
    //  (3) peer is either the ethereum/fraxtal frxUSD lockbox or a non-predeterministic address    
    // NOTE on partial token deployments, {token}Oft must be set
    function determinePeer(
        uint256 _chainid,
        address _oft,
        address[] memory _peerOfts
    ) public virtual view returns (address peer) {
        if (_chainid == 252) {
            peer = getPeerFromArray({
                _oft: _oft,
                _oftArray: fraxtalLockboxes
            });
            require(peer != address(0), "Invalid fraxtal peer");
        } else if (_chainid == 1) {
            peer = getPeerFromArray({
                _oft: _oft,
                _oftArray: ethLockboxes
            });
            require(peer != address(0), "Invalid ethereum peer");
        } else if (_chainid == 59144) {
            peer = getPeerFromArray({
                _oft: _oft,
                _oftArray: lineaProxyOfts
            });
            require(peer != address(0), "Invalid linea peer");
        } else if (_chainid == 8453) {
            peer = getPeerFromArray({
                _oft: _oft,
                _oftArray: baseProxyOfts
            });
            require(peer != address(0), "Invalid base peer");
        } else if (_chainid == 2741 || _chainid == 324) {
            peer = getPeerFromArray({
                _oft: _oft,
                _oftArray: zkEraProxyOfts
            });
            require(peer != address(0), "Invalid Zk Era peer");
        } else if (_chainid == 534352) {
            peer = getPeerFromArray({
                _oft: _oft,
                _oftArray: scrollProxyOfts
            });
            require(peer != address(0), "Invalid Scroll peer");
        } else if (_chainid == 11155111) {
            peer = getTestnetPeerFromArray({
                _oft: _oft,
                _oftArray: ethSepoliaLockboxes
            });
            require(peer != address(0), "Invalid eth sepolia peer");
        } else if (_chainid == 421614) {
            peer = getTestnetPeerFromArray({
                _oft: _oft,
                _oftArray: arbitrumSepoliaOfts
            });
            require(peer != address(0), "Invalid arbitrum sepolia peer");
        } else if (_chainid == 2522) {
            peer = getTestnetPeerFromArray({
                _oft: _oft,
                _oftArray: fraxtalTestnetLockboxes
            });
            require(peer != address(0), "Invalid fraxtal testnet peer");
        } else {
            peer = getPeerFromArray({
                _oft: _oft,
                _oftArray: _peerOfts
            });
            require(peer != address(0), "Invalid proxy peer");
        }
    }

    function getPeerFromArray(address _oft, address[] memory _oftArray) public virtual view returns (address peer) {
        require(_oftArray.length == 6, "getPeerFromArray index mismatch");
        require(_oft != address(0), "getPeerFromArray() OFT == address(0)");
        /// @dev maintains array of deployFraxOFTUpgradeablesAndProxies(), where proxyOfts is pushed to in the respective order
        if (_oft == wfraxOft || _oft == proxyFraxOft) {
            peer = _oftArray[0];
        } else if (_oft == sfrxUsdOft || _oft == proxySFrxUsdOft) {
            peer = _oftArray[1];
        } else if (_oft == sfrxEthOft || _oft == proxySFrxEthOft) {
            peer = _oftArray[2];
        } else if (_oft == frxUsdOft || _oft == proxyFrxUsdOft) {
            peer = _oftArray[3];
        } else if (_oft == frxEthOft || _oft == proxyFrxEthOft) {
            peer = _oftArray[4];
        } else if (_oft == fpiOft || _oft == proxyFpiOft) {
            peer = _oftArray[5];
        }
    }

    function getTestnetPeerFromArray(address _oft, address[] memory _oftArray) public virtual view returns (address peer) {
        require(_oftArray.length == 1, "getPeerFromTestnetArray index mismatch");
        require(_oft != address(0), "getPeerFromTestnetArray() OFT == address(0)");
        // should only be frxUsd
        if (_oft == frxUsdOft || _oft == proxyFrxUsdOft) {
            peer = _oftArray[0];
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
        pushSerializedTx({
            _name:"setPeer",
            _to:_connectedOft,
            _value:0,
            _data:data
        });
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

    function setMovementEnforcedOptions(
        address[] memory _connectedOfts
    ) public virtual {
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(5_000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(5_000, 0);

        L0Config[] memory configs = new L0Config[](1);
        configs[0] = nonEvmConfigs[1]; // mapped to movement

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
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(5_000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(5_000, 0);

        L0Config[] memory configs = new L0Config[](1);
        configs[0] = nonEvmConfigs[2]; // mapped to Aptos

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

        // Tempo-specific enforced options (higher gas)
        bytes memory tempoOptionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(2_000_000, 0);
        bytes memory tempoOptionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(2_500_000, 0);

        // Build enforced options for each chain
        for (uint256 c=0; c<_configs.length; c++) {            
            // cannot set enforced options to self
            if (block.chainid == _configs[c].chainid) continue;

            // Use higher gas limits for Tempo (eid 30410)
            if (_configs[c].eid == 30410) {
                enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 1, tempoOptionsTypeOne));
                enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 2, tempoOptionsTypeTwo));
            } else {
                enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 1, _optionsTypeOne));
                enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 2, _optionsTypeTwo));
            }
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
        pushSerializedTx({
            _name:"setEnforcedOptions",
            _to: _connectedOft,
            _value:0,
            _data:data
        });
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
            pushSerializedTx({
                _name:"setSendLibrary",
                _to: _connectedConfig.endpoint,
                _value : 0,
                _data:data

            });
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
            pushSerializedTx({
                _name:"setReceiveLibrary",
                _to: _connectedConfig.endpoint,
                _value:0,
                _data:data
            });
        }
    }

    /// @dev overrides the virtual pushSerializedTx inherited in Set{X}.s.sol as serializedTxs does not exist in the inherited contract
    function pushSerializedTx(
        string memory _name,
        address _to,
        uint256 _value,
        bytes memory _data
    ) public virtual override {
        serializedTxs.push(
            SerializedTx({
                name: _name,
                to: _to,
                value: _value,
                data: _data
            })
        );
    }

    /// @notice Deploy a contract deterministically using Nick's CREATE2 factory
    /// @dev Address = keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))[12:].
    ///      Identical salt + initCode yields the same address on every chain.
    /// @param _salt A string used to generate the CREATE2 salt
    /// @param _initCode The full creation code (creationCode ++ constructor args) to deploy
    /// @return deployed The deployed contract address
    function deployCreate2(
        string memory _salt,
        bytes memory _initCode
    ) public virtual returns (address deployed) {
        bytes32 salt = _generateCreate2Salt(msg.sender, _salt);

        // Deploy via Nick's CREATE2 factory: calldata = salt ++ initCode
        (bool success, bytes memory ret) = NICK_CREATE2_DEPLOYER.call(
            abi.encodePacked(salt, _initCode)
        );
        require(success && ret.length == 20, "Nick CREATE2 deployment failed");
        deployed = address(uint160(bytes20(ret)));
    }

    /// @notice Compute the deterministic address for a Nick's CREATE2 deployment
    /// @param _salt A string used to generate the CREATE2 salt
    /// @param _initCode The full creation code (creationCode ++ constructor args)
    /// @return The predicted address
    function computeCreate2Address(
        string memory _salt,
        bytes memory _initCode
    ) public virtual view returns (address) {
        bytes32 salt = _generateCreate2Salt(GCS_DEPLOYER, _salt);
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            NICK_CREATE2_DEPLOYER,
            salt,
            keccak256(_initCode)
        )))));
    }

    /// @notice Generate a CREATE2 salt for deterministic deployment
    /// @param _deployer The address of the deployer
    /// @param _name The name used to generate the salt
    /// @return The generated salt
    function _generateCreate2Salt(address _deployer, string memory _name) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_deployer, _name));
    }
}
