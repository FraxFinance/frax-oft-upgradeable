import { VersionedMessage, VersionedTransaction } from '@solana/web3.js'
import bs58 from 'bs58'
import fs from "fs"

const txData = [
  {
    "point": {
      "eid": 30168,
      "address": "76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6"
    },
    "data": "0201080c3c1b094729102e0c095ee2417e5940ee4f1eab4763f6113fe75281ab74c62398d686ca6c5f329a8001280fc5746b81b4d7adbe81cd03aecb55686030d0438690ac5e5f07910ec7692174a4c082309da3b556c2321b0849737411eaf114174d5e0d9eb9aff1fa173accfca1d7725ae40f547c4cba4acbd3012c677eb85abfde6916b7830c3f8a44c810ca87de56e032889c358ec75d4732bf7361862658acb2af25608cf65075dbb141996e875a41ea9d68eda43b81377015ffcdfa96604fa7123bb66c6947983775eb253df3d1c9818c2f958899b64a23b05a51bc8ed358f6e95aad76da514b6e1dcf11037e904dac3d375f525c9fbafcb19507b78907d8c18b619e429a1de67854bd455ee6643f568d6236cde8e9442a3abf029f016faae63064addff32f7e70f064aaeb7199486126df6abfa7e1b33d41a4673fab17868534a558dec6aa74873ea9a42693053ff1a2ffa51912d8d34fc84ce2c71469677a47d578e9a30dd675e5136de2053bfa788ca50b12e9126862581411f169ab67bad1a4342e21784444efc70ea1b27288e8f350ad74a0c084dec673014cac1e80230901070c010b060408040203050a0908a7016c9e9aafd46234424939035f8dd13d15a9386e28b6705519aa6f488791323466a3c0116a201e51aa2f760000030000007300000005000000000000000300000300000033cdb9fb56d28a2f028cbb36c254a7d54c92f0419b53e44ddcc0a5c373f854f25246d8507e84b6b25cc8122a05d4f5c8f945561d26d3df0fe8b9e88d8fb73ec6f3ea64a20ecedc882c28a0ba115a3a338ce2bb0d746d123c5b4abbdbead761f200000000",
    "description": "Setting config for ULN 7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH to [\n\t{\n\t\t\"eid\": 30255,\n\t\t\"configType\": 3,\n\t\t\"config\": {\n\t\t\t\"confirmations\": \"5\",\n\t\t\t\"optionalDVNThreshold\": 0,\n\t\t\t\"requiredDVNs\": [\n\t\t\t\t\"4VDjp6XQaxoZf5RGwiPU9NR1EXSZn2TP4ATMmiSzLfhb\",\n\t\t\t\t\"6YB63FDuyYLt5gnJeiVmYRE4c6tFid5SrBZzMLQFfexm\",\n\t\t\t\t\"HR9NQKK1ynW9NzgdM37dU5CBtqRHTukmbMKS7qkwSkHX\"\n\t\t\t],\n\t\t\t\"optionalDVNs\": [],\n\t\t\t\"requiredDVNCount\": 3,\n\t\t\t\"optionalDVNCount\": 0\n\t\t}\n\t}\n]"
  }
]

const transactionDataHex = '80010004063c1b094729102e0c095ee2417e5940ee4f1eab4763f6113fe75281ab74c62398a8360ae4dd83a509ca02a80763c269baf6769357792fd04e3f188b72c1baeb6c0b7065b1e3d17c45389d527f6b04c3cd58b86c731aa0fdb549b6d1bc03f829460ebef59dac440497ad2b91328e6ee05369dbee1d6d1fb8f34fad284d0bb20a5b000000000000000000000000000000000000000000000000000000000000000006a7d517187bd16635dad40455fdc2c0c124c68f215675a5dbbacb5f08000000b980771914cfe8acd1731638f9f9c5e89e39961032b75146831335977ed8d34d01020b0002020301020004050202d40132000001040000004672617804000000465241588c00000068747470733a2f2f7261772e67697468756275736572636f6e74656e742e636f6d2f4672617846696e616e63652f667261782d6f66742d7570677261646561626c652f333765616565623935653263373438356637383162333934313865353762366136346434386438362f736f6c616e612d6d61696e6e65742d6d657461646174612f6678732e6a736f6e000001010000003c1b094729102e0c095ee2417e5940ee4f1eab4763f6113fe75281ab74c6239801640000000000000000'
const versionedMessage = VersionedMessage.deserialize(Buffer.from(transactionDataHex, 'hex'))
const path = "./scripts/ops/fix/FixDVNs/txs"
const outputFilename = "2b-upgradeDVNSolana-wfrax-252.txt"

txData.forEach(_tx => {
  const tx = new VersionedTransaction(VersionedMessage.deserialize(Buffer.from(_tx.data, 'hex')));
  console.log(_tx.description)
  console.log(bs58.encode(Buffer.from(tx.serialize())))
  const unixTimestamp = Math.floor(Date.now() / 1000);
  const base58Tx = bs58.encode(Buffer.from(tx.serialize()));
  fs.writeFileSync(`${path}/${unixTimestamp}-${outputFilename}`, base58Tx, 'utf8');
});