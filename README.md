<p align="center">
  <a href="https://layerzero.network">
    <img alt="LayerZero" style="width: 400px" src="https://docs.layerzero.network/img/LayerZero_Logo_White.svg"/>
  </a>
</p>

<p align="center">
  <a href="https://layerzero.network" style="color: #a77dff">Homepage</a> | <a href="https://docs.layerzero.network/" style="color: #a77dff">Docs</a> | <a href="https://layerzero.network/developers" style="color: #a77dff">Developers</a>
</p>

<h1 align="center">OFT Example</h1>

<p align="center">
  <a href="https://docs.layerzero.network/v2/developers/evm/oft/quickstart" style="color: #a77dff">Quickstart</a> | <a href="https://docs.layerzero.network/contracts/oapp-configuration" style="color: #a77dff">Configuration</a> | <a href="https://docs.layerzero.network/contracts/options" style="color: #a77dff">Message Execution Options</a> | <a href="https://docs.layerzero.network/contracts/endpoint-addresses" style="color: #a77dff">Endpoint Addresses</a>
</p>

<p align="center">Template project for getting started with LayerZero's <code>OFT</code> contract development.</p>

```
carter@laptop:~/Documents/frax/frax-oft-upgradeable$ forge verify-contract --rpc-url $MODE_RPC_URL --constructor-args $(cast abi-encode "constructor(address)" 0x1a44076050125825900e736c501f859c50fE728c) --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/34443/etherscan' --etherscan-api-key "verifyContract" --chain-id 34443 0x90a706775489D190256D0C721fC6eA3Df64904d0 contracts/FraxOFTUpgradeable.sol:FraxOFTUpgradeable --watch
Start verifying contract `0x90a706775489D190256D0C721fC6eA3Df64904d0` deployed on mode

Submitting verification for [contracts/FraxOFTUpgradeable.sol:FraxOFTUpgradeable] 0x90a706775489D190256D0C721fC6eA3Df64904d0.
Submitted contract for verification:
	Response: `OK`
	GUID: `fdbc2830-068c-5ab7-8814-76ed815b7cdc`
	URL: https://explorer.mode.network/address/0x90a706775489d190256d0c721fc6ea3df64904d0
Contract verification status:
Response: `NOTOK`
Details: `Pending in queue`
Contract verification status:
Response: `NOTOK`
Details: `Pending in queue`
Contract verification status:
Response: `NOTOK`
Details: `Error: contract does not exist`



carter@laptop:~/Documents/frax/frax-oft-upgradeable$ forge verify-contract --rpc-url $MODE_RPC_URL --constructor-args 0x0000000000000000000000006336CFA6eDBeC2A459d869031DB77fC2770Eaa66 --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/34443/etherscan' --etherscan-api-key "verifyContract" --chain-id 34443 0xb65c2079dfed58b7a6e472c0d6971605023ec6a9 node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/ProxyAdmin.sol:ProxyAdmin
Start verifying contract `0xb65c2079dfed58B7a6E472c0d6971605023ec6A9` deployed on mode
Error: 
Failed to get standard json input

Context:
- cannot resolve file at "/home/carter/Documents/frax/frax-oft-upgradeable/node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/ProxyAdmin.sol"


```

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
