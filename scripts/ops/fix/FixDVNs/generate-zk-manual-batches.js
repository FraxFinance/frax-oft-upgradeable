const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const ROOT = path.resolve(__dirname, "../../../..");
const DEFAULT_OUTPUT_DIR = path.join(__dirname, "generated/canary-nethermind");
const OUTPUT_DIR = process.env.FIX_DVNS_GENERATED_DIR
  ? path.resolve(process.cwd(), process.env.FIX_DVNS_GENERATED_DIR)
  : DEFAULT_OUTPUT_DIR;
const SET_CONFIG_ONLY = process.env.FIX_DVNS_SET_CONFIG_ONLY === "true";
const FRAXTAL_CHAIN_ID = 252;
const FRAXTAL_EID = 30255;
const CONFIG_TYPE_ULN = 2;
const CREATED_AT = Date.parse("2026-05-06T00:00:00.000Z");
const NIL_DVN_COUNT = 255;

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const DVN_KEYS = ["bcwGroup", "canary", "frax", "horizen", "lz", "nethermind", "stargate"];

const ZK_CHAINS = [
  {
    chainId: 2741,
    endpoint: "0x5c6cfF4b7C49805F8295Ff73C204ac83f3bC4AE7",
    sendLib302: "0x166CAb679EBDB0853055522D3B523621b94029a1",
    receiveLib302: "0x9d799c1935c51CA399e6465Ed9841DEbCcEc413E",
    blockedLibrary: "0x3258287147fb7887d8a643006e26e19368057377",
  },
  {
    chainId: 324,
    endpoint: "0xd07C30aF3Ff30D96BDc9c6044958230Eb797DDBF",
    sendLib302: "0x07fD0e370B49919cA8dA0CE842B8177263c0E12c",
    receiveLib302: "0x04830f6deCF08Dec9eD6C3fCAD215245B78A59e1",
    blockedLibrary: "0x0fddfc529b5912e1cbe38ccedf8e226566e596d3",
  },
];

const ZK_OFTS = [
  "0xAf01aE13Fb67AD2bb2D76f29A83961069a5F245F",
  "0x9F87fbb47C33Cd0614E43500b9511018116F79eE",
  "0xFD78FD3667DeF2F1097Ed221ec503AE477155394",
  "0xEa77c590Bb36c43ef7139cE649cFBCFD6163170d",
  "0xc7Ab797019156b543B7a3fBF5A99ECDab9eb4440",
  "0x580F2ee1476eDF4B1760bd68f6AaBaD57dec420E",
];

const endpoint = new ethers.utils.Interface([
  "function setSendLibrary(address _oapp,uint32 _eid,address _newLib)",
  "function setConfig(address _oapp,address _lib,tuple(uint32 eid,uint32 configType,bytes config)[] _params)",
]);

const coder = ethers.utils.defaultAbiCoder;

function dvnConfig(chainId) {
  return JSON.parse(fs.readFileSync(path.join(ROOT, "config/dvn", `${chainId}.json`), "utf8"));
}

function confirmationConfig(srcChainId, dstChainId) {
  const config = JSON.parse(fs.readFileSync(path.join(ROOT, "config/confirmations", `${srcChainId}.json`), "utf8"));
  const route = config[String(dstChainId)];
  if (!route) {
    throw new Error(`Missing confirmation config for ${srcChainId} -> ${dstChainId}`);
  }
  return route;
}

function isZero(address) {
  return address.toLowerCase() === ZERO_ADDRESS;
}

function craftDvnStack(srcChainId, dstChainId) {
  const src = dvnConfig(srcChainId)[String(dstChainId)];
  const dst = dvnConfig(dstChainId)[String(srcChainId)];

  const dvns = [];
  for (const key of DVN_KEYS) {
    if (!src || !dst) {
      throw new Error(`Missing DVN config for ${srcChainId} <> ${dstChainId}`);
    }
    if (!isZero(src[key]) || !isZero(dst[key])) {
      if (isZero(src[key]) || isZero(dst[key])) {
        throw new Error(`DVN Stack misconfigured: ${srcChainId} <> ${dstChainId} - ${key}`);
      }
      dvns.push(ethers.utils.getAddress(src[key]));
    }
  }

  return dvns.sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
}

function ulnConfig(requiredDVNs, confirmations) {
  return coder.encode(
    ["tuple(uint64,uint8,uint8,uint8,address[],address[])"],
    [[confirmations, requiredDVNs.length, NIL_DVN_COUNT, 0, requiredDVNs, []]]
  );
}

function transaction(to, data) {
  return { data, operation: "0", to, value: "0" };
}

function batch(chainId, transactions) {
  return {
    chainId,
    createdAt: CREATED_AT,
    meta: {
      description: "",
      name: "Transactions Batch",
    },
    transactions,
    version: "1.0",
  };
}

function writeBatch(name, chainId, transactions) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  const filename = `manual-${name}-${chainId}-to-${FRAXTAL_CHAIN_ID}.json`;
  fs.writeFileSync(path.join(OUTPUT_DIR, filename), `${JSON.stringify(batch(chainId, transactions), null, 2)}\n`);
  console.log(`${filename}: ${transactions.length}`);
}

function setSendLibraryTransactions(chain, lib) {
  return ZK_OFTS.map((oft) => {
    const data = endpoint.encodeFunctionData("setSendLibrary", [oft, FRAXTAL_EID, lib]);
    return transaction(chain.endpoint, data);
  });
}

function setConfigTransactions(chain) {
  const requiredDVNs = craftDvnStack(chain.chainId, FRAXTAL_CHAIN_ID);
  const confirmationRoute = confirmationConfig(chain.chainId, FRAXTAL_CHAIN_ID);
  return ZK_OFTS.flatMap((oft) => [
    [chain.sendLib302, confirmationRoute.sendConfirmations],
    [chain.receiveLib302, confirmationRoute.receiveConfirmations],
  ].map(([lib, confirmationValue]) => {
    const config = ulnConfig(requiredDVNs, confirmationValue);
    const data = endpoint.encodeFunctionData("setConfig", [
      oft,
      lib,
      [{ eid: FRAXTAL_EID, configType: CONFIG_TYPE_ULN, config }],
    ]);
    return transaction(chain.endpoint, data);
  }));
}

for (const chain of ZK_CHAINS) {
  if (!SET_CONFIG_ONLY) {
    writeBatch("1b_SetBlockSendLibZK", chain.chainId, setSendLibraryTransactions(chain, chain.blockedLibrary));
  }
  writeBatch("2b_FixDVNsZK", chain.chainId, setConfigTransactions(chain));
  if (!SET_CONFIG_ONLY) {
    writeBatch("3b_SetSendLibZK", chain.chainId, setSendLibraryTransactions(chain, chain.sendLib302));
  }
}
