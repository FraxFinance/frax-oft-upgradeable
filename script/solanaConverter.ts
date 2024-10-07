import {addressToBytes32} from "@layerzerolabs/lz-v2-utilities";
import { utils } from "ethers";

// phantom 4nHaq4EiQZVnDhPAnK1zZEd3qKJVwzBuyTdrbBvvvUS3
// cb 5KYEyuA1cAdnZFj4i6zUjTEre4s7snacyXbkTmNqLjJs
function main() {
    let converted = addressToBytes32("0xb0E1650A9760e0f383174af042091fc544b8356f");
    let asHex = utils.hexlify(converted);
    console.log(asHex);
}

main();