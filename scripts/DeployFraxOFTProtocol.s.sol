// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// TODO: package names under same base dir
import { Script } from "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "frax-template/src/Constants.sol";
import {SerializedTx, SafeTxUtil} from "./SafeBatchSerialize.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { ImplementationMock } from "contracts/mocks/ImplementationMock.sol";
import { ProxyAdmin, TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/ProxyAdmin.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { EndpointV2 } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/EndpointV2.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SetConfigParam, IMessageLibManager} from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/uln/UlnBase.sol";
import { EnforcedOptionParam, IOAppOptionsType3 } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { Constant } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/test/util/Constant.sol";

import { IOAppCore } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppCore.sol";

/*
TODO
- push txs to files
- Setup frxETH, FPI with L0 mainnet adapter & legacies
- Proxy EIDs

Required DVNs:
- L0
- Horizon
- example: https://explorer.metis.io/tx/0x465d4dac4e7bc8cb9c8be8908aac5bdc00b4bc64988f82c1e46c10b3c93829e5/eventlog

Mainnet Addresses
- FXSOFTAdapter:        0x23432452B720C80553458496D4D9d7C5003280d0
- sFRAXOFTAdapter:      0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E
- sfrxETHOFTAdapter:    0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A
- FRAXOFTAdapter:       0x909DBdE1eBE906Af95660033e478D59EFe831fED
    > Has no TVL / txs
    > I have not confirmed DVNs
*/


