// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../../BaseL0Script.sol";

import { SetDVNs } from "scripts/DeployFraxOFTProtocol/inherited/SetDVNs.s.sol";
import { TestnetFrxUSDOFTUpgradeable } from "contracts/frxUsd/TestnetFrxUSDOFTUpgradeable.sol";

/// @dev same as DeployFraxOFTProtocolFraxtalHub but with testnet config and only deploys TestnetFrxUSDOFTUpgradeable
contract DeployTestnetFraxOFTProtocolFraxtalHub is SetDVNs, BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    L0Config[] fraxtalTestnetConfigAsArray;

    modifier selectForkAndBroadcast(L0Config memory _config) {
        vm.createSelectFork(_config.RPC);

        // store for later referencing
        simulateConfig = _config;

        // use the correct OFT addresses
        _populateConnectedOfts();

        vm.startBroadcast(configDeployerPK);
        _;
        vm.stopBroadcast();
    }

    function version() public virtual override pure returns (uint256, uint256, uint256) {
        return (1, 3, 1);
    }

    function setUp() public virtual override {
        super.setUp();

        for (uint256 i=0; i<testnetConfigs.length; i++) {
            // TODO: change back to 2522 once fraxtal testnet is back and running
            if (testnetConfigs[i].chainid == 11155111) fraxtalTestnetConfigAsArray.push(testnetConfigs[i]);
        }
        require(fraxtalTestnetConfigAsArray.length == 1, "fraxtalTestnetConfigAsArray.length != 1");
    }

    function run() public virtual {
        deploySource();
        setupSource();
        setupFraxtal();
    }

    function deploySource() public virtual {
        // preDeployChecks();
        deployFraxOFTUpgradeablesAndProxies();
        postDeployChecks();
    }

    function setupFraxtal() public virtual {
        setupDestination(fraxtalTestnetConfigAsArray[0]);
    }

    function setupDestination(
        L0Config memory _connectedConfig
    ) public virtual selectForkAndBroadcast(_connectedConfig) {
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

    function setupSource() public virtual broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        // setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: fraxtalTestnetConfigAsArray
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: fraxtalTestnetConfigAsArray
        });

        setPriviledgedRoles();
    }

    function setupEvms() public virtual {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: fraxtalTestnetConfigAsArray
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: expectedTestnetProxyOfts,
            _configs: fraxtalTestnetConfigAsArray
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
        for (uint256 e=0; e<testnetConfigs.length; e++) {
            uint32 eid = uint32(testnetConfigs[e].eid);
            require(
                IMessageLibManager(broadcastConfig.endpoint).isSupportedEid(eid),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
    }

    function postDeployChecks() internal virtual view {
        require(proxyOfts.length == 1, "Did not deploy frxUSD");
    }

    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(oftDeployerPK) public virtual {

        // Proxy admin (0x223a681fc5c5522c85C96157c0efA18cd6c5405c if predeterministic)
        proxyAdmin = address(new FraxProxyAdmin(vm.addr(configDeployerPK)));

        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250 if predeterministic)
        implementationMock = address(new ImplementationMock());

        // Deploy frxUSD
        (,frxUsdOft) = deployTestnetFrxUsdOFTUpgradeableAndProxy();

    }

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    ///     With state checks
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public virtual returns (address implementation, address proxy) {
        implementation = address(new FraxOFTUpgradeable(broadcastConfig.endpoint)); 
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

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    ///     With state checks
    function deployTestnetFrxUsdOFTUpgradeableAndProxy() public virtual returns (address implementation, address proxy) {
        implementation = address(new TestnetFrxUSDOFTUpgradeable(broadcastConfig.endpoint)); 
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));

        /// @dev: broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FrxUSDOFTUpgradeable.initialize.selector,
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
        if (_chainid == 11155111) {
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
        } else if (_chainid == 2201) {
            peer = getTestnetPeerFromArray({
                _oft: _oft,
                _oftArray: stableTestnetOfts
            });
            require(peer != address(0), "Invalid stable testnet peer");
        } else if (_chainid == 11155420) {
            peer = getTestnetPeerFromArray({
                _oft: _oft,
                _oftArray: opSepoliaOfts
            });
            require(peer != address(0), "Invalid op sepolia peer");
        } else {
            peer = getTestnetPeerFromArray({
                _oft: _oft,
                _oftArray: _peerOfts
            });
            require(peer != address(0), "Unsupported testnet peer");
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
        address lib;
        try IMessageLibManager(_connectedConfig.endpoint).getSendLibrary({
            _sender: _connectedOft,
            _eid: uint32(_config.eid)
        }) returns (address _lib) {
            lib = _lib;
        } catch {} // entered with `LZ_DefaultSendLibUnavailable()`
 
        bool isDefault = IMessageLibManager(_connectedConfig.endpoint).isDefaultSendLibrary({
            _sender: _connectedOft,
            _eid: uint32(_config.eid)
        });
        if (lib != _connectedConfig.sendLib302 || isDefault) {
            // bytes memory data = abi.encodeCall(
            //     IMessageLibManager.setSendLibrary,
            //     (
            //         _connectedOft, uint32(_config.eid), _connectedConfig.sendLib302
            //     )
            // );
            // (bool success,) = _connectedConfig.endpoint.call(data);
            // require(success, "Unable to call setSendLibrary");
            // pushSerializedTx({
            //     _name:"setSendLibrary",
            //     _to: _connectedConfig.endpoint,
            //     _value : 0,
            //     _data:data
            // });
        }

        // set receiveLib to default if not already set
        try IMessageLibManager(_connectedConfig.endpoint).getReceiveLibrary({
            _receiver: _connectedOft,
            _eid: uint32(_config.eid)
        }) returns (address _lib, bool _isDefault) {
            lib = _lib;
            isDefault = _isDefault;
        } catch { // entered when attempting to read receive lib when default lib is address(0) and receiveLib is not yet set
            lib = address(0);
            isDefault = true;
        }
        if (lib != _connectedConfig.receiveLib302 || isDefault) {
            // bytes memory data = abi.encodeCall(
            //     IMessageLibManager.setReceiveLibrary,
            //     (
            //         _connectedOft, uint32(_config.eid), _connectedConfig.receiveLib302, 0
            //     )
            // );
            // (bool success,) = _connectedConfig.endpoint.call(data);
            // require(success, "Unable to call setReceiveLibrary");
            // pushSerializedTx({
            //     _name:"setReceiveLibrary",
            //     _to: _connectedConfig.endpoint,
            //     _value:0,
            //     _data:data
            // });
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
}
