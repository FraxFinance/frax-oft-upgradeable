# SafeOnchainExec

Execute Safe Transaction-Builder JSON batches on a chain with **no hosted Safe UI / transaction service**, using only an RPC:
pack → `MultiSendCallOnly` → EIP-712 `safeTxHash` → owners `approveHash` on-chain → anyone `execTransaction`.

Full step-by-step (Mode Safe `0x6336…Eaa66`): see [`MODE-SAFE-ONCHAIN-EXEC.md`](../../../MODE-SAFE-ONCHAIN-EXEC.md) at the repo root.

```
build-safe-batches.sh <config>                       # deterministic: out/batch-NN.json, .decoded.md, SUMMARY.md, COMMANDS.md
simulate-safe-batches.sh <config> [--only NN]        # anvil fork end-to-end + post-condition checks -> SIMULATION.md
exec-safe-batch.sh <config> NN --approvers a,b,c --sender s [--send --ledger]
decode-multisend.sh <config> <hex|batch.json> --nonce N
```
To reuse for another Safe/chain: copy `config/34443-0x6336.json`, change `safe`, `chainId`, `rpc`, `multiSendCallOnly` (canonical v1.3.0 `0x40A2aCCbd92BCA938b02010E17A5b8929b49130D` on most chains), `startNonce`, `inputsDir`, `groups`; drop JSONs + `MANIFEST.tsv` into `inputsDir`. Requires a Safe v1.3.0 (hash typehashes are 1.3.0's; 1.4.1 uses the same SafeTx typehash and domain, so it works there too) and bash 3.2+, jq, Foundry.
