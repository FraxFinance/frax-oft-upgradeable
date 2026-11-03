import { task } from "hardhat/config";
import { EndpointId } from "@layerzerolabs/lz-definitions";
import { types as devtoolsTypes } from "@layerzerolabs/devtools-evm-hardhat";
import {
    Connection,
    PublicKey,
    TransactionMessage,
    VersionedTransaction,
} from "@solana/web3.js";
import { BN } from "@coral-xyz/anchor";
import bs58 from "bs58";
import { OnlinePumpAmmSdk, PumpAmmSdk } from "@pump-fun/pump-swap-sdk";

function fmt(raw: bigint | string | number, decimals: number): string {
    const s = BigInt(raw).toString();
    const neg = s.startsWith("-");
    const x = neg ? s.slice(1) : s;
    const whole = x.length > decimals ? x.slice(0, x.length - decimals) : "0";
    const frac = x.length > decimals ? x.slice(x.length - decimals) : x.padStart(decimals, "0");
    return `${neg ? "-" : ""}${whole}.${frac}`.replace(/\.?0+$/, "");
}

task("pumpswap:withdraw-lp:squads", "Build PumpSwap LP withdraw tx for Squads")
    .addParam("eid", "Solana eid", undefined, devtoolsTypes.eid)
    .addOptionalParam("pool", "PumpSwap pool", "2NbB2EUbJ8hfxvP9Av8ppe39w2k7wen3KqG1WMNeGxHD", devtoolsTypes.string)
    .addOptionalParam("vault", "Squads vault", "FSRTW4KPGifKL8yKcZ8mfoR9mKtAjwZiTHbHwgix8AQo", devtoolsTypes.string)
    .addOptionalParam("lpAmount", "Raw LP amount, or ALL to use vault LP balance", "ALL", devtoolsTypes.string)
    .addOptionalParam("slippage", "2 = 2%", 2, devtoolsTypes.float)
    .addOptionalParam("rpcUrl", "Solana RPC URL", "", devtoolsTypes.string)
    .setAction(async ({ eid, pool, vault, lpAmount, slippage, rpcUrl }) => {
        if (eid !== EndpointId.SOLANA_V2_MAINNET) {
            throw new Error(`Expected Solana mainnet eid ${EndpointId.SOLANA_V2_MAINNET}`);
        }

        const finalRpcUrl =
            rpcUrl ||
            process.env.SOLANA_RPC_URL ||
            process.env.RPC_URL_SOLANA ||
            process.env.RPC_URL_SOLANA_MAINNET ||
            "https://api.mainnet-beta.solana.com";

        const connection = new Connection(finalRpcUrl, "confirmed");
        const onlineSdk = new OnlinePumpAmmSdk(connection);
        const sdk = new PumpAmmSdk();

        const poolKey = new PublicKey(pool);
        const user = new PublicKey(vault);

        const liquiditySolanaState = await onlineSdk.liquiditySolanaState(poolKey, user);
        const decodedPool = liquiditySolanaState.pool;

        const lpMint = decodedPool.lpMint as PublicKey;
        const baseMint = decodedPool.baseMint as PublicKey;
        const quoteMint = decodedPool.quoteMint as PublicKey;

        const lpMintInfo = await connection.getTokenSupply(lpMint);
        const lpDecimals = lpMintInfo.value.decimals;
        const lpSupplyRaw = BigInt(lpMintInfo.value.amount);

        const userPoolTokenAccount = liquiditySolanaState.userPoolTokenAccount as PublicKey;
        const vaultLpBalance =
            liquiditySolanaState.userPoolAccountInfo === null
                ? null
                : await connection.getTokenAccountBalance(userPoolTokenAccount);
        const vaultLpRaw = BigInt(vaultLpBalance?.value.amount ?? "0");

        const withdrawLpRaw =
            lpAmount.toUpperCase() === "ALL" ? vaultLpRaw : BigInt(lpAmount);

        const poolBaseRaw = BigInt(liquiditySolanaState.poolBaseTokenAccount.amount.toString());
        const poolQuoteRaw = BigInt(liquiditySolanaState.poolQuoteTokenAccount.amount.toString());

        const baseSupply = await connection.getTokenSupply(baseMint);
        const quoteSupply = await connection.getTokenSupply(quoteMint);
        const baseDecimals = baseSupply.value.decimals;
        const quoteDecimals = quoteSupply.value.decimals;

        const ownershipBps =
            lpSupplyRaw === 0n ? 0n : (vaultLpRaw * 10000n) / lpSupplyRaw;
        const withdrawBps =
            lpSupplyRaw === 0n ? 0n : (withdrawLpRaw * 10000n) / lpSupplyRaw;

        console.log("RPC:", finalRpcUrl);
        console.log("Pool:", poolKey.toBase58());
        console.log("Vault/User/Fee payer:", user.toBase58());
        console.log("Base mint:", baseMint.toBase58());
        console.log("Quote mint:", quoteMint.toBase58());
        console.log("LP mint:", lpMint.toBase58());
        console.log("Vault LP token account:", userPoolTokenAccount.toBase58());

        console.log("\n--- Current on-chain state ---");
        console.log("Pool base reserve raw:", poolBaseRaw.toString(), "formatted:", fmt(poolBaseRaw, baseDecimals));
        console.log("Pool quote reserve raw:", poolQuoteRaw.toString(), "formatted:", fmt(poolQuoteRaw, quoteDecimals));
        console.log("LP supply raw:", lpSupplyRaw.toString(), "formatted:", fmt(lpSupplyRaw, lpDecimals));
        console.log("Vault LP balance raw:", vaultLpRaw.toString(), "formatted:", fmt(vaultLpRaw, lpDecimals));
        console.log("Vault LP ownership:", `${Number(ownershipBps) / 100}%`);

        console.log("\n--- Withdrawal config ---");
        console.log("Requested LP raw:", withdrawLpRaw.toString(), "formatted:", fmt(withdrawLpRaw, lpDecimals));
        console.log("Requested LP as % of total supply:", `${Number(withdrawBps) / 100}%`);
        console.log("Slippage:", `${slippage}%`);

        if (withdrawLpRaw > vaultLpRaw) {
            throw new Error("Requested lpAmount exceeds vault LP balance");
        }

        if (withdrawLpRaw !== vaultLpRaw) {
            console.warn("WARNING: Requested lpAmount is not equal to vault LP balance.");
        }

        if (vaultLpRaw !== lpSupplyRaw) {
            console.warn("WARNING: Vault does NOT own 100% of LP supply.");
            console.warn("This withdrawal will NOT empty the pool.");
        } else {
            console.log("Vault owns 100% of LP supply. Full withdrawal should empty the pool except dust/rounding.");
        }

        const lpToken = new BN(withdrawLpRaw.toString());

        const expected = sdk.withdrawInputs(liquiditySolanaState, lpToken, slippage);

        console.log("\n--- Expected withdrawal ---");
        console.log("Base out raw:", expected.base?.toString?.(), "formatted:", fmt(expected.base.toString(), baseDecimals));
        console.log("Quote out raw:", expected.quote?.toString?.(), "formatted:", fmt(expected.quote.toString(), quoteDecimals));
        console.log("Min base raw:", expected.minBase?.toString?.(), "formatted:", fmt(expected.minBase.toString(), baseDecimals));
        console.log("Min quote raw:", expected.minQuote?.toString?.(), "formatted:", fmt(expected.minQuote.toString(), quoteDecimals));

        const expectedBaseRaw = BigInt(expected.base.toString());
        const expectedQuoteRaw = BigInt(expected.quote.toString());

        console.log("\n--- Expected post-withdraw pool reserves ---");
        console.log("Pool base after raw:", (poolBaseRaw - expectedBaseRaw).toString(), "formatted:", fmt(poolBaseRaw - expectedBaseRaw, baseDecimals));
        console.log("Pool quote after raw:", (poolQuoteRaw - expectedQuoteRaw).toString(), "formatted:", fmt(poolQuoteRaw - expectedQuoteRaw, quoteDecimals));

        const instructions = await sdk.withdrawInstructions(
            liquiditySolanaState,
            lpToken,
            slippage
        );

        const { blockhash } = await connection.getLatestBlockhash("finalized");

        const message = new TransactionMessage({
            payerKey: user,
            recentBlockhash: blockhash,
            instructions,
        }).compileToV0Message();

        const tx = new VersionedTransaction(message);
        const serialized = tx.serialize();

        console.log("\nBASE58:");
        console.log(bs58.encode(serialized));

        console.log("\nBASE64:");
        console.log(Buffer.from(serialized).toString("base64"));

        console.log("\nVerify in Squads simulation:");
        console.log("- Program: pAMMBay6oceH9fJKBRHGP5D4bD4sWpmSwMn52FMfXEA");
        console.log("- Pool:", poolKey.toBase58());
        console.log("- LP mint burned:", lpMint.toBase58());
        console.log("- Outputs to vault:", user.toBase58());
    });
