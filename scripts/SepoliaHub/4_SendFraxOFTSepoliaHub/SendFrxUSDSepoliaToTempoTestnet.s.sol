// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOFT, SendParam, MessagingFee } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";

/// @title SendFrxUSDSepoliaToTempoTestnet
/// @notice Sends frxUSD cross-chain from Ethereum Sepolia to Tempo testnet (Moderato) via LayerZero OFT
/// @dev Usage:
/// forge script scripts/SepoliaHub/4_SendFraxOFTSepoliaHub/SendFrxUSDSepoliaToTempoTestnet.s.sol --rpc-url https://ethereum-sepolia.gateway.tatum.io --broadcast
contract SendFrxUSDSepoliaToTempoTestnet is Script {
    using OptionsBuilder for bytes;

    uint256 public configDeployerPK = vm.envUint("PK_CONFIG_DEPLOYER");

    // frxUSD token on Sepolia
    address internal constant FRXUSD_TOKEN = 0xcA35C3FE456a87E6CE7827D1D784741613463204;

    // frxUSD OFT lockbox adapter on Sepolia
    address internal constant FRXUSD_LOCKBOX = 0x29a5134D3B22F47AD52e0A22A63247363e9F35c2;

    // Tempo testnet (Moderato) EID
    uint32 internal constant DST_EID = 40444;

    // Amount to send (1 frxUSD with 18 decimals)
    uint256 internal constant AMOUNT = 1e18;

    function run() external {
        vm.startBroadcast(configDeployerPK);

        address sender = vm.addr(configDeployerPK);
        address receiver = 0x1d434906Aa520E592fAB2b82406BEfF859be8e82;

        // Check balance
        uint256 balance = IERC20(FRXUSD_TOKEN).balanceOf(sender);
        require(balance >= AMOUNT, "Insufficient frxUSD balance");

        // 1. Approve the lockbox to spend frxUSD tokens
        uint256 allowance = IERC20(FRXUSD_TOKEN).allowance(sender, FRXUSD_LOCKBOX);
        if (allowance < AMOUNT) {
            IERC20(FRXUSD_TOKEN).approve(FRXUSD_LOCKBOX, type(uint256).max);
        }

        // 2. Build SendParam for cross-chain transfer
        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
            dstEid: DST_EID,
            to: bytes32(uint256(uint160(receiver))), // Send to receiver on destination
            amountLD: AMOUNT,
            minAmountLD: AMOUNT, // No slippage tolerance
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // 3. Quote the fee
        MessagingFee memory fee = IOFT(FRXUSD_LOCKBOX).quoteSend(sendParam, false);

        console.log("Sending frxUSD from Sepolia to Tempo testnet");
        console.log("Amount:", AMOUNT);
        console.log("Native fee:", fee.nativeFee);
        console.log("LZ token fee:", fee.lzTokenFee);

        // 4. Send tokens cross-chain
        IOFT(FRXUSD_LOCKBOX).send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(sender)
        );

        console.log("Transaction submitted successfully!");

        vm.stopBroadcast();
    }
}
