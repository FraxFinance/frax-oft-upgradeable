export const getLayerZeroChainSuppliesAsOfBlock = async ({
  token,
  blockNumberEthereum,
  blockNumberFraxtal,
}: {
  token: 'frxUSD' | 'sfrxUSD';
  blockNumberEthereum: bigint;
  blockNumberFraxtal: bigint;
}) => {
  const lockboxAddressFraxtal = token === 'frxUSD' ? ADDRESSES.fraxtal.frxusd_lockbox : ADDRESSES.fraxtal.sfrxusd_lockbox;
  const lockboxAddressEthereum = token === 'frxUSD' ? ADDRESSES.ethereum.frxusd_lockbox : ADDRESSES.ethereum.sfrxusd_lockbox;
  const fraxtalProvider = evmRpcProvider.fraxtal;
  const ethereumProvider = evmRpcProvider.ethereum;
  const lzChains = Object.entries(LZ_SETTINGS).map(([chain, lzSettings]) => ({
    chain,
    eid: lzSettings.endpointId,
    asOfFraxtalBlock: lzSettings.asOfFraxtalBlock,
    asOfEthereumBlock: lzSettings.asOfEthereumBlock,
    tokenAddress: token === 'frxUSD' ? lzSettings.frxusd.address : lzSettings.sfrxusd.address,
    initialSupply: token === 'frxUSD' ? lzSettings.frxusd.initialSupplyE18 : lzSettings.sfrxusd.initialSupplyE18,
  }));

  const fraxOftMintableAdapterAbi = parseAbi([
    'function totalTransferFrom(uint32 eid) view returns (uint256 amount)',
    'function totalTransferTo(uint32 eid) view returns (uint256 amount)',
    'function initialTotalSupply(uint32 eid) view returns (uint256 amount)',
  ]);

  const results = await pMap(
    lzChains.filter((f) => blockNumberEthereum > f.asOfEthereumBlock && blockNumberFraxtal > f.asOfFraxtalBlock),
    async ({ chain, eid, initialSupply }) => {
      const [fraxtalFromBeforeReset, fraxtalToBeforeReset, fraxtalFrom, fraxtalTo, ethereumFrom, ethereumTo] = await Promise.all([
        blockNumberFraxtal < 27219462
          ? Promise.resolve(0n)
          : fraxtalProvider.readContract({
              address: lockboxAddressFraxtal,
              abi: fraxOftMintableAdapterAbi,
              functionName: 'totalTransferFrom',
              args: [eid],
              blockNumber: 27219462n,
            }),
        blockNumberFraxtal < 27219462
          ? Promise.resolve(0n)
          : fraxtalProvider.readContract({
              address: lockboxAddressFraxtal,
              abi: fraxOftMintableAdapterAbi,
              functionName: 'totalTransferTo',
              args: [eid],
              blockNumber: 27219462n,
            }),
        fraxtalProvider.readContract({
          address: lockboxAddressFraxtal,
          abi: fraxOftMintableAdapterAbi,
          functionName: 'totalTransferFrom',
          args: [eid],
          blockNumber: blockNumberFraxtal,
        }),
        fraxtalProvider.readContract({
          address: lockboxAddressFraxtal,
          abi: fraxOftMintableAdapterAbi,
          functionName: 'totalTransferTo',
          args: [eid],
          blockNumber: blockNumberFraxtal,
        }),
        ethereumProvider.readContract({
          address: lockboxAddressEthereum,
          abi: fraxOftMintableAdapterAbi,
          functionName: 'totalTransferFrom',
          args: [eid],
          blockNumber: blockNumberEthereum,
        }),
        ethereumProvider.readContract({
          address: lockboxAddressEthereum,
          abi: fraxOftMintableAdapterAbi,
          functionName: 'totalTransferTo',
          args: [eid],
          blockNumber: blockNumberEthereum,
        }),
      ]);

      // At block 27219463, storage was reset
      const totalFrom = fraxtalFrom + ethereumFrom + fraxtalFromBeforeReset;
      const totalTo = fraxtalTo + ethereumTo + fraxtalToBeforeReset;
      const netTransfers = totalTo - totalFrom;
      const chainTotalSupply = initialSupply + netTransfers;

      return {
        chain,
        eid,
        fraxtalFrom,
        fraxtalTo,
        ethereumFrom,
        ethereumTo,
        totalFrom,
        totalTo,
        netTransfers: netTransfers.toString(),
        netTransfersDec: +formatUnits(netTransfers, 18),
        chainTotalSupply,
        chainTotalSupplyDec: +formatUnits(chainTotalSupply, 18),
      };
    },
    { concurrency: 8 },
  );

    const fraxtalItem = results.find((f) => f.chain === 'fraxtal');
  const ethereumItem = results.find((f) => f.chain === 'ethereum');

  if (fraxtalItem == null || ethereumItem == null) {
    throw new Error('Unable to find fraxtal/ethereum items');
  }

  const netTransferSummary = Object.fromEntries(results.map((x) => [x.chain, x.netTransfersDec]));
  const supplySummary = Object.fromEntries(results.map((x) => [x.chain, x.chainTotalSupplyDec]));

  return { supplySummary, netTransferSummary, results };
};

