import OFT_ABI from "./abis/OFT_ABI.json";
import OFT_ADAPTER_ABI from "./abis/OFT_ADAPTER_ABI.json";
import OFT_MINTABLE_ADAPTER_ABI from "./abis/OFT_MINTABLE_ADAPTER_ABI.json";
import { OFTMetadata } from "./types";

export const solanaOFTs: Record<string, Record<string, string>> = {
    frxUSD: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "GzX1ireZDU865FiMaKrdVB1H6AE8LAqWYCg6chrMrfBw",
        "mintAuthority": "52e8UiVqx28VEqyiEqMbMVehFC3LheNGqnA9m82XF6GK",
        "escrow": "84AFSH3TSzyjbEFJX9z8sjpV7npTWq7f8ZR5zkLG22hX",
        "oftStore": "7LS6y37WXXCyBHkBU6zVpiqaqbkXLr4P85ZhQi3eonSp"
    },
    sfrxUSD: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "DUvWQMyASSkLNJFwsMDA4kwxEvmfaqpPGrvUVKtitX45",
        "mintAuthority": "EK2qrg4ggSVmxNDU3qSvVcKx7HYpmNT3kWbLHMtL5vaV",
        "escrow": "8vRGMiktFX3VhQRfwkaWsAG3KHHzVnRYEKkDKEYzgmCa",
        "oftStore": "A28EK6j1euK4e6taP1KLFpGEoR1mDpXR4vtfiyCE1Nxv"
    },
    frxETH: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "5sDrwVNiHMM2jC78hRBH1CtysDQYiNKihubgW2zNu8tf",
        "mintAuthority": "Ea6GvxUc4xh4LoPgJXePhKFsUcuW8G2RASdNYyuoohxr",
        "escrow": "H17Anco2cnEtSyfSwt4XKhsU7nbFyP57qqXhsff39UW3",
        "oftStore": "4pyqBQFhzsuL7ED76x3AyzT4bCVpMpQWXhS1LqEsfQtz"
    },
    sfrxETH: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "58zpC9acE6F4FBtd88L64NoWHJcmzLsQSy5bjz35Ydgv",
        "mintAuthority": "BVQcQygw2f6nrDu6HNTfQ1ECjRRx8nm2CnBANt4yqqvp",
        "escrow": "AmjMhAYdCz2crdKYG4U9WMPT7ccHsXSx12qJ5TTjoHYq",
        "oftStore": "DsJYjDF5yVSopMC15q9W42v833MhWGhCxcU2J39oS3wN"
    },
    wfrax: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "zZbQjiRg8uSxZaPu996XuviuZeSY6nsaMuutKZQBJga",
        "mintAuthority": "CMCA6bzoCH4KcDZtwCviFYF2c5tasLHjEhX8ThMeCpqk",
        "escrow": "FwmRDpyFBLkdk7BLRkWF5p5DqwBX2LzVTARGkG5haHbV",
        "oftStore": "5vqBiG7nxNnoCst8mEVVS6ax7C1ypEEenPfcZ4kLgj9B"
    },
    fpi: {
        "programId": "E1ht9dUh1ZkgWWRRPCuN3kExEoF2FXiyADXeN3XyMHaQ",
        "mint": "8xKX8CRH9LxriRUNCPittu1jiovyQQr4EonWQjHZjWyH",
        "mintAuthority": "F3YLUzqvJndUpypxUgxsFZQFHD3KUNC5QrkpNJKLBGje",
        "escrow": "EPmy89v6at8rxrV2n1E3xZP74MzaGi7BWdFNiA2xW64Z",
        "oftStore": "FFozEKoFQ1CZD6Kn7bpwAxaWhK1jEA76pjucvBBHf9ZH"
    }
}

