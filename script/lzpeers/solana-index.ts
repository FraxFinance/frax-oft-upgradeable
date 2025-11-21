// import { createUmi } from "@metaplex-foundation/umi-bundle-defaults";
// import { oft } from "@layerzerolabs/oft-v2-solana-sdk";
// import { publicKey } from "@metaplex-foundation/umi";
import { Connection, PublicKey } from "@solana/web3.js";


async function main() {
  const connection = new Connection("https://api.mainnet-beta.solana.com", "confirmed");
  const mintAddress = new PublicKey("GzX1ireZDU865FiMaKrdVB1H6AE8LAqWYCg6chrMrfBw");

  let response = await connection.getTokenSupply(mintAddress);

  console.log(response.value.uiAmount)

  // const solanaUmi = createUmi("https://api.mainnet-beta.solana.com");
  // const res = await oft.getPeerAddress(
  //   solanaUmi.rpc,
  //   publicKey("FFozEKoFQ1CZD6Kn7bpwAxaWhK1jEA76pjucvBBHf9ZH"),
  //   30255,
  //   publicKey("E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ")
  // );
  // console.log(res)
}

main();
