// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import {UlnConfig} from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/uln/UlnBase.sol";

import {Arrays} from "@openzeppelin-5/contracts/utils/Arrays.sol";

/*
struct UlnConfig {
    uint64 confirmations;
    // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
    uint8 requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNThreshold; // (0, optionalDVNCount]
    address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
    address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
}
*/

// forge script scripts/ops/UpgradeDVNs/UpgradeDVNs.s.sol --rpc-url https://rpc.frax.com
contract UpgradeDVNs is DeployFraxOFTProtocol {

    using Strings for uint256;
    using stdJson for string;

    // used in getDvnStack to craft the memory array
    address[] dvnStackTemp;

    // Used in writing filename
    L0Config dstConfig;

    struct DvnStack {
        address bcwGroup;
        address horizen;
        address lz;
        address nethermind;
        address stargate;
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeDVNs/txs/");

        string memory name = string.concat(simulateConfig.chainid.toString(), "-");
        name = string.concat(name, dstConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function run() public override {
        proxyOfts = new address[](6);

        for (uint256 s=0; s<proxyConfigs.length; s++) {
            L0Config memory srcConfig = proxyConfigs[s];

            // NOTE: only checking for fraxtal <> xlayer
            if (srcConfig.chainid != 196 && srcConfig.chainid != 252) continue;
            setAllConfigs({
                _srcConfig: srcConfig,
                _dstConfigs: proxyConfigs                
            });
        }
    }

    function setAllConfigs(
        L0Config memory _srcConfig,
        L0Config[] memory _dstConfigs
    ) public {
        // loop through ofts
        for (uint256 d=0; d<_dstConfigs.length; d++) {
            dstConfig = _dstConfigs[d];

            // cannot set dvn options to self
            if (_srcConfig.chainid == dstConfig.chainid) continue;

            // NOTE: only checking for fraxtal <> xlayer
            if (dstConfig.chainid != 196 && dstConfig.chainid != 252) continue;

            setConfigs({
                _srcConfig: _srcConfig,
                _dstConfig: dstConfig
            });
        }
    }

    function setConfigs(
        L0Config memory _srcConfig,
        L0Config memory _dstConfig
    ) public virtual simulateAndWriteTxs(_srcConfig) {
        for (uint256 o=0; o<connectedOfts.length; o++) {
            address oft = connectedOfts[o];

            setConfig({
                _srcConfig: _srcConfig,
                _dstConfig: _dstConfig,
                _lib: _srcConfig.sendLib302,
                _oft: oft
            });

            setConfig({
                _srcConfig: _srcConfig,
                _dstConfig: _dstConfig,
                _lib: _srcConfig.receiveLib302,
                _oft: oft
            });
        }
    }

    function setConfig(
        L0Config memory _srcConfig,
        L0Config memory _dstConfig,
        address _lib,
        address _oft
    ) public {
        // get the current DVN stack for the given oft and library
        bytes memory currentUlnConfigBytes = IMessageLibManager(_srcConfig.endpoint).getConfig({
            _oapp: _oft,
            _lib: _lib,
            _eid: uint32(_dstConfig.eid),
            _configType: Constant.CONFIG_TYPE_ULN
        });
        UlnConfig memory currentUlnConfig = abi.decode(currentUlnConfigBytes, (UlnConfig));

        // generate the DVN stack as defined in the config
        address[] memory desiredDVNs = craftDvnStack({
            _srcChainId: _srcConfig.chainid,
            _dstChainId: _dstConfig.chainid
        });

        // Determine if we are working with a different array of DVNs than what is currently configured
        // Do nothing if the stack is the same as before
        if (arraysAreEqual(currentUlnConfig.requiredDVNs, desiredDVNs)) return;

        // generate the config
        UlnConfig memory desiredUlnConfig;
        desiredUlnConfig.requiredDVNCount = uint8(desiredDVNs.length);
        desiredUlnConfig.requiredDVNs = desiredDVNs;

        SetConfigParam[] memory setConfigParamArray = new SetConfigParam[](1);
        setConfigParamArray[0] = SetConfigParam({
            eid: uint32(_dstConfig.eid),
            configType: Constant.CONFIG_TYPE_ULN,
            config: abi.encode(desiredUlnConfig)
        });

        // generate data and call
        bytes memory data = abi.encodeCall(
            IMessageLibManager.setConfig,
            (
                _oft,
                _lib,
                setConfigParamArray
            )
        );
        (bool success, ) = _srcConfig.endpoint.call(data);
        require(success, "Unable to setConfig");
        serializedTxs.push(
            SerializedTx({
                name: "setConfig",
                to: _srcConfig.endpoint,
                value: 0,
                data: data
            })
        );
    }

    function arraysAreEqual(address[] memory _dvnStackA, address[] memory _dvnStackB) public pure returns (bool) {
        if (_dvnStackA.length != _dvnStackB.length) {
            return false;
        } else {
            for (uint256 i=0; i<_dvnStackA.length; i++) {
                if (_dvnStackA[i] != _dvnStackB[i]) {
                    return false;
                }
            }
        }
        return true;
    }

    // Returns the ascending-sorted DVN stack of the connected chain 
    function craftDvnStack(
        uint256 _srcChainId,
        uint256 _dstChainId
    ) public returns (address[] memory desiredDVNs) {
        DvnStack memory srcDVNs = getDvnStack({
            _srcChainId: _srcChainId,
            _dstChainId: _dstChainId
        });
        DvnStack memory dstDVNs = getDvnStack({
            _srcChainId: _dstChainId,
            _dstChainId: _srcChainId
        });

        // start with a fresh array
        delete dvnStackTemp;

        // populate the temporary dvn stack array
        if (srcDVNs.horizen != address(0) || dstDVNs.horizen != address(0)) {
            require(
                srcDVNs.horizen != address(0) && dstDVNs.horizen != address(0),
                incorrectDvnMatchMsg("horizen", _srcChainId, _dstChainId)
            );
            dvnStackTemp.push(srcDVNs.horizen);
        }

        if (srcDVNs.lz != address(0) || dstDVNs.lz != address(0)) {
            require(
                srcDVNs.lz != address(0) && dstDVNs.lz != address(0),
                incorrectDvnMatchMsg("lz", _srcChainId, _dstChainId)
            );
            dvnStackTemp.push(srcDVNs.lz);
        }

        if (srcDVNs.nethermind != address(0) || dstDVNs.nethermind != address(0)) {
            require(
                srcDVNs.nethermind != address(0) && dstDVNs.nethermind != address(0),
                incorrectDvnMatchMsg("nethermind", _srcChainId, _dstChainId)
            );
            dvnStackTemp.push(srcDVNs.nethermind);
        }

        // populate the output array and sort ascending
        desiredDVNs = new address[](dvnStackTemp.length);
        for (uint256 i=0; i<dvnStackTemp.length; i++) {
            desiredDVNs[i] = dvnStackTemp[i];
        }
        desiredDVNs = Arrays.sort(desiredDVNs);
    }

    function incorrectDvnMatchMsg(string memory dvnName, uint256 chainId1, uint256 chainId2) public pure returns (string memory) {
        string memory message = string.concat("DVN Stack misconfigured: ", chainId1.toString());
        message = string.concat(message, " <> ");
        message = string.concat(message, chainId2.toString());
        message = string.concat(message, " - ");
        message = string.concat(message, dvnName);
        return message;
    }

    function getDvnStack(uint256 _srcChainId, uint256 _dstChainId) public virtual view returns (DvnStack memory dvnStack) {
        // craft path
        string memory root = vm.projectRoot();
        root = string.concat(root, "/config/dvn/");
        string memory name = string.concat(_srcChainId.toString(), ".json");
        string memory path = string.concat(root, name);
        
        // load json
        string memory jsonFile = vm.readFile(path);

        // NOTE: a missing key will cause this decoding to revert
        string memory key = string.concat(".", _dstChainId.toString());
        dvnStack = abi.decode(jsonFile.parseRaw(key), (DvnStack));
    }

}