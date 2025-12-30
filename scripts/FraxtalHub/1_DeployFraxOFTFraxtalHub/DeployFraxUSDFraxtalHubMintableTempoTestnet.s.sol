// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { FraxOFTMintableAdapterUpgradeableTIP20 } from "contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol";

// Deploy everything with a hub model vs. a spoke model where the only peer is Fraxtal
// forge script scripts/FraxtalHub/1_DeployFraxOFTFraxtalHub/DeployFraxUSDFraxtalHubMintableTempoTestnet.s.sol --rpc-url $RPC_URL --broadcast
contract DeployFraxUSDFraxtalHubMintableTempoTestnet is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;
    address[] public proxyOftWallets;

    function setUp() public virtual override {
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(StdTokens.PATH_USD_ADDRESS);
        super.setUp();
    }

    function run() public override {
        require(broadcastConfig.chainid != 11155111, "Deployment not allowed on Ethereum Sepolia");
        for (uint256 i; i < testnetConfigs.length; i++) {
            // Set up destinations for Ethereum Sepolia lockboxes only
            if (testnetConfigs[i].chainid == 11155111 || testnetConfigs[i].chainid == broadcastConfig.chainid) {
                tempConfigs.push(testnetConfigs[i]);
            }
        }

        require(tempConfigs.length == 2, "Incorrect tempConfigs array");

        delete testnetConfigs;
        for (uint256 i = 0; i < tempConfigs.length; i++) {
            testnetConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        deploySource();
    }

    function preDeployChecks() public view override {
        for (uint256 i = 0; i < tempConfigs.length; i++) {
            uint32 eid = uint32(tempConfigs[i].eid);
            require(
                IMessageLibManager(broadcastConfig.endpoint).isSupportedEid(eid),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
    }

    function deploySource() public override {
        preDeployChecks();
        deployFraxOFTUpgradeablesAndProxies();
        deployFraxOFTWalletUpgradeableAndProxy();
        postDeployChecks();
    }

    function deployFraxOFTUpgradeablesAndProxies() public override broadcastAs(oftDeployerPK) {
        // Proxy admin (0x223a681fc5c5522c85C96157c0efA18cd6c5405c if predeterministic)
        proxyAdmin = address(new FraxProxyAdmin(vm.addr(configDeployerPK)));

        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250 if predeterministic)
        implementationMock = address(new ImplementationMock());

        // Deploy frxUSD
        (, frxUsdOft) = deployFrxUsdOFTUpgradeableAndProxy();
    }

    function deployFrxUsdOFTUpgradeableAndProxy() public override returns (address implementation, address proxy) {
        ITIP20 token = ITIP20(0x20C00000000000000000000000000000001116e8);
        implementation = address(new FraxOFTMintableAdapterUpgradeableTIP20(address(token), broadcastConfig.endpoint));
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));

        /// @dev: broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTMintableAdapterUpgradeableTIP20.initialize.selector,
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
            isStringEqual(ITIP20(address(FraxOFTMintableAdapterUpgradeableTIP20(proxy).token())).name(), "Frax USD"),
            "OFT name incorrect"
        );
        require(
            isStringEqual(ITIP20(address(FraxOFTMintableAdapterUpgradeableTIP20(proxy).token())).symbol(), "frxUSD"),
            "OFT symbol incorrect"
        );
        require(
            address(FraxOFTMintableAdapterUpgradeableTIP20(proxy).endpoint()) == broadcastConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(
            FraxOFTMintableAdapterUpgradeableTIP20(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }

    function deployFraxOFTWalletUpgradeableAndProxy()
        public
        broadcastAs(oftDeployerPK)
        returns (address implementation, address proxy)
    {
        implementation = address(new FraxOFTWalletUpgradeable());
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));
        /// @dev: broadcastConfig deployer is temporary owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTWalletUpgradeable.initialize.selector,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        proxyOftWallets.push(proxy);
    }

    function postDeployChecks() internal view override {
        require(proxyOfts.length == 1, "Did not deploy 1 OFT");
        require(proxyOftWallets.length == 1, "Did not deploy proxy OFT wallet");
    }
}
