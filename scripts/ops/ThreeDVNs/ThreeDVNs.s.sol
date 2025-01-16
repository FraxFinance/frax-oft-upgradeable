// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import {UlnConfig} from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/uln/UlnBase.sol";

// forge script scripts/ops/ThreeDVNs/ThreeDVNs.s.sol --rpc-url https://rpc.frax.com
contract ThreeDVNs is DeployFraxOFTProtocol {

    address endpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    address oft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address lib = 0x8bC1e36F015b9902B54b1387A4d733cebc2f5A4e;
    uint32 eid = uint32(30101);
    uint32 configType = uint32(2);
    
    uint256 dstChainId = 1;
    uint256 srcChainId = 252;

    struct DvnStack {
        address[] dvns;
        string[] stack;
    }

    function run() public override {
        // get config of chain
        bytes memory config = IMessageLibManager(endpoint).getConfig({
            _oapp: oft,
            _lib: lib,
            _eid: eid,
            _configType: configType
        });

        UlnConfig memory ulnConfig = abi.decode(config, (UlnConfig));

        // console.log(requiredDVNs.length);
        console.log(ulnConfig.confirmations);
        console.log(ulnConfig.requiredDVNs.length);
        console.log(ulnConfig.optionalDVNs.length);

        address[] memory dvns = getDvnStack(srcChainId, dstChainId);
    }

    function getDvnStack(uint32 srcChainId, uint32 dstChainId) public virtual view returns (address[] memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "config/dvn/)
    }
}