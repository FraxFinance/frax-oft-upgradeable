// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FrxUSDOFTUpgradeable} from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import {SFrxUSDOFTUpgradeable} from "contracts/frxUsd/SFrxUSDOFTUpgradeable.sol";


/// @dev craft tx to upgrade the FRAX / sFRAX OFT with the new name & symbol
// TODO: add etherscan / verifier links
/// @dev forge script scripts/UpgradeFrax/5b_UpgradeOFTMetadata.s.sol --rpc-url https://xlayerrpc.okx.com
/// @dev forge script scripts/UpgradeFrax/5b_UpgradeOFTMetadata.s.sol --rpc-url https://mainnet.mode.network
/// @dev forge script scripts/UpgradeFrax/5b_UpgradeOFTMetadata.s.sol --rpc-url https://twilight-crimson-grass.sei-pacific.quiknode.pro/1fe7cb5c6950df0f3ebceead37f8eefdf41ddbe9
contract UpgradeOFTMetadata is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    /// @dev these change per chain
    address public frxUsdImplementation;
    address public sfrxUsdImplementation;

    constructor() {
        /// @dev declared in BaseL0Script.sol, already deployed
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;

        if (block.chainid == 34443) {
            // mode
            frxUsdImplementation = 0x83a3581c22C143a574B584af583DE3D6d3A2fD50;
            sfrxUsdImplementation = 0x09EE6975fEff1Ba02d7FEA060Dd196c58e2e4c9E;
        } else if (block.chainid == 1329) {
            // sei
            frxUsdImplementation = 0x9735Eef5e5D7fA1BC5a7956C7439d15D5E658601;
            sfrxUsdImplementation = 0x493f17254f8A6cF7B4346a9d6927148521B03680;
        } else {
            // xlayer
            frxUsdImplementation = 0x9D0FEe988A8134Db109c587DB047761904A34B5b;
            sfrxUsdImplementation = 0xD09F0B6B4b76D5832BfE911793437f5b4c143100;
        }
    }

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeFrxUsd/txs/");
        string memory name = string.concat("5b_UpgradeOFTMetadata-", broadcastConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function run() public override {
        upgradeOfts();
    }

    function upgradeOfts() public simulateAndWriteTxs(broadcastConfig) {
        upgradeOft({
            _oft: frxUsdOft,
            _implementation: frxUsdImplementation,
            _name: "Frax USD",
            _symbol: "frxUSD"
        });
        upgradeOft({
            _oft: sfrxUsdOft,
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

        bytes memory upgrade = abi.encodeCall(
            ProxyAdmin.upgrade,
            (
                TransparentUpgradeableProxy(payable(_oft)),
                _implementation
            )
        );
        (bool success, ) = proxyAdmin.call(upgrade);
        require(success, "Unable to upgrade proxy");

        // state checks
        require(supplyBefore == IERC20(_oft).totalSupply(), "total supply changed");
        require(isStringEqual(_name, IERC20Metadata(_oft).name()), "name not changed");
        require(isStringEqual(_symbol, IERC20Metadata(_oft).symbol()), "symbol not changed");

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
                name: "upgrade",
                to: proxyAdmin,
                value: 0,
                data: upgrade
            })
        );
    }
}