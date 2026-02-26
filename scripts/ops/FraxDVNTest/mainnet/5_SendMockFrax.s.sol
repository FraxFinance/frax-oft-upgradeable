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

// fraxtal : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.frax.com --broadcast
// ethereum : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://ethereum-rpc.publicnode.com --broadcast
// blast : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.blast.io --broadcast
// base : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.base.org --broadcast
// mode : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.mode.network/ --broadcast
// sei : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://evm-rpc.sei-apis.com --broadcast
// xlayer : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.xlayer-rpc.com --legacy --broadcast
// sonic : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.soniclabs.com/ --broadcast
// ink : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc-gel.inkonchain.com --broadcast
// arbitrum : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://arb1.arbitrum.io/rpc --broadcast
// op : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://optimism-mainnet.public.blastapi.io --broadcast
// polygon : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://polygon-rpc.com --broadcast
// avalanche : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://api.avax.network/ext/bc/C/rpc --broadcast
// bnb : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://neat-lingering-orb.bsc.quiknode.pro/a9e1547db6f8261bf94f92603eec0cc3d0c66605 --broadcast
// zkpolygon : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://zkevm-rpc.com --broadcast
// berachain : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.berachain.com --broadcast
// linea : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.linea.build --broadcast --evm-version paris
// worldchain : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://worldchain-mainnet.g.alchemy.com/public --broadcast
// zksync era : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.era.zksync.io --zksync // Note: this was performed directly on etherscan
// abstract : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://api.mainnet.abs.xyz --zksync  // Note: this was performed directly on etherscan
// unichain : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.unichain.org --broadcast
// plumephoenix : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.plume.org --broadcast
// katana : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.katana.network --broadcast
// aurora : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.aurora.dev --legacy --broadcast
// scroll : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.scroll.io --broadcast
// hyperliquid : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast --slow
// tempo : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.tempo.org --gas-estimate-multiplier 100 --broadcast

contract SendMockFrax is BaseL0Script {
    // 1,81457,8453,34443,1329,252,196,146,57073,42161,10,137,43114,56,1101,80094,480,130,
    // 98866,747474,534352,999,143,988,4217
    address public constant mockFrax = 0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8;
    address public constant mockFraxWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
    // 324, zksync, 30165
    address public constant mockFraxZkSync = 0x3Fc877008e396FdD7f9Ee3Deb2e8A54d54da705A;
    address public constant mockFraxZkSyncWallet = 0x0065435a2FcC4D4D5CD2c284C5daA9588E6fe03d;
    // 2741, abstract, 30324
    address public constant mockFraxAbstract = 0xBd39033994F5324Fe8D50bB524396A78ff9dFe22;
    address public constant mockFraxAbstractWallet = 0x72018C396221e5919c856a809E3Be54CbfDb1fa2;
    // 59144,linea, 30183
    address public constant mockFraxLinea = 0x6185334f1542a9966CbaD694577fFbede3DD1f1F;
    address public constant mockFraxLineaWallet = 0xD555D90A6b23B285575cd6192D972e35F70b5B89;
    // 1313161554, aurora, 30211
    address public constant mockFraxAurora = 0xA057D8D4Fc86a62801CE363C169b0A8d192F6cEE;
    address public constant mockFraxAuroraWallet = 0x4a767e2ef83577225522Ef8Ed71056c6E3acB216;

    uint256 amount = 25; // 0.25 tokens, scaled by decimals in _amount() function

    // mockfrxUSD TIP20 : 0x20C000000000000000000000CFD2e14f4Cdf1380
    address gasToken = 0x20C000000000000000000000CFD2e14f4Cdf1380; // StdTokens.PATH_USD_ADDRESS; // Tempo's TIP20 gas token, used when broadcasting to Tempo

    SendParam[] public sendParams;
    IOFT[] public ofts;
    address[] public destinations;

    /// @dev Returns 0.25 tokens scaled to the OFT's decimals
    function _amount(address _oft) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_oft).decimals();
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
                if (allConfigs[_i].chainid == 59144) {
                    // linea
                    sourceOFT = mockFraxLinea;
                    senderWallet = mockFraxLineaWallet;
                } else if (allConfigs[_i].chainid == 2741) {
                    // abstract
                    sourceOFT = mockFraxAbstract;
                    senderWallet = mockFraxAbstractWallet;
                } else if (allConfigs[_i].chainid == 324) {
                    // zksync
                    sourceOFT = mockFraxZkSync;
                    senderWallet = mockFraxZkSyncWallet;
                } else if (allConfigs[_i].chainid == 1313161554) {
                    // aurora
                    sourceOFT = mockFraxAurora;
                    senderWallet = mockFraxAuroraWallet;
                } else {
                    // 1,81457,8453,34443,1329,252,196,146,57073,42161,10,137,43114,56,1101,80094,480,130,98866,
                    // 747474,534352,999,143,988,4217
                    sourceOFT = mockFrax;
                    senderWallet = mockFraxWallet;
                }
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
            } else if (allConfigs[_i].chainid == 59144) {
                // linea
                recipientWallet = addressToBytes32(mockFraxLineaWallet);
            } else if (allConfigs[_i].chainid == 2741) {
                // abstract
                recipientWallet = addressToBytes32(mockFraxAbstractWallet);
            } else if (allConfigs[_i].chainid == 324) {
                // zksync
                recipientWallet = addressToBytes32(mockFraxZkSyncWallet);
            } else if (allConfigs[_i].chainid == 1313161554) {
                // aurora
                recipientWallet = addressToBytes32(mockFraxAuroraWallet);
            } else {
                // 1,81457,8453,34443,1329,252,196,146,57073,42161,10,137,43114,56,1101,80094,480,130,98866,747474,
                // 534352,999,143,988,4217
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
