// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// TODO: package names under same base dir
import { BaseScript } from "frax-std/BaseScript.sol";
import { Constants } from "frax-template/src/contracts/Constants.sol";
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
- Mode msig
- Mode RPC
- Legacy chains
    - setProxyPeers()
    - setEnforcedOptions()
    - setDVNs()
- Sam to setup frxETH, FPI with L0 mainnet adapter & legacies

Required DVNs:
- L0
- Horizon

Mainnet Addresses
- FXSOFTAdapter:        0x23432452B720C80553458496D4D9d7C5003280d0
- sFRAXOFTAdapter:      0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E
- sfrxETHOFTAdapter:    0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A
- FRAXOFTAdapter:       0x909DBdE1eBE906Af95660033e478D59EFe831fED
    > Has no TVL / txs
    > I have not confirmed DVNs
*/


contract DeployFraxOFTProtocol is BaseScript {
    using OptionsBuilder for bytes;

    uint256 public oftDeployer = vm.envUint("PK_OFT_DEPLOYER");
    uint256 public configDeployer = vm.envUint("PK_CONFIG_DEPLOYER");
    address public delegate = vm.envAddress("DELEGATE");

    // TODO: load in dynamic
    address public endpoint = 0x1a44076050125825900e736c501f859c50fE728c;

    // Deployed proxies
    address public proxyAdmin
    address public fxsOft;
    address public sFraxOft;
    address public frxEthOft;
    address public sFraxOft;

    /// EIDs- each value should be unique
    uint32[] public legacyEids;
    uint32[] public proxyEids;
    
    // 1:1 match between these arrays for setting peers
    address[] public legacyOfts;
    address[] public proxyOfts;

    EnforcedOptionParam[] public enforcedOptionsParams;

    SetConfigParam[] public setConfigParams;

    uint256 public chainId;
    // string public rpc;

    modifier broadcastAs(uint256 privateKey) {
        vm.startBroadcast(privateKey);
        _;
        vm.stopBroadcast();
    }

    function setUp() external {
        // Set constants based on deployment chain id
        chainId = block.chainid;
        if (chainId == 1) {
            delegate = Constants.Mainnet.TIMELOCK_ADDRESS;
            endpoint = Constants.Mainnet.L0_ENDPOINT; // TODO: does this vary per OFT?
        } else if (chainId == 34443) {
            // mode
            delegate = Constants.Mode.TIMELOCK_ADDRESS;
            endpoint = Constants.Mode.L0_ENDPOINT;
        }
        require(delegate != address(0), "Empty delegate");
        require(endpoint != address(0), "Empty endpoint");

        /// @dev: this array maintains the same token order as proxyOfts and the addrs are confirmed on eth mainnet.
        legacyOfts.push(0x23432452B720C80553458496D4D9d7C5003280d0); // fxs
        legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX
        legacyOfts.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sfrxETH
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX

        /// @dev EIDs from https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
        legacyEids.push(uint32(30101)); // ethereum
        legacyEids.push(uint32(30151)); // metis
        legacyEids.push(uint32(30184)); // base
        legacyEids.push(uint32(30253)); // blast
    }

    function run() external {
        deployFraxOFTUpgradeablesAndProxies();
        setLegacyPeers();
        setProxyPeers();
        setEnforcedOptions();
        setDVNs();
        setPriviledgedRoles();
    }

    function setDVNs() public {
        UlnConfig memory ulnConfig;
        ulnConfig.requiredDVNCount = 2;
        address[] memory requiredDVNs = new address[](2);
        // TODO: change from mode
        // https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses#layerzero-labs
        address dvnHorizon = 0xaCDe1f22EEAb249d3ca6Ba8805C8fEe9f52a16e7;
        address dvnL0 = 0xce8358bc28dd8296Ce8cAF1CD2b44787abd65887;
        // sort in ascending order
        if (uint160(dvnHorizon) < uint160(dvnL0)) {
            requiredDvns[0] = dvnHorizon;
            requiredDVNs[1] = dvnL0;
        } else {
            requiredDVNs[0] = dvnL0;
            requiredDvns[1] = dvnHorizon;
        }
        ulnConfig.requiredDVNs = requiredDVNs;

        // push config for legacy OFTs
        for (uint256 e=0; e<legacyEids.length; e++) {
            setConfigParams.push(
                SetConfigParam({
                    eid: legacyEids[e],
                    configType: Constant.CONFIG_TYPE_ULN,
                    abi.encode(ulnConfig)                    
                })
            );
        }

        // TODO: push config for proxy OFTs
        for (uint256 e=0; e<proxyEids.length; e++) {
            setConfigParams.push(
                SetConfigParam({
                    eid: proxyEids[e],
                    configType: Constant.CONFIG_TYPE_ULN,
                    abi.encode(ulnConfig)
                })
            );
        }

        // TODO: change from mode
        address receiveLib302 = 0xc1B621b18187F74c8F6D52a6F709Dd2780C09821;
        address sendLib302 = 0x2367325334447C5E1E0f1b3a6fB947b262F58312;

        // Submit txs to setup DVN on source chain
        for (uint256 i=0; i<proxyOfts.length; i++) {
            IMessageLibManager(endpoint).setConfig({
                _oapp: proxyOfts[i],
                _lib: receiveLib302,
                _params: setConfigParams
            });
            IMessageLibManager(endpoint).setConfig({
                _oapp: proxyOfts[i],
                _lib: sendLib302,
                _params: setConfigParams
            });
        }
    }

    function setPriviledgedRoles() public {
        /// @dev transfer ownership of OFT and proxy
        for (uint256 i=0; i<proxyOfts.length; i++) {
            address proxyOft = proxyOfts[i];
            Ownable(proxyOft).transferOwnership(delegate);
            OFTUpgradeable(proxyOft).setDelegate(delegate);
        }
    }

    function setEnforcedOptions() public {
        // For each peer, default 
        // https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/OFT.t.sol#L417
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250000, 0);

        // legacy eids
        for (uint256 e=0; e<legacyEids.length; e++) {
            uint32 eid = legacyEids[e];
            enforcedOptionsParams.push(EnforcedOptionParam(eid, 1, optionsTypeOne));
            enforcedOptionsParams.push(EnforcedOptionParam(eid, 2, optionsTypeTwo));
        }

        // TODO: proxy eids
        // for (uint256 p=0; p<proxyEids.length; p++) {
        //     uint32 eid = proxyEids[p];
        //     enforcedOptionsParams.push(EnforcedOptionParam(eid, 1, optionsTypeOne));
        //     enforcedOptionsParams.push(EnforcedOptionParam(eid, 2, optionsTypeTwo));
        // }

        for (uint256 i=0; i<proxyOfts.length; i++) {
            OFTUpgradeable(proxyOfts[i]).setEnforcedOptions(enforcedOptionsParams);
        }
    }

    /// @dev legacy, non-upgradeable OFTs
    function setLegacyPeers() public broadcastAs(configDeployer) {
        for (uint256 i=0; i<proxyOfts.length; i++) {
            address proxyOft = proxyOfts[i];
            address legacyOft = legacyOfts[i];
            for (uint256 e=0; e<legacyEids.length; e++) {
                OFTUpgradeable(proxyOft).setPeer(legacyEids[e], addressToBytes32(legacyOft));
            }
        }
    }

    /// @dev Upgradeable OFTs maintaining the same address cross-chain.
    function setProxyPeers() public broadcastAs(configDeployer) {
        // TODO
        for (uint256 i=0; i<proxyOfts.length; i++) {
            address proxyOft = proxyOfts[i];
            // TODO: setup proxyEids
            // for (uint256 p=0; i<proxyEids.length; p++) {
            //     OFTUpgradeable(proxyOft).setPeer(proxyEids[p], addressToBytes32(proxyOft));
            // }
        }
    }


    // TODO: missing ecosystem tokens (FPI, etc.)
    function deployFraxOFTUpgradeablesAndProxies() public {

        // Proxy admin
        proxyAdmin = new ProxyAdmin(delegate);

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
    ) public broadcastAs(oftDeployer) returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(OFTUpgradeable).creationCode),
            abi.encode(endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: config deployer is temporary proxy admin until post-setup
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTUpgradeable.initialize.selector,
            _name,
            _symbol,
            configDeployer
        );
        proxy = address(new TransparentUpgradeableProxy(implementation, proxyAdmin, initializeArgs));
        proxyOfts.push(proxy);

        // State checks
        require(
            isStringEqual(OFTUpgradeable(proxy).name(), _name),
            "OFT name incorrect"
        );
        require(
            isStringEqual(OFTUpgradeable(proxy).symbol(), _symbol),
            "OFT symbol incorrect"
        );
        require(
            address(OFTUpgradeable(proxy).endpoint()) == endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(endpoint).delegates(address(this)) == configDeployer,
            "Endpoint delegate incorrect"
        );
        require(
            OFTUpgradeable(proxy).owner() == configDeployer,
            "OFT owner incorrect"
        );
        require(
            TransparentUpgradeableProxy(proxy).admin() == configDeployer,
            "Proxy admin incorrect"
        );
    }

    function isStringEqual(string memory _a, string memory _b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
