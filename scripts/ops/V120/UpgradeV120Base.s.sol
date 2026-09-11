// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

import {ERC1967Utils} from "@openzeppelin-5/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FraxOFTAdapterUpgradeable} from "contracts/FraxOFTAdapterUpgradeable.sol";
import {FraxOFTMintableAdapterUpgradeable} from "contracts/FraxOFTMintableAdapterUpgradeable.sol";
import {FraxOFTMintableAdapterUpgradeableTIP20} from "contracts/FraxOFTMintableAdapterUpgradeableTIP20.sol";
import {FraxOFTUpgradeable} from "contracts/FraxOFTUpgradeable.sol";
import {FraxOFTUpgradeableTempo} from "contracts/FraxOFTUpgradeableTempo.sol";
import {WFRAXTokenOFTUpgradeable} from "contracts/WFRAXTokenOFTUpgradeable.sol";
import {FrxUSDOFTUpgradeable} from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import {SFrxUSDOFTUpgradeable} from "contracts/frxUsd/SFrxUSDOFTUpgradeable.sol";

interface IV120OFTView {
    function approvalRequired() external view returns (bool);
    function endpoint() external view returns (address);
    function owner() external view returns (address);
    function symbol() external view returns (string memory);
    function token() external view returns (address);
    function version() external view returns (string memory);
}

interface ISupplyLedger {
    function initialTotalSupply(uint32 eid) external view returns (uint256);
    function totalTransferFrom(uint32 eid) external view returns (uint256);
    function totalTransferTo(uint32 eid) external view returns (uint256);
}

interface ITempoV120View {
    function nativeToken() external view returns (address);
}

/// @notice Compound-style timelock owning the Ethereum ProxyAdmin (Miscellany/Timelock.sol).
interface IV120Timelock {
    function admin() external view returns (address);
    function delay() external view returns (uint256);
    function GRACE_PERIOD() external view returns (uint256);
    function queueTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external returns (bytes32);
    function executeTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external payable returns (bytes memory);
}

