// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FrxUSDOFTUpgradeable} from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import {SFrxUSDOFTUpgradeable} from "contracts/frxUsd/SFrxUSDOFTUpgradeable.sol";


/// @dev craft tx to upgrade the FRAX / sFRAX OFT with the new name & symbol
// TODO: add etherscan / verifier links
/// @dev forge script scripts/UpgradeFrax/8_UpgradeOFTMetadata.s.sol --rpc-url https://xlayerrpc.okx.com
/// @dev forge script scripts/UpgradeFrax/8_UpgradeOFTMetadata.s.sol --rpc-url https://mainnet.mode.network
/// @dev forge script scripts/UpgradeFrax/8_UpgradeOFTMetadata.s.sol --rpc-url https://twilight-crimson-grass.sei-pacific.quiknode.pro/1fe7cb5c6950df0f3ebceead37f8eefdf41ddbe9
contract UpgradeOFTMetadata is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    address public proxyAdmin_ = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
    address public frxUsdProxy = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address public sfrxUsdProxy = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    // TODO: (7) can be executed with (8) if we uncomment out deployImplementations() within run()
    address public frxUsdImplementation = 0x9D0FEe988A8134Db109c587DB047761904A34B5b;
    address public sfrxUsdImplementation = 0xD09F0B6B4b76D5832BfE911793437f5b4c143100;

    /// @dev override to alter file save location
    modifier simulateAndWriteTxs(L0Config memory _config) override {
        // Clear out arrays
        delete enforcedOptionsParams;
        delete setConfigParams;
        delete serializedTxs;

        vm.createSelectFork(_config.RPC);
        chainid = _config.chainid;
        vm.startPrank(_config.delegate);
        _;
        vm.stopPrank();

        // create filename and save
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/UpgradeFrax/txs/");
        string memory filename = string.concat("8_UpgradeOFTMetadata-", _config.chainid.toString());
        filename = string.concat(filename, ".json");

        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }

    function run() public override {
        // deployImplementations();
        upgradeOfts();
    }

    function upgradeOfts() public simulateAndWriteTxs(activeConfig) {
        upgradeOft({
            _oft: frxUsdProxy,
            _implementation: frxUsdImplementation,
            _name: "Frax USD",
            _symbol: "frxUSD"
        });
        upgradeOft({
            _oft: sfrxUsdProxy,
            _implementation: sfrxUsdImplementation,
            _name: "Staked Frax USD",
            _symbol: "sfrxUSD"
        });
    }

    function upgradeOft(
        address _oft,
        address _implementation,
        string memory _name,
        string memory _symbol
    ) public {
        uint256 supplyBefore = IERC20(_oft).totalSupply();
        require(supplyBefore > 0, "Supply before == 0");

        bytes memory upgradeAndCall = abi.encodeCall(
            ProxyAdmin.upgradeAndCall,
            (
                TransparentUpgradeableProxy(payable(_oft)),
                _implementation,
                abi.encodeWithSignature("name()") // simple func call to prevent fallback call
            )
        );
        (bool success, ) = proxyAdmin_.call(upgradeAndCall);
        require(success, "Unable to upgrade proxy");

        // state checks
        require(supplyBefore == IERC20(_oft).totalSupply(), "total supply changed");
        require(uint256(keccak256(abi.encodePacked(_name))) == uint256(keccak256(abi.encodePacked(IERC20Metadata(_oft).name()))), "name not changed");
        require(uint256(keccak256(abi.encodePacked(_symbol))) == uint256(keccak256(abi.encodePacked(IERC20Metadata(_oft).symbol()))), "symbol not changed");

        // make sure contract cannot be re-initialized
        bytes memory initialize = abi.encodeCall(
            FraxOFTUpgradeable.initialize,
            (
                "Mock name", "mName", address(1)
            )
        );
        (success, ) = _oft.call(initialize);
        require(!success, "should not be able to initialize");

        serializedTxs.push(
            SerializedTx({
                name: "upgradeAndCall",
                to: proxyAdmin_,
                value: 0,
                data: upgradeAndCall
            })
        );
    }
}