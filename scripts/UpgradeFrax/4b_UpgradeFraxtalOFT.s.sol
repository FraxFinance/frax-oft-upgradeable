// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";
import { IMessageLibManager } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";

/// @dev Upgrade the FRAX/sFRAX OFTs on Fraxtal to be lockboxes (aka adapters)
// forge script scripts/UpgradeFrax/4b_UpgradeFraxtalOFT.s.sol --rpc-url https://rpc.frax.com
contract UpgradeFraxtalOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    address public frxUsd = 0xFc00000000000000000000000000000000000001;
    address public sfrxUsd = 0xfc00000000000000000000000000000000000008;
    address public frxUsdAdapterImp = 0xDe41062782F469816cD44ca3B40C16900aaA2EFf;
    address public sfrxUsdAdapterImp = 0x5abB63fE6214cfb8C8030E01378D732fCDEec74a;

    constructor() {
        /// @dev: already deployed
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        fraxOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sFraxOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    }

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/UpgradeFrax/txs/");
        string memory name = string.concat("4b_UpgradeFraxtalOFT-", broadcastConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function run() public override {
        upgradeOfts();
    }

    /// @dev Deploy the FRAX and sFRAX adapter implementations,
    /// upgrade OFT to adapter through ProxyAdmin as delegate (txs must be pranked and crafted for msig execution)
    function upgradeOfts() simulateAndWriteTxs(broadcastConfig) public {

        // upgrade frax
        upgradeOft({
            _token: frxUsd,
            _oft: fraxOft,
            _implementation: frxUsdAdapterImp
        });

        // upgrade sFrax
        upgradeOft({
            _token: sfrxUsd,
            _oft: sFraxOft,
            _implementation: sfrxUsdAdapterImp
        });
    }

    /// @dev create the oft lockbox implementation and upgrade the proxy to the lockbox
   function upgradeOft(
        address _token,
        address _oft,
        address _implementation
    ) public {
        // Proxy admin - upgrade to new implementation
        bytes memory upgrade = abi.encodeCall(
            ProxyAdmin.upgrade,
            (
                TransparentUpgradeableProxy(payable(_oft)), _implementation
            )
        );
        (bool success, ) = proxyAdmin.call(upgrade);
        require(success, "Unable to upgrade proxy");

        // save tx
        serializedTxs.push(
            SerializedTx({
                name: "upgrade",
                to: proxyAdmin,
                value: 0,
                data: upgrade
            })
        );

        // Make sure contract cannot be re-initialized
        bytes memory initialize = abi.encodeCall(
            FraxOFTAdapterUpgradeable.initialize,
            (
                address(1)
            )
        );
        (success, ) = _oft.call(initialize);
        require(!success, "should not be able to initialize");

        // Ensure state remains / new token view is added
        require(
            address(FraxOFTUpgradeable(_oft).endpoint()) == broadcastConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            FraxOFTUpgradeable(_oft).owner() == broadcastConfig.delegate,
            "OFT owner incorrect"
        );
        require(
            FraxOFTAdapterUpgradeable(_oft).token() == _token,
            "OFT token not set"
        );

        // ensure old oft methods no longer pass
        (success, ) = _oft.call(abi.encodeWithSignature("name()"));
        require(!success, "token metadata still exists");
        (success, ) = _oft.call(abi.encodeWithSignature("totalSupply()"));
        require(!success, "oft supply still exists");
    }
}