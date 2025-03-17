// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { OFTUpgradeableMockMint } from "contracts/mocks/OFTUpgradeableMockMint.sol";
import { CustodianMock } from "contracts/mocks/CustodianMock.sol";

/*
1. Deploy Custodian
2. Deploy upgradeable mock OFTs and mint supply to custodian
3. Build msig tx for Fraxtal msig to send mock OFTs to Ethereum legacy lockboxes 
4. Submit Fraxtal msig tx
    - Fraxtal msig will send the mock OFTs
5. Submit Ethereum tx
     - Legacy lockboxes will be wired to the mock OFTs to execute the send, moving supply
*/

// forge script scripts/ops/MoveLegacyLiquidity/1_DeployMockOFTsAndSend.s.sol --rpc-url https://rpc.frax.com
contract DeployMockOFTsAndSend is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    L0Config public ethConfig;
    CustodianMock public custodian;

    /*
    How balances were determined:
    1. Go to the legacy lockbox address on Ethereum
    2. Get the total balance of token in the legacy lockbox
    3. Using the same address on base, blast, and metis, subtract the token total supply

    Even if users bridge to/from these chains and the balances change, the additional balances in the lockboxes remain constant.
    */
    uint256 initialFrxUsdSupply = 294_703.796e18 -     // ethereum
                                        101.751e18 -    // base
                                        0.001e18 -      // blast
                                        0.01e18;        // metis

    uint256 initialSfrxUsdSupply = 288_442.533e18 -    // ethereum
                                        31_816.103e18 - // base
                                        3_496.227e18 -  // blast
                                        102.138e18;     // metis

    uint256 initialFrxEthSupply = 257.507e18 -         // ethereum
                                        0.1923e18 -     // base
                                        0.0057e18 -     // blast
                                        0;              // metis

    uint256 initialSfrxEthSupply = 199.12e18 -         // ethereum
                                        45.7842e18 -    // base
                                        23.7698e18 -    // blast
                                        3.9053e18;      // metis

    uint256 initialFxsSupply = 131_950.021e18 -        // ethereum
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
        root = string.concat(root, "/scripts/ops/MoveLegacyLiquidity/txs/1_DeployMockOFTsAndSend-");

        string memory file = string.concat(simulateConfig.chainid.toString(), ".json");
        return string.concat(root, file);
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
        require(ethConfig.chainid == 1, "ethConfig not properly set");
        delete proxyConfigs;
        proxyConfigs.push(ethConfig);

        deploySource();
        setupSource();
        buildCustodianSendTx();
        setupDestinations();
    }

    function buildCustodianSendTx() public simulateAndWriteTxs(broadcastConfig) {
        bytes memory data = abi.encodeCall(
            CustodianMock.send,
            (
                address(frxUsdOft),
                address(sfrxUsdOft),
                address(frxEthOft),
                address(sfrxEthOft),
                address(fxsOft)
            )
        );
        uint256 value = 0.1e18;
        (bool success, ) = address(custodian).call{value: value}(data);
        require(success, "CustodianMock.send failed");
        serializedTxs.push(
            SerializedTx({
                name: "CustodianMock.send",
                to: address(custodian),
                value: value,
                data: data
            })
        );
    }

    function deploySource() public override {
        deployCustodianMock();
        deployFraxOFTUpgradeablesAndProxies();
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

        setPriviledgedRoles();
    }

    /// @notice skip proxyAdmin ownership transfer
    function setPriviledgedRoles() public virtual {
        /// @dev transfer ownership of OFT
        for (uint256 o=0; o<proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(broadcastConfig.delegate);
            Ownable(proxyOft).transferOwnership(broadcastConfig.delegate);
        }

        /// @dev transfer ownership of ProxyAdmin
        // Ownable(proxyAdmin).transferOwnership(broadcastConfig.delegate);
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
            _symbol: "mfrxUSD",
            _initialSupply: initialFrxUsdSupply
        });

        // Deploy sfrxUSD
        (,sfrxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Staked Frax USD",
            _symbol: "msfrxUSD",
            _initialSupply: initialSfrxUsdSupply
        });

        // Deploy frxETH
        (,frxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax Ether",
            _symbol: "mfrxETH",
            _initialSupply: initialFrxEthSupply
        });

        // Deploy sfrxETH
        (,sfrxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Staked Frax Ether",
            _symbol: "msfrxETH",
            _initialSupply: initialSfrxEthSupply
        });

        // Deploy FXS
        (,fxsOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax Share",
            _symbol: "mFXS",
            _initialSupply: initialFxsSupply
        });
    }

    function deployCustodianMock() public broadcastAs(configDeployerPK) {
        // Deploy the mock custodian
        custodian = new CustodianMock({
            _initialOwner: broadcastConfig.delegate
        });
        console.log("CustodianMock deployed at:", address(custodian));
    }

    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) public returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(OFTUpgradeableMockMint).creationCode),
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

        bytes memory initializeArgs = abi.encodeWithSelector(
            OFTUpgradeableMockMint.initialize.selector,
            _name,
            _symbol,
            vm.addr(configDeployerPK),
            _initialSupply,
            address(custodian)
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