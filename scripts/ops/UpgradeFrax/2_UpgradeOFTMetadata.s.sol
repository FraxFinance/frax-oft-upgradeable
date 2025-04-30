// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract UpgradeOFTMetadata is DeployFraxOFTProtocol {
    using Strings for uint256;

    address public fxsImplementation;

    constructor() {
        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        if (block.chainid == 34443) { // mode
            fxsImplementation = 0x8f6F4359090BbF65938392874Cac44dcE165A285;
        } else if (block.chainid == 1329) { // sei
            fxsImplementation = 0x27E751C568111C3BDbAd705B25b14D1322E4213C;
        } else if (block.chainid == 196) { // xlayer
            fxsImplementation = 0x40f713Fb5b4054d1A3d4158913C6409Fb32384B4;
        } else if (block.chainid == 146) { // sonic
            fxsImplementation = 0xEb5E8F69d1A05D2A2cFc418cb6f56aC54230bbc3;
        } else if (block.chainid == 57073) { // ink
            fxsImplementation = 0x9671B991615a9550FBe04791FAC71d3d091e5dfa;
        } else if (block.chainid == 42161) { // arbitrum
            fxsImplementation = 0xb2Dd76CD8484146C4D3205853327Bf9F5cb68Fb6;
        } else if (block.chainid == 10) { // optimism
            fxsImplementation = 0x5Bfd5AecF3c474217eE50Fb696b897fA22915a3b;
        } else if (block.chainid == 137) { // polygon
            fxsImplementation = 0xBfb4e31D365A4816AfE52b280087028D7b5f3b9E;
        } else if (block.chainid == 43114) { // avalanche
            fxsImplementation = 0xc1f81f22e3A502A2071b7f9D45675D8D8315b894;
        } else if (block.chainid == 56) { // bsc
            fxsImplementation = 0xEA8A307c3eB6E68E136A9b94A5d9cb995b6ACEc0;
        } else if (block.chainid == 1101) { // polygon zkevm
            fxsImplementation = 0x78F175e220eff8129EA50B0CeF432B5058890cCC;
        } else if (block.chainid == 81457) { // blast
            fxsImplementation = 0x96A7dd70799f8962Ea256a14DDaa120d19de7D8a;
        } else if (block.chainid == 8453) { // base
            fxsImplementation = 0x9c245a6bBc9F946993Ba3777641dDCeAC259CD6A;
        } else if (block.chainid == 80094) { // berachain
            fxsImplementation = 0xCd18b5A6Dff9a8be40e81b494b9cC112698dDc4B;
        } else if (block.chainid == 59144) { // linea
            fxsImplementation = 0x370DD74Dd32d8D47d3Cd0Abc5fcf2Cd1e9912a97;
        } else if (block.chainid == 324) { // zksync
            fxsImplementation = 0xFc329f4f94CCe9e10Cc005dA2350fBef0746820e; 
        } else if (block.chainid == 2741) { // abstract
            fxsImplementation = 0xFc329f4f94CCe9e10Cc005dA2350fBef0746820e;
        } else {
            revert("Unsupported chain");
        }
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeFrax/txs/");
        string memory name = string.concat("2_UpgradeOFTMetadata-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function run() public override simulateAndWriteTxs(broadcastConfig) {
        fxsOft = connectedOfts[0]; // fxs
        // OZ contracts/proxy/ERC1967/ERC1967Upgrade.sol `_ADMIN_SLOT`
        proxyAdmin = address(uint160(uint256(vm.load(fxsOft, 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103))));

        // verify OFT is FXS
        require(isStringEqual("Frax Share", IERC20Metadata(fxsOft).name()), "OFT is not FXS");
        require(isStringEqual("FXS", IERC20Metadata(fxsOft).symbol()), "OFT is not FXS");

        uint256 supplyBefore = IERC20(fxsOft).totalSupply();

        bytes memory upgrade = abi.encodeCall(
            ProxyAdmin.upgrade,
            (TransparentUpgradeableProxy(payable(fxsOft)), fxsImplementation)
        );
        (bool success, ) = proxyAdmin.call(upgrade);
        require(success, "Unable to upgrade proxy");

        // state checks
        require(supplyBefore == IERC20(fxsOft).totalSupply(), "total supply changed");
        require(isStringEqual("Frax", IERC20Metadata(fxsOft).name()), "name not changed");
        require(isStringEqual("FRAX", IERC20Metadata(fxsOft).symbol()), "symbol not changed");

        // make sure contract cannot be re-initialized
        bytes memory initialize = abi.encodeCall(
            FraxOFTUpgradeable.initialize,
            ("Mock name", "mName", address(1))
        );
        (success, ) = fxsOft.call(initialize);
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