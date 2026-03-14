// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { IStablecoinDEX } from "tempo-std/interfaces/IStablecoinDEX.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";

/// @notice Read-only script to check frxUSD state, DEX liquidity, and balances
/// @dev Run with:
/// forge script scripts/SepoliaHub/3_SetupDestinationFraxOFTSepoliaHub/CheckFrxUsdState.s.sol --rpc-url https://rpc.moderato.tempo.xyz
contract CheckFrxUsdState is Script {
    // frxUSD TIP20
    address internal constant FRXUSD = 0x20c000000000000000000000cf5b0F48F7fEDC7F;
    
    // frxUSD OFT adapter on Tempo testnet
    address internal constant OFT_ADAPTER = 0x16FBfCF4970D4550791faF75AE9BaecE75C85A27;

    function run() external view {
        address sender = 0x1d434906Aa520E592fAB2b82406BEfF859be8e82;
        
        console.log("=== TOKEN ADDRESSES ===");
        console.log("frxUSD TIP20:", FRXUSD);
        console.log("PATH_USD:", StdTokens.PATH_USD_ADDRESS);
        console.log("OFT Adapter:", OFT_ADAPTER);
        
        console.log("");
        console.log("=== frxUSD TOKEN INFO ===");
        ITIP20 frxUsd = ITIP20(FRXUSD);
        console.log("Name:", frxUsd.name());
        console.log("Symbol:", frxUsd.symbol());
        console.log("Decimals:", frxUsd.decimals());
        console.log("Quote Token:", address(frxUsd.quoteToken()));
        console.log("Currency:", frxUsd.currency());
        
        console.log("");
        console.log("=== BALANCES FOR SENDER ===");
        console.log("Sender:", sender);
        console.log("frxUSD balance:", frxUsd.balanceOf(sender));
        console.log("PATH_USD balance:", ITIP20(StdTokens.PATH_USD_ADDRESS).balanceOf(sender));
        
        console.log("");
        console.log("=== OFT ADAPTER BALANCES ===");
        console.log("frxUSD balance:", frxUsd.balanceOf(OFT_ADAPTER));
        console.log("PATH_USD balance:", ITIP20(StdTokens.PATH_USD_ADDRESS).balanceOf(OFT_ADAPTER));
        
        console.log("");
        console.log("=== DEX STATE ===");
        IStablecoinDEX dex = StdPrecompiles.STABLECOIN_DEX;
        console.log("DEX address:", address(dex));
        
        bytes32 pairKey = dex.pairKey(FRXUSD, StdTokens.PATH_USD_ADDRESS);
        console.log("Pair key:", vm.toString(pairKey));
        
        (address base, address quote, int16 bestBid, int16 bestAsk) = dex.books(pairKey);
        console.log("");
        console.log("=== ORDERBOOK ===");
        console.log("Base token:", base);
        console.log("Quote token:", quote);
        console.log("Best bid tick:");
        console.logInt(int256(bestBid));
        console.log("Best ask tick:");
        console.logInt(int256(bestAsk));
        
        if (base != address(0)) {
            console.log("");
            console.log("=== LIQUIDITY AT TICK 0 ===");
            
            // Check tick 0 bids
            (uint128 head0, uint128 tail0, uint128 liq0) = dex.getTickLevel(FRXUSD, 0, true);
            console.log("Tick 0 BID - head:", head0);
            console.log("Tick 0 BID - tail:", tail0);
            console.log("Tick 0 BID - liquidity:", liq0);
            
            // Check tick 0 asks
            (uint128 head0a, uint128 tail0a, uint128 liq0a) = dex.getTickLevel(FRXUSD, 0, false);
            console.log("Tick 0 ASK - head:", head0a);
            console.log("Tick 0 ASK - tail:", tail0a);
            console.log("Tick 0 ASK - liquidity:", liq0a);
        } else {
            console.log("");
            console.log("!!! PAIR DOES NOT EXIST - needs to be created !!!");
        }
    }
}
