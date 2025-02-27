import {addressToBytes32} from "@layerzerolabs/lz-v2-utilities";
import { utils } from "ethers";
import { makeBytes32 } from '@layerzerolabs/devtools'
import bs58 from 'bs58'

function main() {
    let converted = addressToBytes32("Fn5fevRHJT71PLvyLanbiTtpp67DzpU8JdY84rp65zZS");
    let asHex = utils.hexlify(converted);
    console.log(asHex);
    // solana base58 to bytes32
    console.log(makeBytes32(bs58.decode("8JAtiM2ebc7D6jDAYK2U7uSj72PkXgkNmB1NvfxCLzmx")))
}

main();