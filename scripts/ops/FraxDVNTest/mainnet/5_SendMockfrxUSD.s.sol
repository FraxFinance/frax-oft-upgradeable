// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/BaseL0Script.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";
import { FraxOFTWalletUpgradeableTempo } from "contracts/FraxOFTWalletUpgradeableTempo.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { ITIP20 } from "@tempo/interfaces/ITIP20.sol";

// fraxtal : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockfrxUSD.s.sol --rpc-url https://rpc.frax.com --broadcast
// tempo : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockfrxUSD.s.sol --rpc-url https://mainnet.tempo.org --gas-estimate-multiplier 100 --broadcast

contract SendMockFrax is BaseL0Script {
    // 252,4217
    address public constant mockfrxUSD = 0x458edF815687e48354909A1a848f2528e1655764;
    address public constant mockFraxWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;

    uint256 amount = 25; // 0.25 tokens, scaled by decimals in _amount() function

    // mockfrxUSD TIP20 : 0x20C000000000000000000000CFD2e14f4Cdf1380
    address gasToken = 0x20C000000000000000000000CFD2e14f4Cdf1380; // StdTokens.PATH_USD_ADDRESS; // Tempo's TIP20 gas token, used when broadcasting to Tempo

    SendParam[] public sendParams;
    IOFT[] public ofts;
    address[] public destinations;

    /// @dev Returns 0.25 tokens scaled to the OFT's decimals.
    ///      Uses IOFT.token() which returns the underlying ERC20 for adapters, or address(this) for pure OFTs.
    function _amount(address _oft) internal view returns (uint256) {
        address underlying = IOFT(_oft).token();
        uint8 decimals = IERC20Metadata(underlying).decimals();
        return (amount * (10 ** decimals)) / 100;
    }

    function run() public broadcastAs(configDeployerPK) {
        uint256 _totalEthFee;
        address sourceOFT;
        address senderWallet;
        uint256 start = 0;
        uint256 end = allConfigs.length;
        for (uint256 _i; _i < allConfigs.length; _i++) {
            if (allConfigs[_i].eid == 30151) continue;
            if (allConfigs[_i].eid == 30376) continue;
            if (broadcastConfig.eid == 30370) {
                // if broadcast config is plumephoenix,
                // skip x-layer (30274), polygon zkevm (30158), worldchain (30319), zksync (30165), movement (30325)
                // and aptos (30108)
                if (
                    allConfigs[_i].eid == 30274 ||
                    allConfigs[_i].eid == 30158 ||
                    allConfigs[_i].eid == 30319 ||
                    allConfigs[_i].eid == 30165 ||
                    allConfigs[_i].eid == 30325 ||
                    allConfigs[_i].eid == 30108
                ) continue;
            }
            if (broadcastConfig.eid == 30375) {
                // L0 team has not setup defaultSendLibrary and defaultReceiveLibrary on katana for
                // unichain (30320), plumephoenix, (30370), movement (30325) and aptos (30108)
                if (
                    allConfigs[_i].eid == 30320 ||
                    allConfigs[_i].eid == 30370 ||
                    allConfigs[_i].eid == 30325 ||
                    allConfigs[_i].eid == 30108
                ) continue;
            }
            if (broadcastConfig.eid == 30211) {
                // L0 team has not setup defaultSendLibrary and defaultReceiveLibrary on aurora for
                // aptos (30108)
                if (allConfigs[_i].eid == 30108) continue;
            }
            if (broadcastConfig.eid == 30410) {
                // L0 team has not setup defaultSendLibrary and defaultReceiveLibrary on tempo for
                // Solana (30168), Movement (30325), Aptos (30108), Blast (30243)
                if (
                    allConfigs[_i].eid == 30168 ||
                    allConfigs[_i].eid == 30325 ||
                    allConfigs[_i].eid == 30108 ||
                    allConfigs[_i].eid == 30243
                ) continue;
            }
            if (broadcastConfig.chainid == allConfigs[_i].chainid) {
                // 252,4217
                sourceOFT = mockfrxUSD;
                senderWallet = mockFraxWallet;
                break;
            }
        }

        require(sourceOFT != address(0), "SendMockFrax: sourceOFT should not be zero");
        require(senderWallet != address(0), "SendMockFrax: senderWallet should not be zero");
        for (uint256 _i = start; _i < end; _i++) {
            if (broadcastConfig.chainid == allConfigs[_i].chainid) continue;
            if (allConfigs[_i].eid == 30151) continue;
            if (allConfigs[_i].eid == 30376) continue;
            if (broadcastConfig.eid == 30370) {
                // if broadcast config is plumephoenix,
                // skip x-layer (30274), polygon zkevm (30158), worldchain (30319), zksync (30165), movement (30325)
                // and aptos (30108)
                if (
                    allConfigs[_i].eid == 30274 ||
                    allConfigs[_i].eid == 30158 ||
                    allConfigs[_i].eid == 30319 ||
                    allConfigs[_i].eid == 30165 ||
                    allConfigs[_i].eid == 30325 ||
                    allConfigs[_i].eid == 30108
                ) continue;
            }
            if (broadcastConfig.eid == 30375) {
                // L0 team has not setup defaultSendLibrary and defaultReceiveLibrary on katana for
                // unichain (30320), plumephoenix, (30370), movement (30325) and aptos (30108)
                // // TODO : temporary block sending to ethereum
                // if (allConfigs[_i].eid == 30101) continue;
                if (
                    allConfigs[_i].eid == 30320 ||
                    allConfigs[_i].eid == 30370 ||
                    allConfigs[_i].eid == 30325 ||
                    allConfigs[_i].eid == 30108
                ) continue;
            }
            if (broadcastConfig.eid == 30211) {
                // L0 team has not setup defaultSendLibrary and defaultReceiveLibrary on aurora for
                // Aptos (30108)
                if (allConfigs[_i].eid == 30108) continue;
            }
            if (broadcastConfig.eid == 30367) {
                // L0 team has not setup defaultSendLibrary and defaultReceiveLibrary on hyperliquid for
                // Botanix (botanixlabs)
                if (allConfigs[_i].eid == 30376) continue;
            }
            if (broadcastConfig.eid == 30410) {
                // L0 team has not setup defaultSendLibrary and defaultReceiveLibrary on tempo for
                // Solana (30168), Movement (30325), Aptos (30108), Blast (30243)
                if (
                    allConfigs[_i].eid == 30168 ||
                    allConfigs[_i].eid == 30325 ||
                    allConfigs[_i].eid == 30108 ||
                    allConfigs[_i].eid == 30243
                ) continue;
                StdPrecompiles.TIP_FEE_MANAGER.setUserToken(gasToken);
            }
            bytes32 recipientWallet;
            if (allConfigs[_i].eid == 30168) {
                // solana
                recipientWallet = 0x3c1b094729102e0c095ee2417e5940ee4f1eab4763f6113fe75281ab74c62398;
            } else if (allConfigs[_i].eid == 30325) {
                // movement
                // do no include xlayer(196), sei(1329), worldchain(480) and unichain(130)
                if (
                    broadcastConfig.chainid == 196 ||
                    broadcastConfig.chainid == 1329 ||
                    broadcastConfig.chainid == 480 ||
                    broadcastConfig.chainid == 130
                ) continue;
                recipientWallet = 0x09d0eb2763c96e085fa74ba6cf0d49136f8654c48ec7dbc59279a9066c7dd409;
            } else if (allConfigs[_i].eid == 30108) {
                // aptos
                // do no include zkpolygon(1101), worldchain(480), abstract(2741), ink(57073) and aurora(1313161554)
                if (
                    broadcastConfig.chainid == 1101 ||
                    broadcastConfig.chainid == 480 ||
                    broadcastConfig.chainid == 2741 ||
                    broadcastConfig.chainid == 57073 ||
                    broadcastConfig.chainid == 1313161554
                ) continue;
                recipientWallet = 0x09d0eb2763c96e085fa74ba6cf0d49136f8654c48ec7dbc59279a9066c7dd409;
            } else {
                // 252,4217
                recipientWallet = addressToBytes32(mockFraxWallet);
            }
            SendParam memory _sendParam = SendParam({
                dstEid: uint32(allConfigs[_i].eid),
                to: recipientWallet,
                amountLD: _amount(sourceOFT),
                minAmountLD: 0,
                extraOptions: "",
                composeMsg: "",
                oftCmd: ""
            });
            sendParams.push(_sendParam);
            MessagingFee memory _fee = IOFT(sourceOFT).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            ofts.push(IOFT(sourceOFT));
            destinations.push(senderWallet);
        }
        if (broadcastConfig.eid == 30410) {
            // Tempo: set gas token, approve wallet to pull TIP20 gas token, then bridge
            ITIP20(gasToken).approve(senderWallet, _totalEthFee);
            FraxOFTWalletUpgradeableTempo(senderWallet).batchBridgeWithTIP20FeeFromWallet(
                sendParams,
                ofts,
                destinations
            );
        } else {
            // All other chains: pays ETH
            FraxOFTWalletUpgradeable(senderWallet).batchBridgeWithEthFeeFromWallet{ value: _totalEthFee }(
                sendParams,
                ofts,
                destinations
            );
        }
    }
}
