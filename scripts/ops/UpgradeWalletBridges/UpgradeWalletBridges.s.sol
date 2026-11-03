// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/BaseL0Script.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";
import { FraxOFTWalletUpgradeableTempo } from "contracts/FraxOFTWalletUpgradeableTempo.sol";

/// @dev Admin surface of the OZ v4.9 TransparentUpgradeableProxy the wallets sit behind.
interface IWalletProxyAdminSurface {
    function upgradeTo(address newImplementation) external;
}

// Upgrades the FraxOFTWallet proxies used to test the LZ mesh.
//
// Two admin models exist on chain, and the script picks the path from the proxy's EIP-1967 admin slot:
//  1. Dev wallets (FraxDVNTest `1b_DeployMockFrax`, owner 0x45dc...): admin is the EOA WALLET_ADMIN_EOA, which calls
//     `upgradeTo` on the proxy directly. Nothing goes through a msig.
//  2. Hub-deploy wallets on Monad / Stable (`DeployFraxOFTFraxtalHub`, owner 0x0990be...): admin is the chain's
//     FraxProxyAdmin, owned by the chain msig. WALLET_ADMIN_EOA deploys the new implementation, and
//     `ProxyAdmin.upgrade(proxy, impl)` is written to txs/UpgradeWalletBridges-<chainid>.json for the msig to execute.
//     (`upgradeAndCall(proxy, impl, "")` would revert: the proxy force-delegatecalls the empty calldata into an
//     implementation that has no fallback.)
//
// Signer: WALLET_ADMIN_EOA for every broadcast. Export PK_WALLET_ADMIN, or pass --private-key / --account / --ledger.
// Drop --broadcast for a dry run (every chain is still upgraded and checked on a fork). Only submit Safe JSON
// written by a --broadcast run: its implementation address is the one actually deployed.
//
// All standard-EVM chains (Linea, zkSync and Abstract are skipped - see below):
//   forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol --broadcast --slow
// One chain:
//   forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol --sig "upgradeChain(uint256)" 42161 --broadcast
// Linea (no PUSH0 - existing impl was built for paris):
//   forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol --sig "upgradeChain(uint256)" 59144 \
//     --rpc-url https://rpc.linea.build --evm-version paris --broadcast
// zkSync / Abstract (foundry-zksync):
//   forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol --sig "upgradeChain(uint256)" 324 \
//     --rpc-url https://mainnet.era.zksync.io --zksync --broadcast
//   forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol --sig "upgradeChain(uint256)" 2741 \
//     --rpc-url https://api.mainnet.abs.xyz --zksync --broadcast
contract UpgradeWalletBridges is BaseL0Script {
    using Strings for uint256;

    bytes32 internal constant EIP1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant EIP1967_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev Admin of every dev wallet (`mFraxProxyAdmin` in 1b_DeployMockFrax); also deploys the implementations.
    address public constant WALLET_ADMIN_EOA = 0x8d8290d49e88D16d81C6aDf6C8774eD88762274A;

    // Default wallet proxy used on most chains
    address public constant DEFAULT_WALLET_PROXY = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;

    // Chain-specific dev wallet proxies (admin: WALLET_ADMIN_EOA)
    address public constant LINEA_WALLET_PROXY = 0xD555D90A6b23B285575cd6192D972e35F70b5B89;
    address public constant ABSTRACT_WALLET_PROXY = 0x72018C396221e5919c856a809E3Be54CbfDb1fa2;
    address public constant ZKSYNC_WALLET_PROXY = 0x0065435a2FcC4D4D5CD2c284C5daA9588E6fe03d;
    address public constant AURORA_WALLET_PROXY = 0x4a767e2ef83577225522Ef8Ed71056c6E3acB216;
    address public constant SOMNIA_WALLET_PROXY = 0xE75177ED629a4770e2DA00e1395c28A5f9B745d4;

    // Hub-deploy wallet proxies (admin: chain FraxProxyAdmin, owned by the chain msig).
    // Same addresses as scripts/FraxtalHub/4_SendFraxOFTFraxtalHub/SendFraxOFT{Monad,Stable}ToFraxtal.s.sol
    address public constant MONAD_WALLET_PROXY = 0x8F37D9F5404067d4bAEc77e42956A198d1858080;
    address public constant STABLE_WALLET_PROXY = 0xF6f45CCB5E85D1400067ee66F9e168f83e86124E;

    uint256 public walletAdminPK = vm.envOr("PK_WALLET_ADMIN", uint256(0));

    function run() public {
        for (uint256 i; i < proxyConfigs.length; i++) {
            uint256 chainid = proxyConfigs[i].chainid;
            if (needsDedicatedRun(chainid)) {
                console.log("Skipping chain, run upgradeChain() with its own flags:", chainid);
                continue;
            }
            _upgradeWallet(proxyConfigs[i]);
        }
    }

    function upgradeChain(uint256 _chainid) public {
        _upgradeWallet(_proxyConfig(_chainid));
    }

    function _upgradeWallet(L0Config memory _config) internal {
        // Reuse the --rpc-url fork when it already matches (required for --zksync runs)
        if (block.chainid != _config.chainid) vm.createSelectFork(_config.RPC);

        address proxy = walletProxy(_config.chainid);
        if (proxy.code.length == 0) {
            console.log("No wallet proxy deployed, skipping chain:", _config.chainid);
            return;
        }

        address admin = _loadAddress(proxy, EIP1967_ADMIN_SLOT);
        address owner = FraxOFTWalletUpgradeable(proxy).owner();

        address implementation;
        if (admin.code.length == 0) {
            // Dev wallet: the admin EOA deploys the implementation and upgrades the proxy itself
            _startBroadcastAs(admin);
            implementation = _deployImplementation(_config.chainid);
            IWalletProxyAdminSurface(proxy).upgradeTo(implementation);
            vm.stopBroadcast();
        } else {
            implementation = _queueProxyAdminUpgrade(proxy, admin, _config.chainid);
        }

        require(_loadAddress(proxy, EIP1967_IMPLEMENTATION_SLOT) == implementation, "Wallet implementation not updated");
        require(_loadAddress(proxy, EIP1967_ADMIN_SLOT) == admin, "Wallet admin changed");
        require(FraxOFTWalletUpgradeable(proxy).owner() == owner, "Wallet owner changed");

        console.log("Upgraded wallet on chain:", _config.chainid);
        console.log("  proxy:", proxy);
        console.log("  implementation:", implementation);
    }

    /// @dev ProxyAdmin-managed wallet: broadcast the implementation deploy, simulate the upgrade as the ProxyAdmin
    ///      owner (msig) and write that call as a Safe batch.
    function _queueProxyAdminUpgrade(address _proxy, address _proxyAdmin, uint256 _chainid)
        internal
        returns (address implementation)
    {
        _startBroadcastAs(WALLET_ADMIN_EOA);
        implementation = _deployImplementation(_chainid);
        vm.stopBroadcast();

        bytes memory upgradeData =
            abi.encodeCall(ProxyAdmin.upgrade, (TransparentUpgradeableProxy(payable(_proxy)), implementation));

        address msig = Ownable(_proxyAdmin).owner();
        vm.prank(msig);
        (bool success,) = _proxyAdmin.call(upgradeData);
        require(success, "ProxyAdmin.upgrade simulation failed");

        delete serializedTxs;
        serializedTxs.push(SerializedTx({ name: "upgradeWallet", to: _proxyAdmin, value: 0, data: upgradeData }));
        string memory dir = string.concat(vm.projectRoot(), "/scripts/ops/UpgradeWalletBridges/txs/");
        vm.createDir(dir, true);
        string memory path = string.concat(dir, "UpgradeWalletBridges-", _chainid.toString(), ".json");
        new SafeTxUtil().writeTxs(serializedTxs, path);

        console.log("Safe batch for the ProxyAdmin owner (msig):", msig);
        console.log("  written to:", path);
    }

    function _deployImplementation(uint256 _chainid) internal returns (address) {
        return isTempoChain(_chainid)
            ? address(new FraxOFTWalletUpgradeableTempo())
            : address(new FraxOFTWalletUpgradeable());
    }

    function _startBroadcastAs(address _signer) internal {
        if (walletAdminPK == 0) {
            // Signer supplied on the CLI (--private-key / --account / --ledger)
            vm.startBroadcast(_signer);
        } else {
            require(vm.addr(walletAdminPK) == _signer, "PK_WALLET_ADMIN is not the expected signer");
            vm.startBroadcast(walletAdminPK);
        }
    }

    function _proxyConfig(uint256 _chainid) internal view returns (L0Config memory) {
        for (uint256 i; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == _chainid) return proxyConfigs[i];
        }
        revert("Chain not in L0Config.json Proxy configs");
    }

    function _loadAddress(address _proxy, bytes32 _slot) internal view returns (address) {
        return address(uint160(uint256(vm.load(_proxy, _slot))));
    }

    /// @dev Chains that cannot share the default compiler settings of a multi-chain run.
    function needsDedicatedRun(uint256 _chainid) public pure returns (bool) {
        return _chainid == 59144 // Linea: --evm-version paris
            || _chainid == 324 // zkSync: --zksync
            || _chainid == 2741; // Abstract: --zksync
    }

    function isTempoChain(uint256 _chainid) public pure returns (bool) {
        return _chainid == 4217;
    }

    function walletProxy(uint256 _chainid) public pure returns (address) {
        if (_chainid == 59144) return LINEA_WALLET_PROXY;
        if (_chainid == 2741) return ABSTRACT_WALLET_PROXY;
        if (_chainid == 324) return ZKSYNC_WALLET_PROXY;
        if (_chainid == 1313161554) return AURORA_WALLET_PROXY;
        if (_chainid == 5031) return SOMNIA_WALLET_PROXY;
        if (_chainid == 143) return MONAD_WALLET_PROXY;
        if (_chainid == 988) return STABLE_WALLET_PROXY;
        return DEFAULT_WALLET_PROXY;
    }
}
