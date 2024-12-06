// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { OFTUpgradeableMock } from "contracts/mocks/OFTUpgradeableMock.sol";

/// @dev deploy upgradeable mock OFTs and mint lockbox supply to the fraxtal msig
// forge script scripts/UpgradeFrax/2_DeployMockOFT.s.sol --rpc-url https://rpc.frax.com --broadcast
contract DeployMockOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256 initialFraxSupply = 1_000_000.123e18; // TODO
    uint256 initialSFraxSupply = 1_400_000.55e18; // TODO
    address deployer = 0xb0E1650A9760e0f383174af042091fc544b8356f;

    /// @dev override to only use FRAX, sFRAX as peer
    function setUp() public virtual override {
        loadJsonConfig();

        delete legacyOfts;
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        legacyOfts.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sFRAX
    }

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/UpgradeFrax/txs/");
        string memory name = string.concat("2_DeployMockOFT-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    /// @dev override to skip setting up solana
    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        // setupNonEvms();

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        setPriviledgedRoles();
    }

    /// @dev only setup Ethereum destination
    function setupDestinations() public override {
        for (uint256 i=0; i<legacyConfigs.length; i++) {
            L0Config memory connectedConfig = legacyConfigs[i];
            if (connectedConfig.chainid == 1) {
                setupDestination({
                    _connectedConfig: connectedConfig,
                    _connectedOfts: legacyOfts
                });
            }
        }
    }

    /// @dev simple checks override
    function postDeployChecks() public override view {
        require(fraxOft != address(0));
        require(sFraxOft != address(0));
    }

    /// @dev only deploy the mock FRAX and sFRAX, as config deployer to maintain semi-deterministic-ness of the deployer nonce
    function deployFraxOFTUpgradeablesAndProxies() /* broadcastAs(oftDeployerPK) */ broadcastAs(configDeployerPK) public override {
        // already deployed
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;

        // deploy frax
        (, fraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax",
            _symbol: "mFRAX",
            _initialSupply: initialFraxSupply
        });

        // deploy sFrax
        (, sFraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock sFrax",
            _symbol: "msFrax",
            _initialSupply: initialSFraxSupply
        });
    }

    /// @dev override the bytecode to the mock contract and mint to the msig
   function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) public returns (address implementation, address proxy) {
        /// @dev override here
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

        /// @dev override to configDeployerPK
        proxy = address(new TransparentUpgradeableProxy(implementationMock, /* vm.addr(oftDeployerPK) */ vm.addr(configDeployerPK), ""));

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

        /// @dev mint initial circulating supply
        OFTUpgradeableMock(proxy).mintInitialSupply(broadcastConfig.delegate, _initialSupply);

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

    /// @dev do nothing
    function setPriviledgedRoles() public override {
        for (uint256 o=0; o<proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            // FraxOFTUpgradeable(proxyOft).setDelegate(deployer);
            // Ownable(proxyOft).transferOwnership(broadcastConfig.delegate);
        }

        // Ownable(proxyAdmin).transferOwnership(broadcastConfig.delegate);
    }
}