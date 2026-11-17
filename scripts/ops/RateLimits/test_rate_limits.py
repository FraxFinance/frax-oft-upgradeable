#!/usr/bin/env python3
"""Offline unit tests for rate_limits.py (no network).

    python3 -m unittest scripts/ops/RateLimits/test_rate_limits.py -v

ABI vectors were produced independently with `cast calldata` / `cast abi-encode` (Foundry 1.9) and
selectors cross-checked against `forge inspect ... methodIdentifiers`. The fork test
(e2e_fork_test.py) runs the same code against the real v1.2.0 bytecode.
"""

import copy
import os
import sys
import unittest
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rate_limits as rl  # noqa: E402

DAY = 86400
E18 = 10 ** 18


class KeccakAndSelectors(unittest.TestCase):
    def test_keccak_vectors(self):
        self.assertEqual(rl.keccak256(b"").hex(), "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        self.assertEqual(rl.keccak256(b"abc").hex(), "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        # Padding edges around the 136-byte rate, and a multi-block input.
        self.assertEqual(rl.keccak256(b"a" * 135).hex(), "34367dc248bbd832f4e3e69dfaac2f92638bd0bbd18f2912ba4ef454919cf446")
        self.assertEqual(rl.keccak256(b"a" * 136).hex(), "a6c4d403279fe3e0af03729caada8374b5ca54d8065329a3ebcaeb4b60aa386e")
        self.assertEqual(rl.keccak256(b"a" * 200).hex(), "96ea54061def936c4be90b518992fdc6f12f535068a256229aca54267b4d084d")

    def test_selectors_match_compiled_abi(self):
        expected = {
            "setRateLimitGlobalConfig": "b21f9c32", "setDefaultRateLimitConfig": "70e1a938",
            "setRateLimitConfigs": "f6daa770", "setRateLimitStates": "d43a23c3", "checkpointRateLimits": "77900ae2",
            "rateLimitGlobalConfig": "a666f224", "defaultRateLimitConfig": "361e7dac",
            "storedRateLimitConfig": "c192b814", "storedRateLimitState": "015bd6dc", "rateLimitState": "c8c5038e",
            "peers": "bb0b6a53", "aggregate3": "82ad56cb", "getThreshold": "e75235b8", "getOwners": "a0e67e2b",
        }
        for name, sel in expected.items():
            self.assertEqual(rl.SEL[name].hex(), sel, name)

    def test_checksum(self):
        self.assertEqual(rl.checksum("0x5f25218ed9474b721d6a38c115107428e832fa2e"), "0x5f25218ed9474b721d6a38c115107428E832fA2E")
        self.assertEqual(rl.checksum("0xffffff4f3bac444b2c0ecf2a1840d018be783937"), "0xfFFffF4F3baC444b2C0ecf2A1840d018bE783937")
        # EIP-55 reference vector
        self.assertEqual(rl.checksum("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"), "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")


class Encoding(unittest.TestCase):
    def test_set_default(self):
        config = rl.RLConfig(False, rl.Direction(True, 1_000_000 * E18, DAY), rl.Direction(True, 1_250_000 * E18, DAY // 2))
        # cast calldata "setDefaultRateLimitConfig((bool,bool,bool,uint32,uint32,uint112,uint112))" \
        #   "(false,true,true,86400,43200,1000000000000000000000000,1250000000000000000000000)"
        self.assertEqual("0x" + rl.calldata_set_default(config).hex(),
                         "0x70e1a938000000000000000000000000000000000000000000000000000000000000000000000000000000"
                         "0000000000000000000000000000000000000000000000000100000000000000000000000000000000000000"
                         "0000000000000000000000000100000000000000000000000000000000000000000000000000000000000151"
                         "80000000000000000000000000000000000000000000000000000000000000a8c00000000000000000000000"
                         "0000000000000000000000d3c21bcecceda10000000000000000000000000000000000000000000000000108"
                         "b2a2c2802909400000")

    def test_set_configs(self):
        params = [(30101, rl.RLConfig(True, rl.Direction(True, 5_000_000_000, 3600), rl.OFF)), (30168, rl.EMPTY)]
        expected = ("0xf6daa770" + "20".rjust(64, "0") + "2".rjust(64, "0") + "7595".rjust(64, "0")
                    + "1".rjust(64, "0") + "1".rjust(64, "0") + "0".rjust(64, "0") + "e10".rjust(64, "0")
                    + "0".rjust(64, "0") + "12a05f200".rjust(64, "0") + "0".rjust(64, "0")
                    + "75d8".rjust(64, "0") + "0" * 64 * 7)
        self.assertEqual("0x" + rl.calldata_set_configs(params).hex(), expected)

    def test_set_states_checkpoint_global(self):
        self.assertEqual("0x" + rl.calldata_set_states([(30110, 0, 123456789, 1794877200)]).hex(),
                         "0xd43a23c3" + "20".rjust(64, "0") + "1".rjust(64, "0") + "759e".rjust(64, "0")
                         + "0".rjust(64, "0") + "75bcd15".rjust(64, "0") + "6afba710".rjust(64, "0"))
        self.assertEqual("0x" + rl.calldata_checkpoint([30110, 30111, 30168]).hex(),
                         "0x77900ae2" + "20".rjust(64, "0") + "3".rjust(64, "0") + "759e".rjust(64, "0")
                         + "759f".rjust(64, "0") + "75d8".rjust(64, "0"))
        self.assertEqual("0x" + rl.calldata_set_global(True).hex(), "0xb21f9c32" + "1".rjust(64, "0"))

    def test_aggregate3_roundtrip(self):
        calls = [("0x96A394058E2b84A89bac9667B19661Ed003cF5D4", bytes.fromhex("a666f224")),
                 ("0x80Eede496655FB9047dd39d9f418d5483ED600df", bytes.fromhex("c192b814" + "7595".rjust(64, "0")))]
        self.assertEqual(
            "0x" + rl.encode_aggregate3(calls).hex(),
            "0x82ad56cb" + "20".rjust(64, "0") + "2".rjust(64, "0") + "40".rjust(64, "0") + "e0".rjust(64, "0")
            + "96a394058e2b84a89bac9667b19661ed003cf5d4".rjust(64, "0") + "1".rjust(64, "0") + "60".rjust(64, "0")
            + "4".rjust(64, "0") + "a666f224".ljust(64, "0")
            + "80eede496655fb9047dd39d9f418d5483ed600df".rjust(64, "0") + "1".rjust(64, "0") + "60".rjust(64, "0")
            + "24".rjust(64, "0") + ("c192b814" + "7595".rjust(64, "0")).ljust(128, "0"))
        returned = bytes.fromhex(
            "20".rjust(64, "0") + "3".rjust(64, "0") + "60".rjust(64, "0") + "e0".rjust(64, "0") + "140".rjust(64, "0")
            + "1".rjust(64, "0") + "40".rjust(64, "0") + "20".rjust(64, "0") + "1".rjust(64, "0")
            + "0".rjust(64, "0") + "40".rjust(64, "0") + "0".rjust(64, "0")
            + "1".rjust(64, "0") + "40".rjust(64, "0") + "2".rjust(64, "0") + "1234".ljust(64, "0"))
        self.assertEqual(rl.decode_aggregate3(returned),
                         [(True, (1).to_bytes(32, "big")), (False, b""), (True, bytes.fromhex("1234"))])

    def test_decode_config_and_revert(self):
        config = rl.RLConfig(True, rl.Direction(True, 7, 5), rl.Direction(False, 0, 0))
        self.assertEqual(rl.decode_config(rl.encode_config(config)), config)
        with self.assertRaises(rl.DecodeError):
            rl.decode_config(rl.word(2) + rl.word(0) * 6)
        self.assertEqual(rl.decode_revert("0x973190b6"), "InvalidRateLimitConfig()")
        ownable = ("0x08c379a0" + "20".rjust(64, "0") + "20".rjust(64, "0")
                   + "4f776e61626c653a2063616c6c6572206973206e6f7420746865206f776e6572")
        self.assertEqual(rl.decode_revert(ownable), "Error('Ownable: caller is not the owner')")

    def test_decode_version(self):
        self.assertEqual(rl.decode_version(rl.word(1) + rl.word(0) + rl.word(0)), "v1.0.0")
        encoded = rl.word(0x20) + rl.word(5) + b"1.2.0".ljust(32, b"\x00")
        self.assertEqual(rl.decode_version(encoded), "1.2.0")


class Parsing(unittest.TestCase):
    def test_durations(self):
        for raw, seconds in ((86400, 86400), ("86400", 86400), ("3600s", 3600), ("30min", 1800),
                             ("12h", 43200), ("1d", 86400), ("2 days", 172800), ("1w", 604800)):
            self.assertEqual(rl.parse_duration(raw, "t"), seconds, raw)
        for raw in ("1m", "0", 0, -5, "1.5h", True, "1y", 2 ** 32):
            with self.assertRaises(rl.ConfigError, msg=repr(raw)):
                rl.parse_duration(raw, "t")

    def test_amounts(self):
        self.assertEqual(rl.parse_amount("1_000_000", "t"), Decimal(1_000_000))
        self.assertEqual(rl.parse_amount(250, "t"), Decimal(250))
        self.assertEqual(rl.parse_amount("2500.5", "t"), Decimal("2500.5"))
        for raw in (1e6, "1e6", "-5", "0", "abc", "1,000", True, None):
            with self.assertRaises(rl.ConfigError, msg=repr(raw)):
                rl.parse_amount(raw, "t")
        self.assertEqual(rl.to_base_units(Decimal("2500.5"), 6, "t"), 2_500_500_000)
        with self.assertRaises(rl.ConfigError):
            rl.to_base_units(Decimal("0.0000001"), 6, "t")


def mesh():
    return rl.load_mesh()


MESH = mesh()
FRAXTAL = MESH.chains[252]
ARBITRUM = MESH.chains[42161]
TEMPO = MESH.chains[4217]


def config(tokens):
    return rl.parse_config({"schema": 1, "tokens": tokens}, MESH)


def lim(amount, window="1d"):
    return {"limit": amount, "window": window}


class Compile(unittest.TestCase):
    def test_repo_mesh(self):
        self.assertIn(252, MESH.chains)
        self.assertNotIn(81457, MESH.chains, "Blast is legacy-only")
        self.assertEqual(MESH.active_tokens, ["WFRAX", "SFRXUSD", "SFRXETH", "FRXUSD", "FRXETH"])
        self.assertEqual(MESH.ofts[252]["FRXUSD"], "0x96A394058E2b84A89bac9667B19661Ed003cF5D4")
        self.assertEqual(MESH.ofts[1]["FRXUSD"], "0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0")
        self.assertEqual(MESH.ofts[42161]["FRXUSD"], "0x80Eede496655FB9047dd39d9f418d5483ED600df")
        self.assertIn(30168, MESH.universe_eids)
        self.assertIn(30260, MESH.universe_eids, "retired Mode eid still probed")

    def test_unlisted_is_off(self):
        desired = rl.compile_desired(config({}), "FRXUSD", ARBITRUM, 18)
        self.assertTrue(desired.is_off())

    def test_star_and_field_level_override(self):
        cfg = config({"frxUSD": {
            "*": {"default": {"outbound": lim("1_000_000"), "inbound": lim("1_100_000")}, "globallyDisabled": True},
            "fraxtal": {"globallyDisabled": False,
                        "peers": {"ethereum": {"outbound": lim("10_000_000")}, "solana": {"inbound": "off"}}},
        }})
        spoke = rl.compile_desired(cfg, "FRXUSD", ARBITRUM, 18)
        self.assertTrue(spoke.globally_disabled)
        self.assertEqual(spoke.default, rl.RLConfig(False, rl.Direction(True, 1_000_000 * E18, DAY),
                                                    rl.Direction(True, 1_100_000 * E18, DAY)))
        hub = rl.compile_desired(cfg, "FRXUSD", FRAXTAL, 18)
        self.assertFalse(hub.globally_disabled, "chain field beats `*` field")
        self.assertEqual(hub.default, spoke.default, "default inherited from `*`")
        self.assertEqual(hub.overrides[30101], rl.RLConfig(True, rl.Direction(True, 10_000_000 * E18, DAY),
                                                           rl.Direction(True, 1_100_000 * E18, DAY)))
        self.assertEqual(hub.inherited[30101], (False, True))
        self.assertEqual(hub.overrides[30168], rl.RLConfig(True, rl.Direction(True, 1_000_000 * E18, DAY), rl.OFF))

    def test_decimals_are_per_chain(self):
        cfg = config({"frxUSD": {"*": {"default": {"outbound": lim("1_000_000")}}}})
        self.assertEqual(rl.compile_desired(cfg, "FRXUSD", TEMPO, 6).default.outbound.limit, 1_000_000 * 10 ** 6)
        self.assertEqual(rl.compile_desired(cfg, "FRXUSD", ARBITRUM, 18).default.outbound.limit, 1_000_000 * E18)

    def test_contract_validation_mirrored(self):
        cfg = config({"frxUSD": {"tempo": {"default": {"outbound": lim("0.01", "1d")}}}})
        with self.assertRaises(rl.ConfigError) as ctx:
            rl.compile_desired(cfg, "FRXUSD", TEMPO, 6)
        self.assertIn("below the window", str(ctx.exception))
        cfg = config({"frxUSD": {"tempo": {"default": {"outbound": lim("1.1234567")}}}})
        with self.assertRaises(rl.ConfigError):
            rl.compile_desired(cfg, "FRXUSD", TEMPO, 6)

    def test_blocked_is_the_contract_minimum(self):
        cfg = config({"frxUSD": {"tempo": {"default": {"outbound": "blocked", "inbound": lim(5)}}}})
        tempo = rl.compile_desired(cfg, "FRXUSD", TEMPO, 6)
        self.assertEqual(tempo.default.outbound, rl.Direction(True, DAY, DAY))
        self.assertIn("blocked", rl.fmt_direction(tempo.default.outbound, 6))
        self.assertEqual(rl.compile_desired(cfg, "FRXUSD", TEMPO, 6).default.inbound.limit, 5 * 10 ** 6)

    def test_star_peer_on_itself_is_skipped(self):
        cfg = config({"frxUSD": {"*": {"default": {"outbound": lim(1000)}, "peers": {"fraxtal": {"inbound": lim(5)}}}}})
        hub = rl.compile_desired(cfg, "FRXUSD", FRAXTAL, 18)
        self.assertNotIn(30255, hub.overrides)
        self.assertTrue(hub.notes)
        self.assertIn(30255, rl.compile_desired(cfg, "FRXUSD", ARBITRUM, 18).overrides)

    def test_config_errors(self):
        bad = [
            {"schema": 2, "tokens": {}},
            {"schema": 1, "tokens": {"FOO": {}}},
            {"schema": 1, "tokens": {"FPI": {}}},
            {"schema": 1, "tokens": {"frxUSD": {"atlantis": {}}}},
            {"schema": 1, "tokens": {"frxUSD": {"fraxtal": {"defualt": {}}}}},
            {"schema": 1, "tokens": {"frxUSD": {"fraxtal": {}, "252": {}}}},
            {"schema": 1, "tokens": {"frxUSD": {"fraxtal": {"peers": {"fraxtal": {}}}}}},
            {"schema": 1, "tokens": {"frxUSD": {"fraxtal": {"default": {"outbound": {"limit": 5}}}}}},
            {"schema": 1, "tokens": {"frxUSD": {"fraxtal": {"default": {"outbound": "on"}}}}},
            {"schema": 1, "tokens": {"frxUSD": {"fraxtal": {"globallyDisabled": "yes"}}}},
            {"schema": 1, "tokens": {"frxUSD": {"blast": {}}}},
            {"schema": 1, "tokens": {"frxUSD": {"mode": {}}}},
            {"schema": 1, "tokens": {}, "extra": 1},
        ]
        for raw in bad:
            with self.assertRaises(rl.ConfigError, msg=repr(raw)):
                rl.parse_config(raw, MESH)

    def test_shipped_config_parses(self):
        rl.load_config(rl.DEFAULT_CONFIG, MESH)
        example = os.path.join(rl.HERE, "examples", "example.json")
        if os.path.exists(example):
            rl.load_config(example, MESH)


def live_oft(peered=(), tracked=(), default=rl.EMPTY, stored=None, disabled=False, usage=None):
    oft = rl.LiveOft("FRXUSD", "0x96A394058E2b84A89bac9667B19661Ed003cF5D4", capable=True, version="1.2.0",
                     owner="0x5f25218ed9474b721d6a38c115107428E832fA2E", decimals=18)
    oft.globally_disabled = disabled
    oft.default = default
    for eid in MESH.universe_eids:
        if eid == FRAXTAL.eid:
            continue
        oft.peers[eid] = "0x" + "11" * 32 if eid in peered else rl.ZERO32
        oft.stored[eid] = (stored or {}).get(eid, rl.EMPTY)
        oft.tracked[eid] = eid in tracked
        oft.usage[eid] = (usage or {}).get(eid, (0, 0))
    return oft


def desired(default=rl.EMPTY, overrides=None, disabled=False):
    return rl.Desired("test", disabled, default, dict(overrides or {}))


ON = rl.RLConfig(False, rl.Direction(True, 1000 * E18, DAY), rl.Direction(True, 1100 * E18, DAY))


class Planner(unittest.TestCase):
    def test_nothing_to_do(self):
        self.assertEqual(rl.plan_oft(FRAXTAL, live_oft(peered=(30110,)), desired()), [])

    def test_enable_default_registers_untracked_peers_first(self):
        oft = live_oft(peered=(30110, 30111, 30101), tracked=(30101,))
        calls = rl.plan_oft(FRAXTAL, oft, desired(ON))
        self.assertEqual([c.name for c in calls], ["checkpointRateLimits", "setDefaultRateLimitConfig"])
        self.assertEqual(calls[0].data, rl.calldata_checkpoint([30110, 30111]))
        self.assertEqual(calls[1].data, rl.calldata_set_default(ON))

    def test_override_write_registers_its_own_eid(self):
        override = ON.as_override()
        calls = rl.plan_oft(FRAXTAL, live_oft(peered=(30110, 30101)), desired(rl.EMPTY, {30101: override}))
        self.assertEqual([c.name for c in calls], ["setRateLimitConfigs"])
        self.assertEqual(calls[0].data, rl.calldata_set_configs([(30101, override)]))

    def test_stray_override_is_cleared(self):
        stray = rl.RLConfig(True, rl.Direction(True, 5 * E18, 3600), rl.OFF)
        oft = live_oft(peered=(30110,), tracked=(30110, 30260), default=ON, stored={30260: stray})
        calls = rl.plan_oft(FRAXTAL, oft, desired(ON))
        self.assertEqual([c.name for c in calls], ["setRateLimitConfigs"])
        self.assertEqual(calls[0].data, rl.calldata_set_configs([(30260, rl.EMPTY)]))
        self.assertIn("clear override", calls[0].lines[0])

    def test_global_switch_first_and_idempotent(self):
        oft = live_oft(peered=(30110,), tracked=(30110,), default=ON)
        calls = rl.plan_oft(FRAXTAL, oft, desired(ON, disabled=True))
        self.assertEqual([c.name for c in calls], ["setRateLimitGlobalConfig"])
        oft.globally_disabled = True
        self.assertEqual(rl.plan_oft(FRAXTAL, oft, desired(ON, disabled=True)), [])

    def test_disabled_direction_with_stale_fields_is_normalized(self):
        stale = rl.RLConfig(False, rl.Direction(False, 7, 9), rl.OFF)
        calls = rl.plan_oft(FRAXTAL, live_oft(default=stale), desired())
        self.assertEqual([c.name for c in calls], ["setDefaultRateLimitConfig"])
        self.assertEqual(calls[0].data, rl.calldata_set_default(rl.EMPTY))

    def test_untracked_peer_with_live_limits_is_drift(self):
        # A chain onboarded after limits were enabled: config already matches, the new eid is unregistered.
        oft = live_oft(peered=(30110, 30416), tracked=(30110,), default=ON)
        calls = rl.plan_oft(FRAXTAL, oft, desired(ON))
        self.assertEqual([(c.name, c.data) for c in calls], [("checkpointRateLimits", rl.calldata_checkpoint([30416]))])

    def test_full_cycle_applied_model_converges(self):
        override = rl.RLConfig(True, rl.Direction(True, 9 * E18, 3600), rl.OFF)
        oft = live_oft(peered=(30110, 30101))
        want = desired(ON, {30101: override})
        calls = rl.plan_oft(FRAXTAL, oft, want)
        self.assertEqual([c.name for c in calls], ["checkpointRateLimits", "setDefaultRateLimitConfig", "setRateLimitConfigs"])
        after = copy.deepcopy(oft)
        after.default = ON
        after.stored[30101] = override
        after.tracked[30110] = after.tracked[30101] = True
        self.assertEqual(rl.plan_oft(FRAXTAL, after, want), [])

    def test_impact_lines(self):
        oft = live_oft(peered=(30110,), tracked=(30110,), default=ON, usage={30110: (900 * E18, 0)})
        tighter = rl.RLConfig(False, rl.Direction(True, 500 * E18, DAY), ON.inbound)
        lines = rl.impact_lines(oft, desired(tighter))
        self.assertEqual(len(lines), 1)
        self.assertIn("clamped", lines[0])


class Lint(unittest.TestCase):
    def _plans(self, hub_default, spoke_default, hub_disabled=False):
        hub = rl.OftPlan(FRAXTAL, "FRXUSD", live_oft(peered=(30110,)), desired(hub_default, disabled=hub_disabled))
        spoke_oft = live_oft(peered=())
        spoke_oft.peers = {30255: "0x" + "22" * 32}
        spoke = rl.OftPlan(ARBITRUM, "FRXUSD", spoke_oft, desired(spoke_default))
        return [hub, spoke]

    def test_balanced_lanes_pass(self):
        balanced = rl.RLConfig(False, rl.Direction(True, 1000 * E18, DAY), rl.Direction(True, 1200 * E18, DAY))
        self.assertEqual(rl.lint_lanes(self._plans(balanced, balanced), MESH, Decimal("0.1")), [])

    def test_tight_inbound_and_inbound_only(self):
        tight = rl.RLConfig(False, rl.Direction(True, 1000 * E18, DAY), rl.Direction(True, 1000 * E18, DAY))
        warnings = rl.lint_lanes(self._plans(tight, tight), MESH, Decimal("0.1"))
        self.assertEqual(len(warnings), 2, warnings)
        inbound_only = rl.RLConfig(False, rl.OFF, rl.Direction(True, 1000 * E18, DAY))
        warnings = rl.lint_lanes(self._plans(rl.EMPTY, inbound_only), MESH, Decimal("0.1"))
        self.assertEqual(len(warnings), 1)
        self.assertIn("stuck", warnings[0])

    def test_slower_refill(self):
        out = rl.RLConfig(False, rl.Direction(True, 1000 * E18, 3600), rl.Direction(True, 2000 * E18, 3600))
        slow = rl.RLConfig(False, rl.Direction(True, 1000 * E18, 3600), rl.Direction(True, 2000 * E18, DAY))
        warnings = rl.lint_lanes(self._plans(out, slow), MESH, Decimal("0.1"))
        self.assertTrue(any("refills slower" in w for w in warnings), warnings)


class Output(unittest.TestCase):
    def test_batch_document(self):
        owner = rl.Owner("0x5f25218ed9474b721d6a38c115107428E832fA2E", "safe", 3, 6)
        call = rl.Call("setDefaultRateLimitConfig", "0x96a394058e2b84a89bac9667b19661ed003cf5d4",
                       rl.calldata_set_default(ON), [])
        batch = rl.Batch(FRAXTAL, owner, [], [call], 1_800_000_000)
        doc = rl.batch_document(batch)
        self.assertEqual(sorted(doc), ["chainId", "createdAt", "meta", "transactions", "version"])
        self.assertEqual(doc["chainId"], 252)
        self.assertEqual(doc["createdAt"], 1_800_000_000_000)
        self.assertEqual(doc["meta"], {"description": "", "name": "Transactions Batch"})
        self.assertEqual(doc["transactions"][0]["to"], "0x96A394058E2b84A89bac9667B19661Ed003cF5D4")
        self.assertEqual(doc["transactions"][0]["operation"], "0")
        self.assertEqual(doc["transactions"][0]["value"], "0")
        self.assertEqual(rl.batch_filename("RateLimits", batch),
                         "RateLimits-252-0x5f25218ed9474b721d6a38c115107428e832fa2e.json")

    def test_formatting(self):
        self.assertEqual(rl.fmt_amount(1_234_567_890_000_000_000_000_000, 18), "1,234,567.89")
        self.assertEqual(rl.fmt_amount(1_000_000 * 10 ** 6, 6), "1,000,000")
        self.assertEqual(rl.fmt_window(86400), "1d")
        self.assertEqual(rl.fmt_window(5400), "90min")
        self.assertEqual(rl.fmt_window(61), "61s")


if __name__ == "__main__":
    unittest.main()
