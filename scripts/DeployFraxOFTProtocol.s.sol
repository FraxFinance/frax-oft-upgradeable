// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// TODO: package names under same base dir
import { BaseScript } from "frax-std/BaseScript.sol";
import { Constants } from "frax-template/src/contracts/Constants.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EndpointV2 } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/EndpointV2.sol";

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

            OFTUpgradeable(proxyOft).setPeer(ethereum, addressToBytes32(legacyOft));
            OFTUpgradeable(proxyOft).setPeer(base, addressToBytes32(legacyOft));
            OFTUpgradeable(proxyOft).setPeer(blast, addressToBytes32(legacyOft));
            OFTUpgradeable(proxyOft).setPeer(metis, addressToBytes32(legacyOft));
        }
    }

    /// @dev Upgradeable OFTs maintaining the same address cross-chain.
    function setProxyPeers() public broadcastAs(configDeployer) {
        // TODO
        for (uint256 i=0; i<proxyOfts.length; i++) {
            address proxyOft = proxyOfts[i];
            // TODO: setup peerEids
            // for (uint256 p=0; i<peerEids.length; p++) {
            //     OFTUpgradeable(proxyOft).setPeer(peerEids[p], addressToBytes32(proxyOft));
            // }
        }
    }


    // TODO: missing ecosystem tokens (FPI, etc.)
    function deployFraxOFTUpgradeablesAndProxies() public {
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
        proxy = address(new TransparentUpgradeableProxy(implementation, configDeployer, initializeArgs));
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
