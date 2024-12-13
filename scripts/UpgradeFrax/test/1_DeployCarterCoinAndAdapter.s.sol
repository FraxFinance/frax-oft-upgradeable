// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";
import { ERC20Mock } from "contracts/mocks/ERC20Mock.sol";
import "../../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev deploy Carter coin with initial supply and setup OFT lockbox
/// TODO: deploy script to base
contract DeployCarterCoinAndAdapter is DeployFraxOFTProtocol {
    ERC20Mock public erc20;
    FraxOFTAdapterUpgradeable public adapter;

    function run() public override {
        deploySource();
        // setupSource();
        // setupDestinations();
    }

    function deploySource() public override {
        deployCarterCoin();
        deployOFTAdapter();
    }

    function deployCarterCoin() public broadcastAs(configDeployerPK) {
        erc20 = new ERC20Mock("Carter Coin", "CAC");
        erc20.mint(0xb0E1650A9760e0f383174af042091fc544b8356f, 1_000_000e18);
    
        console.log("Carter coin @ ", address(erc20));
    }

    function deployOFTAdapter() public broadcastAs(configDeployerPK) {
        adapter = new FraxOFTAdapterUpgradeable(address(erc20), broadcastConfig.endpoint);
        adapter.initialize(vm.addr(configDeployerPK));

        console.log("Adapter @ ", address(adapter));
    }
}