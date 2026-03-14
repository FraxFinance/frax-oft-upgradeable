// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { IFeeAMM } from "tempo-std/interfaces/IFeeAMM.sol";
import { IStablecoinDEX } from "tempo-std/interfaces/IStablecoinDEX.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";

/// @notice Seeds liquidity for frxUSD on Tempo in both:
///         1. FeeAMM - enables paying transaction fees in frxUSD
///         2. StablecoinDEX - enables trading frxUSD/PATH_USD
///
/// @dev The FeeAMM and StablecoinDEX are separate systems:
///      - FeeAMM: Converts user fee tokens → PATH_USD for validators
///      - StablecoinDEX: General trading between stablecoins
///
/// Run with:
/// forge script scripts/SepoliaHub/3_SetupDestinationFraxOFTSepoliaHub/CreateFrxUsdPathLiquidity.s.sol --rpc-url https://rpc.moderato.tempo.xyz --broadcast
contract CreateFrxUsdPathLiquidity is Script {
    // frxUSD TIP20
    address internal constant FRXUSD = 0x20c000000000000000000000cf5b0F48F7fEDC7F;

    // FeeAMM: PATH_USD liquidity to enable frxUSD fee payments
    // MIN_LIQUIDITY = 1000, adding 10 PATH_USD (10e6)
    uint256 public constant FEE_AMM_LIQ = 10_000_000; // 10 PATH_USD

    // StablecoinDEX: Bid-side liquidity at tick 0 (1:1 rate)
    uint256 public constant DEX_LIQ = 100_000_000; // 100 PATH_USD

    function run() external {
        uint256 pk = vm.envUint("PK_CONFIG_DEPLOYER");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // Use PATH_USD for gas fees initially
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(StdTokens.PATH_USD_ADDRESS);

        // ============================================
        // 1. FeeAMM - Enable frxUSD as fee token
        // ============================================
        console.log("=== 1. FeeAMM Liquidity ===");

        IFeeAMM feeAmm = IFeeAMM(address(StdPrecompiles.TIP_FEE_MANAGER));

        // Check current FeeAMM pool state
        bytes32 feePoolId = feeAmm.getPoolId(FRXUSD, StdTokens.PATH_USD_ADDRESS);
        IFeeAMM.Pool memory feePoolBefore = feeAmm.getPool(FRXUSD, StdTokens.PATH_USD_ADDRESS);

        console.log("Pool ID:", vm.toString(feePoolId));
        console.log("Reserve frxUSD (before):", feePoolBefore.reserveUserToken);
        console.log("Reserve PATH_USD (before):", feePoolBefore.reserveValidatorToken);

        // Only add liquidity if pool is empty
        if (feePoolBefore.reserveValidatorToken == 0) {
            // Approve PATH_USD for the FeeAMM
            ITIP20(StdTokens.PATH_USD_ADDRESS).approve(address(feeAmm), FEE_AMM_LIQ);

            // Mint liquidity - provide PATH_USD (validator token)
            uint256 liquidity = feeAmm.mint(
                FRXUSD,                      // userToken (what users pay with)
                StdTokens.PATH_USD_ADDRESS,  // validatorToken (what validators receive)
                FEE_AMM_LIQ,                 // amount of validatorToken to add
                deployer                     // LP tokens go to deployer
            );

            IFeeAMM.Pool memory feePoolAfter = feeAmm.getPool(FRXUSD, StdTokens.PATH_USD_ADDRESS);
            console.log("Liquidity tokens received:", liquidity);
            console.log("Reserve PATH_USD (after):", feePoolAfter.reserveValidatorToken);
        } else {
            console.log("FeeAMM pool already has liquidity, skipping");
        }

        // ============================================
        // 2. StablecoinDEX - Enable frxUSD trading
        // ============================================
        console.log("");
        console.log("=== 2. StablecoinDEX Liquidity ===");

        IStablecoinDEX dex = StdPrecompiles.STABLECOIN_DEX;

        // Ensure pair exists
        bytes32 pairKey = dex.pairKey(FRXUSD, StdTokens.PATH_USD_ADDRESS);
        (address base,,,) = dex.books(pairKey);

        if (base == address(0)) {
            console.log("Creating frxUSD/PATH_USD pair...");
            dex.createPair(FRXUSD);
        } else {
            console.log("Pair already exists");
        }

        // Approve PATH_USD for DEX bid liquidity
        ITIP20(StdTokens.PATH_USD_ADDRESS).approve(address(dex), DEX_LIQ);

        // Place bid at tick 0 (1:1 rate)
        console.log("Placing bid liquidity:", DEX_LIQ);
        dex.place(FRXUSD, uint128(DEX_LIQ), true, 0);

        console.log("");
        console.log("=== Done ===");
        console.log("frxUSD can now be used for fees and trading on Tempo");

        vm.stopBroadcast();
    }
}
