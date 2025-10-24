pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import {FraxOFTMintableAdapterUpgradeable} from "contracts/FraxOFTMintableAdapterUpgradeable.sol";

interface IERC20PermitPermissionedOptiMintable {
    function addMinter(address) external;
}

interface IAdapter {
    function token() external view returns (address);
}

interface IProxyAdmin {
    function upgrade(address payable proxy, address implementation) external payable;
}

// forge script scripts/testnet/ops/V110/ethereum/UpgradeAdapterEthereum.s.sol --rpc-url https://eth-sepolia.public.blastapi.io --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
contract UpgradeAdapter is DeployFraxOFTProtocol {

    function run() public override broadcastAs(configDeployerPK) {

        address frxUsd = IAdapter(ethSepoliaFrxUsdLockbox).token();
        proxyAdmin = 0x6CA2338a21B2fE9dD39040d2fE06AAD861f77F95;

        address implementation = address(new FraxOFTMintableAdapterUpgradeable(
            frxUsd,
            broadcastConfig.endpoint
        ));

        IProxyAdmin(payable(proxyAdmin)).upgrade(
            payable(ethSepoliaFrxUsdLockbox),
            implementation
        );
    }
}