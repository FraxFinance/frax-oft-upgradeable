import {addressToBytes32} from "@layerzerolabs/lz-v2-utilities";
import { utils } from "ethers";
import { makeBytes32 } from '@layerzerolabs/devtools'
import bs58 from 'bs58'
import { buffer } from "stream/consumers";

function main() {
    let converted = addressToBytes32("Fn5fevRHJT71PLvyLanbiTtpp67DzpU8JdY84rp65zZS");
    let asHex = utils.hexlify(converted);
    console.log(asHex);
    // solana base58 to bytes32
    console.log(makeBytes32(bs58.decode("8JAtiM2ebc7D6jDAYK2U7uSj72PkXgkNmB1NvfxCLzmx")))
    // encode base58
    console.log(bs58.encode(Buffer.from("020101043c1b094729102e0c095ee2417e5940ee4f1eab4763f6113fe75281ab74c62398d686ca6c5f329a8001280fc5746b81b4d7adbe81cd03aecb55686030d04386903290f7cb566e3551d3b61847d7de7ecef11c221abd502eb1f4009e9b72f5926ec15627c37a10f89f1c6fc7fedd83ebbdd82cbddd14df55674498ec9c1eae1b3105ee6856400bbb2ad7b9a0ecb0f3765fe4b9309c888bd966d997d971d942de77010302010229377e57d99f4218c2003c1b094729102e0c095ee2417e5940ee4f1eab4763f6113fe75281ab74c62398","hex")))
}

main();