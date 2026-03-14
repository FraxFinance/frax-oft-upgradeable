// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { DeployMintableMockFrax } from "./1a_DeployMintableMockFrax.s.sol";
import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { ITIP20RolesAuth } from "tempo-std/interfaces/ITIP20RolesAuth.sol";
import { FraxOFTMintableAdapterUpgradeableTIP20 } from "contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol";
import { FrxUSDPolicyAdminTempo } from "contracts/frxUsd/FrxUSDPolicyAdminTempo.sol";

// tempo : forge script ./scripts/ops/FraxDVNTest/mainnet/1e_DeployMintablemockfrxUSDTIP20.s.sol --rpc-url $TEMPO_RPC_URL --tempo.fee-token 0x20c0000000000000000000000000000000000000 --gas-estimate-multiplier 100 --broadcast --verify

contract DeployMintablemockfrxUSDTIP20 is DeployMintableMockFrax {
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    address public policyAdminImplementation;
    address public policyAdminProxy;

    function deployFraxOFTUpgradeablesAndProxies() public override broadcastAs(oftDeployerPK) {
        // Implementation mock — deployed deterministically via Nick's CREATE2
        implementationMock = deployCreate2({
            _salt: "ImplementationMock",
            _initCode: type(ImplementationMock).creationCode
        });

        // Deploy Mock frax USD
        deployFraxOFTUpgradeableAndProxy({ _name: "Mock frax USD", _symbol: "mockfrxUSD" });
    }

    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public virtual override returns (address implementation, address proxy) {
        proxyAdmin = mFraxProxyAdmin;

        // Create TIP20 token via factory
        address tokenAddr = StdPrecompiles.TIP20_FACTORY.createToken({
            name: _name,
            symbol: _symbol,
            currency: "USD",
            quoteToken: StdTokens.PATH_USD,
            admin: vm.addr(oftDeployerPK),
            salt: bytes32(0)
        });
        ITIP20 token = ITIP20(tokenAddr);

        implementation = address(new FraxOFTMintableAdapterUpgradeableTIP20(address(token), broadcastConfig.endpoint));
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

        // Log deployed addresses
        console.log("FraxOFTMintableAdapterUpgradeableTIP20 proxy:", proxy);
        console.log("FraxOFTMintableAdapterUpgradeableTIP20 implementation:", implementation);
        console.log("TIP20 mockfrxUSD:", address(token));
        console.log("FrxUSDPolicyAdminTempo implementation:", policyAdminImplementation);
        console.log("FrxUSDPolicyAdminTempo proxy:", policyAdminProxy);
        console.log("Policy ID:", FrxUSDPolicyAdminTempo(policyAdminProxy).policyId());

        // State checks
        require(
            isStringEqual(ITIP20(address(FraxOFTMintableAdapterUpgradeableTIP20(proxy).token())).name(), _name),
            "OFT name incorrect"
        );
        require(
            isStringEqual(ITIP20(address(FraxOFTMintableAdapterUpgradeableTIP20(proxy).token())).symbol(), _symbol),
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

    function postDeployChecks() internal view override {
        require(proxyOfts.length == 1, "Did not deploy OFT");
    }
}