/// @notice Shared v1.2.0 deployment, Safe serialization, and post-upgrade validation.
/// @dev Implementations are deliberately resolved per chain profile. In particular,
///      Tempo (4217) must retain EndpointV2Alt behavior and its frxUSD TIP-20 adapter.
abstract contract UpgradeV120Base is DeployFraxOFTProtocol {
    using Strings for uint256;

    uint256 internal constant ETHEREUM_CHAIN_ID = 1;
    uint256 internal constant FRAXTAL_CHAIN_ID = 252;
    uint256 internal constant TEMPO_CHAIN_ID = 4217;
    uint256 internal constant ZKSYNC_CHAIN_ID = 324;

    uint256 internal constant ABSTRACT_CHAIN_ID = 2741;

    enum ImplementationKind {
        StandardOFT,
        TempoOFT,
        EscrowAdapter,
        MintableAdapter,
        Tip20Adapter
    }

    struct ProxyState {
        string symbol;
        address token;
        address endpoint;
        address owner;
        address nativeToken;
        address proxyAdmin;
        bool approvalRequired;
    }

    struct Ledger {
        uint256 initialTotalSupply;
        uint256 transferFrom;
        uint256 transferTo;
        uint8 decimals;
    }

    struct SupplySeed {
        address oft;
        uint32 eid;
        uint256 initialTotalSupply;
        bool allowNegativeSupply;
        uint256 sourceChainid;
        uint256 sourceBlock;
    }

    /// @notice Execution slots for the split-authority rollout, in mandatory execution order.
    /// @dev SeedAhead: numeric `setInitialTotalSupply` executed by the OFT owner BEFORE the
    ///      upgrade (the v1.1.0 lockboxes already expose the setter and the ERC-7201 storage
    ///      persists across the upgrade). Upgrade: direct ProxyAdmin calls by its owner.
    ///      TimelockQueue/TimelockExecute: used instead of Upgrade when the ProxyAdmin owner
    ///      is a Compound-style timelock (Ethereum) — queued and, after `delay`, executed by
    ///      the timelock's admin Safe. PostUpgrade: v1.2.0-only setters (`setAllowNegative-
    ///      Supply`) executed by the OFT owner after the upgrade lands.
    enum BatchPhase {
        SeedAhead,
        Upgrade,
        TimelockQueue,
        TimelockExecute,
        PostUpgrade
    }

    struct PhasedTx {
        address executor;
        BatchPhase phase;
        SerializedTx stx;
    }

    PhasedTx[] internal phasedTxs;

    /// @dev ProxyAdmin owner (may be a timelock contract), resolved on-fork per chain.
    address internal upgradeAuthority;
    /// @dev Safe that actually signs the upgrade batch: the authority itself, or the
    ///      timelock's admin when the authority is a timelock.
    address internal upgradeExecutor;
    bool internal upgradeViaTimelock;
    uint256 internal timelockEta;

    function outputDirectory() public view virtual returns (string memory);

    function filename() public view override returns (string memory) {
        return string.concat(outputDirectory(), "/", _batchPrefix(), "-", simulateConfig.chainid.toString(), ".json");
    }

    /// @notice Directory for a V120 Safe batch: scripts/ops/V120/<leaf>/txs.
    function _txsDirectory(string memory _leaf) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/scripts/ops/V120/", _leaf, "/txs");
    }

    /// @notice Chains whose proxy OFTs belong to the legacy mesh rather than the active
    ///         hub-and-spoke, and are therefore out of scope for v1.2.0.
    /// @dev Blast (81457) appears in both the Legacy and Proxy sections of L0Config. Its proxy
    ///      OFTs still carry outbound peers to active chains, but no active chain peers back, so
    ///      the wiring is one-way and stale. FPI is likewise out of the mesh entirely.
    function _isLegacyOnlyChain(uint256 _chainid) internal pure returns (bool) {
        return _chainid == 81457;
    }

    /// @notice True when `_slot` is one of the tokens v1.2.0 upgrades.
    /// @dev Arrays stay `NUM_OFTS` wide and are indexed by `Token` slot, so retired slots (FPI)
    ///      exist but are never deployed, upgraded or validated. Post-FPI chains carry
    ///      `address(0)` there, and pre-retirement chains keep an FPI proxy this upgrade leaves alone.
    function _isActiveSlot(uint256 _slot) internal view returns (bool) {
        for (uint256 i; i < activeTokens.length; ++i) {
            if (uint256(activeTokens[i]) == _slot) return true;
        }
        return false;
    }

    /// @notice True for ZK-stack chains (zkSync Era, Abstract) handled by the dedicated ZK script.
    function _isZkStackChain(uint256 _chainid) internal pure returns (bool) {
        return _chainid == ZKSYNC_CHAIN_ID || _chainid == ABSTRACT_CHAIN_ID;
    }

    /// @notice Fork the chain, deploy its profile's implementations, and emit the Safe
    ///         batches. Supply seeds with numeric values are simulated and serialized
    ///         AHEAD of the upgrade (against the live v1.1.0 proxies); upgrades are
    ///         simulated as the actual ProxyAdmin owner (Safe or timelock); v1.2.0-only
    ///         setters follow after.
    function _upgradeChain(L0Config memory _config) internal {
        _prepareUpgrade(_config);
        (address[] memory implementations, ImplementationKind[] memory kinds) = _deployImplementations();
        SupplySeed[] memory seeds = _resolveSupplySeeds(kinds);
        _simulateSeedAhead(kinds, seeds);
        _resolveUpgradeAuthority();
        _simulateUpgrades(implementations, kinds);
        _simulatePostUpgradeSeeds(kinds, seeds);
        _writeBatches();
    }

    /// @notice Upgrade the proxy config matching `_chainid`; reverts if it is not configured.
    function _upgradeChainById(uint256 _chainid) internal {
        for (uint256 i; i < proxyConfigs.length; ++i) {
            if (proxyConfigs[i].chainid != _chainid) continue;
            _upgradeChain(proxyConfigs[i]);
            return;
        }
        revert(string.concat("V120: config not found for chain ", _chainid.toString()));
    }

    function _prepareUpgrade(L0Config memory _config) internal {
        require(!isDeprecatedChain(_config.chainid), "V120: deprecated chain");

        vm.createSelectFork(_config.RPC);
        simulateConfig = _config;
        _populateConnectedOfts();
        delete serializedTxs;
        delete phasedTxs;
        upgradeAuthority = address(0);
        upgradeExecutor = address(0);
        upgradeViaTimelock = false;
        timelockEta = 0;

        require(connectedOfts.length == NUM_OFTS, "V120: unexpected OFT count");
        for (uint256 i; i < connectedOfts.length; ++i) {
            if (!_isActiveSlot(i)) continue;
            require(connectedOfts[i] != address(0), "V120: zero OFT");
            require(connectedOfts[i].code.length != 0, "V120: OFT not deployed");
        }
    }

    /// @notice Hook for profile-specific implementation deployment.
    function _deployImplementations()
        internal
        virtual
        returns (address[] memory implementations, ImplementationKind[] memory kinds);

    /// @notice Resolve who can actually execute `ProxyAdmin.upgrade*` on this chain.
    /// @dev On the destinations and Tempo the ProxyAdmin owner is the delegate Safe; on the
    ///      hubs it is NOT (Ethereum: a Compound-style timelock admin'd by a Safe; Fraxtal:
    ///      a different Safe). Ownership stays where it is — batches are split by executor.
    function _resolveUpgradeAuthority() internal {
        address proxyAdmin = address(uint160(uint256(vm.load(connectedOfts[0], ERC1967Utils.ADMIN_SLOT))));
        require(proxyAdmin != address(0), "V120: zero ProxyAdmin");
        upgradeAuthority = Ownable(proxyAdmin).owner();
        require(upgradeAuthority != address(0), "V120: zero ProxyAdmin owner");

        (bool hasDelay, bytes memory delayData) = upgradeAuthority.staticcall(abi.encodeWithSignature("delay()"));
        (bool hasAdmin, bytes memory adminData) = upgradeAuthority.staticcall(abi.encodeWithSignature("admin()"));
        if (hasDelay && delayData.length == 32 && hasAdmin && adminData.length == 32) {
            upgradeViaTimelock = true;
            upgradeExecutor = abi.decode(adminData, (address));
            require(upgradeExecutor != address(0), "V120: zero timelock admin");
            uint256 delay = abi.decode(delayData, (uint256));
            // eta must still satisfy `eta >= block.timestamp + delay` when the queue batch
            // actually executes on-chain — the margin covers Safe signature collection.
            timelockEta = vm.envOr("V120_TIMELOCK_ETA", block.timestamp + delay + 3 days);
            require(timelockEta >= block.timestamp + delay, "V120: eta below timelock delay");
            console.log("V120: ProxyAdmin owner is a timelock", upgradeAuthority);
            console.log("V120: timelock admin (queue/execute Safe)", upgradeExecutor);
            console.log("V120: timelock eta", timelockEta);
        } else {
            upgradeExecutor = upgradeAuthority;
        }
    }

    function _simulateUpgrades(address[] memory _implementations, ImplementationKind[] memory _kinds) internal {
        require(_implementations.length == connectedOfts.length, "V120: implementation length mismatch");
        require(_kinds.length == connectedOfts.length, "V120: kind length mismatch");

        uint256 count = connectedOfts.length;
        ProxyState[] memory beforeStates = new ProxyState[](count);
        bytes[] memory upgradeCalldatas = new bytes[](count);
        address[] memory proxyAdmins = new address[](count);

        for (uint256 i; i < count; ++i) {
            if (!_isActiveSlot(i)) continue;
            (beforeStates[i], upgradeCalldatas[i]) = _stageUpgrade(connectedOfts[i], _implementations[i], _kinds[i]);
            proxyAdmins[i] = beforeStates[i].proxyAdmin;
            require(Ownable(proxyAdmins[i]).owner() == upgradeAuthority, "V120: mixed upgrade authority");
        }

        if (!upgradeViaTimelock) {
            vm.startPrank(upgradeAuthority);
            for (uint256 i; i < count; ++i) {
                if (!_isActiveSlot(i)) continue;
                _safeCall(proxyAdmins[i], upgradeCalldatas[i], "V120: upgrade");
                _pushPhasedTx(
                    upgradeExecutor,
                    BatchPhase.Upgrade,
                    string.concat("Upgrade ", beforeStates[i].symbol, " to v1.2.0"),
                    proxyAdmins[i],
                    upgradeCalldatas[i]
                );
            }
            vm.stopPrank();
        } else {
            // Queue batch (executable now), then the real upgrades via executeTransaction
            // after the timelock delay — both signed by the timelock's admin Safe.
            vm.startPrank(upgradeExecutor);
            for (uint256 i; i < count; ++i) {
                if (!_isActiveSlot(i)) continue;
                bytes memory queueData = abi.encodeCall(
                    IV120Timelock.queueTransaction, (proxyAdmins[i], 0, "", upgradeCalldatas[i], timelockEta)
                );
                _safeCall(upgradeAuthority, queueData, "V120: timelock queue");
                _pushPhasedTx(
                    upgradeExecutor,
                    BatchPhase.TimelockQueue,
                    string.concat("Queue ", beforeStates[i].symbol, " v1.2.0 upgrade"),
                    upgradeAuthority,
                    queueData
                );
            }
            vm.stopPrank();

            vm.warp(timelockEta + 1);

            vm.startPrank(upgradeExecutor);
            for (uint256 i; i < count; ++i) {
                if (!_isActiveSlot(i)) continue;
                bytes memory executeData = abi.encodeCall(
                    IV120Timelock.executeTransaction, (proxyAdmins[i], 0, "", upgradeCalldatas[i], timelockEta)
                );
                _safeCall(upgradeAuthority, executeData, "V120: timelock execute");
                _pushPhasedTx(
                    upgradeExecutor,
                    BatchPhase.TimelockExecute,
                    string.concat("Execute ", beforeStates[i].symbol, " v1.2.0 upgrade"),
                    upgradeAuthority,
                    executeData
                );
            }
            vm.stopPrank();
        }

        for (uint256 i; i < count; ++i) {
            if (!_isActiveSlot(i)) continue;
            _validateUpgrade(connectedOfts[i], _kinds[i], beforeStates[i]);
        }
    }

    function _pushPhasedTx(
        address _executor,
        BatchPhase _phase,
        string memory _name,
        address _to,
        bytes memory _data
    ) internal {
        phasedTxs.push(
            PhasedTx({executor: _executor, phase: _phase, stx: SerializedTx({name: _name, to: _to, value: 0, data: _data})})
        );
    }

    /// @notice Write one Safe batch per (phase, executor) group, in mandatory execution
    ///         order. When every tx shares a single executor the batch collapses into the
    ///         legacy single `UpgradeV120-<chainid>.json` (destinations, Tempo).
    function _writeBatches() internal {
        require(phasedTxs.length != 0, "V120: nothing serialized");
        vm.createDir(outputDirectory(), true);

        bool singleExecutor = true;
        for (uint256 i = 1; i < phasedTxs.length; ++i) {
            if (phasedTxs[i].executor != phasedTxs[0].executor) {
                singleExecutor = false;
                break;
            }
        }

        if (singleExecutor) {
            SerializedTx[] memory txs = new SerializedTx[](phasedTxs.length);
            for (uint256 i; i < phasedTxs.length; ++i) {
                txs[i] = phasedTxs[i].stx;
            }
            new SafeTxUtil().writeTxs(txs, filename());
            console.log("V120 batch (single executor):", filename());
            console.log("  executor:", phasedTxs[0].executor);
            return;
        }

        uint256 step;
        for (uint8 p; p <= uint8(BatchPhase.PostUpgrade); ++p) {
            // distinct executors within this phase, in insertion order
            for (uint256 i; i < phasedTxs.length; ++i) {
                if (uint8(phasedTxs[i].phase) != p) continue;
                bool seen;
                for (uint256 j; j < i; ++j) {
                    if (uint8(phasedTxs[j].phase) == p && phasedTxs[j].executor == phasedTxs[i].executor) {
                        seen = true;
                        break;
                    }
                }
                if (seen) continue;

                uint256 groupCount;
                for (uint256 j; j < phasedTxs.length; ++j) {
                    if (uint8(phasedTxs[j].phase) == p && phasedTxs[j].executor == phasedTxs[i].executor) ++groupCount;
                }
                SerializedTx[] memory txs = new SerializedTx[](groupCount);
                uint256 w;
                for (uint256 j; j < phasedTxs.length; ++j) {
                    if (uint8(phasedTxs[j].phase) == p && phasedTxs[j].executor == phasedTxs[i].executor) {
                        txs[w++] = phasedTxs[j].stx;
                    }
                }

                ++step;
                string memory path = string.concat(
                    outputDirectory(),
                    "/",
                    _batchPrefix(),
                    "-",
                    simulateConfig.chainid.toString(),
                    "-step",
                    step.toString(),
                    "-",
                    _phaseLabel(BatchPhase(p)),
                    "-",
                    Strings.toHexString(uint160(phasedTxs[i].executor), 20),
                    ".json"
                );
                new SafeTxUtil().writeTxs(txs, path);
                console.log("V120 batch step", step);
                console.log("  phase:", _phaseLabel(BatchPhase(p)));
                console.log("  executor (Safe):", phasedTxs[i].executor);
                console.log("  txs:", groupCount);
                console.log("  file:", path);
            }
        }
        if (upgradeViaTimelock) {
            console.log("V120: execute the TimelockQueue step first; the TimelockExecute step");
            console.log("      is only valid from eta until eta + GRACE_PERIOD:");
            console.log("  eta:", timelockEta);
        }
        console.log("V120: steps MUST execute in ascending order (seed-ahead before upgrade).");
    }

    function _phaseLabel(BatchPhase _phase) internal pure returns (string memory) {
        if (_phase == BatchPhase.SeedAhead) return "seed";
        if (_phase == BatchPhase.Upgrade) return "upgrade";
        if (_phase == BatchPhase.TimelockQueue) return "queue";
        if (_phase == BatchPhase.TimelockExecute) return "execute";
        return "allow-negative";
    }

    function _startImplementationBroadcast() internal {
        if (configDeployerPK != 0) {
            vm.startBroadcast(configDeployerPK);
            return;
        }

        require(msg.sender == GCS_DEPLOYER, "V120: missing PK_CONFIG_DEPLOYER or GCS sender");
        vm.startBroadcast();
    }

    function _deployStandardDestinationImplementations()
        internal
        returns (address[] memory implementations, ImplementationKind[] memory kinds)
    {
        implementations = new address[](NUM_OFTS);
        kinds = new ImplementationKind[](NUM_OFTS);

        _startImplementationBroadcast();
        implementations[uint256(Token.WFRAX)] = address(new WFRAXTokenOFTUpgradeable(simulateConfig.endpoint));
        implementations[uint256(Token.SFRXUSD)] = address(new SFrxUSDOFTUpgradeable(simulateConfig.endpoint));
        address standardOft = address(new FraxOFTUpgradeable(simulateConfig.endpoint));
        implementations[uint256(Token.SFRXETH)] = standardOft;
        implementations[uint256(Token.FRXUSD)] = address(new FrxUSDOFTUpgradeable(simulateConfig.endpoint));
        implementations[uint256(Token.FRXETH)] = standardOft;
        vm.stopBroadcast();

        for (uint256 i; i < NUM_OFTS; ++i) {
            if (_isActiveSlot(i)) kinds[i] = ImplementationKind.StandardOFT;
        }
    }

    function _deployTempoImplementations()
        internal
        returns (address[] memory implementations, ImplementationKind[] memory kinds)
    {
        require(simulateConfig.chainid == TEMPO_CHAIN_ID, "V120: not Tempo");

        implementations = new address[](NUM_OFTS);
        kinds = new ImplementationKind[](NUM_OFTS);
        address tip20 = IV120OFTView(connectedOfts[uint256(Token.FRXUSD)]).token();

        _startImplementationBroadcast();
        address tempoOft = address(new FraxOFTUpgradeableTempo(simulateConfig.endpoint));
        address tip20Adapter = address(new FraxOFTMintableAdapterUpgradeableTIP20(tip20, simulateConfig.endpoint));
        vm.stopBroadcast();

        implementations[uint256(Token.WFRAX)] = tempoOft;
        implementations[uint256(Token.SFRXUSD)] = tempoOft;
        implementations[uint256(Token.SFRXETH)] = tempoOft;
        implementations[uint256(Token.FRXUSD)] = tip20Adapter;
        implementations[uint256(Token.FRXETH)] = tempoOft;

        kinds[uint256(Token.WFRAX)] = ImplementationKind.TempoOFT;
        kinds[uint256(Token.SFRXUSD)] = ImplementationKind.TempoOFT;
        kinds[uint256(Token.SFRXETH)] = ImplementationKind.TempoOFT;
        kinds[uint256(Token.FRXUSD)] = ImplementationKind.Tip20Adapter;
        kinds[uint256(Token.FRXETH)] = ImplementationKind.TempoOFT;
    }

    function _deployFraxtalImplementations()
        internal
        returns (address[] memory implementations, ImplementationKind[] memory kinds)
    {
        require(simulateConfig.chainid == FRAXTAL_CHAIN_ID, "V120: not Fraxtal");

        implementations = new address[](NUM_OFTS);
        kinds = new ImplementationKind[](NUM_OFTS);

        _startImplementationBroadcast();
        for (uint256 i; i < NUM_OFTS; ++i) {
            if (!_isActiveSlot(i)) continue;
            address token = IV120OFTView(connectedOfts[i]).token();
            bool mintable = i == uint256(Token.SFRXUSD) || i == uint256(Token.FRXUSD);

            if (mintable) {
                implementations[i] = address(new FraxOFTMintableAdapterUpgradeable(token, simulateConfig.endpoint));
                kinds[i] = ImplementationKind.MintableAdapter;
            } else {
                implementations[i] = address(new FraxOFTAdapterUpgradeable(token, simulateConfig.endpoint));
                kinds[i] = ImplementationKind.EscrowAdapter;
            }
        }
        vm.stopBroadcast();
    }

    function _deployEthereumImplementations()
        internal
        returns (address[] memory implementations, ImplementationKind[] memory kinds)
    {
        require(simulateConfig.chainid == ETHEREUM_CHAIN_ID, "V120: not Ethereum");

        implementations = new address[](NUM_OFTS);
        kinds = new ImplementationKind[](NUM_OFTS);

        _startImplementationBroadcast();
        implementations[uint256(Token.WFRAX)] = address(new WFRAXTokenOFTUpgradeable(simulateConfig.endpoint));
        kinds[uint256(Token.WFRAX)] = ImplementationKind.StandardOFT;

        for (uint256 i = 1; i < NUM_OFTS; ++i) {
            if (!_isActiveSlot(i)) continue;
            address token = IV120OFTView(connectedOfts[i]).token();
            bool mintable = i == uint256(Token.SFRXUSD) || i == uint256(Token.FRXUSD);

            if (mintable) {
                implementations[i] = address(new FraxOFTMintableAdapterUpgradeable(token, simulateConfig.endpoint));
                kinds[i] = ImplementationKind.MintableAdapter;
            } else {
                implementations[i] = address(new FraxOFTAdapterUpgradeable(token, simulateConfig.endpoint));
                kinds[i] = ImplementationKind.EscrowAdapter;
            }
        }
        vm.stopBroadcast();
    }

    /// @notice Read the proxy's pre-upgrade state and build the ProxyAdmin calldata.
    ///         Execution and serialization happen in `_simulateUpgrades` under the
    ///         resolved upgrade authority.
    function _stageUpgrade(address _oft, address _implementation, ImplementationKind _kind)
        internal
        returns (ProxyState memory beforeState, bytes memory data)
    {
        require(_implementation.code.length != 0, "V120: implementation not deployed");

        beforeState = _readProxyState(_oft, _kind);
        if (simulateConfig.proxyAdmin != address(0)) {
            require(beforeState.proxyAdmin == simulateConfig.proxyAdmin, "V120: unexpected ProxyAdmin");
        }

        bool needsInitializer = _kind == ImplementationKind.StandardOFT || _kind == ImplementationKind.TempoOFT;
        if (needsInitializer) {
            data = abi.encodeCall(
                ProxyAdmin.upgradeAndCall,
                (
                    TransparentUpgradeableProxy(payable(_oft)),
                    _implementation,
                    abi.encodeWithSignature("initializeV120()")
                )
            );
        } else {
            data = abi.encodeCall(ProxyAdmin.upgrade, (TransparentUpgradeableProxy(payable(_oft)), _implementation));
        }
    }

    function _readProxyState(address _oft, ImplementationKind _kind) internal returns (ProxyState memory state) {
        IV120OFTView oft = IV120OFTView(_oft);
        state.token = oft.token();
        state.symbol = _isAdapter(_kind) ? _tokenSymbol(state.token) : oft.symbol();
        state.endpoint = oft.endpoint();
        state.owner = oft.owner();
        state.approvalRequired = oft.approvalRequired();
        state.proxyAdmin = address(uint160(uint256(vm.load(_oft, ERC1967Utils.ADMIN_SLOT))));
        require(state.proxyAdmin != address(0), "V120: zero ProxyAdmin");

        if (_kind == ImplementationKind.TempoOFT || _kind == ImplementationKind.Tip20Adapter) {
            state.nativeToken = ITempoV120View(_oft).nativeToken();
            require(state.nativeToken != address(0), "V120: Tempo native token missing");
        }
    }

    function _validateUpgrade(address _oft, ImplementationKind _kind, ProxyState memory _beforeState) internal {
        IV120OFTView oft = IV120OFTView(_oft);

        require(oft.token() == _beforeState.token, "V120: token changed");
        string memory symbolAfter = _isAdapter(_kind) ? _tokenSymbol(_beforeState.token) : oft.symbol();
        require(isStringEqual(symbolAfter, _beforeState.symbol), "V120: symbol changed");
        require(oft.endpoint() == _beforeState.endpoint, "V120: endpoint changed");
        require(oft.owner() == _beforeState.owner, "V120: owner changed");
        require(oft.approvalRequired() == _beforeState.approvalRequired, "V120: OFT/adapter kind changed");
        require(isStringEqual(oft.version(), "1.2.0"), "V120: version mismatch");

        (bool hasRateLimiter, bytes memory rateLimiterData) =
            _oft.staticcall(abi.encodeWithSignature("rateLimitGlobalConfig()"));
        require(hasRateLimiter && rateLimiterData.length >= 32, "V120: rate limiter missing");

        if (_kind == ImplementationKind.TempoOFT || _kind == ImplementationKind.Tip20Adapter) {
            require(ITempoV120View(_oft).nativeToken() == _beforeState.nativeToken, "V120: Tempo native token changed");
        }
    }

    /// @notice Resolve the supply seeds for this chain.
    /// @dev If scripts/ops/V120/supply/<chainid>.json exists, it is treated as the reviewed source
    ///      of truth. Otherwise, EVM-readable seeds are generated from fresh peer-chain forks and
    ///      the snapshot artifact is written for review.
    function _resolveSupplySeeds(ImplementationKind[] memory _kinds) internal returns (SupplySeed[] memory seeds) {
        string memory path =
            string.concat(vm.projectRoot(), "/scripts/ops/V120/supply/", simulateConfig.chainid.toString(), ".json");

        if (vm.exists(path)) {
            return _parseSupplySeedsJson(path);
        }

        seeds = _buildAutomaticSupplySeeds(_kinds);
        if (seeds.length != 0) {
            _writeGeneratedSupplySeeds(seeds);
        }
    }

    function _parseSupplySeedsJson(string memory _path) internal view returns (SupplySeed[] memory seeds) {
        string memory j = vm.readFile(_path);
        address[] memory ofts = vm.parseJsonAddressArray(j, ".oft");
        uint256[] memory eids = vm.parseJsonUintArray(j, ".eid");
        string[] memory amounts = vm.parseJsonStringArray(j, ".initialTotalSupply");
        bool[] memory allowNegatives = vm.parseJsonBoolArray(j, ".allowNegativeSupply");
        require(
            ofts.length == eids.length && eids.length == amounts.length && amounts.length == allowNegatives.length,
            "V120: supply seed arrays length mismatch"
        );

        seeds = new SupplySeed[](ofts.length);
        for (uint256 i; i < ofts.length; ++i) {
            seeds[i] = SupplySeed({
                oft: ofts[i],
                eid: uint32(eids[i]),
                initialTotalSupply: vm.parseUint(amounts[i]),
                allowNegativeSupply: allowNegatives[i],
                sourceChainid: 0,
                sourceBlock: 0
            });
        }
    }

    /// @notice Simulate + serialize the numeric `setInitialTotalSupply` seeds AGAINST THE
    ///         LIVE v1.1.0 PROXIES, before any upgrade — executed by each OFT's owner.
    ///         Seeding first removes the post-upgrade freeze window entirely: the ERC-7201
    ///         supply storage persists across the implementation upgrade.
    function _simulateSeedAhead(ImplementationKind[] memory _kinds, SupplySeed[] memory _seeds) internal {
        for (uint256 i; i < _seeds.length; ++i) {
            if (_seeds[i].initialTotalSupply == 0) continue;
            // Skip anything the chain already satisfies; the setter overwrites, so lowering a
            // live baseline would shrink headroom rather than extend it.
            if (ISupplyLedger(_seeds[i].oft).initialTotalSupply(_seeds[i].eid) >= _seeds[i].initialTotalSupply) {
                continue;
            }
            string memory symbol = _requireSupplyTrackedOft(_seeds[i].oft, _kinds);
            address owner = IV120OFTView(_seeds[i].oft).owner();
            bytes memory data = abi.encodeCall(
                FraxOFTMintableAdapterUpgradeable.setInitialTotalSupply,
                (_seeds[i].eid, _seeds[i].initialTotalSupply)
            );
            string memory name =
                string.concat("Set ", symbol, " initialTotalSupply[", uint256(_seeds[i].eid).toString(), "] (pre-upgrade)");

            vm.startPrank(owner);
            _safeCall(_seeds[i].oft, data, name);
            vm.stopPrank();
            _pushPhasedTx(owner, BatchPhase.SeedAhead, name, _seeds[i].oft, data);
        }
    }

    /// @notice Simulate + serialize the v1.2.0-only `setAllowNegativeSupply` calls after the
    ///         upgrade — executed by each OFT's owner. When the chain upgrades through a
    ///         timelock and the owner is the same Safe that fires `executeTransaction`, the
    ///         call is folded into that batch so it lands atomically with the upgrade.
    function _simulatePostUpgradeSeeds(ImplementationKind[] memory _kinds, SupplySeed[] memory _seeds) internal {
        for (uint256 i; i < _seeds.length; ++i) {
            if (!_seeds[i].allowNegativeSupply) continue;
            if (_allowNegativeSupplyIsSet(_seeds[i].oft, _seeds[i].eid)) continue; // already enabled
            string memory symbol = _requireSupplyTrackedOft(_seeds[i].oft, _kinds);
            address owner = IV120OFTView(_seeds[i].oft).owner();
            bytes memory data =
                abi.encodeCall(FraxOFTMintableAdapterUpgradeable.setAllowNegativeSupply, (_seeds[i].eid, true));
            string memory name =
                string.concat("Allow negative supply ", symbol, "[", uint256(_seeds[i].eid).toString(), "]");

            // `setAllowNegativeSupply` ships with v1.2.0, so it cannot be simulated while the
            // proxy still serves v1.1.0. The call is still serialized: this step is executed
            // after the upgrade, by which point the setter exists.
            if (_isUpgraded(_seeds[i].oft)) {
                vm.startPrank(owner);
                _safeCall(_seeds[i].oft, data, name);
                vm.stopPrank();
            } else {
                console.log("V120: not yet on v1.2.0, serializing unsimulated (executes post-upgrade):", name);
            }

            bool foldIntoExecute =
                upgradeViaTimelock && owner == upgradeExecutor && _hasPhase(BatchPhase.TimelockExecute);
            BatchPhase phase = foldIntoExecute ? BatchPhase.TimelockExecute : BatchPhase.PostUpgrade;
            _pushPhasedTx(owner, phase, name, _seeds[i].oft, data);
        }
    }

    function _buildAutomaticSupplySeeds(ImplementationKind[] memory)
        internal
        virtual
        returns (SupplySeed[] memory seeds)
    {
        return new SupplySeed[](0);
    }

    function _buildFraxtalSupplySeeds(ImplementationKind[] memory _kinds) internal returns (SupplySeed[] memory seeds) {
        console.log(
            "V120 WARNING: Somnia (5031, EIP-1898 unsupported) cannot be fork-read; add its circulating supply (and Solana's, if non-zero) manually to scripts/ops/V120/supply/252.json"
        );
        uint256 targetFork = vm.activeFork();
        address targetSfrxUsdOft = connectedOfts[uint256(Token.SFRXUSD)];
        address targetFrxUsdOft = connectedOfts[uint256(Token.FRXUSD)];
        ImplementationKind targetSfrxUsdKind = _kinds[uint256(Token.SFRXUSD)];
        ImplementationKind targetFrxUsdKind = _kinds[uint256(Token.FRXUSD)];
        SupplySeed[] memory pendingSeeds = new SupplySeed[](proxyConfigs.length * NUM_OFTS);
        uint256 seedCount;

        // Snapshot the live ledger while the target chain is still the active fork.
        Ledger[] memory sfrxLedger = _snapshotLedger(targetSfrxUsdOft, targetSfrxUsdKind);
        Ledger[] memory frxLedger = _snapshotLedger(targetFrxUsdOft, targetFrxUsdKind);

        for (uint256 c; c < proxyConfigs.length; ++c) {
            L0Config memory peerConfig = proxyConfigs[c];
            if (!_shouldAutoReadSupply(peerConfig)) continue;
            address[] memory peerOfts = _getChainPeers(peerConfig.chainid);

            uint256 peerFork = vm.createFork(peerConfig.RPC);
            vm.selectFork(peerFork);
            require(block.chainid == peerConfig.chainid, "V120: peer RPC chain mismatch");

            uint256 sourceBlock = block.number;
            seedCount = _recordPeerSupplySeed({
                _seeds: pendingSeeds,
                _seedCount: seedCount,
                _targetOft: targetSfrxUsdOft,
                _targetKind: targetSfrxUsdKind,
                _peerOft: peerOfts[uint256(Token.SFRXUSD)],
                _peerConfig: peerConfig,
                _sourceBlock: sourceBlock,
                _ledger: sfrxLedger[c]
            });
            seedCount = _recordPeerSupplySeed({
                _seeds: pendingSeeds,
                _seedCount: seedCount,
                _targetOft: targetFrxUsdOft,
                _targetKind: targetFrxUsdKind,
                _peerOft: peerOfts[uint256(Token.FRXUSD)],
                _peerConfig: peerConfig,
                _sourceBlock: sourceBlock,
                _ledger: frxLedger[c]
            });

            vm.selectFork(targetFork);
        }

        vm.selectFork(targetFork);
        return _trimSupplySeeds(pendingSeeds, seedCount);
    }

    /// @notice Hub-facing bypass for every eid this adapter actually peers with.
    /// @dev A numeric baseline here would have to equal the whole rest-of-mesh supply, which drifts
    ///      continuously; the bypass is the transitional answer and should be reverted per eid once
    ///      the ledger is reconciled. Covers every live peer, not just the hub — Ethereum's adapters
    ///      also peer Solana directly, and an uncovered eid reverts on its first inbound transfer.
    function _buildHubFacingAllowNegativeSeeds(ImplementationKind[] memory _kinds)
        internal
        view
        returns (SupplySeed[] memory seeds)
    {
        SupplySeed[] memory pending = new SupplySeed[](_kinds.length * allConfigs.length);
        uint256 seedCount;

        for (uint256 i; i < _kinds.length; ++i) {
            if (!_isSupplyTracked(_kinds[i])) continue;
            for (uint256 c; c < allConfigs.length; ++c) {
                uint256 peerChainid = allConfigs[c].chainid;
                if (peerChainid == simulateConfig.chainid) continue;
                if (isDeprecatedChain(peerChainid)) continue;

                uint32 eid = uint32(allConfigs[c].eid);
                if (IOAppCore(connectedOfts[i]).peers(eid) == bytes32(0)) continue;

                pending[seedCount++] = SupplySeed({
                    oft: connectedOfts[i],
                    eid: eid,
                    initialTotalSupply: 0,
                    allowNegativeSupply: true,
                    sourceChainid: peerChainid,
                    sourceBlock: 0
                });
            }
        }

        return _trimSupplySeeds(pending, seedCount);
    }

    function _recordPeerSupplySeed(
        SupplySeed[] memory _seeds,
        uint256 _seedCount,
        address _targetOft,
        ImplementationKind _targetKind,
        address _peerOft,
        L0Config memory _peerConfig,
        uint256 _sourceBlock,
        Ledger memory _ledger
    ) internal returns (uint256 seedCount) {
        seedCount = _seedCount;
        if (!_isSupplyTracked(_targetKind)) return seedCount;
        if (_peerOft.code.length == 0) return seedCount;

        uint256 supply = _readCirculatingSupply(_peerOft, _ledger.decimals);

        // The upgrade does NOT reset this ledger: v1.1.0 already accumulates transferTo/transferFrom
        // in the same namespaced slot and is already partially seeded — it simply never enforces the
        // guard. v1.2.0 starts enforcing against those accumulated counters, so the seed must be
        // derived from the live ledger. Seeding the peer's raw supply would overwrite a calibrated
        // baseline and can drop an eid straight into a permanent revert.
        // Target headroom == the peer's circulating supply: at most that much can ever come back.
        uint256 required = _ledger.transferFrom > _ledger.transferTo
            ? _ledger.transferFrom - _ledger.transferTo + supply
            : supply;
        if (required <= _ledger.initialTotalSupply) return seedCount; // already covered; never lower it

        _seeds[seedCount++] = SupplySeed({
            oft: _targetOft,
            eid: uint32(_peerConfig.eid),
            initialTotalSupply: required,
            allowNegativeSupply: false,
            sourceChainid: _peerConfig.chainid,
            sourceBlock: _sourceBlock
        });
    }

    /// @notice Read the supply ledger for every configured peer eid on the active (target) fork.
    function _snapshotLedger(address _oft, ImplementationKind _kind) internal returns (Ledger[] memory out) {
        out = new Ledger[](proxyConfigs.length);
        if (!_isSupplyTracked(_kind)) return out;
        uint8 localDecimals = _localDecimals(_oft);
        for (uint256 i; i < proxyConfigs.length; ++i) {
            uint32 eid = uint32(proxyConfigs[i].eid);
            out[i] = Ledger({
                initialTotalSupply: ISupplyLedger(_oft).initialTotalSupply(eid),
                transferFrom: ISupplyLedger(_oft).totalTransferFrom(eid),
                transferTo: ISupplyLedger(_oft).totalTransferTo(eid),
                decimals: localDecimals
            });
        }
    }

    function _writeGeneratedSupplySeeds(SupplySeed[] memory _seeds) internal {
        string memory directory = string.concat(vm.projectRoot(), "/scripts/ops/V120/supply/generated");
        vm.createDir(directory, true);
        string memory path = string.concat(directory, "/", simulateConfig.chainid.toString(), ".json");
        vm.writeFile(path, _buildSupplySeedsJson(_seeds));
    }

    function _buildSupplySeedsJson(SupplySeed[] memory _seeds) internal view returns (string memory body) {
        body = string.concat(
            "{\n",
            '  "_comment": "Auto-generated by UpgradeV120Base from fresh EVM fork reads. ',
            'Copy to scripts/ops/V120/supply/<chainid>.json to pin/review manually.",\n',
            '  "chainId": ',
            simulateConfig.chainid.toString(),
            ",\n",
            '  "sourceChainId": ',
            _uintArrayJson(_seeds, 0),
            ",\n",
            '  "sourceBlock": ',
            _uintArrayJson(_seeds, 1),
            ",\n",
            '  "oft": ',
            _addressArrayJson(_seeds),
            ",\n",
            '  "eid": ',
            _uintArrayJson(_seeds, 2),
            ",\n",
            '  "initialTotalSupply": ',
            _amountArrayJson(_seeds),
            ",\n",
            '  "allowNegativeSupply": ',
            _boolArrayJson(_seeds),
            "\n",
            "}\n"
        );
    }

    function _addressArrayJson(SupplySeed[] memory _seeds) internal pure returns (string memory out) {
        out = "[";
        for (uint256 i; i < _seeds.length; ++i) {
            if (i != 0) out = string.concat(out, ", ");
            out = string.concat(out, '"', Strings.toHexString(uint160(_seeds[i].oft), 20), '"');
        }
        return string.concat(out, "]");
    }

    function _uintArrayJson(SupplySeed[] memory _seeds, uint256 _field) internal pure returns (string memory out) {
        out = "[";
        for (uint256 i; i < _seeds.length; ++i) {
            if (i != 0) out = string.concat(out, ", ");
            uint256 value =
                _field == 0 ? _seeds[i].sourceChainid : _field == 1 ? _seeds[i].sourceBlock : uint256(_seeds[i].eid);
            out = string.concat(out, value.toString());
        }
        return string.concat(out, "]");
    }

    function _amountArrayJson(SupplySeed[] memory _seeds) internal pure returns (string memory out) {
        out = "[";
        for (uint256 i; i < _seeds.length; ++i) {
            if (i != 0) out = string.concat(out, ", ");
            out = string.concat(out, '"', _seeds[i].initialTotalSupply.toString(), '"');
        }
        return string.concat(out, "]");
    }

    function _boolArrayJson(SupplySeed[] memory _seeds) internal pure returns (string memory out) {
        out = "[";
        for (uint256 i; i < _seeds.length; ++i) {
            if (i != 0) out = string.concat(out, ", ");
            out = string.concat(out, _seeds[i].allowNegativeSupply ? "true" : "false");
        }
        return string.concat(out, "]");
    }

    function _trimSupplySeeds(SupplySeed[] memory _seeds, uint256 _length)
        internal
        pure
        returns (SupplySeed[] memory trimmed)
    {
        trimmed = new SupplySeed[](_length);
        for (uint256 i; i < _length; ++i) {
            trimmed[i] = _seeds[i];
        }
    }

    /// @dev Peer supply reads run entirely node-side via `eth_call` — peer contracts may be
    ///      EraVM bytecode (zkSync Era / Abstract), TIP-20 native accounts (Tempo), or use
    ///      opcodes newer than the local fork spec (Ethereum sfrxUSD); none of those can be
    ///      executed by the local fork EVM. The node answers at its own latest block, which
    ///      may sit slightly ahead of the fork's pinned block — acceptable for seed
    ///      generation, and the reviewed supply JSON remains the final source of truth.
    /// @notice Peer circulating supply, expressed in `_targetDecimals`.
    /// @dev The guard compares against local-denomination amounts, so a peer whose token uses a
    ///      different precision (Tempo's TIP-20 is 6dp against an 18dp hub) must be rescaled or the
    ///      seed lands orders of magnitude short.
    function _readCirculatingSupply(address _oft, uint8 _targetDecimals) internal returns (uint256) {
        address supplyToken = _supplyTokenOf(_oft);
        bytes memory ret = _peerEthCall(supplyToken, "0x18160ddd"); // totalSupply()
        require(ret.length == 32, "V120: bad totalSupply response");
        uint256 supply = abi.decode(ret, (uint256));

        uint8 peerDecimals = uint8(abi.decode(_peerEthCall(supplyToken, "0x313ce567"), (uint256))); // decimals()
        if (peerDecimals < _targetDecimals) return supply * (10 ** (_targetDecimals - peerDecimals));
        if (peerDecimals > _targetDecimals) return supply / (10 ** (peerDecimals - _targetDecimals));
        return supply;
    }

    /// @dev approvalRequired() distinguishes adapters (read the underlying token) from OFTs.
    function _supplyTokenOf(address _oft) internal returns (address) {
        bool approvalRequired = abi.decode(_peerEthCall(_oft, "0x9f68b964"), (bool));
        if (!approvalRequired) return _oft;
        return abi.decode(_peerEthCall(_oft, "0xfc0c546a"), (address)); // token()
    }

    /// @notice Local accounting precision of a supply-tracked adapter on the active fork.
    function _localDecimals(address _oft) internal returns (uint8) {
        return uint8(abi.decode(_peerEthCall(_supplyTokenOf(_oft), "0x313ce567"), (uint256)));
    }

    /// @notice Read an ERC-20 `symbol()` node-side: several live token implementations
    ///         (Fraxtal predeploys, Ethereum sfrxUSD) use opcodes newer than the local
    ///         fork spec and revert `NotActivated` when executed in the local EVM.
    function _tokenSymbol(address _token) internal returns (string memory) {
        bytes memory ret = vm.rpc(
            "eth_call",
            string.concat('[{"to":"', Strings.toHexString(uint160(_token), 20), '","data":"0x95d89b41"},"latest"]')
        );
        return abi.decode(ret, (string));
    }

    /// @notice `eth_call` against the ACTIVE fork's RPC (select the peer fork first).
    function _peerEthCall(address _to, string memory _selectorHex) internal returns (bytes memory ret) {
        ret = vm.rpc(
            "eth_call",
            string.concat('[{"to":"', Strings.toHexString(uint160(_to), 20), '","data":"', _selectorHex, '"},"latest"]')
        );
        require(ret.length == 32, "V120: unexpected eth_call response");
    }

    function _shouldAutoReadSupply(L0Config memory _config) internal view returns (bool) {
        if (isDeprecatedChain(_config.chainid)) return false;
        if (_config.chainid == simulateConfig.chainid) return false;
        if (_config.endpoint == address(0)) return false;
        // Somnia's node software rejects EIP-1898 blockHash-pinned queries, which forge's
        // fork backend requires — it cannot be forked. Its circulating supply MUST be added
        // manually to the reviewed scripts/ops/V120/supply/<chainid>.json.
        if (_config.chainid == 5031) return false;
        return bytes(_config.RPC).length != 0;
    }

    function _eidForChain(uint256 _chainid) internal view returns (uint32) {
        for (uint256 i; i < proxyConfigs.length; ++i) {
            if (proxyConfigs[i].chainid == _chainid) return uint32(proxyConfigs[i].eid);
        }
        revert(string.concat("V120: EID not found for chain ", _chainid.toString()));
    }

    function _hasPhase(BatchPhase _phase) internal view returns (bool) {
        for (uint256 i; i < phasedTxs.length; ++i) {
            if (phasedTxs[i].phase == _phase) return true;
        }
        return false;
    }

    /// @dev Filename stem for emitted Safe batches; overridden by standalone operations.
    function _batchPrefix() internal view virtual returns (string memory) {
        return "UpgradeV120";
    }

    /// @notice True once the proxy serves the v1.2.0 implementation.
    function _isUpgraded(address _oft) internal view returns (bool) {
        (bool ok, bytes memory ret) = _oft.staticcall(abi.encodeWithSignature("version()"));
        if (!ok || ret.length == 0) return false;
        return isStringEqual(abi.decode(ret, (string)), "1.2.0");
    }

    /// @dev The getter only exists from v1.2.0, so a failed call means "not set yet".
    function _allowNegativeSupplyIsSet(address _oft, uint32 _eid) internal view returns (bool) {
        (bool ok, bytes memory ret) =
            _oft.staticcall(abi.encodeWithSignature("allowNegativeSupply(uint32)", _eid));
        return ok && ret.length == 32 && abi.decode(ret, (bool));
    }

    /// @notice Implementation-kind matrix for the active chain, without deploying anything.
    function _kindsForChain() internal view returns (ImplementationKind[] memory kinds) {
        kinds = new ImplementationKind[](NUM_OFTS);
        uint256 chainid = simulateConfig.chainid;

        if (chainid == TEMPO_CHAIN_ID) {
            for (uint256 i; i < NUM_OFTS; ++i) kinds[i] = ImplementationKind.TempoOFT;
            kinds[uint256(Token.FRXUSD)] = ImplementationKind.Tip20Adapter;
        } else if (chainid == FRAXTAL_CHAIN_ID || chainid == ETHEREUM_CHAIN_ID) {
            for (uint256 i; i < NUM_OFTS; ++i) kinds[i] = ImplementationKind.EscrowAdapter;
            if (chainid == ETHEREUM_CHAIN_ID) kinds[uint256(Token.WFRAX)] = ImplementationKind.StandardOFT;
            kinds[uint256(Token.SFRXUSD)] = ImplementationKind.MintableAdapter;
            kinds[uint256(Token.FRXUSD)] = ImplementationKind.MintableAdapter;
        } else {
            for (uint256 i; i < NUM_OFTS; ++i) kinds[i] = ImplementationKind.StandardOFT;
        }
    }

    function _isSupplyTracked(ImplementationKind _kind) internal pure returns (bool) {
        return _kind == ImplementationKind.MintableAdapter || _kind == ImplementationKind.Tip20Adapter;
    }

    /// @notice Ensure `_oft` is a supply-tracked adapter on this chain; returns its token symbol.
    function _requireSupplyTrackedOft(address _oft, ImplementationKind[] memory _kinds)
        internal
        returns (string memory symbol)
    {
        for (uint256 i; i < connectedOfts.length; ++i) {
            if (connectedOfts[i] != _oft) continue;
            require(
                _kinds[i] == ImplementationKind.MintableAdapter || _kinds[i] == ImplementationKind.Tip20Adapter,
                "V120: supply seed targets non-supply-tracked OFT"
            );
            return _tokenSymbol(IV120OFTView(_oft).token());
        }
        revert("V120: supply seed OFT not on this chain");
    }

    function _isAdapter(ImplementationKind _kind) private pure returns (bool) {
        return _kind == ImplementationKind.EscrowAdapter || _kind == ImplementationKind.MintableAdapter
            || _kind == ImplementationKind.Tip20Adapter;
    }
}
