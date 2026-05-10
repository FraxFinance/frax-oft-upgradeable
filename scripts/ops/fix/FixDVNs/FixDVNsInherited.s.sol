// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

contract FixDVNsInherited is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant FRAXTAL_CHAIN_ID = 252;
    uint256 public constant SOLANA_CHAIN_ID = 111111111;

    uint256 public sourceChainId = vm.envOr("SOURCE_CHAIN_ID", uint256(0));
    uint256 public dstChainId = vm.envOr("DST_CHAIN_ID", uint256(0));

    function filenameForStep(string memory _stepName) public view returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/fix/FixDVNs/generated/canary-nethermind/evm/");

        string memory name = string.concat((block.timestamp).toString(), "-");
        name = string.concat(name, _stepName);
        name = string.concat(name, "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        if (dstChainId != 0) {
            name = string.concat(name, "-to-");
            name = string.concat(name, dstChainId.toString());
        }
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function isZkChain(uint256 _chainId) public pure returns (bool) {
        return _chainId == 324 || _chainId == 2741;
    }

    function matchesSource(L0Config memory _config) public view returns (bool) {
        if (sourceChainId != 0 && _config.chainid != sourceChainId) return false;
        return true;
    }

    function matchesEvmDestination(L0Config memory _srcConfig, L0Config memory _dstConfig) public view returns (bool) {
        if (_srcConfig.chainid == _dstConfig.chainid) return false;
        if (dstChainId != 0 && _dstConfig.chainid != dstChainId) return false;
        if (!isFraxtalHubRoute(_srcConfig.chainid, _dstConfig.chainid)) return false;
        return true;
    }

    function matchesNonEvmDestination(L0Config memory _srcConfig, L0Config memory _dstConfig) public view returns (bool) {
        if (_srcConfig.chainid == _dstConfig.chainid) return false;
        if (dstChainId != 0 && _dstConfig.chainid != dstChainId) return false;
        if (!isFraxtalHubRoute(_srcConfig.chainid, _dstConfig.chainid) && !isEthereumSolanaRoute(_srcConfig.chainid, _dstConfig.chainid)) {
            return false;
        }
        return true;
    }

    function isFraxtalHubRoute(uint256 _srcChainId, uint256 _dstChainId) public pure returns (bool) {
        return _srcChainId == FRAXTAL_CHAIN_ID || _dstChainId == FRAXTAL_CHAIN_ID;
    }

    function isEthereumSolanaRoute(uint256 _srcChainId, uint256 _dstChainId) public pure returns (bool) {
        return (_srcChainId == ETHEREUM_CHAIN_ID && _dstChainId == SOLANA_CHAIN_ID)
            || (_srcChainId == SOLANA_CHAIN_ID && _dstChainId == ETHEREUM_CHAIN_ID);
    }
}
