// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { DeployMintableMockFrax } from "./1a_DeployMintableMockFrax.s.sol";
import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";

// fraxtal : forge script ./scripts/ops/FraxDVNTest/mainnet/1c_DeployMintablemockfrxUSD.s.sol --rpc-url https://rpc.frax.com --verifier-url $FRAXSCAN_API_URL --etherscan-api-key $$ETHERSCAN_API_KEY --verify --broadcast

contract DeployMintablemockfrxUSD is DeployMintableMockFrax {
    function deployFraxOFTUpgradeablesAndProxies() public override broadcastAs(oftDeployerPK) {
        // Implementation mock — deployed deterministically via Nick's CREATE2
        implementationMock = deployCreate2({
            _salt: "ImplementationMock",
            _initCode: type(ImplementationMock).creationCode
        });

        // Deploy mock frxUSD
        deployFraxOFTUpgradeableAndProxy({ _name: "mock frxUSD", _symbol: "mockfrxUSD" });
    }

    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public virtual override returns (address implementation, address proxy) {
        proxyAdmin = mFraxProxyAdmin;

        implementation = address(new FraxOFTMintableUpgradeable(broadcastConfig.endpoint));

        /// @dev: deploy deterministic proxy via Nick's CREATE2
        proxy = deployCreate2({
            _salt: _symbol,
            _initCode: abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(implementationMock, vm.addr(oftDeployerPK), "")
            )
        });

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
            isStringEqual(FraxOFTMintableUpgradeable(proxy).name(), _name),
            "OFT name incorrect"
        );
        require(
            isStringEqual(FraxOFTMintableUpgradeable(proxy).symbol(), _symbol),
            "OFT symbol incorrect"
        );
        require(
            address(FraxOFTMintableUpgradeable(proxy).endpoint()) == broadcastConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(
            FraxOFTMintableUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }

    function postDeployChecks() internal view virtual override {
        require(proxyOfts.length == 1, "Did not deploy OFT");
    }
}
