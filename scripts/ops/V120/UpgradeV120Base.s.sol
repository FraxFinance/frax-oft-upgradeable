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

    function outputDirectory() public view virtual returns (string memory);

    function filename() public view override returns (string memory) {
        return string.concat(
            outputDirectory(),
            "/UpgradeV120-",
            simulateConfig.chainid.toString(),
            ".json"
        );
    }

    function _prepareChain(L0Config memory _config) internal {
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

    function _startImplementationBroadcast() internal {
        require(configDeployerPK != 0, "V120: missing PK_CONFIG_DEPLOYER");
        vm.startBroadcast(configDeployerPK);
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

        for (uint256 i; i < NUM_OFTS; ++i) kinds[i] = ImplementationKind.StandardOFT;
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
        address tip20Adapter = address(
            new FraxOFTMintableAdapterUpgradeableTIP20(tip20, simulateConfig.endpoint)
        );
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
                implementations[i] = address(
                    new FraxOFTMintableAdapterUpgradeable(token, simulateConfig.endpoint)
                );
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
                implementations[i] = address(
                    new FraxOFTMintableAdapterUpgradeable(token, simulateConfig.endpoint)
                );
                kinds[i] = ImplementationKind.MintableAdapter;
            } else {
                implementations[i] = address(new FraxOFTAdapterUpgradeable(token, simulateConfig.endpoint));
                kinds[i] = ImplementationKind.EscrowAdapter;
            }
        }
        vm.stopBroadcast();
    }

    function _submitUpgrades(address[] memory _implementations, ImplementationKind[] memory _kinds) internal {
        require(_implementations.length == connectedOfts.length, "V120: implementation length mismatch");
        require(_kinds.length == connectedOfts.length, "V120: kind length mismatch");
        require(simulateConfig.delegate != address(0), "V120: zero delegate");

        vm.startPrank(simulateConfig.delegate);
        for (uint256 i; i < connectedOfts.length; ++i) {
            _submitUpgrade(connectedOfts[i], _implementations[i], _kinds[i]);
        }
        vm.stopPrank();

        require(serializedTxs.length == connectedOfts.length, "V120: missing serialized upgrade");
        vm.createDir(outputDirectory(), true);
        new SafeTxUtil().writeTxs(serializedTxs, filename());
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
            data = abi.encodeCall(
                ProxyAdmin.upgrade,
                (TransparentUpgradeableProxy(payable(_oft)), _implementation)
            );
        }

        (bool success, bytes memory returnData) = beforeState.proxyAdmin.call(data);
        if (!success) _revertWithData(returnData);

        serializedTxs.push(
            SerializedTx({
                name: string.concat("Upgrade ", beforeState.symbol, " to v1.2.0"),
                to: beforeState.proxyAdmin,
                value: 0,
                data: data
            })
        );

        _validateUpgrade(_oft, _kind, beforeState);
    }

    function _readProxyState(address _oft, ImplementationKind _kind)
        internal
        view
        returns (ProxyState memory state)
    {
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
        string memory symbolAfter = _isAdapter(_kind)
            ? IERC20Metadata(_beforeState.token).symbol()
            : oft.symbol();
        require(isStringEqual(symbolAfter, _beforeState.symbol), "V120: symbol changed");
        require(oft.endpoint() == _beforeState.endpoint, "V120: endpoint changed");
        require(oft.owner() == _beforeState.owner, "V120: owner changed");
        require(oft.approvalRequired() == _beforeState.approvalRequired, "V120: OFT/adapter kind changed");
        require(isStringEqual(oft.version(), "1.2.0"), "V120: version mismatch");

        (bool hasRateLimiter, bytes memory rateLimiterData) = _oft.staticcall(
            abi.encodeWithSignature("rateLimitGlobalConfig()")
        );
        require(hasRateLimiter && rateLimiterData.length >= 32, "V120: rate limiter missing");

        if (_kind == ImplementationKind.TempoOFT || _kind == ImplementationKind.Tip20Adapter) {
            require(
                ITempoV120View(_oft).nativeToken() == _beforeState.nativeToken,
                "V120: Tempo native token changed"
            );
        }
    }

    function _isAdapter(ImplementationKind _kind) private pure returns (bool) {
        return _kind == ImplementationKind.EscrowAdapter
            || _kind == ImplementationKind.MintableAdapter
            || _kind == ImplementationKind.Tip20Adapter;
    }

    function _revertWithData(bytes memory _returnData) private pure {
        if (_returnData.length == 0) revert("V120: upgrade failed");
        assembly {
            revert(add(_returnData, 32), mload(_returnData))
        }
    }
}
