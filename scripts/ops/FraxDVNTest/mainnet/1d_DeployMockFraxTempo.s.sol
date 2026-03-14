// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { DeployMockFrax } from "./1b_DeployMockFrax.s.sol";
import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTUpgradeableTempo } from "contracts/FraxOFTUpgradeableTempo.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";

// # Set environment variables
// export TEMPO_RPC_URL=https://user:pass@rpc.tempo.xyz
// export VERIFIER_URL=https://user:pass@contracts.tempo.xyz/v2/contract

// # Run all tests on Tempo's testnet
// forge test

// # Deploy a simple contract
// forge create src/Mail.sol:Mail \
//   --rpc-url $TEMPO_RPC_URL \
//   --interactive \
//   --broadcast \
//   --verify \
//   --constructor-args 0x20c000000000000000000000033abb6ac7d235e5

// # Deploy a simple contract with custom fee token
// forge create src/Mail.sol:Mail \
//   --fee-token <FEE_TOKEN_ADDRESS> \
//   --rpc-url $TEMPO_RPC_URL \
//   --interactive \
//   --broadcast \
//   --verify \
//   --constructor-args 0x20c000000000000000000000033abb6ac7d235e5

// # Run a deployment script and verify on Tempo's explorer
// forge script script/Mail.s.sol \
//   --sig "run(string)" <SALT> \
//   --rpc-url $TEMPO_RPC_URL \
//   --interactive \
//   --sender <YOUR_WALLET_ADDRESS> \
//   --broadcast \
//   --verify

// # Run a deployment script with custom fee token and verify on Tempo's explorer
// forge script script/Mail.s.sol \
//   --fee-token <FEE_TOKEN_ADDRESS> \
//   --sig "run(string)" <SALT> \
//   --rpc-url $TEMPO_RPC_URL \
//   --interactive \
//   --sender <YOUR_WALLET_ADDRESS> \
//   --broadcast \
//   --verify

// tempo : forge script ./scripts/ops/FraxDVNTest/mainnet/1d_DeployMockFraxTempo.s.sol --rpc-url $TEMPO_RPC_URL --tempo.fee-token 0x20c0000000000000000000000000000000000000 --gas-estimate-multiplier 100 --broadcast --verify --skip-simulation

contract DeployMockFraxTempo is DeployMockFrax {
    function deployFraxOFTUpgradeablesAndProxies() public override broadcastAs(oftDeployerPK) {
        // Implementation mock
        implementationMock = address(new ImplementationMock());

        // Deploy Mock Frax using Tempo variant
        deployFraxOFTUpgradeableAndProxy({ _name: "Mock Frax", _symbol: "mFRAX" });

        // Deploy OFT Wallet
        deployFraxOFTWalletUpgradeableAndProxy();
    }

    /// @notice Deploy FraxOFTUpgradeableTempo instead of FraxOFTUpgradeable
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public override returns (address implementation, address proxy) {
        proxyAdmin = mFraxProxyAdmin;

        // Use FraxOFTUpgradeableTempo instead of FraxOFTUpgradeable
        implementation = address(new FraxOFTUpgradeableTempo(broadcastConfig.endpoint));
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
