// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// TODO: package names under same base dir
import { BaseScript } from "frax-std/BaseScript.sol";
import { Constants } from "frax-template/src/contracts/Constants.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/*
TODO
- Mode msig
- Mode RPC
- state checks
- PK inits
- Mainnet sig

https://etherscan.io/tx/0xc83526447f7c7467d16ea65975a2b39edeb3ebe7c88959af333194a0a24ef0e4#eventlog
(FXS) Mainnet => Base

Required DVNs:
- 0x380275805876Ff19055EA900CDb2B46a94ecF20D
- 0x589dEDbD617e0CBcB916A9223F4d1300c294236b

Delegate & owner: 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27

Mainnet Addresses
- FXSOFTAdapter:        0x23432452B720C80553458496D4D9d7C5003280d0
- sFRAXOFTAdapter:      0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E
- sfrxETHOFTAdapter:    0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A
- FRAXOFTAdapter:       0x909DBdE1eBE906Af95660033e478D59EFe831fED
    > Has no TVL / txs
    > I have not confirmed DVNs
*/


contract DeployFraxOFTProtocol is BaseScript {

    // TODO: convert to PK
    uint256 public oftDeployer = 1;
    uint256 public configDeployer = 1;

    address public delegate;
    address public endpoint;

    // Deployed proxies
    address public fxsOft;
    address public sFraxOft;
    address public frxEthOft;
    address public sFraxOft;

    // 1:1 match between these arrays for setting peers
    address[] public proxyOfts;
    address[] public legacyOfts;

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

        /// @dev: this array maintains the same token order as proxyOfts and the addrs are confirmed on eth mainnet.
        legacyOfts.push(0x23432452B720C80553458496D4D9d7C5003280d0); // fxs
        legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX
        legacyOfts.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sfrxETH
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
    }

    function run() external {
        deployFraxOFTUpgradeablesAndProxies();
        setLegacyPeers();
        setProxyPeers();
        // TODO: set enforced options
        setDelegate();
        transferOwnerships();
        // TODO: state checks
    }

    function trasferOwnerships() public broadcastAs(configDeployer) {
        /// @dev transfer ownership of OFT and proxy
        for (uint256 i=0; i<proxyOfts.length; i++) {
            address proxyOft = proxyOfts[i];
            Ownable(proxyOft).transferOwnership(delegate);
            TransparentUpgradeableProxy(proxyOft).changeAdmin(delegate);
        }
    }

    function setDelegate() public broadcastAs(configDeployer) {
        for (uint256 i=0; i<proxyOfts.length; i++) {
            OFTUpgradeable(proxyOfts[i]).setDelegate(delegate);
        }
    }

    /// @dev legacy, non-upgradeable OFTs
    function setLegacyPeers() public broadcastAs(configDeployer) {
        /// @dev EIDs from https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
        uint256 ethereum = 30101;
        uint256 metis = 30151;
        uint256 base = 30184;
        uint256 blast = 30243;
        
        for (uint256 i=0; i<proxyOfts.length; i++) {
            address proxyOft = proxyOfts[i];
            address legacyOft = legacyOfts[i];

            OFTUpgradeable(proxyOft).setPeer(ethereum, abi.encode(legacyOft));
            OFTUpgradeable(proxyOft).setPeer(base, abi.encode(legacyOft));
            OFTUpgradeable(proxyOft).setPeer(blast, abi.encode(legacyOft));
            OFTUpgradeable(proxyOft).setPeer(metis, abi.encode(legacyOft));
        }
    }

    /// @dev Upgradeable OFTs maintaining the same address cross-chain.
    function setProxyPeers() public broadcastAs(configDeployer) {
        // TODO
        for (uint256 i=0; i<proxyOfts.length; i++) {
            address proxyOft = proxyOfts[i];
            // TODO: setup peerEids
            // for (uint256 p=0; i<peerEids.length; p++) {
            //     OFTUpgradeable(proxyOft).setPeer(peerEids[p], abi.encode(proxyOft));
            // }
        }
    }


    // TODO: missing ecosystem tokens (FPI, etc.)
    function deployFraxOFTUpgradeablesAndProxies() public {
        /// @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d

        // Deploy FXS
        (,fxsOft) = deployFraxOFTUpgradeableAndProxy({
            _oftBytecode: type(OFTUpgradeable).creationCode,
            _constructorArgs: abi.encode(endpoint),
            _initializeArgs: abi.encodeWithSelector(
                FraxOFTUpgradeable.initialize.selector,
                "Frax Share",
                "FXS",
                configDeployer
            )
        });

        // Deploy sFRAX
        (,sFraxOft) = deployFraxOFTUpgradeableAndProxy({
            _oftBytecode: type(OFTUpgradeable).creationCode,
            _constructorArgs: abi.encode(endpoint),
            _initializeArgs: abi.encodeWithSelector(
                FraxOFTUpgradeable.initialize.selector,
                "Staked Frax",
                "sFRAX",
                configDeployer
            )
        });

        // sfrxETH
        (,sfrxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _oftBytecode: type(OFTUpgradeable).creationCode,
            _constructorArgs: abi.encode(endpoint),
            _initializeArgs: abi.encodeWithSelector(
                FraxOFTUpgradeable.initialize.selector,
                "Staked Frax Ether",
                "sfrxETH",
                configDeployer
            )
        });

        // Deploy FRAX
        (,fraxOft) = deployFraxOFTUpgradeableAndProxy({
            _oftBytecode: type(OFTUpgradeable).creationCode,
            _constructorArgs: abi.encode(endpoint),
            _initializeArgs: abi.encodeWithSelector(
                FraxOFTUpgradeable.initialize.selector,
                "Frax",
                "FRAX",
                configDeployer
            )
        });

            // Deploy FPI
        // address frxEthOft = deployFraxOFTUpgradeableAndProxy({
        //     _oftBytecode: type(OFTUpgradeable).creationCode,
        //     _constructorArgs: abi.encode(endpoint),
        //     _initializeArgs: abi.encodeWithSelector(
        //         FraxOFTUpgradeable.initialize.selector,
        //         "Frax Price Index",
        //         "FPI",
        //         delegate
        //     )
        // });

    }

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    function deployFraxOFTUpgradeableAndProxy(
        bytes memory _oftBytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs
    ) public broadcastAs(oftDeployer) returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oftBytecode), _constructorArgs);
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: config deployer is temporary proxy admin until post-setup
        proxy = address(new TransparentUpgradeableProxy(implementation, configDeployer, _initializeArgs));

        proxyOfts.push(proxy);
    }
}