export const CHAIN_NAME_TO_LZ_EID = {
  abstract: 30324,
  aptos: 30108,
  arbitrum: 30110,
  aurora: 30211,
  avalanche: 30106,
  base: 30184,
  berachain: 30362,
  blast: 30243,
  bsc: 30102,
  ethereum: 30101,
  fraxtal: 30255,
  hyperliquid: 30367,
  ink: 30339,
  katana: 30375,
  linea: 30183,
  mode: 30260,
  movement: 30325,
  optimism: 30111,
  plasma: 30383,
  plume: 30370,
  polygon_zkevm: 30158,
  polygon: 30109,
  scroll: 30214,
  sei: 30280,
  solana: 30168,
  sonic: 30332,
  unichain: 30320,
  worldchain: 30319,
  xlayer: 30274,
  zksync: 30165,
} as const;

export const LZ_SETTINGS = {
  abstract: {
    endpointId: CHAIN_NAME_TO_LZ_EID.abstract,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 34400986000000000000n,
      address: '0xEa77c590Bb36c43ef7139cE649cFBCFD6163170d',
    },
    sfrxusd: {
      initialSupplyE18: 40101000000000000n,
      address: '0x9F87fbb47C33Cd0614E43500b9511018116F79eE',
    },
  },
  aptos: {
    endpointId: CHAIN_NAME_TO_LZ_EID.aptos,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 25000000000000000n,
      address: '0xe067037681385b86d8344e6b7746023604c6ac90ddc997ba3c58396c258ad17b',
    },
    sfrxusd: {
      initialSupplyE18: 25000000000000000n,
      address: '0xc9bdfdc965bb7fcdcfa6b45870eab33bfaf8f4e8e3f6b89d3e0203aba634a1c9',
    },
  },
  arbitrum: {
    endpointId: CHAIN_NAME_TO_LZ_EID.arbitrum,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 5001888523536000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 6001013674802000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  aurora: {
    endpointId: CHAIN_NAME_TO_LZ_EID.aurora,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 0n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 0n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  avalanche: {
    endpointId: CHAIN_NAME_TO_LZ_EID.avalanche,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 103864754000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 689055000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  base: {
    endpointId: CHAIN_NAME_TO_LZ_EID.base,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 284870510382000000000000n,
      address: '0xe5020A6d073a794B6E7f05678707dE47986Fb0b6',
    },
    sfrxusd: {
      initialSupplyE18: 14440653140000000000000n,
      address: '0x91A3f8a8d7a881fBDfcfEcd7A2Dc92a46DCfa14e',
    },
  },
  blast: {
    endpointId: CHAIN_NAME_TO_LZ_EID.blast,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 711320000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 500000000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  berachain: {
    endpointId: CHAIN_NAME_TO_LZ_EID.berachain,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 22450195000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 279100000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  bsc: {
    endpointId: CHAIN_NAME_TO_LZ_EID.bsc,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 149464217699000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 434350482000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
          },
  },
  ethereum: {
    endpointId: CHAIN_NAME_TO_LZ_EID.ethereum,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: -1n,
      address: '',
    },
    sfrxusd: {
      initialSupplyE18: -1n,
      address: '',
    },
  },
  fraxtal: {
    endpointId: CHAIN_NAME_TO_LZ_EID.fraxtal,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: -1n,
      address: '',
    },
    sfrxusd: {
      initialSupplyE18: -1n,
      address: '',
    },
  },
  hyperliquid: {
    endpointId: CHAIN_NAME_TO_LZ_EID.hyperliquid,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 0n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 0n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  ink: {
    endpointId: CHAIN_NAME_TO_LZ_EID.ink,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 594878467000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 2153100000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  linea: {
    endpointId: CHAIN_NAME_TO_LZ_EID.linea,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 647825829689000000000000n,
      address: '0xC7346783f5e645aa998B106Ef9E7f499528673D8',
    },
    sfrxusd: {
      initialSupplyE18: 144532057000000000000n,
      address: '0x592a48c0FB9c7f8BF1701cB0136b90DEa2A5B7B6',
    },
  },
  katana: {
    endpointId: CHAIN_NAME_TO_LZ_EID.katana,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 485120672881000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 112538057665000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  mode: {
    endpointId: CHAIN_NAME_TO_LZ_EID.mode,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 13285223000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 11287000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  movement: {
    endpointId: CHAIN_NAME_TO_LZ_EID.movement,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 15009900000000000000n,
      address: '0xe067037681385b86d8344e6b7746023604c6ac90ddc997ba3c58396c258ad17b',
    },
    sfrxusd: {
      initialSupplyE18: 14400000000000000000n,
      address: '0xc9bdfdc965bb7fcdcfa6b45870eab33bfaf8f4e8e3f6b89d3e0203aba634a1c9',
    },
  },
  optimism: {
    endpointId: CHAIN_NAME_TO_LZ_EID.optimism,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 1249279914000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 1046460795449000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  plasma: {
    endpointId: CHAIN_NAME_TO_LZ_EID.plasma,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 0n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },    sfrxusd: {
      initialSupplyE18: 0n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  plume: {
    endpointId: CHAIN_NAME_TO_LZ_EID.plume,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 101000000000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 0n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  polygon: {
    endpointId: CHAIN_NAME_TO_LZ_EID.polygon,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 2604120000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 3041846000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  polygon_zkevm: {
    endpointId: CHAIN_NAME_TO_LZ_EID.polygon_zkevm,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 1891270000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 33299000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  scroll: {
    endpointId: CHAIN_NAME_TO_LZ_EID.scroll,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 23100000000000000000n,
      address: '0x397F939C3b91A74C321ea7129396492bA9Cdce82',
    },
    sfrxusd: {
      initialSupplyE18: 0n,
      address: '0xC6B2BE25d65760B826D0C852FD35F364250619c2',
    },
  },
  sei: {
    endpointId: CHAIN_NAME_TO_LZ_EID.sei,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 12902740735000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 609222028331000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  solana: {
    endpointId: CHAIN_NAME_TO_LZ_EID.solana,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 1160597873340446000000000n,
      address: 'GzX1ireZDU865FiMaKrdVB1H6AE8LAqWYCg6chrMrfBw',
    },
    sfrxusd: {
      initialSupplyE18: 2108000000000000n,
      address: 'DUvWQMyASSkLNJFwsMDA4kwxEvmfaqpPGrvUVKtitX45',
    },
  },
  sonic: {
    endpointId: CHAIN_NAME_TO_LZ_EID.sonic,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 1356050234321000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 682574585449000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  unichain: {
    endpointId: CHAIN_NAME_TO_LZ_EID.unichain,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 14051736268000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 100000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  worldchain: {
    endpointId: CHAIN_NAME_TO_LZ_EID.worldchain,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 100000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 100000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  xlayer: {
    endpointId: CHAIN_NAME_TO_LZ_EID.xlayer,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {
      initialSupplyE18: 181000300000000000000n,
      address: '0x80Eede496655FB9047dd39d9f418d5483ED600df',
    },
    sfrxusd: {
      initialSupplyE18: 732912000000000000n,
      address: '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0',
    },
  },
  zksync: {
    endpointId: CHAIN_NAME_TO_LZ_EID.zksync,
    asOfFraxtalBlock: 26922516,
    asOfEthereumBlock: 23593376,
    frxusd: {      initialSupplyE18: 3006300000000000000n,
      address: '0xEa77c590Bb36c43ef7139cE649cFBCFD6163170d',
    },
    sfrxusd: {
      initialSupplyE18: 100000000000000n,
      address: '0x9F87fbb47C33Cd0614E43500b9511018116F79eE',
    },
  },
} as const;

export const LZ_EID_TO_CHAIN_NAME = Object.fromEntries(Object.entries(CHAIN_NAME_TO_LZ_EID).map(([k, v]) => [v, k])) as Record<
  number,
  keyof typeof CHAIN_NAME_TO_LZ_EID
>;