pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { console } from "frax-std/FraxTest.sol";

import { FraxProxyAdmin } from "contracts/FraxProxyAdmin.sol";

/*
DESCRIPTION:
Task to deploy ProxyAdmin to testnet chains where frxUSD OFT is not yet controlled by a ProxyAdmin instance

Eth sepolia
forge script scripts/testnet/ops/DeployProxyAdmin/DeployProxyAdmin.s.sol --rpc-url https://eth-sepolia.public.blastapi.io --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
0x6CA2338a21B2fE9dD39040d2fE06AAD861f77F95

Arb sepolia
forge script scripts/testnet/ops/DeployProxyAdmin/DeployProxyAdmin.s.sol --rpc-url https://arbitrum-sepolia-rpc.publicnode.com --broadcast
0x452420df4AC1e3db5429b5FD629f3047482C543C.

Fraxtal testnet
forge script scripts/testnet/ops/DeployProxyAdmin/DeployProxyAdmin.s.sol --rpc-url https://rpc.testnet.frax.com --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
0x009195b94E1b7D545DD0606aCc148916b720Ea5a
*/
contract DeployProxyAdmin is Script {

    uint256 public carterDeployerPK = vm.envUint("PK_SENDER_DEPLOYER");

    function run() external {
        vm.startBroadcast(carterDeployerPK);

        new FraxProxyAdmin(vm.addr(carterDeployerPK));

        vm.stopBroadcast();
    }

}