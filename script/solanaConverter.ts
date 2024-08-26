import {addressToBytes32} from "@layerzerolabs/lz-v2-utilities";
import { utils } from "ethers";

function main() {
    let converted = addressToBytes32("5KYEyuA1cAdnZFj4i6zUjTEre4s7snacyXbkTmNqLjJs");
    let asHex = utils.hexlify(converted);
    console.log(asHex);
}

main();