<h1 align="center">Frax Finance <> LayerZero OFTs</h1>
This repository contains all of the contracts and deployment code used to manage and operate Frax Protocol's LayerZero OFT network.


## Contracts & Addresses
### Admin
- `ProxyAdmin`
  - `Mode`, `Sei`, `Fraxtal`, `X-Layer`, `Ink`, `Sonic`, `Arbitrum`, `Optimism`, `Polygon`, `Avalanche`, `BSC`, `Polygon zkEvm`
    - `0x223a681fc5c5522c85c96157c0efa18cd6c5405c`
  - `Base`
    - `0xF59C41A57AB4565AF7424F64981523DfD7A453c5`
  - `Linea`
    - `0x3cf371c128b092b085B7732069cEAF3Fd863F270`
  - `ZKSync`
    - TODO

- Msigs (links to gnosis safe)
  - [`Ethereum`](https://app.safe.global/home?safe=eth:0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27)
  - [`Blast`](https://app.safe.global/home?safe=blast:0x33A133020b2C2CD41a24F74033B11EC2fC0bF97a)
  - [`Metis`](https://metissafe.tech/home?safe=metis-andromeda:0xF4A4F32732F9B2fB84Ee28c58616946F3bF80F7d)
  - [`Base`](https://app.safe.global/home?safe=base:0xCBfd4Ef00a8cf91Fd1e1Fe97dC05910772c15E53)
  - [`Mode`](https://safe.optimism.io/home?safe=mode:0x6336CFA6eDBeC2A459d869031DB77fC2770Eaa66)
  - [`Sei`](https://sei-safe.protofire.io/home?safe=sei:0x0357D02fc95320b990322d3ff69204c3D251171b)
  - [`Fraxtal`](https://safe.mainnet.frax.com/home?safe=fraxtal:0x5f25218ed9474b721d6a38c115107428E832fA2E)
  - [`X-Layer`](https://app.safe.global/home?safe=xlayer:0xe7Cc52f0C86f4FAB6630f1E26167B487fbF66a61)
  - [`Solana`](https://app.squads.so/squads/FSRTW4KPGifKL8yKcZ8mfoR9mKtAjwZiTHbHwgix8AQo)
  - [`Sonic`](https://app.safe.global/home?safe=sonic:0x87c7A1ef67c67cd57CBF101522a0c3B19D2C3aAc)
  - [`Ink`](https://app.safe.global/home?safe=ink:0x91eBC17cD330DD694225133455583FBCA54b8eC8)
  - [`Arbitrum`](https://app.safe.global/home?safe=arb1:0x3da490b19F300E7cb2280426C8aD536dB2df445c)
  - [`Optimism`](https://app.safe.global/home?safe=oeth:0x419e672d625f998dd07a7ecf2E06B896F8717cb2)
  - [`Polygon`](https://app.safe.global/home?safe=matic:0xDbf59edA454679bB157b3B048Ba54C4D762b559E)
  - [`Avalanche`](https://app.safe.global/home?safe=avax:0xBF1fF4D8B05F0871ca3f49e49fF1cA8AeeBD3b4b)
  - [`BSC`](https://app.safe.global/home?safe=bnb:0xB1eff95B323D60cc04B1a44Ca1dBcbC935ae2C84)
  - [`Polygon zkEvm`](https://app.safe.global/home?safe=zkevm:0x57445fD8d544e5D313e4f715220103b091814df4)
  - [`Berachain`](https://safe.berachain.com/home?safe=berachain:0x436b303dAf4b95e94ad86cA3821d5E50eB0De3aA)
  - [`Linea`](https://safe.linea.build/home?safe=linea:0x0E5a5284820E350ffce7fe7ba3364FaC1C53eaFD)

### Proxy (upgradeable) OFTs
- Chain: `Mode`, `Sei`, `X-Layer`, `Ink`, `Sonic`, `Arbitrum`, `Optimism`, `Polygon`, `BSC`, `Avalanche`, `Polygon zkEvm`, `Blast`, `Berachain`
  - OFTs
    - `frxUSD`: `0x80Eede496655FB9047dd39d9f418d5483ED600df`
    - `sfrxUSD`: `0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0`
    - `frxETH`: `0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050`
    - `sfrxETH`: `0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45`
    - `FXS`: `0x64445f0aecC51E94aD52d8AC56b7190e764E561a`
    - `FPI` : `0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927`
- Chain: `Base`
  - OFTs
    - `frxUSD`: `0xe5020A6d073a794B6E7f05678707dE47986Fb0b6`
    - `sfrxUSD`: `0x91A3f8a8d7a881fBDfcfEcd7A2Dc92a46DCfa14e`
    - `frxETH`: `0x7eb8d1E4E2D0C8b9bEDA7a97b305cF49F3eeE8dA`
    - `sfrxETH`: `0x192e0C7Cc9B263D93fa6d472De47bBefe1Fb12bA`
    - `FXS`: `0x0CEAC003B0d2479BebeC9f4b2EBAd0a803759bbf`
    - `FPI` : `0xEEdd3A0DDDF977462A97C1F0eBb89C3fbe8D084B`
- Chain: `Linea`
  - OFTs:
      - `frxUSD`: `0xC7346783f5e645aa998B106Ef9E7f499528673D8`
      - `sfrxUSD`: `0x592a48c0FB9c7f8BF1701cB0136b90DEa2A5B7B6`
      - `frxETH`: `0xB1aFD04774c02AE84692619448B08BA79F19b1ff`
      - `sfrxETH`: `0x383Eac7CcaA89684b8277cBabC25BCa8b13B7Aa2`
      - `FXS`: `0x5217Ab28ECE654Aab2C68efedb6A22739df6C3D5`
      - `FPI`:  `0xDaF72Aa849d3C4FAA8A9c8c99f240Cf33dA02fc4`
- Chain: `ZkSync`
  - OFTs
    - TODO


### Lockbox design
Frax operates a dual-lockbox design where users can exit their OFT token into the native Frax-asset token on both Ethereum and Fraxtal.  Utilizing a dual-lockbox design is a novel solution to bridging as liquidity is  unlocked from more than one location.  More about this solution is be explained in the [docs](TODO).

#### Fraxtal Lockboxes
- `frxUSD`: `0x96A394058E2b84A89bac9667B19661Ed003cF5D4`
- `sfrxUSD`: `0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361`
- `frxETH`: `0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604`
- `sfrxETH`: `0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168`
- `FXS`: `0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A`
- `FPI`: `0x75c38D46001b0F8108c4136216bd2694982C20FC`

#### Ethereum Lockboxes
There are two sets of Ethereum lockboxes: (1) the upgradeable lockboxes used in current deployments and (2) legacy immutable lockboxes used to unlock immutable OFT liquidity.
You can expect to use (1) unless you are holding OFTs on Base, Blast, or Metis prior to February 2025.  Legacy liquidity can be unlocked through Stargate UI.
1. Upgradeable (current) Lockboxes
  - `frxUSD`: `0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0`
  - `sfrxUSD`: `0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126`
  - `frxETH` : `0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6`
  - `sfrxETH`: `0xbBc424e58ED38dd911309611ae2d7A23014Bd960`
  - `FXS`: `0xC6F59a4fD50cAc677B51558489E03138Ac1784EC`
  - `FPI`: `0x9033BAD7aA130a2466060A2dA71fAe2219781B4b`
2. Immutable (legacy) Lockboxes
  - `FRAX`: `0x909DBdE1eBE906Af95660033e478D59EFe831fED`
  - `sFRAX`: `0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E`
  - `frxETH` : `0xF010a7c8877043681D59AD125EbF575633505942`
  - `sfrxETH`: `0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A`
  - `FXS`: `0x23432452B720C80553458496D4D9d7C5003280d0`
  - `FPI`: `0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d`

### Solana
- Admin: Chain-respective msig
- `FRAX`
  - SPL Token: `B4Ds2fCbxjSiVLNyGQd44htvvNuVxzdoJSxNsRv3nxpE`
  - OFT Config: `7pw5h3gc4LQCGPdq9qsqCdBDt6vtyk5CWjL9spsjp7Sa`
    - As bytes32: `0x656d91ab3d464c05cd1345ce21c78e36140a36491e102fbb08c58af73aafe89b`
- `sFrax`
  - SPL Token: `DnVyztLHnDyTqL3xfPYF9Uqpgrhcxphn6e31sVAwtg6K`
  - OFT Config: `3BcysJF4fQx86fVTDTBGNpZyRpeMyTF8XsuvPHJQuP3V`
    - As bytes32: `0x206fdd7d0be90d8ff93f6f7f4bd4d8b42ca8977317da0b7d2861299e3c589dd8`
- `frxETH`
  - SPL Token: `CuXHLCxCcyPkmbemPxh7PAWedfFffeL82b6VPJmonTaa`
  - OFT Config: `AzaSy9yr44e4bnWNdrNkxmye1kEYmbbgGfY8a3ZqzuMf`
    - As bytes32: `0x94791ba0aae2b57460c63d36346392d849b22f39fd3eafad5bc82d01e352dde6`
- `sfrxETH`
  - SPL Token: `6iHW2j5dvW8EiEVSXqQFjm7c5xNd4MdYuXLrW3eQ1UYw`
  - OFT Config: `8AdTghMT8yyNpWrTuPoDjrtXW7t1YEZgLVjWDftWfCxo`
    - As bytes32: `0x6a7942e4eb4938d5490d8187183d01123f515025f4244670aff7f8ecd2250d50`
- `FXS`
  - SPL Token: `8QRvtWw4XYQW7UqTiGhzyWZkhCqSwZDA5qjRWDotSZ4e`
  - OFT Config: `5KYEyuA1cAdnZFj4i6zUjTEre4s7snacyXbkTmNqLjJs`
    - As bytes32: `0x402e86d1cfd2cde4fac63aa8d9892eca6d3c0e08e8335622124332a95df6c10c`
- `FPI`
  - SPL Token: `FqRC7vNLS3ubbhtdqNSz8Q5ei8VdUxF6H6eoXQLHxihr`
  - OFT Config: `BG9oPj76NRPbj1e1GbL4imnqo9VD7W2ukpnRFSWtq5CA`
    - As bytes32: `0x9876880bee04a9020e619b1be124ee307e03ca94bab4f32a7a22cfd2ccee3927`

### Legacy (non-upgradeable) OFTs
- Chain: `Ethereum`, `Metis`, `Blast`, `Base`
- Chain to convert from native token into OFT: Ethereum
- Admin: Chain-respective msig
- OFTs
  - `FRAX`: `0x909DBdE1eBE906Af95660033e478D59EFe831fED`
  - `sFRAX`: `0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E`
  - `frxETH` : `0xF010a7c8877043681D59AD125EbF575633505942`
  - `sfrxETH`: `0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A`
  - `FXS`: `0x23432452B720C80553458496D4D9d7C5003280d0`
  - `FPI`: `0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d`


## New Chain Deployment
- Ensure `PK_OFT_DEPLOYER` and `PK_CONFIG_DEPLOYER` are the private keys for `0x9C9dD956b413cdBD81690c9394a6B4D22afe6745` and `0x0990be6dB8c785FBbF9deD8bAEc612A10CaE814b`, respectively.
- Modify `.env` `RPC_URL` to the new chain RPC
- Add an item to `scripts/L0Config.json:Proxy` with the new chain details (incorrect data will cause the script to fail).
- `source .env && forge script scripts/DeployFraxOFTProtocol.s.sol --rpc-url $RPC_URL`
- Verify files created within `scripts/txs/{SOURCE_CHAIN_ID}-{DESTINATION_CHAIN_ID}.json` are correct peers, config
  - Notably, Fraxtal OFTs are the (s)frxUSD lockbox contracts
- `source .env && forge script scripts/DeployFraxOFTProtocol.s.sol --rpc-url $RPC_URL --broadcast --slow`
- Manually verify each contract on the deployed chain (do not need to verify ImplementationMock)
  - Use `contracts/flat`, Solidity version 0.8.22, default compiler, 200 optimizer runs
- Modify `scripts/tx/{SOURCE_CHAIN_ID}-{DESTINATION_CHAIN_ID}.json` values to so that:
  - `\"` => `"`
  - `"[` => `[`
  - `]"` => `]`

TODO: automatically save as strings.

- Submit each newly crafted json to the respective `DESTINATION_CHAIN_ID` msig. 

## TODO
- Ink, Sonic, Arbitrum, Optimism, Polygon, Avalanche, BSC, Polygon zkEvm
  - Wire (s)frxETH/FPI to legacy Ethereum lockbox
- Solana
  - Configure for Ink, Sonic, Arbitrum, Optimism, Polygon, Avalanche, BSC, Polygon zkEvm, Ethereum (s)frxUSD, Fraxtal lockboxes

## 1) Developing Contracts

#### Installing dependencies

We recommend using `pnpm` as a package manager (but you can of course use a package manager of your choice):

```bash
pnpm install
```

#### Compiling your contracts

This project supports both `hardhat` and `forge` compilation. By default, the `compile` command will execute both:

```bash
pnpm compile
```

If you prefer one over the other, you can use the tooling-specific commands:

```bash
pnpm compile:forge
pnpm compile:hardhat
```

Or adjust the `package.json` to for example remove `forge` build:

```diff
- "compile": "$npm_execpath run compile:forge && $npm_execpath run compile:hardhat",
- "compile:forge": "forge build",
- "compile:hardhat": "hardhat compile",
+ "compile": "hardhat compile"
```

#### Running tests

Similarly to the contract compilation, we support both `hardhat` and `forge` tests. By default, the `test` command will execute both:

```bash
pnpm test
```

If you prefer one over the other, you can use the tooling-specific commands:

```bash
pnpm test:forge
pnpm test:hardhat
```

Or adjust the `package.json` to for example remove `hardhat` tests:

```diff
- "test": "$npm_execpath test:forge && $npm_execpath test:hardhat",
- "test:forge": "forge test",
- "test:hardhat": "$npm_execpath hardhat test"
+ "test": "forge test"
```

## 2) Deploying Contracts

Set up deployer wallet/account:

- Rename `.env.example` -> `.env`
- Choose your preferred means of setting up your deployer wallet/account:

```
MNEMONIC="test test test test test test test test test test test junk"
or...
PRIVATE_KEY="0xabc...def"
```

- Fund this address with the corresponding chain's native tokens you want to deploy to.

To deploy your contracts to your desired blockchains, run the following command in your project's folder:

```bash
npx hardhat lz:deploy
```

More information about available CLI arguments can be found using the `--help` flag:

```bash
npx hardhat lz:deploy --help
```

By following these steps, you can focus more on creating innovative omnichain solutions and less on the complexities of cross-chain communication.

<br></br>

<p align="center">
  Join our community on <a href="https://discord-layerzero.netlify.app/discord" style="color: #a77dff">Discord</a> | Follow us on <a href="https://twitter.com/LayerZero_Labs" style="color: #a77dff">Twitter</a>
</p>