export const aptosMovementOFTs: Record<string, Record<string, string>> = {
    frxUSD: {
        "oft": "0xe067037681385b86d8344e6b7746023604c6ac90ddc997ba3c58396c258ad17b",
        "oftfa": "0xe4354602aa4311f36240dd57f3f3435ffccdbd0cd2963f1a69da39a2dbcd59b5"
    },
    sfrxUSD: {
        "oft": "0xc9bdfdc965bb7fcdcfa6b45870eab33bfaf8f4e8e3f6b89d3e0203aba634a1c9",
        "oftfa": "0xbf2efbffbbd7083aaf006379d96b866b73bb4eb9684a7504c62feafe670962c2"
    },
    frxETH: {
        "oft": "0xecb3a766f12981919158fc8ec3b98dd3f8b39a59280e62e80c600cea1b2c0f9c",
        "oftfa": "0x8645126a60d36e138d435a28875a2aeef253bf80aae22bebcd411ad4251f1585"
    },
    sfrxETH: {
        "oft": "0x28b7264258592031a024ed8e1632090648ec53797c269ac91aa0c9ed94268356",
        "oftfa": "0x80d729c4632bcc6279b7bed2542e01e2cebd34ca9f3f15963c29d1621efc221a"
    },
    wfrax: {
        "oft": "0x267749b1a80d9d582019e6b0572c1dbc98648e24101b0861395cdbed095ceff2",
        "oftfa": "0x4e4cce8f877d7ad45c896c1823017fe07874f3d8db6e15960eda26e211151300"
    },
    fpi: {
        "oft": "0xadf0ffffa5ee44a94f0c65be05e701951e65e276419f7460286a139d9403e864",
        "oftfa": "0x15607151cc023512886f5af24d4f77e6e7a5d6fb8a482dfb56b9c4f5c1fca0b2"
    }
}

const determinsticOFTs: Record<string, OFTMetadata> = {
    fpi: {
        address: "0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927",
        abi: OFT_ABI
    },
    frxETH: {
        address: "0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050",
        abi: OFT_ABI
    },
    frxUSD: {
        address: "0x80Eede496655FB9047dd39d9f418d5483ED600df",
        abi: OFT_ABI
    },
    sfrxETH: {
        address: "0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45",
        abi: OFT_ABI
    },
    sfrxUSD: {
        address: "0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0",
        abi: OFT_ABI
    },
    wfrax: {
        address: "0x64445f0aecC51E94aD52d8AC56b7190e764E561a",
        abi: OFT_ABI
    }
}

export const ethereumOFTs: Record<string, OFTMetadata> = {
    fpi: {
        address: "0x9033BAD7aA130a2466060A2dA71fAe2219781B4b",
        abi: OFT_MINTABLE_ADAPTER_ABI
    },
    frxETH: {
        address: "0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6",
        abi: OFT_ADAPTER_ABI
    },
    frxUSD: {
        address: "0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0",
        abi: OFT_MINTABLE_ADAPTER_ABI
    },
    sfrxETH: {
        address: "0xbBc424e58ED38dd911309611ae2d7A23014Bd960",
        abi: OFT_ADAPTER_ABI
    },
    sfrxUSD: {
        address: "0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126",
        abi: OFT_MINTABLE_ADAPTER_ABI
    },
    wfrax: {
        address: "0x04ACaF8D2865c0714F79da09645C13FD2888977f",
        abi: OFT_ABI
    }
}

export const fraxtalOFTs: Record<string, OFTMetadata> = {
    fpi: {
        address: "0x75c38D46001b0F8108c4136216bd2694982C20FC",
        abi: OFT_MINTABLE_ADAPTER_ABI
    },
    frxETH: {
        address: "0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604",
        abi: OFT_MINTABLE_ADAPTER_ABI
    },
    frxUSD: {
        address: "0x96A394058E2b84A89bac9667B19661Ed003cF5D4",
        abi: OFT_MINTABLE_ADAPTER_ABI
    },
    sfrxETH: {
        address: "0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168",
        abi: OFT_MINTABLE_ADAPTER_ABI
    },
    sfrxUSD: {
        address: "0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361",
        abi: OFT_MINTABLE_ADAPTER_ABI
    },
    wfrax: {
        address: "0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A",
        abi: OFT_ADAPTER_ABI
    }
}

export const baseOFTs: Record<string, OFTMetadata> = {
    fpi: {
        address: "0xEEdd3A0DDDF977462A97C1F0eBb89C3fbe8D084B",
        abi: OFT_ABI
    },
    frxETH: {
        address: "0x7eb8d1E4E2D0C8b9bEDA7a97b305cF49F3eeE8dA",
        abi: OFT_ABI
    },
    frxUSD: {
        address: "0xe5020A6d073a794B6E7f05678707dE47986Fb0b6",
        abi: OFT_ABI
    },
    sfrxETH: {
        address: "0x192e0C7Cc9B263D93fa6d472De47bBefe1Fb12bA",
        abi: OFT_ABI
    },
    sfrxUSD: {
        address: "0x91A3f8a8d7a881fBDfcfEcd7A2Dc92a46DCfa14e",
        abi: OFT_ABI
    },
    wfrax: {
        address: "0x0CEAC003B0d2479BebeC9f4b2EBAd0a803759bbf",
        abi: OFT_ABI
    }
}

