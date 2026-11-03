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
// Production flow (the proxy admin 0x8d82... is a hardware wallet):
//  1. Deploy + verify the implementation on every active chain from a hot EOA (no privileges needed):
//       python3 scripts/ops/UpgradeWalletBridges/deploy_implementations.py            # dry run
//       PK_IMPL_DEPLOYER=<key> ETHERSCAN_API_KEY=<key> \
//       python3 scripts/ops/UpgradeWalletBridges/deploy_implementations.py --broadcast
//     It runs `deployImplementation()` per chain (Somnia via `forge create`) and records the addresses in
//     implementations.json. zkSync is deferred until foundry-zksync is installed.
//  2. Sign `upgradeTo` with the admin in the separate MetaMask upgrade console (wallet-upgrade-ui), which reads
//     implementations.json. Monad and Stable are administered by their chain Safe: the console writes the batch.
//
// Two admin models exist on chain, and the script picks the path from the proxy's EIP-1967 admin slot:
//  1. Dev wallets (FraxDVNTest `1b_DeployMockFrax`, owner 0x45dc...): admin is the EOA WALLET_ADMIN_EOA, which calls
//     `upgradeTo` on the proxy directly. Nothing goes through a msig.
//  2. Hub-deploy wallets on Monad / Stable (`DeployFraxOFTFraxtalHub`, owner 0x0990be...): admin is the chain's
//     FraxProxyAdmin, owned by the chain Safe (3 of 6). The upgrade is `ProxyAdmin.upgrade(proxy, impl)` from the Safe.
//     (`upgradeAndCall(proxy, impl, "")` would revert: the proxy force-delegatecalls the empty calldata into an
//     implementation that has no fallback.)
//
// `run()` / `upgradeChain()` simulate the complete upgrade (deploy + upgradeTo as the admin, or the Safe batch) on
// forks; the fork test uses them. Keep them as dry runs: broadcasting would need the admin key (--ledger works).
// --ffi is required where a Safe batch is written (Stable in the multi-chain run, Monad): SafeTxUtil shells out to sed.
// Flaky L0Config RPC? Override per chain, e.g. WALLET_UPGRADE_RPC_480=https://worldchain-mainnet.g.alchemy.com/public
//
// Retired chains are never touched: L0Config.json `Proxy` still lists Blast, Aurora and Abstract, but they are
// disconnected from the mesh (no Fraxtal hub lockbox peers, no FraxtalHopV2 route) - see `isRetired()`.
//
// Dry-run commands (chains that need their own flags are skipped by `run()` - see `needsDedicatedRun()`):
//   forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol --ffi
//   forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol --sig "upgradeChain(uint256)" 59144 \
//     --rpc-url https://rpc.linea.build --evm-version paris
//   forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol --sig "upgradeChain(uint256)" 143 \
//     --rpc-url https://rpc.monad.xyz --ffi
// Somnia cannot be forked by forge >= 1.9 (its RPCs reject EIP-1898 block-hash params): no script runs there,
// deploy_implementations.py uses `forge create` for it.
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
    address public constant ZKSYNC_WALLET_PROXY = 0x0065435a2FcC4D4D5CD2c284C5daA9588E6fe03d;
    address public constant SOMNIA_WALLET_PROXY = 0xE75177ED629a4770e2DA00e1395c28A5f9B745d4;

    // Hub-deploy wallet proxies (admin: chain FraxProxyAdmin, owned by the chain msig).
    // Same addresses as scripts/FraxtalHub/4_SendFraxOFTFraxtalHub/SendFraxOFT{Monad,Stable}ToFraxtal.s.sol
    address public constant MONAD_WALLET_PROXY = 0x8F37D9F5404067d4bAEc77e42956A198d1858080;
    address public constant STABLE_WALLET_PROXY = 0xF6f45CCB5E85D1400067ee66F9e168f83e86124E;

    uint256 public walletAdminPK = vm.envOr("PK_WALLET_ADMIN", uint256(0));

    /// @dev Hot EOA for implementation deployments (no privileges needed). Unset: signer from --private-key/--account.
    uint256 public implDeployerPK = vm.envOr("PK_IMPL_DEPLOYER", uint256(0));

    function run() public {
        for (uint256 i; i < proxyConfigs.length; i++) {
            uint256 chainid = proxyConfigs[i].chainid;
            if (isRetired(chainid)) {
                console.log("Skipping chain retired from the mesh:", chainid);
                continue;
            }
            if (needsDedicatedRun(chainid)) {
                console.log("Skipping chain, run upgradeChain() with its own flags:", chainid);
                continue;
            }
            _upgradeWallet(proxyConfigs[i]);
        }
    }

    /// @notice Active upgrade targets for off-chain tooling (the MetaMask signing UI in ./ui): every L0Config `Proxy`
    ///         chain that is not retired, with its RPC, wallet proxy and implementation build.
    /// @dev Builds: 0 = default, 1 = Linea (paris), 2 = Tempo variant, 3 = zkSync (zksolc, deployed externally).
    ///      forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol --sig "upgradeTargets()" --json
    function upgradeTargets()
        public
        view
        returns (uint256[] memory chainids, string[] memory rpcs, address[] memory proxies, uint8[] memory builds)
    {
        uint256 count;
        for (uint256 i; i < proxyConfigs.length; i++) {
            if (!isRetired(proxyConfigs[i].chainid)) count++;
        }
        chainids = new uint256[](count);
        rpcs = new string[](count);
        proxies = new address[](count);
        builds = new uint8[](count);

        uint256 j;
        for (uint256 i; i < proxyConfigs.length; i++) {
            uint256 chainid = proxyConfigs[i].chainid;
            if (isRetired(chainid)) continue;
            chainids[j] = chainid;
            rpcs[j] = _rpcFor(proxyConfigs[i]);
            proxies[j] = walletProxy(chainid);
            builds[j] = implementationBuild(chainid);
            j++;
        }
    }

    /// @notice Deploy the wallet implementation for the chain `--rpc-url` points at, from an EOA. The proxy upgrade is
    ///         signed later by the admin in the upgrade console. One chain per run so --verify and per-chain flags apply
    ///         (deploy_implementations.py drives this for every chain):
    ///   forge script scripts/ops/UpgradeWalletBridges/UpgradeWalletBridges.s.sol --sig "deployImplementation()" \
    ///     --rpc-url <rpc> --broadcast --verify [verifier flags] [--evm-version paris on Linea]
    function deployImplementation() public returns (address implementation) {
        require(!isRetired(block.chainid), "Chain is retired from the mesh");
        _proxyConfig(block.chainid); // reverts for chains outside L0Config `Proxy`
        require(walletProxy(block.chainid).code.length != 0, "No wallet proxy on this chain");

        if (implDeployerPK == 0) vm.startBroadcast();
        else vm.startBroadcast(implDeployerPK);
        implementation = _deployImplementation(block.chainid);
        vm.stopBroadcast();

        console.log("Implementation deployed for chain:", block.chainid);
        console.log("  implementation:", implementation);
    }

    function upgradeChain(uint256 _chainid) public {
        require(!isRetired(_chainid), "Chain is retired from the mesh");
        _upgradeWallet(_proxyConfig(_chainid));
    }

    function _upgradeWallet(L0Config memory _config) internal {
        // Reuse the --rpc-url fork when it already matches (required for --zksync runs). Otherwise fork the
        // L0Config RPC, or WALLET_UPGRADE_RPC_<chainid> when set (e.g. to route around a flaky public RPC).
        if (block.chainid != _config.chainid) _selectForkWithRetry(_rpcFor(_config));

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

    /// @dev Public RPCs in L0Config.json flake (e.g. drpc "Temporary internal error"). Only fork creation is
    ///      retried: nothing has been recorded for broadcast yet at that point, so a retry cannot duplicate txs.
    function _selectForkWithRetry(string memory _rpc) internal {
        for (uint256 attempt = 1; attempt <= 3; attempt++) {
            try vm.createSelectFork(_rpc) returns (uint256) {
                return;
            } catch {
                console.log("Fork creation failed, attempt", attempt);
                if (attempt < 3) vm.sleep(attempt * 3000);
            }
        }
        revert(string.concat("Could not fork ", _rpc, " - set WALLET_UPGRADE_RPC_<chainid> to a healthy RPC"));
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

    /// @dev L0Config RPC, or WALLET_UPGRADE_RPC_<chainid> when set (e.g. to route around a flaky public RPC).
    function _rpcFor(L0Config memory _config) internal view returns (string memory) {
        return vm.envOr(string.concat("WALLET_UPGRADE_RPC_", _config.chainid.toString()), _config.RPC);
    }

    /// @dev 0 = default, 1 = Linea (paris), 2 = Tempo variant, 3 = zkSync (zksolc, deployed externally).
    function implementationBuild(uint256 _chainid) public pure returns (uint8) {
        if (_chainid == 59144) return 1;
        if (isTempoChain(_chainid)) return 2;
        if (_chainid == 324) return 3;
        return 0;
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

    /// @dev Chains still listed in L0Config.json `Proxy` but disconnected from the mesh: every Fraxtal hub lockbox
    ///      (frxUSD, sfrxUSD, frxETH, sfrxETH, WFRAX) has a zero peer for them and FraxtalHopV2 has no remoteHop.
    ///      Their deprecation batches live in scripts/ops/DeprecateChain/txs/deprecate-<chainid>.
    function isRetired(uint256 _chainid) public pure returns (bool) {
        return _chainid == 81457 // Blast
            || _chainid == 1313161554 // Aurora
            || _chainid == 2741; // Abstract
    }

    /// @dev Chains a single multi-chain run cannot handle: they need their own compiler settings or EVM.
    function needsDedicatedRun(uint256 _chainid) public pure returns (bool) {
        return _chainid == 59144 // Linea: --evm-version paris
            || _chainid == 324 // zkSync: --zksync
            || _chainid == 143 // Monad: own EVM in forge >= 1.9, run with --rpc-url
            || _chainid == 5031; // Somnia: not forkable by forge >= 1.9, upgrade with forge create + cast send
    }

    function isTempoChain(uint256 _chainid) public pure returns (bool) {
        return _chainid == 4217;
    }

    function walletProxy(uint256 _chainid) public pure returns (address) {
        if (_chainid == 59144) return LINEA_WALLET_PROXY;
        if (_chainid == 324) return ZKSYNC_WALLET_PROXY;
        if (_chainid == 5031) return SOMNIA_WALLET_PROXY;
        if (_chainid == 143) return MONAD_WALLET_PROXY;
        if (_chainid == 988) return STABLE_WALLET_PROXY;
        return DEFAULT_WALLET_PROXY;
    }
}
