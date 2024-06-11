// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// TODO: package names under same base dir
import { Script } from "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "frax-template/src/Constants.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { ImplementationMock } from "contracts/mocks/ImplementationMock.sol";
import { ProxyAdmin, TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/ProxyAdmin.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EndpointV2 } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/EndpointV2.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SetConfigParam, IMessageLibManager} from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/uln/UlnBase.sol";
import { EnforcedOptionParam } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { Constant } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/test/util/Constant.sol";

/*
TODO
- Msigs for existings chains
    - Mainnet: 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27 
    - Base: 
    - Metis:
    - Blast: 
- Existing chains >
    - setProxyPeers()
    - setEnforcedOptions()
    - setDVNs()
- Setup frxETH, FPI with L0 mainnet adapter & legacies
- Proxy EIDs
- proxy oft adddrs

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

    uint256 public oftDeployerPK = vm.envUint("PK_OFT_DEPLOYER");
    uint256 public configDeployerPK = vm.envUint("PK_CONFIG_DEPLOYER");

    /// @dev: required to be alphabetical to conform to https://book.getfoundry.sh/cheatcodes/parse-json
    struct L0Config {
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

    // Mock implementation used to enable pre-determinsitic proxy creation
    address public implementationMock;

    // Deployed proxies
    address public proxyAdmin;
    address public fxsOft;
    address public sFraxOft;
    address public sfrxEthOft;
    address public fraxOft;

    // 1:1 match between these arrays for setting peers
    address[] public legacyOfts;
    address[] public proxyOfts;

    EnforcedOptionParam[] public enforcedOptionsParams;

    SetConfigParam[] public setConfigParams;

    uint256 public chainId;
    // string public rpc;

    function version() public pure returns (uint256, uint256, uint256) {
        return (0, 1, 0);
    }

    modifier broadcastAs(uint256 privateKey) {
        vm.startBroadcast(privateKey);
        _;
        vm.stopBroadcast();
    }

    function setUp() external {
        // Set constants based on deployment chain id
        chainId = block.chainid;
        loadJsonConfig();

        /// @dev: this array maintains the same token order as proxyOfts and the addrs are confirmed on eth mainnet.
        legacyOfts.push(0x23432452B720C80553458496D4D9d7C5003280d0); // fxs
        legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX
        legacyOfts.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sfrxETH
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
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
            if (config_.chainid == chainId) {
                proxyConfig = config_;
            }
            proxyConfigs.push(config_);
            configs.push(config_);
        }
        require(proxyConfig.chainid != 0, "L0Config for source not loaded");
    }

    function run() external {
        deploySource();
        deployDestinations();   
    }

    function deploySource() public {
        preDeployChecks();
        deployFraxOFTUpgradeablesAndProxies();
        setLegacyPeers();
        setProxyPeers();
        setEnforcedOptions();
        setDVNs();
        setPriviledgedRoles();
    }

    function deployDestinations() public {
        // Start with Ethereum
        // setProxyPeers()
        // setEnforcedOptions()
        // setDVNs()
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

    function setDVNs() broadcastAs(configDeployerPK) public {
        UlnConfig memory ulnConfig;
        ulnConfig.requiredDVNCount = 2;
        address[] memory requiredDVNs = new address[](2);

        // sort in ascending order (as spec'd in UlnConfig)
        if (uint160(proxyConfig.dvnHorizon) < uint160(proxyConfig.dvnL0)) {
            requiredDVNs[0] = proxyConfig.dvnHorizon;
            requiredDVNs[1] = proxyConfig.dvnL0;
        } else {
            requiredDVNs[0] = proxyConfig.dvnL0;
            requiredDVNs[1] = proxyConfig.dvnHorizon;
        }
        ulnConfig.requiredDVNs = requiredDVNs;

        // push proxyConfig
        for (uint256 e=0; e<configs.length; e++) {
            setConfigParams.push(
                SetConfigParam({
                    eid: uint32(configs[e].eid),
                    configType: Constant.CONFIG_TYPE_ULN,
                    config: abi.encode(ulnConfig)                    
                })
            );
        }

        // Submit txs to setup DVN on source chain
        for (uint256 i=0; i<proxyOfts.length; i++) {
            IMessageLibManager(proxyConfig.endpoint).setConfig({
                _oapp: proxyOfts[i],
                _lib: proxyConfig.receiveLib302,
                _params: setConfigParams
            });
            IMessageLibManager(proxyConfig.endpoint).setConfig({
                _oapp: proxyOfts[i],
                _lib: proxyConfig.sendLib302,
                _params: setConfigParams
            });
        }
    }

    function setPriviledgedRoles() broadcastAs(configDeployerPK) public {
        /// @dev transfer ownership of OFT
        for (uint256 i=0; i<proxyOfts.length; i++) {
            address proxyOft = proxyOfts[i];
            FraxOFTUpgradeable(proxyOft).setDelegate(proxyConfig.delegate);
            Ownable(proxyOft).transferOwnership(proxyConfig.delegate);
        }

        /// @dev transfer ownership of ProxyAdmin
        Ownable(proxyAdmin).transferOwnership(proxyConfig.delegate);
    }

    function setEnforcedOptions() broadcastAs(configDeployerPK) public {
        // For each peer, default 
        // https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/OFT.t.sol#L417
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000, 0);

        for (uint256 e=0; e<configs.length; e++) {
            uint32 eid = uint32(configs[e].eid);
            // source and dest eid cannot be same
            if (eid == uint32(proxyConfig.eid)) continue;

            enforcedOptionsParams.push(EnforcedOptionParam(eid, 1, optionsTypeOne));
            enforcedOptionsParams.push(EnforcedOptionParam(eid, 2, optionsTypeTwo));
        }

        for (uint256 i=0; i<proxyOfts.length; i++) {
            FraxOFTUpgradeable(proxyOfts[i]).setEnforcedOptions(enforcedOptionsParams);
        }
    }

    /// @dev legacy, non-upgradeable OFTs
    function setLegacyPeers() public broadcastAs(configDeployerPK) {
        for (uint256 i=0; i<proxyOfts.length; i++) {
            address proxyOft = proxyOfts[i];
            address legacyOft = legacyOfts[i];
            for (uint256 e=0; e<legacyConfigs.length; e++) {
                FraxOFTUpgradeable(proxyOft).setPeer(uint32(legacyConfigs[e].eid), addressToBytes32(legacyOft));
            }
        }
    }

    /// @dev Upgradeable OFTs maintaining the same address cross-chain.
    function setProxyPeers() public broadcastAs(configDeployerPK) {
        for (uint256 i=0; i<proxyOfts.length; i++) {
            address proxyOft = proxyOfts[i];
            for (uint256 e=0; e<proxyConfigs.length; e++) {
                uint256 eid = proxyConfigs[e].eid;

                // cannot set self as peer
                if (eid == proxyConfig.eid) continue;

                FraxOFTUpgradeable(proxyOft).setPeer(uint32(eid), addressToBytes32(proxyOft));
            }
        }
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

        // Deploy FPI
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
        /// @dev: proxyConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTUpgradeable.initialize.selector,
            _name,
            _symbol,
            vm.addr(configDeployerPK)
        );

        /// @dev: create pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));
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

    function isStringEqual(string memory _a, string memory _b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