contract DeployFraxOFTProtocol is Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256 public oftDeployerPK = vm.envUint("PK_OFT_DEPLOYER");
    uint256 public configDeployerPK = vm.envUint("PK_CONFIG_DEPLOYER");

    /// @dev: required to be alphabetical to conform to https://book.getfoundry.sh/cheatcodes/parse-json
    struct L0Config {
        string RPC;
        uint256 chainid;
        address delegate;
        address dvnL0;
        address dvnHorizon;
        uint256 eid;
        address endpoint;
        address receiveLib302;
        address sendLib302;
    }
    L0Config[] public legacyConfigs;
    L0Config[] public proxyConfigs;
    L0Config[] public configs; // legacy & proxy configs
    L0Config public proxyConfig;
    L0Config[] public proxyConfigArray; // length of 1 of proxyConfig

    // Mock implementation used to enable pre-determinsitic proxy creation
    address public implementationMock;

    // Deployed proxies
    address public proxyAdmin;
    address public fxsOft;
    address public sFraxOft;
    address public sfrxEthOft;
    address public fraxOft;
    uint256 public numOfts;

    // 1:1 match between these arrays for setting peers
    address[] public legacyOfts;
    address[] public proxyOfts;

    EnforcedOptionParam[] public enforcedOptionsParams;

    SetConfigParam[] public setConfigParams;

    SerializedTx[] serializedTxs;

    uint256 public chainid;

    function version() public pure returns (uint256, uint256, uint256) {
        return (0, 2, 0);
    }

    modifier broadcastAs(uint256 privateKey) {
        vm.startBroadcast(privateKey);
        _;
        vm.stopBroadcast();
    }


    modifier simulateAndWriteTxs(L0Config memory _config) {
        vm.createSelectFork(_config.RPC);
        chainid = _config.chainid;
        vm.startPrank(_config.delegate);
        _;
        vm.stopPrank();

        // create filename and save
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/txs/");
        string memory filename = string.concat(proxyConfig.chainid.toString(), "-");
        filename = string.concat(filename, _config.chainid.toString());
        filename = string.concat(filename, ".json");
        
        // new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
        // for (uint256 i=0; i<serializedTxs.length; i++) {
        //     serializedTxs.pop();
        // }
    }

    function setUp() external {
        // Set constants based on deployment chain id
        chainid = block.chainid;
        loadJsonConfig();

        /// @dev: this array maintains the same token order as proxyOfts and the addrs are confirmed on eth mainnet.
        legacyOfts.push(0x23432452B720C80553458496D4D9d7C5003280d0); // fxs
        legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX
        legacyOfts.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sfrxETH
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        numOfts = legacyOfts.length;
    }

    function loadJsonConfig() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/L0Config.json");
        string memory json = vm.readFile(path);
        
        // load and write to persistent storage

        // legacy
        L0Config[] memory legacyConfigs_ = abi.decode(json.parseRaw(".Legacy"), (L0Config[]));
        for (uint256 i=0; i<legacyConfigs_.length; i++) {
            L0Config memory config_ = legacyConfigs_[i];
            legacyConfigs.push(config_);
            configs.push(config_);
        }

        // proxy (active deployment loaded as proxyConfig)
        L0Config[] memory proxyConfigs_ = abi.decode(json.parseRaw(".Proxy"), (L0Config[]));
        for (uint256 i=0; i<proxyConfigs_.length; i++) {
            L0Config memory config_ = proxyConfigs_[i];
            if (config_.chainid == chainid) {
                proxyConfig = config_;
                proxyConfigArray.push(config_);
            }
            proxyConfigs.push(config_);
            configs.push(config_);
        }
        require(proxyConfig.chainid != 0, "L0Config for source not loaded");
    }

    function run() external {
        deploySource();
        setupSource();
        setupDestinations();
    }

    function deploySource() public {
        preDeployChecks();
        deployFraxOFTUpgradeablesAndProxies();
        postDeployChecks();
    }

    function setupDestinations() public {
        setupLegacyDestinations();
        setupProxyDestinations();
    }

    function setupLegacyDestinations() public {
        for (uint256 i=0; i<legacyConfigs.length; i++) {
            setupDestination({
                _connectedConfig: legacyConfigs[i],
                _connectedOfts: legacyOfts
            });
        }
    }

    function setupProxyDestinations() public {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // skip if destination == source
            if (proxyConfigs[i].eid == proxyConfig.eid) continue;
            setupDestination({
                _connectedConfig: proxyConfigs[i],
                _connectedOfts: proxyOfts
            });
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public simulateAndWriteTxs(_connectedConfig) {
        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: proxyConfigArray
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: proxyConfigArray
        });

        setPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: proxyOfts,
            _configs: proxyConfigArray
        });
    }

    function setupSource() public broadcastAs(configDeployerPK) {
        // TODO: this will break if proxyOFT addrs are not the pre-determined addrs verified in postDeployChecks()
        setEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: configs
        });

        setDVNs({
            _connectedConfig: proxyConfig,
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

    function preDeployChecks() public view {
        for (uint256 e=0; e<configs.length; e++) {
            uint256 eid = configs[e].eid;    
            // source and dest eid cannot be same
            if (eid == proxyConfig.eid) continue;
            require(
                IMessageLibManager(proxyConfig.endpoint).isSupportedEid(uint32(configs[e].eid)),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
    }

    function postDeployChecks() public view {
        // Ensure OFTs are their expected pre-determined address.  If not, there's a chance the deployer nonce shifted,
        // the EVM has differing logic, or we are not on an EVM compatable chain.
        // TODO: support for non-evm addresses
        // TODO: validate that differing OFT addrs does not impact assumed setup functions.
        // require(fxsOft == 0x01a438c169d9f463577314f37a32c5fc9a8c4bf7);
        // require(sFraxOft == 0x2c6d5516a6d77478cf17997e8493e3b646715f4a);
        // require(sfrxETH == 0x6e992ac12bbf50f7922a1d61b57b1fd9c1697717);
        // require(fraxOft == 0xfe024ed7199f11a834744ffa2f8e189d1ae930a1);
        require(proxyOfts.length == numOfts);
    }

    // TODO: missing ecosystem tokens (FPI, etc.)
    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(oftDeployerPK) public {

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
    }

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    ///     With state checks
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(FraxOFTUpgradeable).creationCode),
            abi.encode(proxyConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: create pre-deterministic proxy address, then initialize with correct implementation
        bytes32 salt = keccak256(abi.encodePacked(_symbol));
        proxy = address(new TransparentUpgradeableProxy{salt: salt}(implementationMock, vm.addr(oftDeployerPK), ""));

        /// @dev: proxyConfig deployer is temporary OFT owner until setPriviledgedRoles()
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
            address(FraxOFTUpgradeable(proxy).endpoint()) == proxyConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(proxyConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }


    function setPriviledgedRoles() public {
        /// @dev transfer ownership of OFT
        for (uint256 o=0; o<numOfts; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(proxyConfig.delegate);
            Ownable(proxyOft).transferOwnership(proxyConfig.delegate);
        }

        /// @dev transfer ownership of ProxyAdmin
        Ownable(proxyAdmin).transferOwnership(proxyConfig.delegate);
    }

    /// @dev _connectedOfts refers to the OFTs of the RPC we are currently connected to
    function setPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address connectedOft = _connectedOfts[o];
            address peerOft = _peerOfts[o];
            for (uint256 c=0; c<_configs.length; c++) {
                uint32 eid = uint32(_configs[c].eid);

                // cannot set peer to self
                if (chainid == proxyConfig.chainid && eid == proxyConfig.eid) continue;

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
    ) public {
        // For each peer, default
        // https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/OFT.t.sol#L417
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000, 0);

        for (uint256 c=0; c<_configs.length; c++) {            
            uint32 eid = uint32(_configs[c].eid);

            // cannot set enforced options to self
            if (chainid == proxyConfig.chainid && eid == proxyConfig.eid) continue;

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
    ) public {
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
            if (chainid == proxyConfig.chainid && eid == proxyConfig.eid) continue;

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
            // require(success, "Unable to setConfig for receiveLib");
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
            // require(success, "Unable to setConfig for sendLib");
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

    function isStringEqual(string memory _a, string memory _b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
