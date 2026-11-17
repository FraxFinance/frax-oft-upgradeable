# OFT rate limits

OFT v1.2.0 adds a rate limiter to every OFT and lockbox in the mesh. The upgrade leaves it off,
so nothing changes until we choose limits. This folder holds those limits and the tooling to
apply and change them:

- `rate-limits.json` is the source of truth: the desired limits for every token on every chain.
- `rate_limits.py` reads the live chains, diffs them against that file, and writes one Safe
  Transaction Builder batch per chain and owner Safe. Each batch makes its chain match the file.

The tool never signs or sends anything. Every call it writes has been simulated from its real
owner first.

```bash
# from the repo root; Python 3.9+, standard library only
python3 scripts/ops/RateLimits/rate_limits.py status --chains fraxtal --tokens frxUSD   # what is live
python3 scripts/ops/RateLimits/rate_limits.py plan                                      # what would change
python3 scripts/ops/RateLimits/rate_limits.py plan --write --label 2026-12-01-frxusd    # write the batches
python3 scripts/ops/RateLimits/rate_limits.py check                                     # after execution: exit 0 = matches
```

## How the limiter works

### The problem it solves

A bridge mints or releases tokens because a message says tokens were burned or locked somewhere
else. If one lane's verification is compromised (a DVN set, a peer, a bug), the attacker can mint
as fast as they can send messages. A rate limit caps how much value can cross a lane per unit of
time. A compromise then drains at a known, bounded speed, and we have time to react.

### Two buckets per lane

Each OFT keeps, for every remote endpoint id (eid), an **outbound** bucket and an **inbound**
bucket. Sending to an eid uses its outbound bucket; receiving from it uses its inbound bucket.
Each bucket has a `limit` and a `window`. Usage refills continuously at `limit / window` per
second. It is not a calendar day that resets at midnight.

Take Arbitrum frxUSD with outbound 1,000,000 per `1d`. A user who sends 600,000 leaves
400,000 available. Twelve hours later half the limit has refilled: usage is 100,000 and
900,000 is available. A day after the send the bucket is full again.

### Where a limit bites

Outbound limits are checked in `send` on the source chain, so an oversized transfer simply
reverts with `RateLimitExceeded` and the user keeps their tokens. `quoteOFT()` reports the
remaining outbound capacity in `oftLimit.maxAmountLD`, so a UI can show it before the user signs.

Inbound limits are checked in `lzReceive` on the destination. The tokens have already left the
source by then, so an over-limit delivery reverts and **stays at the destination endpoint as a
retryable message**. Nothing is lost, but someone has to retry it after the bucket refills (LayerZero
Scan, or `endpoint.lzReceive` with the original payload).

