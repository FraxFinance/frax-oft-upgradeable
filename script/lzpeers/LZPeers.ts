import * as path from "path";

import * as fs from "fs";
import * as ethers from "ethers";
import * as dotenv from "dotenv";
import { ERC20ABI } from "./abis/ERC20";

dotenv.config();
const ethereum = process.env.ETHEREUM_MAINNET_URL;
const fraxtal = process.env.FRAXTAL_MAINNET_URL;
const abi = ethers.AbiCoder.defaultAbiCoder;

const OFTABI = [
  {
    inputs: [],
    name: "name",
    outputs: [{ internalType: "string", name: "", type: "string" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "token",
    outputs: [{ internalType: "address", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "uint32", name: "_eid", type: "uint32" }],
    name: "peers",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
];

var chains: any[] = [
  { name: "Ethereum-Mainnet", rpc: process.env.ETHEREUM_MAINNET_URL },
  { name: "Fraxtal-Mainnet", rpc: process.env.FRAXTAL_MAINNET_URL },
  { name: "Base-Mainnet", rpc: process.env.BASE_MAINNET_URL },
  { name: "Metis-Mainnet", rpc: process.env.METIS_MAINNET_URL },
  { name: "Blast-Mainnet", rpc: process.env.BLAST_MAINNET_URL },
  { name: "Mode-Mainnet", rpc: process.env.MODE_MAINNET_URL },
  { name: "Sei-Mainnet", rpc: process.env.SEI_MAINNET_URL },
  { name: "X-Layer-Mainnet", rpc: process.env.XLAYER_MAINNET_URL },
  { name: "Sonic-Mainnet", rpc: process.env.SONIC_MAINNET_URL },
  { name: "Ink-Mainnet", rpc: process.env.INK_MAINNET_URL },
  { name: "Arbitrum-Mainnet", rpc: process.env.ARBITRUM_MAINNET_URL },
  { name: "Optimism-Mainnet", rpc: process.env.OPTIMISM_MAINNET_URL },
  { name: "Polygon-Mainnet", rpc: process.env.POLYGON_MAINNET_URL },
  { name: "Avalanche-Mainnet", rpc: process.env.AVALANCHE_MAINNET_URL },
  { name: "BNB-Smart-Chain-Mainnet", rpc: process.env.BSC_MAINNET_URL },
  { name: "Polygon-zkEVM-Mainnet", rpc: process.env.POLYGON_ZKEVM_MAINET_URL },
  { name: "ZkSync-Era-Mainnet", rpc: process.env.ZKSYNC_ERA_MAINNET_URL },
  { name: "Abstract-Mainnet", rpc: process.env.ABSTRACT_MAINNET_URL },
  { name: "Berachain-Mainnet", rpc: process.env.BERACHAIN_MAINNET_URL },
  { name: "Linea-Mainnet", rpc: process.env.LINEA_MAINNET_URL },
];


var contractAddresses = [
  "0x80eede496655fb9047dd39d9f418d5483ed600df",
  "0x5bff88ca1442c2496f7e475e9e7786383bc070c0",
  "0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050",
  "0x3ec3849c33291a9ef4c5db86de593eb4a37fde45",
  "0x64445f0aecc51e94ad52d8ac56b7190e764e561a",
  "0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927",
  "0x909DBdE1eBE906Af95660033e478D59EFe831fED",
  "0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E",
  "0xF010a7c8877043681D59AD125EbF575633505942",
  "0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A",
  "0x23432452B720C80553458496D4D9d7C5003280d0",
];

async function checkPeers() {
  var chainDeployments = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "lzdata/layerzero-v2-deployments.json"),
      "utf-8"
    )
  );
  var dvnDeployments = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "lzdata/dvn-deployments.json"),
      "utf-8"
    )
  );
  var dvnLookup = buildDVNLookup(dvnDeployments);
  var chainsLookup: any = {};
  for (var i = 0; i < chains.length; i++) {
    var chainInfo = chains[i];
    chainInfo.provider = new ethers.JsonRpcProvider(chainInfo.rpc);
    chainInfo.deploymentInfo = chainDeployments[chainInfo.name];
    chainsLookup[chainInfo.name] = chainInfo;
  }
  var contractInfo: any[] = [];
  var promisses: any[] = [];
  for (var i = 0; i < chains.length; i++) {
    var chainInfo = chains[i];
    for (var j = 0; j < contractAddresses.length; j++) {
      var contractAddress = contractAddresses[j];
      promisses.push(getContractInfo(chainInfo, contractAddress));
    }
  }
  for (var i = 0; i < promisses.length; i++) {
    var promiss = promisses[i];
    var info = await promiss;
    if (info) contractInfo.push(info);
  }
  promisses = [];
  for (var i = 0; i < contractInfo.length; i++) {
    var info = contractInfo[i];
    var chainInfo = chainsLookup[info.chain];
    promisses.push(findPeers(chainInfo, info));
  }
  for (var i = 0; i < promisses.length; i++) await promisses[i];
  for (var i = 0; i < contractInfo.length; i++) {
    //console.log(JSON.stringify(contractInfo[i]));
  }
  // console.log(JSON.stringify(contractInfo, null, 2));
}

