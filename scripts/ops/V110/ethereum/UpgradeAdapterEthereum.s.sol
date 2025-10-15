pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTMintableAdapterUpgradeable } from "contracts/FraxOFTMintableAdapterUpgradeable.sol";
import { ERC1967Utils } from "@openzeppelin-5/contracts/proxy/ERC1967/ERC1967Utils.sol";

interface IERC20PermitPermissionedOptiMintable {
    function addMinter(address) external;
    function minters(address) external view returns (bool);
}

interface Timelock {
    function queueTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta) external returns (bytes32);
    function executeTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta) external payable returns (bytes memory);
}

// forge script scripts/ops/V110/ethereum/UpgradeAdapterEthereum.s.sol --rpc-url https://eth-mainnet.public.blastapi.io --ffi --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
contract UpgradeAdapter is DeployFraxOFTProtocol {
    using Strings for uint256;
    using Strings for address;

    address frxUsd = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address sfrxUsd = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    address fpi = 0x5Ca135cB8527d76e932f34B5145575F9d8cbE08E;

    address frxUsdMintableLockboxImp;
    address sfrxUsdMintableLockboxImp;
    address fpiMintableLockboxImp;

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
        file = string.concat(file, "-fpi.json");

        return string.concat(root, file);
    }

    function run() public override {
        deployMintableLockboxes();
        generateTxs();
    }

    function generateTxs() public {
        // addMinterRole(broadcastConfig.delegate, frxUsd, ethFrxUsdLockbox);
        // addMinterRole(0x4b45D73b83686e69d08E61105FdB7F7b51f41Bc1, sfrxUsd, ethSFrxUsdLockbox);
        addFpiMinterRole();

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

    function addFpiMinterRole() public {
        address timelock = 0x8412ebf45bAC1B340BbE8F318b928C466c4E39CA;

        // for fpi timelock arguments
        address target = fpi;
        uint256 value = 0;
        string memory signature = "addMinter(address)";
        bytes memory data = abi.encode(ethFpiLockbox);
        uint256 eta = block.timestamp + 2 days + 4 hours; // 4 hour window from tx generation to submission

        queueTransaction(timelock, target, value, signature, data, eta);

        // fast forward to when tx can be executed
        vm.warp(eta + 1);

        executeTransaction(timelock, target, value, signature, data, eta);
    }

    function queueTransaction(address timelock, address target, uint256 value, string memory signature, bytes memory data, uint256 eta) public prankAndWriteTxs(broadcastConfig.delegate) {
        bytes memory txData = abi.encodeCall(
            Timelock.queueTransaction,
            (target, value, signature, data, eta)
        );
        (bool success, ) = timelock.call(txData);
        require(success, "Queue transaction failed");
        serializedTxs.push(
            SerializedTx({
                name: "Queue fpi minter role",
                to: timelock,
                value: 0,
                data: txData
            })
        );
    }

    function executeTransaction(address timelock, address target, uint256 value, string memory signature, bytes memory data, uint256 eta) public prankAndWriteTxs(broadcastConfig.delegate) {
        bytes memory txData = abi.encodeCall(
            Timelock.executeTransaction,
            (target, value, signature, data, eta)
        );
        (bool success, ) = timelock.call(txData);
        require(success, "Execute transaction failed");
        require(IERC20PermitPermissionedOptiMintable(fpi).minters(ethFpiLockbox), "Minter role not granted");
        serializedTxs.push(
            SerializedTx({
                name: "Execute fpi minter role",
                to: timelock,
                value: 0,
                data: txData
            })
        );
    }

    /// @dev to prevent the script from reverting due to inherited validation
    function _validateAndPopulateMainnetOfts() internal override {}

    function deployMintableLockboxes() broadcastAs(senderDeployerPK) public {
        // frxUsdMintableLockboxImp = deployMintableLockbox(frxUsd);
        // sfrxUsdMintableLockboxImp = deployMintableLockbox(sfrxUsd);
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

    function upgradeExistingLockboxes() public prankAndWriteTxs(broadcastConfig.delegate) {
        // upgradeExistingLockbox(ethFrxUsdLockbox, frxUsdMintableLockboxImp);
        // upgradeExistingLockbox(ethSFrxUsdLockbox, sfrxUsdMintableLockboxImp);
        upgradeExistingLockbox(ethFpiLockbox, fpiMintableLockboxImp);
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
                to: proxyAdmin,
                value: 0,
                data: data
            })
        );
    }
}