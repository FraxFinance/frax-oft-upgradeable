# Tempo Network Integration

This module contains contracts and utilities for integrating with Tempo Network's precompiles and TIP-20 token standard.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    TEMPO NETWORK                                            │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              PRECOMPILES (System Contracts)                          │   │
│  │                                                                                      │   │
│  │  ┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────────┐   │   │
│  │  │   TIP403_REGISTRY   │    │   STABLECOIN_DEX    │    │     TIP_FEE_MANAGER     │   │   │
│  │  │  (0xfeEC...0403)    │    │    (0xDEc0...)      │    │      (0xfeEC...)        │   │   │
│  │  │                     │    │                     │    │                         │   │   │
│  │  │ • createPolicy()    │    │ • swapExactAmountIn │    │ • userTokens(addr)      │   │   │
│  │  │ • modifyBlacklist() │    │ • placeOrder()      │    │ • setUserToken()        │   │   │
│  │  │ • isAuthorized()    │    │ • fillOrders()      │    │                         │   │   │
│  │  └─────────────────────┘    └─────────────────────┘    └─────────────────────────┘   │   │
│  │            ▲                          ▲                            │                 │   │
│  └────────────│──────────────────────────│────────────────────────────│─────────────────┘   │
│               │                          │                            │                     │
│               │ (2) Check policy         │ (5b) Swap TIP20→PATH_USD   │ (4) Get user's      │
│               │     on transfer          │      (if not whitelisted)  │     gas token       │
│               │                          │                            ▼                     │
│  ┌────────────┴──────────────┐    ┌──────┴───────────────────────────────────────────────┐  │
│  │                           │    │                                                      │  │
│  │   FrxUSDPolicyAdminTempo  │    │  FraxOFTMintableAdapterUpgradeableTIP20              │  │
│  │      (Proxy Contract)     │    │  FraxOFTUpgradeableTempo                             │  │
│  │                           │    │                  (Proxy Contracts)                   │  │
│  │  • policyId (BLACKLIST)   │    │                                                      │  │
│  │  • freeze(account)        │    │  • innerToken (frxUSD TIP20)                         │  │
│  │  • thaw(account)          │    │  • endpoint (LayerZero EndpointV2Alt)                │  │
│  │  • addFreezer(account)    │    │  • nativeToken (LZEndpointDollar)                    │  │
│  │                           │    │                                                      │  │
│  │  (1) Calls                │    │  _debit():                                           │  │
│  │      modifyBlacklist()    │    │    (6) transferFrom(user → adapter)                  │  │
│  │      to freeze/thaw       │    │    (7) burn(amount)                                  │  │
│  │                           │    │                                                      │  │
│  └───────────────────────────┘    │  _credit():                                          │  │
│               │                   │    (8) mint(to, amount)                              │  │
│               │                   │                                                      │  │
│               │                   │  _payNative():                                       │  │
│               │                   │    (4) Check userTokens(msg.sender)                  │  │
│               │                   │    (5a) If whitelisted in LZEndpointDollar → wrap    │  │
│               │                   │    (5b) Else swap to PATH_USD, then wrap             │  │
│               │                   │    (9) Send message to LayerZero                     │  │
│               │                   └──────────────────────────────────────────────────────┘  │
│               │                                    │                                        │
│               │                                    │ (5a/5b) wrap()                         │
│               │                                    ▼                                        │
│               │                   ┌──────────────────────────────────────────────────────┐  │
│               │                   │              LZEndpointDollar                        │  │
│               │                   │                                                      │  │
│               │                   │  • wrap(token, to, amount) - wraps whitelisted token │  │
│               │                   │  • unwrap(token, to, amount) - unwraps to token      │  │
│               │                   │  • isWhitelistedToken(token) - check if allowed      │  │
│               │                   │  • decimals() - token decimals                       │  │
│               │                   │                                                      │  │
│               │                   │  Whitelisted tokens can be wrapped directly.         │  │
│               │                   │  Non-whitelisted tokens must swap to PATH_USD first. │  │
│               │                   └──────────────────────────────────────────────────────┘  │
│               │                                    │                                        │
│               ▼                                    ▼                                        │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                       │  │
│  │                              frxUSD TIP20 Token (Precompile)                          │  │
│  │                                                                                       │  │
│  │  • transfer(to, amount)  ──────► Checks TIP403_REGISTRY.isAuthorized(policyId, user)  │  │
│  │  • transferFrom(from, to, amount)           │                                         │  │
│  │  • mint(to, amount)                         │ If on BLACKLIST → revert PolicyForbids  │  │
│  │  • burn(amount)                             │ If not on BLACKLIST → allow transfer    │  │
│  │  • changeTransferPolicyId(policyId)         │                                         │  │
│  │                                             ▼                                         │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              │ (9) LayerZero Message
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              OTHER CHAIN (Ethereum, Fraxtal, etc.)                          │
│                                                                                             │
│                         FraxOFTMintableAdapterUpgradeable / Lockbox                         │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Components

