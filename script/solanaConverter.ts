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
    console.log("frxUSD ", makeBytes32(bs58.decode("7LS6y37WXXCyBHkBU6zVpiqaqbkXLr4P85ZhQi3eonSp")))
    console.log("sfrxUSD ", makeBytes32(bs58.decode("A28EK6j1euK4e6taP1KLFpGEoR1mDpXR4vtfiyCE1Nxv")))
    console.log("frxETH ", makeBytes32(bs58.decode("4pyqBQFhzsuL7ED76x3AyzT4bCVpMpQWXhS1LqEsfQtz")))
    console.log("sfrxETH ", makeBytes32(bs58.decode("DsJYjDF5yVSopMC15q9W42v833MhWGhCxcU2J39oS3wN")))
    console.log("frax ", makeBytes32(bs58.decode("5vqBiG7nxNnoCst8mEVVS6ax7C1ypEEenPfcZ4kLgj9B")))
    console.log("fpi ", makeBytes32(bs58.decode("FFozEKoFQ1CZD6Kn7bpwAxaWhK1jEA76pjucvBBHf9ZH")))
    console.log("wallet ", makeBytes32(bs58.decode("53dNdHXc7uruWqELhWtpx4f4UvpPk5SaT1upQNoKdi7y")))
    // encode base58
    // console.log(bs58.encode(Buffer.from("020101043c1b094729102e0c095ee2417e5940ee4f1eab4763f6113fe75281ab74c62398d686ca6c5f329a8001280fc5746b81b4d7adbe81cd03aecb55686030d04386903290f7cb566e3551d3b61847d7de7ecef11c221abd502eb1f4009e9b72f5926ec15627c37a10f89f1c6fc7fedd83ebbdd82cbddd14df55674498ec9c1eae1b3105ee6856400bbb2ad7b9a0ecb0f3765fe4b9309c888bd966d997d971d942de77010302010229377e57d99f4218c2003c1b094729102e0c095ee2417e5940ee4f1eab4763f6113fe75281ab74c62398","hex")))

    console.log(bs58.encode(Buffer.from("d3cee058686107cc51844f331ee213a33142ab299b5ce473c1cf3a8ddaa721a0","hex")))
}

main();