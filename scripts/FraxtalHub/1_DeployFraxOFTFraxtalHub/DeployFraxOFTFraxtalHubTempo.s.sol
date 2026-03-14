// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { DeployFraxOFTFraxtalHub } from "./DeployFraxOFTFraxtalHub.s.sol";
import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTUpgradeableTempo } from "contracts/FraxOFTUpgradeableTempo.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { ITIP20RolesAuth } from "tempo-std/interfaces/ITIP20RolesAuth.sol";
import { TIP20RolesAuth } from "@tempo/abstracts/TIP20RolesAuth.sol";
import { FraxOFTMintableAdapterUpgradeableTIP20 } from "contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol";
import { FrxUSDPolicyAdminTempo } from "contracts/frxUsd/FrxUSDPolicyAdminTempo.sol";
import { console } from "frax-std/FraxTest.sol";

// Deploy everything with a hub model vs. a spoke model where the only peer is Fraxtal
// Uses FraxOFTUpgradeableTempo for Tempo chain deployments
// frxUSD TIP20 is already deployed, this script deploys the FraxOFTMintableAdapterUpgradeableTIP20 adapter
// tempo : forge script scripts/FraxtalHub/1_DeployFraxOFTFraxtalHub/DeployFraxOFTFraxtalHubTempo.s.sol --rpc-url $TEMPO_RPC_URL --gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc --broadcast --verify
contract DeployFraxOFTFraxtalHubTempo is DeployFraxOFTFraxtalHub {
    /// @notice The already-deployed frxUSD TIP20 token address on Tempo
    address public constant FRXUSD_TIP20 = 0x20C0000000000000000000003554d28269E0f3c2;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0;
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    address public policyAdminImplementation;
    address public policyAdminProxy;

    /// @notice Use --sender / --gcp instead of a raw private key.
    modifier broadcastAs(uint256) override {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    /// @notice Use FraxOFTUpgradeableTempo instead of FraxOFTUpgradeable for non-frxUSD OFTs.
    function _createOFTImplementation() internal override returns (address) {
        return address(new FraxOFTUpgradeableTempo(broadcastConfig.endpoint));
    }

    /// @notice Use msg.sender as temporary proxy admin (GCS deployer broadcasts directly).
    function _proxyTempAdmin() internal view override returns (address) {
        return msg.sender;
    }

    /// @notice Skip wallet deployment on Tempo — not needed.
    function deployFraxOFTWalletUpgradeableAndProxy() public override returns (address, address) {
        // no-op
    }

    /// @notice Skip wallet check — wallet not deployed on Tempo.
    function postDeployChecks() internal view override {
        require(proxyOfts.length == NUM_OFTS, "Did not deploy all OFTs");
    }

    /// @notice Deploy FraxOFTMintableAdapterUpgradeableTIP20 for the existing frxUSD TIP20 token
    /// @dev Follows the pattern from DeployFraxUSDSepoliaHubMintableTempoTestnet.s.sol
    function deployFrxUsdOFTUpgradeableAndProxy()
        public
        virtual
        override
        returns (address implementation, address proxy)
    {
        ITIP20 token = ITIP20(FRXUSD_TIP20);

        implementation = address(new FraxOFTMintableAdapterUpgradeableTIP20(address(token), broadcastConfig.endpoint));

        /// @dev: broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTMintableAdapterUpgradeableTIP20.initialize.selector,
            _proxyTempAdmin()
        );

        /// @dev: deploy deterministic proxy via Nick's CREATE2
        proxy = deployCreate2({
            _salt: "frxUSD",
            _initCode: abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(implementationMock, _proxyTempAdmin(), "")
            )
        });

        // Upgrade to real implementation and initialize
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });

        // Transfer admin to proxyAdmin
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        proxyOfts.push(proxy);
        frxUsdOft = proxy;

        // Deploy FrxUSDPolicyAdminTempo for freeze/thaw management
        (policyAdminImplementation, policyAdminProxy) = deployFrxUSDPolicyAdminTempo(address(token));

        // Grant ISSUER_ROLE to the adapter so it can mint/burn
        ITIP20RolesAuth(address(token)).grantRole(ISSUER_ROLE, proxy);
        // Grant DEFAULT_ADMIN to tempo msig
        if (broadcastConfig.delegate == address(0)) revert("Delegate cannot be zero address");
        ITIP20RolesAuth(address(token)).grantRole(DEFAULT_ADMIN_ROLE, broadcastConfig.delegate);
        // Renounce DEFAULT_ADMIN from deployer
        ITIP20RolesAuth(address(token)).renounceRole(DEFAULT_ADMIN_ROLE);
        // transfer FrxUSDPolicyAdminTempo ownership to tempo msig
        FrxUSDPolicyAdminTempo(payable(policyAdminProxy)).transferOwnership(broadcastConfig.delegate);
        // let msig accept ownership of FrxUSDPolicyAdminTempo
        console.log(
            "Please have the multisig accept ownership of the FrxUSDPolicyAdminTempo at address:",
            policyAdminProxy
        );

        // Log deployed addresses
        console.log("FraxOFTMintableAdapterUpgradeableTIP20 proxy:", proxy);
        console.log("FraxOFTMintableAdapterUpgradeableTIP20 implementation:", implementation);
        console.log("TIP20 frxUSD:", address(token));
        console.log("FrxUSDPolicyAdminTempo implementation:", policyAdminImplementation);
        console.log("FrxUSDPolicyAdminTempo proxy:", policyAdminProxy);
        console.log("Policy ID:", FrxUSDPolicyAdminTempo(policyAdminProxy).policyId());

        // State checks
        require(
            isStringEqual(ITIP20(FraxOFTMintableAdapterUpgradeableTIP20(proxy).token()).name(), "Frax USD"),
            "OFT name incorrect"
        );
        require(
            isStringEqual(ITIP20(FraxOFTMintableAdapterUpgradeableTIP20(proxy).token()).symbol(), "frxUSD"),
            "OFT symbol incorrect"
        );
        require(
            address(FraxOFTMintableAdapterUpgradeableTIP20(proxy).endpoint()) == broadcastConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(EndpointV2(broadcastConfig.endpoint).delegates(proxy) == msg.sender, "Endpoint delegate incorrect");
        require(FraxOFTMintableAdapterUpgradeableTIP20(proxy).owner() == msg.sender, "OFT owner incorrect");
        // check DEFAULT_ADMIN_ROLE of frxUSD TIP20 is renounced by deployer and granted to multisig
        require(
            !TIP20RolesAuth(address(token)).hasRole(msg.sender, DEFAULT_ADMIN_ROLE),
            "Deployer should not have DEFAULT_ADMIN_ROLE"
        );
        require(
            TIP20RolesAuth(address(token)).hasRole(broadcastConfig.delegate, DEFAULT_ADMIN_ROLE),
            "Multisig should have DEFAULT_ADMIN_ROLE"
        );
        // check ISSUER_ROLE of frxUSD TIP20 is granted to the adapter
        require(TIP20RolesAuth(address(token)).hasRole(proxy, ISSUER_ROLE), "Adapter should have ISSUER_ROLE");
        // check pending owner of FrxUSDPolicyAdminTempo is multisig
        require(
            FrxUSDPolicyAdminTempo(payable(policyAdminProxy)).pendingOwner() == broadcastConfig.delegate,
            "Multisig should be pending owner of FrxUSDPolicyAdminTempo"
        );
    }

    function deployFrxUSDPolicyAdminTempo(address token) internal returns (address implementation, address proxy) {
        // Deploy implementation
        implementation = address(new FrxUSDPolicyAdminTempo());

        // Deploy proxy
        proxy = address(new TransparentUpgradeableProxy(implementationMock, _proxyTempAdmin(), ""));

        // Initialize - this creates a BLACKLIST policy in TIP-403 Registry
        bytes memory initializeArgs = abi.encodeWithSelector(FrxUSDPolicyAdminTempo.initialize.selector, msg.sender);
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
        require(FrxUSDPolicyAdminTempo(proxy).owner() == msg.sender, "PolicyAdmin owner incorrect");
    }
}
