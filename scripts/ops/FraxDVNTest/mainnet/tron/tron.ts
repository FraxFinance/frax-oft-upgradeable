import { TronWeb } from "tronweb"

export function getTronWeb(privateKey:string) {
    return new TronWeb({
        fullHost: process.env.TRON_RPC_URL,
        privateKey,
        // headers: { 'TRON-PRO-API-KEY': '2c92a8f1-ee7f-4f28-9138-65a9405a6f78' },

    });
}

// import { TronWeb } from 'tronweb';
// const tronWeb = new TronWeb({
//   fullHost: 'https://api.nileex.io',
// });
// (async () => {
//   console.log(await tronWeb.trx.getCurrentBlock());
// })()