That asymmetry drives the advice in [Choosing limits](#choosing-limits).

### Default and per-peer limits

Each OFT has one **default** config that applies to every eid, plus optional **per-peer
overrides**. An override replaces the default for that eid in both directions. The contract
stores the full config, so an override that sets only outbound also turns inbound off for that
peer. The config format avoids this trap: in `rate-limits.json` a direction you leave out of a
peer entry is copied from the default (see [Config reference](#config-reference)).

There is also a per-OFT **global switch** (`isGloballyDisabled`). Turning it on bypasses every
limit on that OFT at once but keeps all the configs. It is the quickest way to unblock everything
in an emergency.

### What a change does to usage already in the bucket

Changing a lane's config first settles its usage under the old config, then clamps it to the new
limit. In practice:

- Raising a limit keeps the usage and adds headroom immediately.
- Lowering a limit below the current usage leaves the lane exhausted until it refills. `plan`
  prints these cases as `impact:` lines.
- Enabling a direction starts with an empty bucket, so the full limit is available. Disabling a
  direction discards its usage.

### Units, validation and ownership

Limits are stored in the OFT's local base units. That is 18 decimals everywhere except **Tempo
frxUSD, which is a 6-decimal TIP-20**. `rate-limits.json` is written in whole tokens and the tool
converts per chain using decimals it reads live (and cross-checks), so the same
`"1_000_000"` is right on every chain.

The contract rejects an enabled direction with `window == 0` or `limit < window` (in base units:
at least one unit of refill per second). The tool checks this before it writes anything.

Every setter is `onlyOwner`, meaning the OFT's owner Safe on that chain. No timelock is involved.
On Ethereum the frxUSD lockbox is owned by `0xfFFffF4F…3937` and the other Ethereum OFTs by
`0xB1748C…3f27`, so an Ethereum change can need two batches. The tool reads `owner()` live and
groups calls by owner.

### Registering lanes before arming them

The first time the limiter writes state for an eid, it also appends that eid to an internal list
(used to settle lanes when the default changes). That one-time write is expensive. If it lands
inside `lzReceive`, it can push the first delivery past the lane's enforced gas. Measured on a
fork of the Fraxtal frxUSD lockbox (`eth_estimateGas` for 1 frxUSD from Arbitrum, intrinsic gas
included):

| limiter state | gas | vs off |
| --- | ---: | ---: |
| limits off | 109,489 | |
| armed, eid already registered | 119,215 | +9,726 |
| armed, eid never written | 181,140 | +71,651 |

The endpoint's own overhead and a first-time recipient come on top, against 200k of enforced gas
on lockbox lanes. So `plan` adds `checkpointRateLimits([...])` for every peered eid that is about
to be armed and has never been written. That moves the one-time write into the owner's
transaction. This mirrors `scripts/DeployFraxOFTProtocol/inherited/SetRateLimits.s.sol`. After
that, an armed lane costs about 10k gas more per delivery. Tempo prices new storage far higher
than other chains, which makes registering in advance even more important there.

## What a limit limits in this mesh

The mesh is hub-and-spoke. Every spoke, Ethereum included, peers only with **Fraxtal**. Fraxtal
peers with every chain, including Solana. So:

- On a spoke, the default config is effectively its one lane, to and from Fraxtal (eid 30255).
- On Fraxtal, the default covers every spoke lane. Per-peer entries carve out the big lanes
  (Ethereum, Base, …).
- One lane involves four settings. For Arbitrum: Arbitrum outbound and inbound for eid 30255,
  and Fraxtal outbound and inbound for eid 30110.

A spoke-to-spoke transfer goes through the Fraxtal hop, so it consumes two lanes. Its second leg
is sent from inside `lzCompose` on Fraxtal. If Fraxtal's outbound bucket toward the destination
is empty, that compose reverts and waits at Fraxtal's endpoint until someone retries it.

On the mintable lockboxes (Fraxtal and Ethereum frxUSD and sfrxUSD, and Tempo frxUSD), the v1.2.0
supply guard runs as well. A delivery has to pass both the guard and the rate limit.

Solana's OFT program has its own per-peer token bucket (`capacity`, `refill_per_second`, set
through Squads with `set_peer_config`). This tool does not manage it. It does manage Fraxtal's
side of the Solana lane.

## Choosing limits

The team still has to decide the numbers. These are the mechanics worth knowing:

- **Inbound limits protect a chain from its peer.** A forged mint arriving over a compromised
  lane is capped by the receiving side's inbound limit, and only by that.
- **Outbound limits protect users.** They stop an oversized transfer at the source, before the
  tokens are in flight.
- **Give each inbound limit headroom over the far side's outbound limit, on the same window.**
  If a destination admits less than its source lets out, transfers can clear the source and then
  get stuck. Delivery delays (DVN latency or an outage) can also bunch messages together. A
  destination that is exactly as strict as its source can then still overflow. `plan` and
  `check` lint every lane whose two ends they read. They warn when inbound is below outbound +
  10% (`--inbound-headroom`), when inbound refills more slowly, or when a lane has an inbound
  limit and no outbound limit.
- Windows between 1 hour and 7 days are the sane range. A short window turns a limit into a
  per-transfer cap; a long window makes recovery after a burst slow.

`examples/example.json` shows a lane-consistent shape (the numbers are placeholders). It passes
the lint.

## Config reference

```jsonc
{
  "schema": 1,
  "tokens": {
    "frxUSD": {                                  // WFRAX, sfrxUSD, sfrxETH, frxUSD, frxETH
      "*": {                                     // every chain not listed, and unset fields of listed ones
        "default": {
          "outbound": { "limit": "2_000_000", "window": "1d" },
          "inbound":  { "limit": "2_200_000", "window": "1d" }
        }
      },
      "fraxtal": {                               // chain name or chain id
        "peers": {                               // per-peer overrides (peer name or chain id)
          "ethereum": { "outbound": { "limit": "25_000_000", "window": "1d" } },  // inbound copied from default
          "solana":   { "inbound": "off" }
        }
      },
      "tempo": { "globallyDisabled": true }      // emergency bypass on this OFT only
    }
  }
}
```

- **Tokens** are keyed by symbol, case-insensitive. A token missing from the file means no limits
  for it anywhere, and the tool will remove limits that are live.
- **Chains** are keyed by name (`fraxtal`, `ethereum`, `base`, `arbitrum`, `tempo`, …; run
  `status` for the list) or numeric chain id. `"*"` is the base for every chain. A chain entry
  overrides `"*"` field by field (`globallyDisabled`, `default`, `peers`), with no deep merge.
  For example, `"tempo": {"globallyDisabled": true}` keeps the `"*"` default on Tempo.
- **`default`** sets both directions. A direction left out is `off`.
- **`peers`** writes one on-chain override per listed peer. A direction left out of a peer entry is
  copied from the chain's default, and kept in sync when the default changes. `"off"` disables
  that direction for that peer only. Remove the peer entry to clear its override.
- **A direction** is `"off"`, `"blocked"`, or `{"limit": <whole tokens>, "window": <duration>}`.
  `"blocked"` writes the smallest limit the contract allows (one base unit per second), which
  stops the direction in practice without touching peers.
- **Amounts** are strings or integers in whole tokens. `_` is allowed as a separator; floats and
  exponents are rejected. **Windows** are seconds, or `30min`, `12h`, `1d`, `1w`. `m` is
  rejected as ambiguous.
- `note` keys are allowed on any object and ignored.

The whole file is authoritative. On every v1.2.0 OFT the tool proposes exactly what the file
implies. That includes clearing overrides and limits that someone set on-chain by hand, so keep
the file in git and change it through review.

## Workflow

1. **Edit `rate-limits.json`** in a PR.
2. **`plan`.** For each chain and owner it prints the calls, from → to in tokens, the lanes whose
   usage gets clamped, the lane lint, and an `eth_call` simulation of every call as the owner,
   with gas estimates. Add `--fork-sim` to also execute the batches on an anvil fork and re-read
   the result (anvil cannot fork Somnia, zkSync or Abstract; those keep the `eth_call` check).
3. **`plan --write --label <name>`.** This writes `txs/<name>/` with
   `RateLimits-<chainid>-<owner>.json` per Safe, `summary.md` for signers, and `plan.json`
   (machine-readable, including the raw calldata). It refuses to write if any simulation fails,
   any OFT errors, or a chain is unreachable (`--skip-unreachable` writes the rest).
4. **Propose each batch on its Safe.** Use Transaction Builder import or the `safe-msig-queue`
   tooling. `summary.md` maps each file to its Safe.
5. **Execute, then run `check`.** Exit 0 means every chain matches the file.

Batches set absolute values, so executing an older batch after a newer one rolls the change back.
Reject superseded proposals, and re-run `plan` if something changed on-chain in between.

`check` exit codes: `0` matches, `1` drift (or `--strict` lint warnings), `2` unreachable chain
or config error. A non-zero result is also how you spot a peer wired after limits were enabled:
its eid shows up as unregistered drift.

## Runbooks

**First enable after the v1.2.0 upgrade.** Fill in `rate-limits.json`, then
`plan --fork-sim`, then `plan --write`. Fraxtal's first batch registers every peered eid
(`checkpointRateLimits`) before setting the default. OFTs still on v1.1.0 are listed as
*pending*; re-run `plan` once they are upgraded.

**Change a limit.** Edit, `plan`, `plan --write`. Check the `impact:` lines: lowering a limit
under current usage exhausts the lane until it refills.

**Onboard a chain or wire a new peer.** Add the chain to the mesh as usual (`L0Config.json`,
plus `L0Constants.sol` if its OFT addresses are non-standard), then run `plan`. The new eid is
registered on Fraxtal and the config is applied on the new chain. Run this before real traffic
flows, so the first delivery does not pay the registration write. Until you add the chain's name
to `CHAINS` in `rate_limits.py`, refer to it by chain id.

**Emergency: a limit is blocking legitimate flow.** The fastest fix for one OFT is
`"globallyDisabled": true` in its entry (or in `"*"` for all chains), then `plan --write`. That
is a single call per OFT. Raising the specific limit is the narrower fix.

**Emergency: stop a lane direction.** Set it to `"blocked"`, then `plan --write`. Remember that
blocking inbound strands messages that are already in flight. They stay retryable.

**Unblock one lane right now without changing limits.**

```bash
python3 scripts/ops/RateLimits/rate_limits.py reset-usage --chain fraxtal --token frxUSD \
    --peer arbitrum --direction outbound --write
```

This writes `setRateLimitStates` with the chosen direction(s) zeroed. A direction you keep is
written with its value at the read block and keeps decaying from there. Afterwards, retry any
stuck inbound messages at the destination endpoint.

**Remove all limits.** Empty `tokens`, then `plan --write`.

## Monitoring

`status` shows used and limit per lane in tokens, whether each peered eid is registered, and any
drift. `--json <file>` writes the same as JSON. `check` is suitable for cron or CI. On-chain, each
consumption emits `RateLimitConsumed(eid, isOutbound, amount, usage, limit)` and an over-limit
transfer reverts with `RateLimitExceeded(eid, isOutbound, amount, available)`. An alert at about
80% usage per lane would be a natural next step for the mesh dashboard.

## What the tool checks, and where it stops

Before writing anything it:

- reads each chain in two Multicall3 round trips at the latest block (Somnia has no Multicall3 and
  gets parallel calls);
- requires the OFT's decimals (`sharedDecimals` × `decimalConversionRate`) to match the token's
  `decimals()`;
- detects the limiter by calling `rateLimitGlobalConfig()`, which only exists from v1.2.0;
- requires every owner to be a Safe;
- mirrors the contract's validation;
- simulates every call with `eth_call` from the owner, and optionally with `--fork-sim`.

The setters revert only on bad input or a non-owner caller, never because of state an earlier call
in the same batch changed, so simulating call by call covers the batch.

Limits worth knowing:

- Overrides can only be seen on the eids the tool probes. That is every eid in
  `scripts/L0Config.json` plus the retired chains' eids. The contract has no getter for the full
  list.
- Solana's own limits are out of scope (see above).
- Nothing stops an outdated batch from being executed, so retire superseded proposals.
- The lane lint only covers lanes whose two ends were read, so run `check` without `--chains`
  for the full picture.
- RPCs come from `scripts/L0Config.json`. Override one with `RPC_URL_<chainid>=…` or
  `--rpc <chainid>=<url>`.

## Tests

```bash
python3 -m unittest scripts/ops/RateLimits/test_rate_limits.py      # offline; ABI vectors from cast
python3 scripts/ops/RateLimits/e2e_fork_test.py                      # anvil + network, ~1 min
```

The fork test points real proxies on Fraxtal, Arbitrum, Ethereum and Tempo forks at their pinned
v1.2.0 implementations (`scripts/ops/V120/implementations/`). It then runs the CLI through
enable → modify → reset usage → remove → `--fork-sim`, executes every written batch as its real
owner Safe, and requires `check` to be clean and a re-plan to be empty after each step. It also
reproduces the gas table above.

`fork-apply --rpc-url <anvil> --batch <file>` replays any batch on your own anvil fork. It refuses
to talk to anything that is not anvil.