### FrxUSDPolicyAdminTempo

Admin contract for managing freeze/thaw operations via TIP-403 Registry.

- Creates a **BLACKLIST** policy on initialization
- **Freeze**: Adds account to blacklist → cannot send or receive tokens
- **Thaw**: Removes account from blacklist → can transfer normally
- Supports freezer roles for delegated freeze operations

### FraxOFTMintableAdapterUpgradeableTIP20

LayerZero OFT adapter for bridging TIP-20 tokens with mint/burn capability.

- **Send (Tempo → Other Chain)**: Burns tokens on Tempo, mints on destination
- **Receive (Other Chain → Tempo)**: Mints tokens on Tempo
- **Gas Payment**: Uses `LZEndpointDollar` for wrapping gas tokens (see Gas Payment Flow below)

### FraxOFTUpgradeableTempo

LayerZero OFT for Tempo that pays gas in ERC20 native token via EndpointV2Alt.

- Inherits from `FraxOFTUpgradeable` with Tempo-specific gas payment logic
- Same gas payment flow as `FraxOFTMintableAdapterUpgradeableTIP20`

### LZEndpointDollar

Wrapper contract for LayerZero EndpointV2Alt's native token. Manages whitelisted stablecoins that can be used for gas payment.

- **wrap(token, to, amount)**: Wraps a whitelisted token and sends to recipient
- **unwrap(token, to, amount)**: Unwraps back to the original token
- **isWhitelistedToken(token)**: Checks if a token is whitelisted for wrapping
- **decimals()**: Returns the token decimals

### Precompiles

| Precompile | Address | Purpose |
|------------|---------|---------|
| TIP403_REGISTRY | `0xfeEC...0403` | Transfer policy management (whitelist/blacklist) |
| STABLECOIN_DEX | `0xDEc0...` | Swap between TIP-20 stablecoins |
| TIP_FEE_MANAGER | `0xfeEC...` | Manage user's preferred gas token |
| TIP20_FACTORY | `0x20Fc...` | Create new TIP-20 tokens |
| PATH_USD | `0x20C0...` | Default whitelisted gas token on Tempo |

## Flows

### Freeze/Thaw Flow

1. Owner/Freezer calls `FrxUSDPolicyAdminTempo.freeze(alice)`
2. PolicyAdmin calls `TIP403_REGISTRY.modifyPolicyBlacklist(policyId, alice, true)`
3. When alice tries `frxUSD.transfer()`, TIP20 checks `TIP403_REGISTRY.isAuthorized()`
4. Alice is on blacklist → **PolicyForbids** error

### Gas Payment Flow

The OFT contracts use `LZEndpointDollar` to handle gas payment with whitelisted tokens:

1. Get user's preferred gas token via `TIP_FEE_MANAGER.userTokens(msg.sender)`
2. Check if `userToken` is whitelisted in `LZEndpointDollar`:
   - **If whitelisted**: Wrap `userToken` directly via `LZEndpointDollar.wrap()`
   - **If not whitelisted**: Check if `PATH_USD` is whitelisted:
     - **If PATH_USD whitelisted**: Swap `userToken` → `PATH_USD` via `STABLECOIN_DEX`, then wrap
     - **If PATH_USD not whitelisted**: Revert with `UnsupportedGasToken`
3. Wrapped tokens are sent to the LayerZero endpoint for gas payment

### Bridge Send Flow (Tempo → Other Chain)

1. User calls `adapter.send(dstEid, to, amount, options)`
2. `_debit()`: Pull tokens from user, burn them
3. `_payNative()`: Handle gas payment via LZEndpointDollar (see Gas Payment Flow)
4. Send LayerZero message to destination chain

### Bridge Receive Flow (Other Chain → Tempo)

1. LayerZero delivers message to adapter
2. `_credit()`: Mint tokens to recipient
