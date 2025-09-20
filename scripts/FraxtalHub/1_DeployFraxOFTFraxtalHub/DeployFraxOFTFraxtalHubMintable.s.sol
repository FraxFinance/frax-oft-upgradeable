// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";

// Deploy everything with a hub model vs. a spoke model where the only peer is Fraxtal
// forge script scripts/FraxtalHub/1_DeployFraxOFTFraxtalHub/DeployFraxOFTFraxtalHubMintable.s.sol --rpc-url https://rpc.frax.com --broadcast --verify --verifier-url $FRAXSCAN_API_URL --etherscan-api-key $FRAXSCAN_API_KEY

contract DeployFraxOFTFraxtalHubMintable is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;

    function run() public override {
        deploySource();
    }

    function preDeployChecks() public view override {
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            uint32 eid = uint32(proxyConfigs[i].eid);
            require(
                IMessageLibManager(broadcastConfig.endpoint).isSupportedEid(eid),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
    }

    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public override returns (address implementation, address proxy) {
        implementation = address(new FraxOFTMintableUpgradeable(broadcastConfig.endpoint));
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));

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
        require(isStringEqual(FraxOFTUpgradeable(proxy).name(), _name), "OFT name incorrect");
        require(isStringEqual(FraxOFTUpgradeable(proxy).symbol(), _symbol), "OFT symbol incorrect");
        require(address(FraxOFTUpgradeable(proxy).endpoint()) == broadcastConfig.endpoint, "OFT endpoint incorrect");
        require(
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK), "OFT owner incorrect");
    }
}
