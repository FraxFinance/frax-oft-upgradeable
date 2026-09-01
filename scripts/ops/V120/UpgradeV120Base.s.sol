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

interface ITempoV120View {
    function nativeToken() external view returns (address);
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

    struct SupplySeed {
        address oft;
        uint32 eid;
        uint256 initialTotalSupply;
        bool allowNegativeSupply;
        uint256 sourceChainid;
        uint256 sourceBlock;
    }

    function outputDirectory() public view virtual returns (string memory);

    function filename() public view override returns (string memory) {
        return string.concat(outputDirectory(), "/UpgradeV120-", simulateConfig.chainid.toString(), ".json");
    }

    /// @notice Directory for a V120 Safe batch: scripts/ops/V120/<leaf>/txs.
    function _txsDirectory(string memory _leaf) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/scripts/ops/V120/", _leaf, "/txs");
    }

    /// @notice True for ZK-stack chains (zkSync Era, Abstract) handled by the dedicated ZK script.
    function _isZkStackChain(uint256 _chainid) internal pure returns (bool) {
        return _chainid == ZKSYNC_CHAIN_ID || _chainid == ABSTRACT_CHAIN_ID;
    }

    /// @notice Fork the chain, deploy its profile's implementations, and emit the Safe upgrade batch.
    function _upgradeChain(L0Config memory _config) internal {
        _prepareUpgrade(_config);
        (address[] memory implementations, ImplementationKind[] memory kinds) = _deployImplementations();
        _simulateUpgrade(implementations, kinds);
        _appendSupplySeeds(kinds);
        _writeUpgrade();
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

        require(connectedOfts.length == NUM_OFTS, "V120: unexpected OFT count");
        for (uint256 i; i < connectedOfts.length; ++i) {
            require(connectedOfts[i] != address(0), "V120: zero OFT");
            require(connectedOfts[i].code.length != 0, "V120: OFT not deployed");
        }
    }

    /// @notice Hook for profile-specific implementation deployment.
    function _deployImplementations()
        internal
        virtual
        returns (address[] memory implementations, ImplementationKind[] memory kinds);

    function _simulateUpgrade(address[] memory _implementations, ImplementationKind[] memory _kinds) internal {
        require(_implementations.length == connectedOfts.length, "V120: implementation length mismatch");
        require(_kinds.length == connectedOfts.length, "V120: kind length mismatch");
        require(simulateConfig.delegate != address(0), "V120: zero delegate");

        vm.startPrank(simulateConfig.delegate);
        for (uint256 i; i < connectedOfts.length; ++i) {
            _submitUpgrade(connectedOfts[i], _implementations[i], _kinds[i]);
        }
        require(serializedTxs.length == connectedOfts.length, "V120: missing serialized upgrade");
        vm.stopPrank();
    }

    function _writeUpgrade() internal {
        vm.createDir(outputDirectory(), true);
        new SafeTxUtil().writeTxs(serializedTxs, filename());
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
            kinds[i] = ImplementationKind.StandardOFT;
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

    function _submitUpgrade(address _oft, address _implementation, ImplementationKind _kind) internal {
        require(_implementation.code.length != 0, "V120: implementation not deployed");

        ProxyState memory beforeState = _readProxyState(_oft, _kind);
        if (simulateConfig.proxyAdmin != address(0)) {
            require(beforeState.proxyAdmin == simulateConfig.proxyAdmin, "V120: unexpected ProxyAdmin");
        }

        bool needsInitializer = _kind == ImplementationKind.StandardOFT || _kind == ImplementationKind.TempoOFT;
        bytes memory data;
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

        _safeCall(beforeState.proxyAdmin, data, "V120: upgrade");
        pushSerializedTx(string.concat("Upgrade ", beforeState.symbol, " to v1.2.0"), beforeState.proxyAdmin, 0, data);

        _validateUpgrade(_oft, _kind, beforeState);
    }

    function _readProxyState(address _oft, ImplementationKind _kind) internal view returns (ProxyState memory state) {
        IV120OFTView oft = IV120OFTView(_oft);
        state.token = oft.token();
        state.symbol = _isAdapter(_kind) ? IERC20Metadata(state.token).symbol() : oft.symbol();
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

    function _validateUpgrade(address _oft, ImplementationKind _kind, ProxyState memory _beforeState) internal view {
        IV120OFTView oft = IV120OFTView(_oft);

        require(oft.token() == _beforeState.token, "V120: token changed");
        string memory symbolAfter = _isAdapter(_kind) ? IERC20Metadata(_beforeState.token).symbol() : oft.symbol();
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

    /// @notice Append `setInitialTotalSupply` / `setAllowNegativeSupply` into the same batch.
    /// @dev If scripts/ops/V120/supply/<chainid>.json exists, it is treated as the reviewed source
    ///      of truth. Otherwise, EVM-readable seeds are generated from fresh peer-chain forks.
    function _appendSupplySeeds(ImplementationKind[] memory _kinds) internal {
        string memory path =
            string.concat(vm.projectRoot(), "/scripts/ops/V120/supply/", simulateConfig.chainid.toString(), ".json");

        if (vm.exists(path)) {
            _appendSupplySeedsFromJson(_kinds, path);
            return;
        }

        SupplySeed[] memory seeds = _buildAutomaticSupplySeeds(_kinds);
        if (seeds.length == 0) return;

        _writeGeneratedSupplySeeds(seeds);
        _appendSupplySeedCalls(_kinds, seeds);
    }

    function _appendSupplySeedsFromJson(ImplementationKind[] memory _kinds, string memory _path) internal {
        string memory j = vm.readFile(_path);
        address[] memory ofts = vm.parseJsonAddressArray(j, ".oft");
        uint256[] memory eids = vm.parseJsonUintArray(j, ".eid");
        string[] memory amounts = vm.parseJsonStringArray(j, ".initialTotalSupply");
        bool[] memory allowNegatives = vm.parseJsonBoolArray(j, ".allowNegativeSupply");
        require(
            ofts.length == eids.length && eids.length == amounts.length && amounts.length == allowNegatives.length,
            "V120: supply seed arrays length mismatch"
        );

        SupplySeed[] memory seeds = new SupplySeed[](ofts.length);
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

        _appendSupplySeedCalls(_kinds, seeds);
    }

    function _buildAutomaticSupplySeeds(ImplementationKind[] memory)
        internal
        virtual
        returns (SupplySeed[] memory seeds)
    {
        return new SupplySeed[](0);
    }

    function _buildFraxtalSupplySeeds(ImplementationKind[] memory _kinds) internal returns (SupplySeed[] memory seeds) {
        uint256 targetFork = vm.activeFork();
        address targetSfrxUsdOft = connectedOfts[uint256(Token.SFRXUSD)];
        address targetFrxUsdOft = connectedOfts[uint256(Token.FRXUSD)];
        ImplementationKind targetSfrxUsdKind = _kinds[uint256(Token.SFRXUSD)];
        ImplementationKind targetFrxUsdKind = _kinds[uint256(Token.FRXUSD)];
        SupplySeed[] memory pendingSeeds = new SupplySeed[](proxyConfigs.length * NUM_OFTS);
        uint256 seedCount;

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
                _sourceBlock: sourceBlock
            });
            seedCount = _recordPeerSupplySeed({
                _seeds: pendingSeeds,
                _seedCount: seedCount,
                _targetOft: targetFrxUsdOft,
                _targetKind: targetFrxUsdKind,
                _peerOft: peerOfts[uint256(Token.FRXUSD)],
                _peerConfig: peerConfig,
                _sourceBlock: sourceBlock
            });

            vm.selectFork(targetFork);
        }

        vm.selectFork(targetFork);
        return _trimSupplySeeds(pendingSeeds, seedCount);
    }

    function _buildHubFacingAllowNegativeSeeds(ImplementationKind[] memory _kinds)
        internal
        view
        returns (SupplySeed[] memory seeds)
    {
        uint256 trackedCount;
        for (uint256 i; i < _kinds.length; ++i) {
            if (_isSupplyTracked(_kinds[i])) ++trackedCount;
        }
        if (trackedCount == 0) return new SupplySeed[](0);

        uint32 fraxtalEid = _eidForChain(FRAXTAL_CHAIN_ID);
        seeds = new SupplySeed[](trackedCount);
        uint256 seedCount;
        for (uint256 i; i < _kinds.length; ++i) {
            if (!_isSupplyTracked(_kinds[i])) continue;
            seeds[seedCount++] = SupplySeed({
                oft: connectedOfts[i],
                eid: fraxtalEid,
                initialTotalSupply: 0,
                allowNegativeSupply: true,
                sourceChainid: FRAXTAL_CHAIN_ID,
                sourceBlock: 0
            });
        }
    }

    function _recordPeerSupplySeed(
        SupplySeed[] memory _seeds,
        uint256 _seedCount,
        address _targetOft,
        ImplementationKind _targetKind,
        address _peerOft,
        L0Config memory _peerConfig,
        uint256 _sourceBlock
    ) internal view returns (uint256 seedCount) {
        seedCount = _seedCount;
        if (!_isSupplyTracked(_targetKind)) return seedCount;
        if (_peerOft.code.length == 0) return seedCount;

        uint256 supply = _readCirculatingSupply(_peerOft);
        if (supply == 0) return seedCount;

        _seeds[seedCount++] = SupplySeed({
            oft: _targetOft,
            eid: uint32(_peerConfig.eid),
            initialTotalSupply: supply,
            allowNegativeSupply: false,
            sourceChainid: _peerConfig.chainid,
            sourceBlock: _sourceBlock
        });
    }

    function _appendSupplySeedCalls(ImplementationKind[] memory _kinds, SupplySeed[] memory _seeds) internal {
        for (uint256 i; i < _seeds.length; ++i) {
            string memory symbol = _requireSupplyTrackedOft(_seeds[i].oft, _kinds);

            if (_seeds[i].initialTotalSupply > 0) {
                _submitSupplyCall(
                    _seeds[i].oft,
                    abi.encodeCall(
                        FraxOFTMintableAdapterUpgradeable.setInitialTotalSupply,
                        (_seeds[i].eid, _seeds[i].initialTotalSupply)
                    ),
                    string.concat("Set ", symbol, " initialTotalSupply[", uint256(_seeds[i].eid).toString(), "]")
                );
            }
            if (_seeds[i].allowNegativeSupply) {
                _submitSupplyCall(
                    _seeds[i].oft,
                    abi.encodeCall(FraxOFTMintableAdapterUpgradeable.setAllowNegativeSupply, (_seeds[i].eid, true)),
                    string.concat("Allow negative supply ", symbol, "[", uint256(_seeds[i].eid).toString(), "]")
                );
            }
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

    function _readCirculatingSupply(address _oft) internal view returns (uint256) {
        IV120OFTView oft = IV120OFTView(_oft);
        address supplyToken = oft.approvalRequired() ? oft.token() : _oft;
        require(supplyToken.code.length != 0, "V120: supply token not deployed");
        return IERC20Metadata(supplyToken).totalSupply();
    }

    function _shouldAutoReadSupply(L0Config memory _config) internal view returns (bool) {
        if (isDeprecatedChain(_config.chainid)) return false;
        if (_config.chainid == simulateConfig.chainid) return false;
        if (_config.endpoint == address(0)) return false;
        return bytes(_config.RPC).length != 0;
    }

    function _eidForChain(uint256 _chainid) internal view returns (uint32) {
        for (uint256 i; i < proxyConfigs.length; ++i) {
            if (proxyConfigs[i].chainid == _chainid) return uint32(proxyConfigs[i].eid);
        }
        revert(string.concat("V120: EID not found for chain ", _chainid.toString()));
    }

    function _isSupplyTracked(ImplementationKind _kind) internal pure returns (bool) {
        return _kind == ImplementationKind.MintableAdapter || _kind == ImplementationKind.Tip20Adapter;
    }

    /// @notice Ensure `_oft` is a supply-tracked adapter on this chain; returns its token symbol.
    function _requireSupplyTrackedOft(address _oft, ImplementationKind[] memory _kinds)
        internal
        view
        returns (string memory symbol)
    {
        for (uint256 i; i < connectedOfts.length; ++i) {
            if (connectedOfts[i] != _oft) continue;
            require(
                _kinds[i] == ImplementationKind.MintableAdapter || _kinds[i] == ImplementationKind.Tip20Adapter,
                "V120: supply seed targets non-supply-tracked OFT"
            );
            return IERC20Metadata(IV120OFTView(_oft).token()).symbol();
        }
        revert("V120: supply seed OFT not on this chain");
    }

    /// @notice Simulate a supply-guard setter as the Safe (owner) then serialize it into the batch.
    function _submitSupplyCall(address _oft, bytes memory _data, string memory _name) internal {
        vm.startPrank(simulateConfig.delegate);
        _safeCall(_oft, _data, _name);
        vm.stopPrank();
        pushSerializedTx(_name, _oft, 0, _data);
    }

    function _isAdapter(ImplementationKind _kind) private pure returns (bool) {
        return _kind == ImplementationKind.EscrowAdapter || _kind == ImplementationKind.MintableAdapter
            || _kind == ImplementationKind.Tip20Adapter;
    }
}
