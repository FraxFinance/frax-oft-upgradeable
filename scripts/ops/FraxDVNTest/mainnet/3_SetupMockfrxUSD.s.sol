// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/StdJson.sol";
import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { Constant } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/test/util/Constant.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

// fraxtal : forge script ./scripts/ops/FraxDVNTest/mainnet/3_SetupMockfrxUSD.s.sol --rpc-url https://rpc.frax.com --broadcast
// tempo   : forge script ./scripts/ops/FraxDVNTest/mainnet/3_SetupMockfrxUSD.s.sol --rpc-url $TEMPO_RPC_URL --tempo.fee-token 0x20c0000000000000000000000000000000000000 --gas-estimate-multiplier 100 --broadcast

contract SetupMockfrxUSD is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    /// @dev Same address on all chains (deployed via Nick's CREATE2 with salt "mockfrxUSD")
    address constant MOCK_FRXUSD = 0x458edF815687e48354909A1a848f2528e1655764;

    function loadJsonConfig() public override {
        delete expectedProxyOfts;

        super.loadJsonConfig();

        /// TODO: Remove this filter once mockfrxUSD is deployed on all chains.
        ///       Currently only Fraxtal (252) and Tempo (4217) have the OFT deployed.
        _filterConfigs();

        // mockfrxUSD has the same deterministic address on all chains
        connectedOfts = new address[](1);
        connectedOfts[0] = MOCK_FRXUSD;
        proxyOfts.push(MOCK_FRXUSD);
        expectedProxyOfts.push(MOCK_FRXUSD);
    }

    /// @notice Temporary filter — restrict to Fraxtal and Tempo until mockfrxUSD is deployed elsewhere
    function _filterConfigs() internal {
        L0Config[] memory filtered;
        uint256 count;

        // Filter proxyConfigs
        filtered = new L0Config[](proxyConfigs.length);
        count = 0;
        for (uint256 i; i < proxyConfigs.length; i++) {
            if (_isEnabledChain(proxyConfigs[i].chainid)) {
                filtered[count++] = proxyConfigs[i];
            }
        }
        delete proxyConfigs;
        for (uint256 i; i < count; i++) {
            proxyConfigs.push(filtered[i]);
        }

        // Filter allConfigs
        filtered = new L0Config[](allConfigs.length);
        count = 0;
        for (uint256 i; i < allConfigs.length; i++) {
            if (_isEnabledChain(allConfigs[i].chainid)) {
                filtered[count++] = allConfigs[i];
            }
        }
        delete allConfigs;
        for (uint256 i; i < count; i++) {
            allConfigs.push(filtered[i]);
        }
    }

    /// @notice Returns true for chains where mockfrxUSD is deployed
    /// TODO: Remove once deployed on all chains
    function _isEnabledChain(uint256 _chainid) internal pure returns (bool) {
        return _chainid == 252 || _chainid == 4217;
    }

    function run() public override {
        setupSource();
    }

    function setupNonEvms() public override {}

    function setPriviledgedRoles() public override {}

    function setPeer(L0Config memory _config, address _connectedOft, bytes32 _peerOftAsBytes32) public override {
        if (hasNoPeer(_connectedOft, _config, _peerOftAsBytes32)) {
            super.setPeer(_config, _connectedOft, _peerOftAsBytes32);
        }
    }

    /// @dev Same deterministic address on every chain
    function determinePeer(uint256, address, address[] memory) public pure override returns (address) {
        return MOCK_FRXUSD;
    }

    function setLib(L0Config memory _connectedConfig, address _connectedOft, L0Config memory _config) public override {
        if (_config.eid == 30168) return;
        if (_config.eid == 30151) return;

        if (_connectedConfig.eid == 30370) {
            // plumephoenix: skip x-layer (30274), polygon zkevm (30158), worldchain (30319),
            // zksync (30165), movement (30325), aptos (30108)
            if (
                _config.eid == 30274 ||
                _config.eid == 30158 ||
                _config.eid == 30319 ||
                _config.eid == 30165 ||
                _config.eid == 30325 ||
                _config.eid == 30108
            ) return;
        }

        if (_connectedConfig.eid == 30375) {
            // katana: skip unichain (30320), plumephoenix (30370), movement (30325), aptos (30108)
            if (_config.eid == 30320 || _config.eid == 30370 || _config.eid == 30325 || _config.eid == 30108) return;
        }

        if (_connectedConfig.eid == 30211) {
            // aurora: skip aptos (30108)
            if (_config.eid == 30108) return;
        }

        if (_connectedConfig.eid == 30367) {
            // hyperliquid: skip botanix (30376)
            if (_config.eid == 30376) return;
        }

        if (_connectedConfig.eid == 30410) {
            // tempo: skip solana (30168), movement (30325), aptos (30108), blast (30243)
            if (_config.eid == 30168 || _config.eid == 30325 || _config.eid == 30108 || _config.eid == 30243) return;
        }

        // TODO : only set library if it is not same as config
        super.setLib(_connectedConfig, _connectedOft, _config);
    }

    function setConfig(
        L0Config memory _srcConfig,
        L0Config memory _dstConfig,
        address _lib,
        address _oft
    ) public override {
        if (_dstConfig.eid == 30168) return;
        if (_dstConfig.eid == 30151) return;

        if (_srcConfig.eid == 30370) {
            // plumephoenix: skip x-layer (30274), polygon zkevm (30158), worldchain (30319),
            // zksync (30165), movement (30325), aptos (30108)
            if (
                _dstConfig.eid == 30274 ||
                _dstConfig.eid == 30158 ||
                _dstConfig.eid == 30319 ||
                _dstConfig.eid == 30165 ||
                _dstConfig.eid == 30325 ||
                _dstConfig.eid == 30108
            ) return;
        }

        if (_srcConfig.eid == 30375) {
            // katana: skip unichain (30320), plumephoenix (30370), movement (30325), aptos (30108)
            if (
                _dstConfig.eid == 30320 || _dstConfig.eid == 30370 || _dstConfig.eid == 30325 || _dstConfig.eid == 30108
            ) return;
        }

        if (_srcConfig.eid == 30211) {
            // aurora: skip aptos (30108)
            if (_dstConfig.eid == 30108) return;
        }

        if (_srcConfig.eid == 30367) {
            // hyperliquid: skip botanix (30376)
            if (_dstConfig.eid == 30376) return;
        }

        if (_srcConfig.eid == 30410) {
            // tempo: skip solana (30168), movement (30325), aptos (30108), blast (30243)
            if (
                _dstConfig.eid == 30168 || _dstConfig.eid == 30325 || _dstConfig.eid == 30108 || _dstConfig.eid == 30243
            ) return;
        }

        super.setConfig(_srcConfig, _dstConfig, _lib, _oft);
    }

    function getDvnStack(
        uint256 _srcChainId,
        uint256 _dstChainId
    ) public view override returns (DvnStack memory dvnStack) {
        require(_srcChainId != _dstChainId, "_srcChainId == _dstChainId");

        string memory root = vm.projectRoot();
        root = string.concat(root, "/config/dvn/");
        string memory name = string.concat(_srcChainId.toString(), ".json");
        string memory path = string.concat(root, name);

        string memory jsonFile = vm.readFile(path);
        string memory key = string.concat(".", _dstChainId.toString());
        dvnStack = abi.decode(jsonFile.parseRaw(key), (DvnStack));
    }

    function postDeployChecks() internal view override {
        require(proxyOfts.length == 1, "Did not deploy OFT");
    }

    function hasNoPeer(
        address _oft,
        L0Config memory _dstConfig,
        bytes32 _peerOftAsBytes32
    ) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(uint32(_dstConfig.eid));
        return peer != _peerOftAsBytes32;
    }
}
