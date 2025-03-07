// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { OFTUpgradeableMock } from "contracts/mocks/OFTUpgradeableMock.sol";
import { CustodianMock } from "contracts/mocks/CustodianMock.sol";

/// @dev deploy/setup upgradeable mock OFTs and mint lockbox supply to the CustodianMock
// forge script scripts/ops/MoveLegacyLiquidity/1_DeployMockOFTs.s.sol --rpc-url https://rpc.frax.com
contract DeployMockOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    L0Config public ethConfig;

    /*
    How balances were determined:
    1. Go to the legacy lockbox address on Ethereum
    2. Get the total balance of token in the legacy lockbox
    3. Using the same address on base, blast, and metis, subtract the token total supply

    Even if users bridge to/from these chains and the balances change, the additional balances in the lockboxes remain constant.
    */
    uint256 intitialFrxUsdSupply = 294_703.796e18 -     // ethereum
                                        101.751e18 -    // base
                                        0.001e18 -      // blast
                                        0.01e18;        // metis

    uint256 intitialSFrxUsdSupply = 288_442.533e18 -    // ethereum
                                        31_816.103e18 - // base
                                        3_496.227e18 -  // blast
                                        102.138e18;     // metis

    uint256 intitialFrxEthSupply = 257.507e18 -         // ethereum
                                        0.1923e18 -     // base
                                        0.0057e18 -     // blast
                                        0;              // metis

    uint256 intitialSFrxEthSupply = 199.12e18 -         // ethereum
                                        45.7842e18 -    // base
                                        23.7698e18 -    // blast
                                        3.9053e18;      // metis

    uint256 intitialFxsSupply = 131_950.021e18 -        // ethereum
                                    27_477.41e18 -      // base
                                    3_557.605e18 -      // blast
                                    111.127e18;         // metis

    constructor() {
        // already deployed
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
        // doesn't matter what address the proxyAdmin is- just needs to be non-zero for `deployFraxOFTUpgradeableAndProxy()`
        proxyAdmin = address(0x11);
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/scripts/ops/MoveLegacyLiquidity/txs/1_DeployMockOFTs.json");
    }

    // Set the config so that we're only pointing to the Ethereum legacy lockboxes
    function run() public override {
        delete connectedOfts;
        connectedOfts.push(ethFraxLockboxLegacy);
        connectedOfts.push(ethSFraxLockboxLegacy);
        connectedOfts.push(ethFrxEthLockboxLegacy);
        connectedOfts.push(ethSFrxEthLockboxLegacy);
        connectedOfts.push(ethFxsLockboxLegacy);

        for (uint256 i=0; i<proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 1) {
                ethConfig = proxyConfigs[i];
            }
        }
        delete proxyConfigs;
        proxyConfigs.push(ethConfig);

        super.run();
    }

    function deploySource() public override {
        deployFraxOFTUpgradeablesAndProxies();
        deployCustodianMock();
    }

    /// @dev override to maintain connectedOfts as configured in run()
    function _populateConnectedOfts() public override {}

    function setupSource() public override broadcastAs(configDeployerPK) {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: connectedOfts,
            _configs: proxyConfigs
        });

        /// @dev configures legacy configs as well
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        // no need to set roles
        // setPriviledgedRoles();
    }

    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "connectedOfts.length != _peerOfts.length");
        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                // address peerOft = determinePeer({
                //     _chainid: _configs[c].chainid,
                //     _oft: _peerOfts[o],
                //     _peerOfts: _peerOfts
                // });
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(_peerOfts[o])
                });
            }
        }
    }    

    // Deploy the mock contracts
    function deployFraxOFTUpgradeablesAndProxies() /* broadcastAs(oftDeployerPK) */ broadcastAs(configDeployerPK) public override {

        // Deploy frxUSD
        (,frxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax USD",
            _symbol: "mfrxUSD"
        });

        // Deploy sfrxUSD
        (,sfrxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Staked Frax USD",
            _symbol: "msfrxUSD"
        });

        // Deploy frxETH
        (,frxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax Ether",
            _symbol: "mfrxETH"
        });

        // Deploy sfrxETH
        (,sfrxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Staked Frax Ether",
            _symbol: "msfrxETH"
        });

        // Deploy FXS
        (,fxsOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax Share",
            _symbol: "mFXS"
        });
    }

    function deployCustodianMock() public broadcastAs(configDeployerPK) {
        // Deploy the mock custodian
        address custodian = address(new CustodianMock({
            _refundAddr: vm.addr(configDeployerPK),
            _mockFrxUsdOft: frxUsdOft,
            _mockSfrxUsdOft: sfrxUsdOft,
            _mockFrxEthOft: frxEthOft,
            _mockSfrxEthOft: sfrxEthOft,
            _mockFxsOft: fxsOft
        }));

        console.log("CustodianMock deployed at:", custodian);

        // Send the initial supply to the mock custodian
        OFTUpgradeableMock(frxUsdOft).mintInitialSupply(custodian, intitialFrxUsdSupply);
        OFTUpgradeableMock(sfrxUsdOft).mintInitialSupply(custodian, intitialSFrxUsdSupply);
        OFTUpgradeableMock(frxEthOft).mintInitialSupply(custodian, intitialFrxEthSupply);
        OFTUpgradeableMock(sfrxEthOft).mintInitialSupply(custodian, intitialSFrxEthSupply);
        OFTUpgradeableMock(fxsOft).mintInitialSupply(custodian, intitialFxsSupply);
    }

    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public override returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(OFTUpgradeableMock).creationCode),
            abi.encode(broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(configDeployerPK), ""));

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
}