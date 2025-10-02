pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTMintableAdapterUpgradeable } from "contracts/FraxOFTMintableAdapterUpgradeable.sol";
import { ERC1967Utils } from "@openzeppelin-5/contracts/proxy/ERC1967/ERC1967Utils.sol";

interface IERC20PermitPermissionedOptiMintable {
    function addMinter(address) external;
}

// forge script scripts/ops/V110/ethereum/UpgradeAdapterEthereum.s.sol --rpc-url https://eth-mainnet.public.blastapi.io
contract UpgradeAdapter is DeployFraxOFTProtocol {
    using Strings for uint256;
    using Strings for address;

    address frxUsd = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address sfrxUsd = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;

    address frxUsdMintableLockboxImp;
    address sfrxUsdMintableLockboxImp;

    uint256 filecount;

    modifier prankAndWriteTxs(address who) {
        vm.startPrank(who);
        _;
        vm.stopPrank();

        new SafeTxUtil().writeTxs(serializedTxs, filename(who));
        delete serializedTxs;
    }

    function filename(address who) public returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/V110/ethereum/txs/");

        filecount++;
        string memory file = string.concat("UpgradeAdapter-", filecount.toString());
        file = string.concat(file, "-");
        file = string.concat(file, who.toHexString());
        file = string.concat(file, ".json");

        return string.concat(root, file);
    }

    function run() public override {
        deployMintableLockboxes();
        generateTxs();
    }

    function generateTxs() public {
        addMinterRole(broadcastConfig.delegate, frxUsd, ethFrxUsdLockbox);
        addMinterRole(0x4b45D73b83686e69d08E61105FdB7F7b51f41Bc1, sfrxUsd, ethSFrxUsdLockbox);

        upgradeExistingLockboxes();
    }

    function addMinterRole(address _msig, address _token, address _lockbox) public prankAndWriteTxs(_msig) {
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

    /// @dev to prevent the script from reverting due to inherited validation
    function _validateAndPopulateMainnetOfts() internal override {}

    function deployMintableLockboxes() broadcastAs(senderDeployerPK) public {
        frxUsdMintableLockboxImp = deployMintableLockbox(frxUsd);
        sfrxUsdMintableLockboxImp = deployMintableLockbox(sfrxUsd);
    }

    function deployMintableLockbox(address _token) public returns (address) {
        return address(
            new FraxOFTMintableAdapterUpgradeable(
                _token,
                broadcastConfig.endpoint
            )
        );
    }

    function upgradeExistingLockboxes() public prankAndWriteTxs(broadcastConfig.delegate) {
        upgradeExistingLockbox(ethFrxUsdLockbox, frxUsdMintableLockboxImp);
        upgradeExistingLockbox(ethSFrxUsdLockbox, sfrxUsdMintableLockboxImp);
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

        bytes32 adminSlot = vm.load(_lockbox, ERC1967Utils.ADMIN_SLOT);
        proxyAdmin = address(uint160(uint256(adminSlot)));
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
}