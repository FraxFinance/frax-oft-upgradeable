// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";
import { FraxOFTWalletUpgradeableTempo } from "contracts/FraxOFTWalletUpgradeableTempo.sol";

// forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol
contract UpgradeWalletBridges is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    // Default wallet proxy used on most chains
    address public constant DEFAULT_WALLET_PROXY = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;

    // Chain-specific wallet proxies
    address public constant LINEA_WALLET_PROXY = 0xD555D90A6b23B285575cd6192D972e35F70b5B89;
    address public constant ABSTRACT_WALLET_PROXY = 0x72018C396221e5919c856a809E3Be54CbfDb1fa2;
    address public constant ZKSYNC_WALLET_PROXY = 0x0065435a2FcC4D4D5CD2c284C5daA9588E6fe03d;
    address public constant AURORA_WALLET_PROXY = 0x4a767e2ef83577225522Ef8Ed71056c6E3acB216;
    address public constant SOMNIA_WALLET_PROXY = 0xE75177ED629a4770e2DA00e1395c28A5f9B745d4;

    address public walletImplementation;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeWalletBridges/txs/");
        string memory name = string.concat("UpgradeWalletBridges-", simulateConfig.chainid.toString());
        return string.concat(root, string.concat(name, ".json"));
    }

    function run() public override {
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            L0Config memory proxyConfig = proxyConfigs[i];
            if (_walletProxy(proxyConfig.chainid) == address(0)) continue;
            upgradeWallet(proxyConfig);
        }
    }

    function upgradeWallet(L0Config memory _config) public {
        vm.createSelectFork(_config.RPC);
        simulateConfig = _config;
        delete serializedTxs;

        address walletProxy = _walletProxy(_config.chainid);
        if (walletProxy.code.length == 0) return;

        vm.startBroadcast(configDeployerPK);
        if (_isTempoChain(_config.chainid)) {
            walletImplementation = address(new FraxOFTWalletUpgradeableTempo());
        } else {
            walletImplementation = address(new FraxOFTWalletUpgradeable());
        }
        vm.stopBroadcast();

        vm.startPrank(_config.delegate);
        bytes memory upgradeData = abi.encodeCall(
            ProxyAdmin.upgradeAndCall,
            (TransparentUpgradeableProxy(payable(walletProxy)), walletImplementation, bytes(""))
        );
        (bool success, ) = _config.proxyAdmin.call(upgradeData);
        require(success, "Upgrade failed: wallet proxy upgrade unsuccessful");

        serializedTxs.push(
            SerializedTx({
                name: "upgradeWalletHopV2",
                to: _config.proxyAdmin,
                value: 0,
                data: upgradeData
            })
        );

        vm.stopPrank();

        if (serializedTxs.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxs, filename());
        }
    }

    function _isTempoChain(uint256 _chainid) internal pure returns (bool) {
        return _chainid == 4217;
    }

    function _walletProxy(uint256 _chainid) internal pure returns (address) {
        if (_chainid == 59144) return LINEA_WALLET_PROXY;
        if (_chainid == 2741) return ABSTRACT_WALLET_PROXY;
        if (_chainid == 324) return ZKSYNC_WALLET_PROXY;
        if (_chainid == 1313161554) return AURORA_WALLET_PROXY;
        if (_chainid == 5031) return SOMNIA_WALLET_PROXY;
        return DEFAULT_WALLET_PROXY;
    }
}