export const lineaOFTs: Record<string, OFTMetadata> = {
    fpi: {
        address: "0xDaF72Aa849d3C4FAA8A9c8c99f240Cf33dA02fc4",
        abi: OFT_ABI
    },
    frxETH: {
        address: "0xB1aFD04774c02AE84692619448B08BA79F19b1ff",
        abi: OFT_ABI
    },
    frxUSD: {
        address: "0xC7346783f5e645aa998B106Ef9E7f499528673D8",
        abi: OFT_ABI
    },
    sfrxETH: {
        address: "0x383Eac7CcaA89684b8277cBabC25BCa8b13B7Aa2",
        abi: OFT_ABI
    },
    sfrxUSD: {
        address: "0x592a48c0FB9c7f8BF1701cB0136b90DEa2A5B7B6",
        abi: OFT_ABI
    },
    wfrax: {
        address: "0x5217Ab28ECE654Aab2C68efedb6A22739df6C3D5",
        abi: OFT_ABI
    }
}

export const absZkOFTs: Record<string, OFTMetadata> = {
    fpi: {
        address: "0x580F2ee1476eDF4B1760bd68f6AaBaD57dec420E",
        abi: OFT_ABI
    },
    frxETH: {
        address: "0xc7Ab797019156b543B7a3fBF5A99ECDab9eb4440",
        abi: OFT_ABI
    },
    frxUSD: {
        address: "0xEa77c590Bb36c43ef7139cE649cFBCFD6163170d",
        abi: OFT_ABI
    },
    sfrxETH: {
        address: "0xFD78FD3667DeF2F1097Ed221ec503AE477155394",
        abi: OFT_ABI
    },
    sfrxUSD: {
        address: "0x9F87fbb47C33Cd0614E43500b9511018116F79eE",
        abi: OFT_ABI
    },
    wfrax: {
        address: "0xAf01aE13Fb67AD2bb2D76f29A83961069a5F245F",
        abi: OFT_ABI
    }
}

export const scrollOFTs: Record<string, OFTMetadata> = {
    fpi: {
        address: "0x93cDc5d29293Cb6983f059Fec6e4FFEb656b6a62",
        abi: OFT_ABI
    },
    frxETH: {
        address: "0x0097Cf8Ee15800d4f80da8A6cE4dF360D9449Ed5",
        abi: OFT_ABI
    },
    frxUSD: {
        address: "0x397F939C3b91A74C321ea7129396492bA9Cdce82",
        abi: OFT_ABI
    },
    sfrxETH: {
        address: "0x73382eb28F35d80Df8C3fe04A3EED71b1aFce5dE",
        abi: OFT_ABI
    },
    sfrxUSD: {
        address: "0xC6B2BE25d65760B826D0C852FD35F364250619c2",
        abi: OFT_ABI
    },
    wfrax: {
        address: "0x879ba0efe1ab0119fefa745a21585fa205b07907",
        abi: OFT_ABI
    }
}

export const ofts: Record<string, Record<string, OFTMetadata>> = {
    ethereum: ethereumOFTs,
    fraxtal: fraxtalOFTs,
    base: baseOFTs,
    blast: determinsticOFTs,
    mode: determinsticOFTs,
    sei: determinsticOFTs,
    xlayer: determinsticOFTs,
    sonic: determinsticOFTs,
    ink: determinsticOFTs,
    arbitrum: determinsticOFTs,
    optimism: determinsticOFTs,
    polygon: determinsticOFTs,
    avalanche: determinsticOFTs,
    bnb: determinsticOFTs,
    zkevm: determinsticOFTs,
    zksync: absZkOFTs,
    abstract: absZkOFTs,
    berachain: determinsticOFTs,
    linea: lineaOFTs,
    aurora: determinsticOFTs,
    hyperliquid: determinsticOFTs,
    katana: determinsticOFTs,
    plumephoenix: determinsticOFTs,
    scroll: scrollOFTs,
    unichain: determinsticOFTs,
    worldchain: determinsticOFTs,
    plasma: determinsticOFTs,
    stable: determinsticOFTs
}