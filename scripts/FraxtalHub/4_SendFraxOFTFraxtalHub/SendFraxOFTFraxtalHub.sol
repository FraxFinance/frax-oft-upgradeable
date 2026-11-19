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
        // Destination-side checks are best-effort: forge >= 1.9 cannot fork across EVM types (e.g. a Monad
        // source cannot fork the OP-stack Fraxtal hub and vice versa). run() still requires the source-side
        // peer for every token it sends.
        try vm.createSelectFork(_destinationRpc) returns (uint256) {
            if (dstEid != 30255) {
                _validateAddrs();
            }
            for (uint256 i; i < NUM_OFTS; i++) {
                Token token = Token(i);
                if (!_sendsToken(token)) continue;
                require(
                    OFTUpgradeable(_dstOft(token)).isPeer(uint32(srcEid), addressToBytes32(_srcOft(token))),
                    string.concat("OFT is not wired to source, Token slot ", vm.toString(i))
                );
            }
            vm.createSelectFork(_sourceRpc);
        } catch {
            console.log("Skipping destination-side peer checks: cannot fork the destination from this chain's EVM");
        }
    }

    function run() public virtual override broadcastAs(configDeployerPK) {
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

        SendParam memory _frxUsdSendParam = _getsendParamsForfrxUSD(_sendParam);

        // One entry per active token this chain has, in Token slot order. frxUSD is matched by token
        // (not by position) so retiring any slot cannot misplace its scaled send params.
        for (uint256 i; i < NUM_OFTS; i++) {
            Token token = Token(i);
            if (!_sendsToken(token)) continue;
            address srcOft = _srcOft(token);
            require(
                OFTUpgradeable(srcOft).isPeer(uint32(dstEid), addressToBytes32(_dstOft(token))),
                string.concat("OFT is not wired to destination, Token slot ", vm.toString(i))
            );
            SendParam memory sendParam_ = token == Token.FRXUSD ? _frxUsdSendParam : _sendParam;
            sendParams.push(sendParam_);
            ofts.push(IOFT(srcOft));
            refundAddresses.push(senderWallet);
            _totalEthFee += IOFT(srcOft).quoteSend(sendParam_, false).nativeFee;
        }

        _executeBatchBridge(_totalEthFee);
    }

    /// @dev Bridge a token only if this chain has it AND it is still active in the mesh
    ///      (L0Constants.activeTokens). Chains keep the addresses of tokens they deployed
    ///      (e.g. FPI on Monad/Stable/Tempo), but retired tokens have no peers, so sending
    ///      one would revert the whole batch.
    function _sendsToken(Token _token) internal view returns (bool) {
        if (!_managesToken(_token)) return false;
        for (uint256 i; i < activeTokens.length; i++) {
            if (activeTokens[i] == _token) return true;
        }
        return false;
    }

    function _srcOft(Token _token) internal view returns (address) {
        if (_token == Token.WFRAX) return srcFraxOft;
        if (_token == Token.SFRXUSD) return srcsfrxusdOft;
        if (_token == Token.SFRXETH) return srcsfrxethOft;
        if (_token == Token.FRXUSD) return srcfrxusdOft;
        if (_token == Token.FRXETH) return srcfrxethOft;
        return srcfpiOft;
    }

    function _dstOft(Token _token) internal view returns (address) {
        if (_token == Token.WFRAX) return dstFraxOft;
        if (_token == Token.SFRXUSD) return dstsfrxusdOft;
        if (_token == Token.SFRXETH) return dstsfrxethOft;
        if (_token == Token.FRXUSD) return dstfrxusdOft;
        if (_token == Token.FRXETH) return dstfrxethOft;
        return dstfpiOft;
    }

    function _getsendParamsForfrxUSD(SendParam memory _sendParam) internal view virtual returns (SendParam memory) {
        return _sendParam;
    }

    /// @dev Override to change the batch bridge execution (e.g. TIP20 gas payment on Tempo).
    function _executeBatchBridge(uint256 _totalFee) internal virtual {
        FraxOFTWalletUpgradeable(senderWallet).batchBridgeWithEthFeeFromWallet{ value: _totalFee }(
            sendParams,
            ofts,
            refundAddresses
        );
    }

    function _validateAddrs() internal view virtual {
        require(isStringEqual(IERC20Metadata(IOFT(frxUsdOft).token()).symbol(), "frxUSD"), "frxUsdOft != frxUSD");
        require(isStringEqual(IERC20Metadata(IOFT(sfrxUsdOft).token()).symbol(), "sfrxUSD"), "sfrxUsdOft != sfrxUSD");
        require(isStringEqual(IERC20Metadata(IOFT(frxEthOft).token()).symbol(), "frxETH"), "frxEthOft != frxETH");
        require(isStringEqual(IERC20Metadata(IOFT(sfrxEthOft).token()).symbol(), "sfrxETH"), "sfrxEthOft != sfrxETH");
        require(isStringEqual(IERC20Metadata(IOFT(wfraxOft).token()).symbol(), "WFRAX"), "wFraxOft != WFRAX");
        // FPI is retired: validate only if it is ever active again for a chain that sets it
        if (_sendsToken(Token.FPI)) {
            require(isStringEqual(IERC20Metadata(IOFT(fpiOft).token()).symbol(), "FPI"), "fpiOft != FPI");
        }
    }
}
