pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import {FraxOFTMintableAdapterUpgradeable} from "contracts/FraxOFTMintableAdapterUpgradeable.sol";

interface IERC20PermitPermissionedOptiMintable {
    function addMinter(address) external;
}

// forge script scripts/ops/V110/fraxtal/UpgradeAdapterFraxtalSFrxEth.s.sol --rpc-url https://rpc.frax.com --ffi --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
contract UpgradeAdapter is DeployFraxOFTProtocol {
    
    address frxEth = 0xFC00000000000000000000000000000000000006;
    address sfrxEth = 0xFC00000000000000000000000000000000000005;

    address comptroller = 0xC4EB45d80DC1F079045E75D5d55de8eD1c1090E6;

    address frxEthMintableLockboxImp;
    address sfrxEthMintableLockboxImp;

    uint256 msigSubmissionCount;

    constructor() {
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
    }

    modifier prankAndWriteTxs(address who) {
        vm.startPrank(who);
        _;
        vm.stopPrank();

        msigSubmissionCount++;

        new SafeTxUtil().writeTxs(serializedTxs, filename());
        delete serializedTxs;
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/V110/fraxtal/txs/UpgradeAdapter");

        if (msigSubmissionCount == 1) {
            return string.concat(root, "-frxETH-upgrade.json");
        } else {
            return string.concat(root, "-frxETH-addMinter.json");
        }
    }

    function run() public override {
        deployMintableLockboxes();
        upgradeExistingLockboxes();
        addMinterRoles();
    }

    function addMinterRoles() public prankAndWriteTxs(comptroller) {
        addMinterRole(frxEth, fraxtalFrxEthLockbox);
        addMinterRole(sfrxEth, fraxtalSFrxEthLockbox);
    }

    function addMinterRole(address _token, address _lockbox) public {
        bytes memory data = abi.encodeCall(
            IERC20PermitPermissionedOptiMintable.addMinter,
            (_lockbox)
        );
        (bool success, ) = _token.call(data);
        require(success, "Add minter role failed");
        serializedTxs.push(
            SerializedTx({
                name: "Add minter role",
                to: _token,
                value: 0,
                data: data
            })
        );
    }

    function _validateAndPopulateMainnetOfts() internal override {}

    function deployMintableLockboxes() broadcastAs(senderDeployerPK) public {
        frxEthMintableLockboxImp = deployMintableLockbox(frxEth);
        sfrxEthMintableLockboxImp = deployMintableLockbox(sfrxEth);
    }

    function deployMintableLockbox(address _token) public returns (address) {
        return address(
            new FraxOFTMintableAdapterUpgradeable(
                _token,
                broadcastConfig.endpoint
            )
        );
    }

    function upgradeExistingLockboxes() public prankAndWriteTxs(comptroller) {
        upgradeExistingLockbox(fraxtalFrxEthLockbox, frxEthMintableLockboxImp);
        upgradeExistingLockbox(fraxtalSFrxEthLockbox, sfrxEthMintableLockboxImp);
    }

    function upgradeExistingLockbox(
        address _lockbox,
        address _implementation
    ) public {
        address tokenBefore = FraxOFTUpgradeable(_lockbox).token();

        bytes memory data = abi.encodeCall(
            ProxyAdmin.upgrade,
            (
                TransparentUpgradeableProxy(payable(_lockbox)),
                _implementation
            )
        );

        (bool success, ) = proxyAdmin.call(data);
        require(success, "Upgrade failed");

        address tokenAfter = FraxOFTUpgradeable(_lockbox).token();
        require(tokenBefore == tokenAfter, "Wrong token");

        serializedTxs.push(
            SerializedTx({
                name: "Upgrade Lockbox",
                to: proxyAdmin,
                value: 0,
                data: data
            })
        );
    }
}