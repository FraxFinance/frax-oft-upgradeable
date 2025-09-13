// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/BaseL0Script.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";
import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { OFTUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract SendFraxOFTFraxtalHub is DeployFraxOFTProtocol {
    SendParam[] public sendParams;
    IOFT[] public ofts;
    address[] public refundAddresses;
    uint256 amount;
    address senderWallet;
    address recipientWallet;
    uint256 dstEid;
    uint256 srcEid;

    address dstFraxOft;
    address dstsfrxusdOft;
    address dstsfrxethOft;
    address dstfrxusdOft;
    address dstfrxethOft;
    address dstfpiOft;

    address srcFraxOft;
    address srcsfrxusdOft;
    address srcsfrxethOft;
    address srcfrxusdOft;
    address srcfrxethOft;
    address srcfpiOft;

    string _destinationRpc;
    string _sourceRpc;

    function setUp() public override {
        require(srcEid != 0, "srcEid is not set");
        require(dstEid != 0, "dstEid is not set");
        super.setUp();
        for (uint256 i; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].eid == dstEid) {
                _destinationRpc = proxyConfigs[i].RPC;
            }
            if (proxyConfigs[i].chainid == block.chainid) {
                _sourceRpc = proxyConfigs[i].RPC;
            }
        }
        if (dstEid != 30255) {
            dstFraxOft = wfraxOft;
            dstsfrxusdOft = sfrxUsdOft;
            dstsfrxethOft = sfrxEthOft;
            dstfrxusdOft = frxUsdOft;
            dstfrxethOft = frxEthOft;
            dstfpiOft = fpiOft;

            srcFraxOft = fraxtalFraxLockbox;
            srcsfrxusdOft = fraxtalSFrxUsdLockbox;
            srcsfrxethOft = fraxtalSFrxEthLockbox;
            srcfrxusdOft = fraxtalFrxUsdLockbox;
            srcfrxethOft = fraxtalFrxEthLockbox;
            srcfpiOft = fraxtalFpiLockbox;
        } else {
            dstFraxOft = fraxtalFraxLockbox;
            dstsfrxusdOft = fraxtalSFrxUsdLockbox;
            dstsfrxethOft = fraxtalSFrxEthLockbox;
            dstfrxusdOft = fraxtalFrxUsdLockbox;
            dstfrxethOft = fraxtalFrxEthLockbox;
            dstfpiOft = fraxtalFpiLockbox;

            srcFraxOft = wfraxOft;
            srcsfrxusdOft = sfrxUsdOft;
            srcsfrxethOft = sfrxEthOft;
            srcfrxusdOft = frxUsdOft;
            srcfrxethOft = frxEthOft;
            srcfpiOft = fpiOft;
        }
        vm.createSelectFork(_destinationRpc);
        if (dstEid != 30255) {
            _validateAddrs();
        }
        require(
            OFTUpgradeable(dstFraxOft).isPeer(uint32(srcEid), addressToBytes32(srcFraxOft)),
            "wfraxOft is not wired to source"
        );
        require(
            OFTUpgradeable(dstsfrxusdOft).isPeer(uint32(srcEid), addressToBytes32(srcsfrxusdOft)),
            "sfrxusdoft is not wired to source"
        );
        require(
            OFTUpgradeable(dstsfrxethOft).isPeer(uint32(srcEid), addressToBytes32(srcsfrxethOft)),
            "sfrxethoft is not wired to source"
        );
        require(
            OFTUpgradeable(dstfrxusdOft).isPeer(uint32(srcEid), addressToBytes32(srcfrxusdOft)),
            "frxusdoft is not wired to source"
        );
        require(
            OFTUpgradeable(dstfrxethOft).isPeer(uint32(srcEid), addressToBytes32(srcfrxethOft)),
            "frxethoft is not wired to source"
        );
        require(
            OFTUpgradeable(dstfpiOft).isPeer(uint32(srcEid), addressToBytes32(srcfpiOft)),
            "fpi is not wired to source"
        );
        vm.createSelectFork(_sourceRpc);
    }

    function run() public override broadcastAs(configDeployerPK) {
        require(
            OFTUpgradeable(srcFraxOft).isPeer(uint32(dstEid), addressToBytes32(dstFraxOft)),
            "wfrax is not wired to destination"
        );
        require(
            OFTUpgradeable(srcsfrxusdOft).isPeer(uint32(dstEid), addressToBytes32(dstsfrxusdOft)),
            "sfrxusd is not wired to destination"
        );
        require(
            OFTUpgradeable(srcsfrxethOft).isPeer(uint32(dstEid), addressToBytes32(dstsfrxethOft)),
            "sfrxeth is not wired to destination"
        );
        require(
            OFTUpgradeable(srcfrxusdOft).isPeer(uint32(dstEid), addressToBytes32(dstfrxusdOft)),
            "frxusd is not wired to destination"
        );
        require(
            OFTUpgradeable(srcfrxethOft).isPeer(uint32(dstEid), addressToBytes32(dstfrxethOft)),
            "frxeth is not wired to destination"
        );
        require(
            OFTUpgradeable(srcfpiOft).isPeer(uint32(dstEid), addressToBytes32(dstfpiOft)),
            "fpi is not wired to destination"
        );

        uint256 _totalEthFee;
        SendParam memory _sendParam = SendParam({
            dstEid: uint32(dstEid),
            to: addressToBytes32(recipientWallet),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        simulateConfig.chainid = block.chainid;
        _validateAndPopulateMainnetOfts();

        for (uint256 i; i < proxyOfts.length; i++) {
            sendParams.push(_sendParam);
            refundAddresses.push(senderWallet);
        }

        ofts.push(IOFT(srcFraxOft));
        MessagingFee memory _fee = IOFT(srcFraxOft).quoteSend(_sendParam, false);
        _totalEthFee += _fee.nativeFee;
        ofts.push(IOFT(srcsfrxusdOft));
        _fee = IOFT(srcsfrxusdOft).quoteSend(_sendParam, false);
        _totalEthFee += _fee.nativeFee;
        ofts.push(IOFT(srcsfrxethOft));
        _fee = IOFT(srcsfrxethOft).quoteSend(_sendParam, false);
        _totalEthFee += _fee.nativeFee;
        ofts.push(IOFT(srcfrxusdOft));
        _fee = IOFT(srcfrxusdOft).quoteSend(_sendParam, false);
        _totalEthFee += _fee.nativeFee;
        ofts.push(IOFT(srcfrxethOft));
        _fee = IOFT(srcfrxethOft).quoteSend(_sendParam, false);
        _totalEthFee += _fee.nativeFee;
        ofts.push(IOFT(srcfpiOft));
        _fee = IOFT(srcfpiOft).quoteSend(_sendParam, false);
        _totalEthFee += _fee.nativeFee;

        FraxOFTWalletUpgradeable(senderWallet).batchBridgeWithEthFeeFromWallet{ value: _totalEthFee }(
            sendParams,
            ofts,
            refundAddresses
        );
    }

    function _validateAddrs() internal view {
        require(isStringEqual(IERC20Metadata(frxUsdOft).symbol(), "frxUSD"), "frxUsdOft != frxUSD");
        require(isStringEqual(IERC20Metadata(sfrxUsdOft).symbol(), "sfrxUSD"), "sfrxUsdOft != sfrxUSD");
        require(isStringEqual(IERC20Metadata(frxEthOft).symbol(), "frxETH"), "frxEthOft != frxETH");
        require(isStringEqual(IERC20Metadata(sfrxEthOft).symbol(), "sfrxETH"), "sfrxEthOft != sfrxETH");
        require(isStringEqual(IERC20Metadata(wfraxOft).symbol(), "WFRAX"), "wFraxOft != WFRAX");
        require(isStringEqual(IERC20Metadata(fpiOft).symbol(), "FPI"), "fpiOft != FPI");
    }
}
