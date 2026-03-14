// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { ITIP20RolesAuth } from "tempo-std/interfaces/ITIP20RolesAuth.sol";
import { ITIP20Factory } from "tempo-std/interfaces/ITIP20Factory.sol";
import { FraxOFTMintableAdapterUpgradeableTIP20 } from "contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol";
import { FrxUSDPolicyAdminTempo } from "contracts/frxUsd/FrxUSDPolicyAdminTempo.sol";

// Deploy everything with a hub model vs. a spoke model where the only peer is Sepolia
// forge script scripts/SepoliaHub/1_DeployFraxOFTSepoliaHub/DeployFraxUSDSepoliaHubMintableTempoTestnet.s.sol --rpc-url https://rpc.moderato.tempo.xyz --broadcast
contract DeployFraxUSDSepoliaHubMintableTempoTestnet is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;
    address[] public proxyOftWallets;

    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    address public policyAdminImplementation;
    address public policyAdminProxy;

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

        // Deploy frxUSD TIP20 token + OFT adapter + FrxUSDPolicyAdminTempo
        address frxUsdOftImplementation;
        (frxUsdOftImplementation, frxUsdOft) = deployFrxUsdOFTUpgradeableAndProxy();

        // Log deployed policy admin addresses
        console.log("FraxOFTMintableAdapterUpgradeableTIP20 proxy :", frxUsdOft);
        console.log("FraxOFTMintableAdapterUpgradeableTIP20 implementation  :", frxUsdOftImplementation);
        console.log("TIP20 frxUSD :", FraxOFTMintableAdapterUpgradeableTIP20(frxUsdOft).token());
        console.log("FrxUSDPolicyAdminTempo implementation:", policyAdminImplementation);
        console.log("FrxUSDPolicyAdminTempo proxy:", policyAdminProxy);
        console.log("Policy ID:", FrxUSDPolicyAdminTempo(policyAdminProxy).policyId());
    }

    function deployFrxUsdOFTUpgradeableAndProxy() public override returns (address implementation, address proxy) {
        // Create TIP20 token via factory
        // address tokenAddr = 0x20C00000000000000000000000000000001116e8;
        address tokenAddr = StdPrecompiles.TIP20_FACTORY.createToken({
            name: "Frax USD",
            symbol: "frxUSD",
            currency: "USD",
            quoteToken: StdTokens.PATH_USD,
            admin: vm.addr(oftDeployerPK),
            salt: bytes32(0)
        });
        ITIP20 token = ITIP20(tokenAddr);

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

        ITIP20RolesAuth(address(token)).grantRole(ISSUER_ROLE, proxy);

        // Deploy FrxUSDPolicyAdminTempo for freeze/thaw management
        (policyAdminImplementation, policyAdminProxy) = deployFrxUSDPolicyAdminTempo(address(token));

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

    function deployFrxUSDPolicyAdminTempo(address token) internal returns (address implementation, address proxy) {
        // Deploy implementation
        implementation = address(new FrxUSDPolicyAdminTempo());

        // Deploy proxy
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));

        // Initialize - this creates a BLACKLIST policy in TIP-403 Registry
        bytes memory initializeArgs = abi.encodeWithSelector(
            FrxUSDPolicyAdminTempo.initialize.selector,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        // Get the policy ID from the deployed policy admin
        uint64 newPolicyId = FrxUSDPolicyAdminTempo(proxy).policyId();

        // Set the TIP20 token's transfer policy to use our blacklist policy
        ITIP20(token).changeTransferPolicyId(newPolicyId);

        // State checks
        require(newPolicyId > 1, "Policy ID should be > 1");
        require(FrxUSDPolicyAdminTempo(proxy).owner() == vm.addr(configDeployerPK), "PolicyAdmin owner incorrect");
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

//   FraxOFTMintableAdapterUpgradeableTIP20 proxy : 0x47a78e4b00775980594B540eD9544E46D40613B7
//   FraxOFTMintableAdapterUpgradeableTIP20 implementation  : 0x129335370e46320D6F64789423D99dc1a355bC47
//   TIP20 frxUSD : 0x20c000000000000000000000b6DF10e2D20b2B9b
//   FrxUSDPolicyAdminTempo implementation: 0x3f0c6ac327C91BF136de572d04DAe456e7D3ac2F
//   FrxUSDPolicyAdminTempo proxy: 0x5d8EB59A12Bc98708702305A7b032f4b69Dd5b5c
//   Policy ID: 138573
