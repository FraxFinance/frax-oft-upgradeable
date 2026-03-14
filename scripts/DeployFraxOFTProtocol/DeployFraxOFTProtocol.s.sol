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
        require(proxyOfts.length == NUM_OFTS, "Error: non-evm setup will be incorrect");

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
        require(proxyOfts.length == NUM_OFTS, "Did not deploy all OFTs");
    }

    function deployFraxOFTUpgradeablesAndProxies() public virtual broadcastAs(oftDeployerPK) {
        // Proxy admin — deployed deterministically via Nick's CREATE2
        proxyAdmin = deployCreate2({
            _salt: "FraxProxyAdmin",
            _initCode: abi.encodePacked(
                type(FraxProxyAdmin).creationCode,
                abi.encode(msg.sender)
            )
        });
        
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

        // Deploy FPI
        (, fpiOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Price Index",
            _symbol: "FPI"
        });
    }

    /// @notice Deploy a FraxOFTUpgradeable behind a TransparentUpgradeableProxy.
    /// @dev    Uses _deployAndValidateProxy() to eliminate duplicated proxy-creation
    ///         and state-check logic (previously copy-pasted across two functions).
    /// @notice Create the OFT implementation contract.
    /// @dev    Override to swap in a chain-specific implementation (e.g. FraxOFTUpgradeableTempo).
    function _createOFTImplementation() internal virtual returns (address) {
        return address(new FraxOFTUpgradeable(broadcastConfig.endpoint));
    }

    /// @notice Return the address used as the temporary TransparentUpgradeableProxy admin
    ///         during deployment (before changeAdmin transfers it to proxyAdmin).
    function _proxyTempAdmin() internal virtual view returns (address) {
        revert("Must override _proxyTempAdmin() to return the address of the temporary proxy admin");
    }

    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public virtual returns (address implementation, address proxy) {
        implementation = _createOFTImplementation();
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTUpgradeable.initialize.selector,
            _name,
            _symbol,
            msg.sender
        );
        proxy = _deployAndValidateProxy(implementation, initializeArgs, _name, _symbol);
    }

    /// @notice Deploy FrxUSDOFTUpgradeable (name/symbol are hardcoded in the contract itself).
    function deployFrxUsdOFTUpgradeableAndProxy() public virtual returns (address implementation, address proxy) {
        implementation = address(new FrxUSDOFTUpgradeable(broadcastConfig.endpoint));
        bytes memory initializeArgs = abi.encodeWithSelector(
            FrxUSDOFTUpgradeable.initialize.selector,
            msg.sender
        );
        proxy = _deployAndValidateProxy(implementation, initializeArgs, "Frax USD", "frxUSD");
    }

    /// @notice Common proxy deployment + post-deploy validation.
    ///         Creates a TransparentUpgradeableProxy pointing at the mock implementation,
    ///         upgrades to the real implementation, transfers admin to proxyAdmin, and
    ///         runs state checks.
    function _deployAndValidateProxy(
        address _implementation,
        bytes memory _initializeArgs,
        string memory _expectedName,
        string memory _expectedSymbol
    ) internal virtual returns (address proxy) {
        /// @dev: deploy proxy deterministically via Nick's CREATE2 using the symbol as salt
        proxy = deployCreate2({
            _salt: _expectedSymbol,
            _initCode: abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(implementationMock, _proxyTempAdmin(), "")
            )
        });

        /// @dev: broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: _implementation,
            data: _initializeArgs
        });

        // Transfer admin to proxyAdmin
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        proxyOfts.push(proxy);

        // State checks
        require(
            isStringEqual(FraxOFTUpgradeable(proxy).name(), _expectedName),
            string.concat("OFT name mismatch: expected ", _expectedName)
        );
        require(
            isStringEqual(FraxOFTUpgradeable(proxy).symbol(), _expectedSymbol),
            string.concat("OFT symbol mismatch: expected ", _expectedSymbol)
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
        console.log(string.concat("  Deployed ", _expectedSymbol, " proxy"));
    }

    /// @notice Transfer delegate + ownership of all OFTs and the ProxyAdmin to the
    ///         configured delegate/multisig.
    /// @dev    Name preserved for backward compatibility with downstream overrides.
    function setPriviledgedRoles() public virtual {
        if (broadcastConfig.delegate == address(0)) revert("Delegate cannot be zero address");
        console.log("Transferring ownership to delegate");
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

    /// @notice Look up the correct peer OFT address for `_oft` on chain `_chainid`.
    ///         Uses the data-driven `chainPeerAddresses` registry from L0Constants for
    ///         registered chains, falls back to the supplied `_peerOfts` array otherwise.
    ///         Adding a new chain only requires a `_registerChain()` call in L0Constants.
    // NOTE on partial token deployments, {token}Oft must be set
    function determinePeer(
        uint256 _chainid,
        address _oft,
        address[] memory _peerOfts
    ) public virtual view returns (address peer) {
        // Testnet chains use separate single-element arrays
        if (_chainid == 11155111) {
            peer = getTestnetPeerFromArray({ _oft: _oft, _oftArray: ethSepoliaLockboxes });
        } else if (_chainid == 421614) {
            peer = getTestnetPeerFromArray({ _oft: _oft, _oftArray: arbitrumSepoliaOfts });
        } else if (_chainid == 2522) {
            peer = getTestnetPeerFromArray({ _oft: _oft, _oftArray: fraxtalTestnetLockboxes });
        } else if (chainPeerAddresses[_chainid].length == NUM_OFTS) {
            // Data-driven: registered chains resolved via the L0Constants registry.
            // No code changes needed when adding new chains.
            peer = getPeerFromArray({ _oft: _oft, _oftArray: chainPeerAddresses[_chainid] });
        } else {
            // Fallback: use the caller-supplied proxy OFT addresses
            peer = getPeerFromArray({ _oft: _oft, _oftArray: _peerOfts });
        }
        require(peer != address(0), string.concat("Invalid peer for chain ", _chainid.toString()));
    }

    /// @notice Resolve an OFT proxy address to the corresponding peer in a given per-chain
    ///         address array.  Uses `tokenIndex()` from BaseL0Script to map the OFT to its
    ///         canonical Token enum index, replacing the previous if/else ladder.
    function getPeerFromArray(address _oft, address[] memory _oftArray) public virtual view returns (address peer) {
        require(_oftArray.length == NUM_OFTS, "getPeerFromArray: array length != NUM_OFTS");
        require(_oft != address(0), "getPeerFromArray: OFT is zero address");
        peer = _oftArray[tokenIndex(_oft)];
    }

    function getTestnetPeerFromArray(address _oft, address[] memory _oftArray) public virtual view returns (address peer) {
        require(_oftArray.length == 1, "getTestnetPeerFromArray: array length != 1");
        require(_oft != address(0), "getTestnetPeerFromArray: OFT is zero address");
        require(tokenIndex(_oft) == uint256(Token.FRXUSD), "getTestnetPeerFromArray: only frxUSD supported on testnet");
        peer = _oftArray[0];
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
        _safeCall(_connectedOft, data, "setPeer");
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
        _safeCall(_connectedOft, data, "setEnforcedOptions");
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
            _safeCall(_connectedConfig.endpoint, data, "setSendLibrary");
            pushSerializedTx({
                _name:"setSendLibrary",
                _to: _connectedConfig.endpoint,
                _value: 0,
                _data: data
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
            _safeCall(_connectedConfig.endpoint, data, "setReceiveLibrary");
            pushSerializedTx({
                _name:"setReceiveLibrary",
                _to: _connectedConfig.endpoint,
                _value: 0,
                _data: data
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
        bytes32 salt = _generateCreate2Salt( _salt);

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
        bytes32 salt = _generateCreate2Salt(_salt);
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            NICK_CREATE2_DEPLOYER,
            salt,
            keccak256(_initCode)
        )))));
    }

    // ── Vanity CREATE2 salts (from create2crunch) ─────────────────────────
    // Each salt is the raw 32-byte value sent to Nick's CREATE2 deployer.
    // All addresses produced have 4 leading zero bytes for gas-efficient storage.

    function _vanitySalt(string memory _name) internal pure returns (bytes32) {
        bytes32 nameHash = keccak256(bytes(_name));

        // Infrastructure
        if (nameHash == keccak256("FraxProxyAdmin"))    return 0x00000000000000000000000000000000000000001ca47e3bdd2f9c2d22000094;
        if (nameHash == keccak256("ImplementationMock")) return 0x00000000000000000000000000000000000000001c9e6c0415a3e0f991090040;

        // OFT proxies
        if (nameHash == keccak256("WFRAX"))    return 0x0000000000000000000000000000000000000000e89cf04fa1492387a9080080;
        if (nameHash == keccak256("sfrxUSD"))  return 0x0000000000000000000000000000000000000000e89cf04fa1497779b3260030;
        if (nameHash == keccak256("sfrxETH"))  return 0x0000000000000000000000000000000000000000e89cf04fa14917675b2700a0;
        if (nameHash == keccak256("frxUSD"))   return 0x0000000000000000000000000000000000000000e89cf04fa149c185b52d0006;
        if (nameHash == keccak256("frxETH"))   return 0x0000000000000000000000000000000000000000e89cf04fa14981f4e2470008;
        if (nameHash == keccak256("FPI"))      return 0x0000000000000000000000000000000000000000e89cf04fa1496467a96d00c0;

        return bytes32(0); // no vanity salt found
    }

    /// @notice Generate a CREATE2 salt for deterministic deployment.
    ///         Uses a vanity salt from create2crunch when available, otherwise
    ///         falls back to keccak256(name).
    /// @param _name The name used to generate the salt
    /// @return The generated salt
    function _generateCreate2Salt(string memory _name) internal pure returns (bytes32) {
        bytes32 vanity = _vanitySalt(_name);
        if (vanity != bytes32(0)) return vanity;
        return keccak256(abi.encodePacked(_name));
    }
}