async function findPeers(chainInfo, info) {
  var contr = new ethers.Contract(info.address, OFTABI, chainInfo.provider);
  // var eid = chainInfo.deploymentInfo.eid;
  info.peers = [];
  for (var i = 0; i < chains.length; i++) {
    var remoteChainInfo = chains[i];
    var remoteEid = remoteChainInfo.deploymentInfo.eid;
    var peer = await contr.peers(remoteEid);
    if (
      peer !=
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ) {
      if (peer.startsWith("0x000000000000000000000000"))
        peer = "0x" + peer.substring(26);
      info.peers.push({ chain: remoteChainInfo.name, address: peer });
      console.log(`${info.name} : ${info.chain} -> ${remoteChainInfo.name}`);
    } else {
    }
  }
}

async function getContractInfo(chainInfo, contractAddress) {
  var info: any;
  var contr = new ethers.Contract(contractAddress, OFTABI, chainInfo.provider);
  try {
    var token = await contr.token();
    var type =
      token.toLowerCase() == contractAddress.toLowerCase()
        ? "OFT"
        : "OFTAdapter";
    var name;
    if (type == "OFTAdapter") {
      var erc20 = new ethers.Contract(token, ERC20ABI, chainInfo.provider);
      name = await erc20.name();
    } else name = await contr.name();
    info = {
      chain: chainInfo.name,
      type: type,
      address: contractAddress,
      token: token,
      name: name,
    };
    //console.log(JSON.stringify(info));
  } catch (ex) {
    //console.log(ex);
    // ignore errors, then contract most likely do not exists
  }
  return info;
}

function buildDVNLookup(dvnDeployments) {
  var dnvLookup = {};
  for (var dvn in dvnDeployments) {
    var dvnChains = dvnDeployments[dvn];
    for (var chain in dvnChains) {
      var address = dvnChains[chain];
      dnvLookup[chain + ":" + address] = dvn;
    }
  }
  //console.log(dnvLookup);
  return dnvLookup;
}

async function plotAllLZPeers() {
  // plotLZPeers("Frax", "Frax USD");
  // console.log("\n");
  // plotLZPeers("Staked FRAX", "Staked Frax USD");
  // console.log("\n");
  // plotLZPeers("Frax Ether", null);
  // console.log("\n");
  // plotLZPeers("Staked Frax Ether", null);
  // console.log("\n");
  // plotLZPeers("Frax Share", null);
  // console.log("\n");
  // plotLZPeers("Frax Price Index", null);
  // console.log("\n");
  /*plotLZPeers("Frax USD");
   console.log("\n");
   plotLZPeers("Staked Frax USD");
   console.log("\n");*/
}

async function plotLZPeers(tokenName1, tokenName2) {
  var contracts = JSON.parse(
    fs.readFileSync(path.join(__dirname, "lzdata/LZPeers.json"), "utf-8")
  );
  var tokenContacts: any[] = [];
  for (var i = 0; i < contracts.length; i++) {
    if (contracts[i].name == tokenName1 || contracts[i].name == tokenName2)
      tokenContacts.push(contracts[i]);
  }
  var str = tokenName1;
  if (tokenName2) str += "/" + tokenName2 + "(*)";
  for (var i = 0; i < tokenContacts.length; i++) {
    var contr: any = tokenContacts[i];
    var label = getLabel(contr);
    str += "," + label;
    if (contr.name == tokenName2) str += "*";
  }
  // console.log(str);
  for (var i = 0; i < tokenContacts.length; i++) {
    var contr: any = tokenContacts[i];
    str = getLabel(contr);
    if (contr.name == tokenName2) str += "*";
    for (var j = 0; j < tokenContacts.length; j++) {
      var contr2 = tokenContacts[j];
      var label2 = getLabel(contr2);
      var found = false;
      for (var k = 0; k < contr.peers.length; k++) {
        var peerLabel = (
          contr.peers[k].chain.substring(0, 4) +
          ":" +
          contr.peers[k].address.substring(0, 8)
        ).toLowerCase();
        //console.log("peerLabel:"+peerLabel);
        if (label2 == peerLabel) found = true;
      }
      if (found) str += ",X";
      else str += ",";
    }
    // console.log(str);
  }
}

function getLabel(contr) {
  var label = contr.chain.substring(0, 4);
  if (contr.chain == "Polygon-zkEVM-Mainnet") label = "Pozk";
  if (label.endsWith("-")) label = label.substring(0, 3);
  label += ":" + contr.address.substring(0, 8);
  return label.toLowerCase();
}

// plotAllLZPeers();
checkPeers();
