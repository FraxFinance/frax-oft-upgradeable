// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import "../../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev: deploy OFT on Fraxtal and hookup to Base adapter
/// @todo fraxtal broadcast
contract DeployOFT is DeployFraxOFTProtocol {
    address adapter = 0x0; // TODO
    FraxOFTUpgradeable public oft;

    address[] public connectedOfts;
    address[] public peerOfts;

    constructor() {
        peerOfts.push(adapter);
    }

    function run() public override {
        // deploySource();
        // setupSource();
        (address imp, address proxy) = deployFraxOFTUpgradeableAndProxy({
            _name: "Carters OFT",
            _symbol: "COFT"
        });
        console.log("Implementation @ ", imp);
        console.log("Proxy @ ", proxy);

        // Setup souce as destinations
        setupDestinations();
    }

    /// @dev: configDeployer as proxy admin, broadcast as configDeployer
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public override broadcastAs(configDeployerPK) returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(FraxOFTUpgradeable).creationCode),
            abi.encode(broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, /*vm.addr(oftDeployerPK) */ vm.addr(configDeployerPK), ""));

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
        // TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);
        // TODO: will need to look at these instead of expectedProxyOFTs if the deployed addrs are different than expected
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

    function setupDestinations() public override {
        // setupLegacyDestinations();
        setupProxyDestinations();
    }


    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public virtual /* simulateAndWriteTxs(_connectedConfig) */ broadcastAs(configDeployerPK) {
        setEvmEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: /* broadcastConfigArray */ proxyConfigs // includes fraxtal
        });

        setEvmPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: /* proxyOfts */ peerOfts,
            _configs: /* broadcastConfigArray */ proxyConfigs // includes fraxtal 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: /* broadcastConfigArray */ proxyConfigs // includes fraxtal
        });
    }
}