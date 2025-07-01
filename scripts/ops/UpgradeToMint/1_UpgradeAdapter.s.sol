pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import {FraxOFTMintableAdapterUpgradeable} from "contracts/FraxOFTMintableAdapterUpgradeable.sol";

interface ITransparentUpgradeableProxy {
    function upgradeTo(address newImplementation) external;
}

// forge script scripts/ops/UpgradeToMint/1_UpgradeAdapter.s.sol --rpc-url https://rpc.frax.com
contract UpgradeAdapter is DeployFraxOFTProtocol {
    
    // TODO: which tokens?
    address frxUsd = 0xFc00000000000000000000000000000000000001;
    address sfrxUsd = 0xfc00000000000000000000000000000000000008;
    address wfrax = 0xFc00000000000000000000000000000000000002;
    address fpi = 0xFc00000000000000000000000000000000000003;

    address frxUsdMintableLockboxImp;
    address sfrxUsdMintableLockboxImp;
    address wfraxMintableLockboxImp;
    address fpiMintableLockboxImp;

    constructor() {
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory filename_ = string.concat(root, "/scripts/ops/UpgradeToMint/txs/252.json");
        return filename_;
    }

    function run() public override {
        deployMintableLockboxes();

        vm.startPrank(broadcastConfig.delegate);
        upgradeExistingLockboxes();
        transferProxyAdminOwnership();
        vm.stopPrank();

        new SafeTxUtil().writeTxs(serializedTxs, filename());
    }

    function _validateAndPopulateMainnetOfts() internal override {}

    function deployMintableLockboxes() broadcastAs(senderDeployerPK) public {
        frxUsdMintableLockboxImp = deployMintableLockbox(frxUsd);
        sfrxUsdMintableLockboxImp = deployMintableLockbox(sfrxUsd);
        wfraxMintableLockboxImp = deployMintableLockbox(wfrax);
        fpiMintableLockboxImp = deployMintableLockbox(fpi);
    }

    function deployMintableLockbox(address _token) public returns (address) {
        return address(
            new FraxOFTMintableAdapterUpgradeable(
                _token,
                broadcastConfig.endpoint
            )
        );
    }

    function upgradeExistingLockboxes() public {
        upgradeExistingLockbox(fraxtalFrxUsdLockbox, frxUsdMintableLockboxImp);
        upgradeExistingLockbox(fraxtalSFrxUsdLockbox, sfrxUsdMintableLockboxImp);
        upgradeExistingLockbox(fraxtalFraxLockbox, wfraxMintableLockboxImp);
        upgradeExistingLockbox(fraxtalFpiLockbox, fpiMintableLockboxImp);
    }

    function upgradeExistingLockbox(
        address _lockbox,
        address _implementation
    ) public {
        bytes memory data = abi.encodeCall(
            ProxyAdmin.upgrade,
            (
                TransparentUpgradeableProxy(payable(_lockbox)),
                _implementation
            )
        );

        (bool success, ) = proxyAdmin.call(data);
        require(success, "Upgrade failed");
        serializedTxs.push(
            SerializedTx({
                name: "Upgrade Lockbox",
                to: _lockbox,
                value: 0,
                data: data
            })
        );
    }

    function transferProxyAdminOwnership() public {
        bytes memory data = abi.encodeCall(
            Ownable.transferOwnership,
            (0xC4EB45d80DC1F079045E75D5d55de8eD1c1090E6)
        );

        (bool success, ) = proxyAdmin.call(data);
        require(success, "Transfer ownership failed");
        serializedTxs.push(
            SerializedTx({
                name: "Transfer Proxy Admin Ownership",
                to: proxyAdmin,
                value: 0,
                data: data
            })
        );
    }
}