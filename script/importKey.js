require("dotenv").config("./.env")
const bs58 = require('bs58');
const { Keypair } = require('@solana/web3.js');

const privateKey = process.env.SOLANA_PRIVATE_KEY;

const keypairData = Keypair.fromSeed(Uint8Array.from(bs58.default.decode(privateKey).slice(0, 32)));

console.log('Public Key:', keypairData.publicKey.toString());
console.log('Secret Key:', keypairData.secretKey.toString());