#!/usr/bin/env python3
"""Offline tests for the research bot (no network, no real money, temp
folders only). Run from the repo root:

  python3 -m unittest stock_bot/research_bot/test_research_bot.py -v
"""

import copy
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import checker  # noqa: E402
import generate  # noqa: E402
import ideas as idea_lib  # noqa: E402
import replay  # noqa: E402
import executor  # noqa: E402
import forecasts as ledger  # noqa: E402
import scorer  # noqa: E402

UTC = dt.timezone.utc
T0 = dt.datetime(2026, 11, 10, 12, 0, tzinfo=UTC)
RULES = ledger.load_rules()


def t(hours):
    return T0 + dt.timedelta(hours=hours)


class TempLedger(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "forecasts.jsonl")
        self.idea = ledger.add_idea("both", "test idea", "test", self.path, now=T0)["id"]

    def fc(self, **kw):
        base = {"idea": self.idea, "asset": "BTC-USD", "direction": "up",
                "probability": 0.6, "opens_at": t(1), "resolves_at": t(25),
                "expected_downside_pct": 5, "reason": "test", "act": True}
        base.update(kw)
        return base


class LedgerTests(TempLedger):
    def test_valid_forecast_logged(self):
        r = ledger.add_forecast(self.fc(), self.path, RULES, now=T0)
        self.assertEqual(r["market"], "crypto")
        self.assertTrue(r["id"].startswith("F-"))
        self.assertEqual(len(ledger.read_lines(self.path)), 2)

    def test_refusals(self):
        bad = [dict(idea="I-nope"), dict(probability=0.5), dict(probability=1.0),
               dict(direction="sideways"), dict(opens_at=t(0.1)),
               dict(resolves_at=t(1.5)), dict(resolves_at=t(24 * 40)),
               dict(direction="down", act=True), dict(reason="x" * 300),
               dict(opens_at="2026-11-10T13:00:00")]
        for kw in bad:
            with self.subTest(kw=kw), self.assertRaises(ledger.LedgerError):
                ledger.add_forecast(self.fc(**kw), self.path, RULES, now=T0)

    def test_stock_market_detected(self):
        r = ledger.add_forecast(self.fc(asset="spy"), self.path, RULES, now=T0)
        self.assertEqual((r["asset"], r["market"]), ("SPY", "stock"))

    def test_no_trade_and_proposal(self):
        ledger.add_no_trade("stock", "nothing clear", "test", self.path, now=T0)
        prop = os.path.join(self.dir, "proposals.jsonl")
        ledger.propose_rule("raise the cap", "AI", prop, now=T0)
        self.assertEqual(ledger.read_lines(prop)[0]["status"], "proposed")
        self.assertEqual(ledger.read_lines(self.path)[-1]["kind"], "no_trade")


class GitProofTests(TempLedger):
    def git(self, *a):
        subprocess.run(["git", "-C", self.dir] + list(a), check=True,
                       capture_output=True)

    def setUp(self):
        super().setUp()
        self.git("init", "-q")
        self.git("config", "user.email", "t@t")
        self.git("config", "user.name", "t")
        self.git("add", ".")
        self.git("commit", "-qm", "one")

    def test_append_only_ok_and_first_seen(self):
        r = ledger.add_forecast(self.fc(), self.path, RULES, now=T0)
        self.git("commit", "-qam", "two")
        ok, problems, seen = ledger.verify(self.path)
        self.assertTrue(ok, problems)
        self.assertIn(r["id"], seen)
        self.assertIn(self.idea, seen)

    def test_edit_is_caught(self):
        with open(self.path) as f:
            text = f.read()
        with open(self.path, "w") as f:
            f.write(text.replace("test idea", "better idea"))
        ok, problems, _ = ledger.verify(self.path)
        self.assertFalse(ok)
        self.git("commit", "-qam", "sneaky")
        ok, problems, _ = ledger.verify(self.path)
        self.assertFalse(ok)
        self.assertIn("changed or removed", problems[0])


class ScorerTests(unittest.TestCase):
    def setUp(self):
        self.prices = {}

    def price_at(self, asset, when):
        return self.prices.get((asset, ledger.iso(when)))

    def line(self, i, direction, p, opens, resolves, act=True, asset="BTC-USD"):
        return {"kind": "forecast", "id": f"F{i}", "asset": asset,
                "market": ledger.market_of(asset), "direction": direction,
                "probability": p, "opens_at": ledger.iso(opens),
                "resolves_at": ledger.iso(resolves), "act": act,
                "created": ledger.iso(opens - dt.timedelta(hours=1))}

    def setp(self, when, px, asset="BTC-USD"):
        self.prices[(asset, ledger.iso(when))] = px

    def test_brier_baselines_and_pnl(self):
        # F1: up at 0.8, goes 100 -> 110 (right). F2: up at 0.7, 110 -> 99 (wrong).
        lines = [self.line(1, "up", 0.8, t(0), t(24)),
                 self.line(2, "up", 0.7, t(24), t(48))]
        for when, px in ((t(-24), 90), (t(0), 100), (t(24), 110), (t(48), 99)):
            self.setp(when, px)
        seen = {"F1": t(-1).timestamp(), "F2": t(-1).timestamp()}
        card = scorer.grade(lines, RULES, self.price_at, seen, now=t(60))
        mc = card["markets"]["crypto"]
        self.assertEqual((mc["graded"], mc["hits"]), (2, 1))
        self.assertAlmostEqual(mc["brier"]["forecaster"], ((0.2 ** 2) + (0.7 ** 2)) / 2)
        self.assertAlmostEqual(mc["brier"]["coin_flip"], 0.25)
        # Base rate: F1 knew nothing (1/2); F2 knew F1 went up (2/3).
        self.assertAlmostEqual(mc["brier"]["base_rate"], (0.5 ** 2 + (2 / 3) ** 2) / 2)
        # Persistence: F1 prev 90->100 up => 0.6 (right); F2 prev 100->110 up => 0.6 (wrong).
        self.assertAlmostEqual(mc["brier"]["tomorrow_equals_today"], (0.4 ** 2 + 0.6 ** 2) / 2)
        # P&L uses the practice broker's crypto fees: 0.5% each way + 0.1% slippage.
        fees = scorer.fee_model(RULES["markets"]["crypto"]["costs"])
        want = scorer.paper_trade(100, 110, 100, fees) + scorer.paper_trade(110, 99, 100, fees)
        self.assertAlmostEqual(mc["paper_pnl"], round(want, 2))
        self.assertEqual(mc["paper_trades"], 2)
        self.assertEqual(card["markets"]["stock"]["graded"], 0)

    def test_fees_match_paper_broker(self):
        # A flat price must LOSE money after costs (stocks: $1.99 min each way).
        fees = scorer.fee_model(RULES["markets"]["stock"]["costs"])
        loss = scorer.paper_trade(50, 50, 100, fees)
        self.assertLess(loss, -3.9)
        self.assertGreater(loss, -4.3)
        cfees = scorer.fee_model(RULES["markets"]["crypto"]["costs"])
        self.assertAlmostEqual(scorer.paper_trade(50, 50, 100, cfees), -1.2, delta=0.02)

    def test_late_forecast_not_counted(self):
        lines = [self.line(1, "up", 0.9, t(0), t(24))]
        self.setp(t(0), 100)
        self.setp(t(24), 120)
        card = scorer.grade(lines, RULES, self.price_at, {"F1": t(0.5).timestamp()},
                            now=t(30))
        mc = card["markets"]["crypto"]
        self.assertEqual((mc["graded"], mc["late_not_counted"]), (0, 1))
        card = scorer.grade(lines, RULES, self.price_at, {}, now=t(30))
        self.assertEqual(card["markets"]["crypto"]["late_not_counted"], 1)

    def test_down_forecast_never_trades_and_open_counted(self):
        lines = [self.line(1, "down", 0.6, t(0), t(24), act=False),
                 self.line(2, "up", 0.6, t(10), t(100))]
        self.setp(t(0), 100)
        self.setp(t(24), 90)
        seen = {"F1": 0, "F2": 0}
        mc = scorer.grade(lines, RULES, self.price_at, seen, now=t(30))["markets"]["crypto"]
        self.assertEqual((mc["graded"], mc["hits"], mc["paper_trades"], mc["open"]), (1, 1, 0, 1))

    def test_evidence_bar_and_benchmark(self):
        lines = [self.line(1, "up", 0.8, t(0), t(24))]
        self.setp(t(0), 100)
        self.setp(t(24), 110)
        card = scorer.grade(lines, RULES, self.price_at, {"F1": 0}, now=t(30))
        card = scorer.add_benchmark(card, RULES, self.price_at,
                                    lambda a, s, e: [100, 80, 120])
        mc = card["markets"]["crypto"]
        self.assertTrue(mc["down_market_seen"])  # 20% drop >= 10%
        self.assertIsNotNone(mc["hold_pnl"])
        bar = scorer.evidence_bar(mc)
        self.assertFalse(bar["one idea meets ALL of the above"])
        self.assertIn("NOT MET", scorer.render(card))
        self.assertIn("client #1 has paid", scorer.render(card))

    def test_luck_p_value(self):
        self.assertAlmostEqual(scorer.binomial_p_value(6, 10), 386 / 1024)
        self.assertLess(scorer.binomial_p_value(65, 100), 0.01)


class CheckerTests(unittest.TestCase):
    def ctx(self, **kw):
        f = {"kind": "forecast", "id": "F1", "asset": "BTC-USD", "market": "crypto",
             "direction": "up", "act": True, "opens_at": ledger.iso(t(0)),
             "resolves_at": ledger.iso(t(24))}
        c = {"rules": copy.deepcopy(RULES), "rules_ok": True, "manual_pause": False,
             "auto_pause": None, "now": t(1), "forecast": f,
             "committed_before_open": True,
             "quote": {"price": 100.0, "time": t(1) - dt.timedelta(seconds=30),
                       "price_ago": 99.5},
             "account": {"value": 1000.0, "cash": 1000.0, "positions": {}},
             "equity": [(t(1), 1000.0)], "seen_ids": set(), "new_orders_today": 0,
             "daily_range_pct": 3.0}
        c.update(kw)
        return c

    BUY = {"id": "F1:buy", "side": "buy", "asset": "BTC-USD", "market": "crypto",
           "dollars": 100.0, "forecast_id": "F1", "stop_pct": 6.0}

    def check(self, order=None, **kw):
        return checker.check_order(order or dict(self.BUY), self.ctx(**kw))

    def test_good_buy_passes(self):
        ok, why, pause = self.check()
        self.assertTrue(ok, why)
        self.assertIsNone(pause)

    def test_hard_caps(self):
        acct = lambda **a: dict({"value": 1000.0, "cash": 1000.0, "positions": {}}, **a)
        cases = {
            "practice": dict(rules=dict(RULES, practice_only=False)),
            "lock": dict(rules_ok=False),
            "PAUSE": dict(manual_pause=True),
            "already tried": dict(seen_ids={"F1:buy"}),
            "no live price": dict(quote=None),
            "old": dict(quote={"price": 100.0, "time": t(1) - dt.timedelta(minutes=10)}),
            "moved": dict(quote={"price": 100.0, "time": t(1), "price_ago": 80.0}),
            "auto-pause": dict(auto_pause="daily loss"),
            "committed": dict(committed_before_open=False),
            "not open": dict(now=t(30), quote={"price": 100.0, "time": t(30)}),
            "already holding": dict(account=acct(positions={"BTC-USD": {}})),
            "positions": dict(account=acct(positions={"A-USD": {}, "B-USD": {}, "C-USD": {}})),
            "cap of 2": dict(new_orders_today=2),
            "not enough": dict(account=acct(cash=60.0)),
        }
        for word, kw in cases.items():
            with self.subTest(word=word):
                ok, why, _ = self.check(**kw)
                self.assertFalse(ok)
                self.assertIn(word.lower(), " ".join(why).lower())

    def test_stop_rules(self):
        ok, why, _ = self.check(daily_range_pct=None)
        self.assertFalse(ok)
        self.assertIn("safe stop", why[0])
        ok, why, _ = self.check(dict(self.BUY, stop_pct=4.0))  # under 2 x 3%
        self.assertFalse(ok)
        self.assertIn("at least 2x", why[0])
        ok, why, _ = self.check(dict(self.BUY, stop_pct=16.0), daily_range_pct=8.0)
        self.assertFalse(ok)
        self.assertIn("$15 per $100", why[0])

    def test_size_limits(self):
        ok, why, _ = self.check(dict(self.BUY, dollars=150.0))
        self.assertFalse(ok)
        self.assertIn("10%", why[0])
        ok, why, _ = self.check(dict(self.BUY, dollars=20.0))
        self.assertFalse(ok)
        self.assertIn("minimum", why[0])

    def test_down_or_no_act_cannot_buy(self):
        for f in ({"direction": "down"}, {"act": False}):
            fc = dict(self.ctx()["forecast"], **f)
            ok, _, _ = self.check(forecast=fc)
            self.assertFalse(ok)

    def test_daily_loss_and_weekly_drawdown_pause(self):
        eq = [(t(-3), 1000.0), (t(1), 965.0)]  # day start 08:00 UTC: t(-3)=09:00
        ok, why, pause = self.check(equity=eq)
        self.assertFalse(ok)
        self.assertIn("daily loss", pause)
        eq = [(t(-72), 1000.0), (t(-20), 960.0), (t(-3), 935.0), (t(1), 935.0)]
        ok, why, pause = self.check(equity=eq)
        self.assertFalse(ok)
        self.assertIn("drawdown", pause)

    def test_sell_rules(self):
        sell = {"id": "F1:sell", "side": "sell", "asset": "BTC-USD", "market": "crypto",
                "forecast_id": "F1"}
        held = {"value": 1000.0, "cash": 900.0, "positions": {"BTC-USD": {"qty": 1}}}
        q = {"price": 100.0, "time": t(25)}
        ok, why, _ = self.check(sell, now=t(25), quote=q, account=held, auto_pause="x")
        self.assertTrue(ok, why)  # closing a due position is allowed in auto-pause
        ok, _, _ = self.check(sell, now=t(25), quote=q, account=held, manual_pause=True)
        self.assertFalse(ok)
        ok, why, _ = self.check(sell, account=held)  # window still open
        self.assertFalse(ok)

    def test_rules_lock(self):
        d = tempfile.mkdtemp()
        rp, lp = os.path.join(d, "rules.json"), os.path.join(d, "rules.lock")
        with open(rp, "w") as f:
            json.dump(RULES, f)
        with open(lp, "w") as f:
            f.write(checker.rules_hash(rp) + "  rules.json\n")
        self.assertTrue(checker.rules_locked_ok(rp, lp))
        with open(rp, "w") as f:
            json.dump(dict(RULES, max_position_pct=50), f)
        self.assertFalse(checker.rules_locked_ok(rp, lp))

    def test_repo_rules_are_locked(self):
        self.assertTrue(checker.rules_locked_ok(),
                        "rules.json differs from rules.lock in the repo")
        self.assertIs(RULES["practice_only"], True)
        self.assertLessEqual(RULES["max_position_pct"], 10)
        self.assertLessEqual(RULES["max_new_orders_per_day"], 2)


class ExecutorTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.f = {"kind": "forecast", "id": "F1", "asset": "BTC-USD", "market": "crypto",
                  "direction": "up", "probability": 0.6, "act": True,
                  "opens_at": ledger.iso(t(0)), "resolves_at": ledger.iso(t(24))}
        self.price = 100.0
        self.rng = 3.0

    def quote(self, now):
        return lambda a: {"price": self.price, "time": now, "price_ago": self.price}

    def go(self, now, dry=False, seen=0.0):
        return executor.run(
            now=now, quote_fn=self.quote(now), dry_run=dry, lines=[self.f],
            first_seen={"F1": seen}, rules=RULES, rules_ok=True, manual_pause=False,
            paper_dir=self.d, orders_path=os.path.join(self.d, "orders.jsonl"),
            equity_path=os.path.join(self.d, "equity.jsonl"),
            auto_pause_path=os.path.join(self.d, "AUTO_PAUSE"),
            range_fn=lambda a: self.rng, lock_path=os.path.join(self.d, "RUN_LOCK"))

    def acct(self):
        with open(os.path.join(self.d, "account-research-crypto.json")) as f:
            return json.load(f)

    def test_buy_then_no_double_then_sell(self):
        log = self.go(t(1))
        self.assertIn("practice buy BTC-USD filled", " ".join(log))
        a = self.acct()
        self.assertEqual(a["cash"], 900.0)
        self.go(t(2))  # retry in the window: must not buy again
        self.assertEqual(len(self.acct()["orders"]), 1)
        self.price = 110.0
        log = self.go(t(25))
        self.assertIn("practice sell BTC-USD filled", " ".join(log))
        a = self.acct()
        self.assertEqual(a["positions"], {})
        self.assertGreater(a["cash"], 1000.0)
        self.assertEqual([o["side"] for o in a["orders"]], ["buy", "sell"])

    def test_stop_sells_before_window_ends(self):
        self.go(t(1))
        orders = ledger.read_lines(os.path.join(self.d, "orders.jsonl"))
        self.assertEqual(orders[-1]["stop_pct"], 6.0)
        self.price = 95.0  # entry ~100.7 incl. fee+slip; 6% stop ~94.7: not yet
        self.assertNotIn("sell", " ".join(self.go(t(2))))
        self.price = 94.0
        log = " ".join(self.go(t(3)))
        self.assertIn("practice sell BTC-USD filled", log)
        self.assertEqual(self.acct()["positions"], {})
        self.assertIn("F1:stop", [o["id"] for o in ledger.read_lines(
            os.path.join(self.d, "orders.jsonl"))])

    def test_too_wild_is_skipped(self):
        self.rng = 9.0  # 2 x 9% = 18% stop > $15 per $100
        self.assertIn("skip", " ".join(self.go(t(1))))

    def test_run_lock(self):
        lock = os.path.join(self.d, "RUN_LOCK")
        with open(lock, "w") as f:
            f.write(f"123 {ledger.iso(t(1))}\n")
        self.assertIn("in progress", self.go(t(1) + dt.timedelta(minutes=5))[0])
        log = self.go(t(1) + dt.timedelta(minutes=45))
        self.assertIn("stale run lock", log[0])
        self.assertIn("practice buy", " ".join(log))
        self.assertFalse(os.path.exists(lock))  # released after the run

    def test_dry_run_places_nothing(self):
        log = self.go(t(1), dry=True)
        self.assertIn("would buy", " ".join(log))
        self.assertFalse(os.path.exists(os.path.join(self.d, "account-research-crypto.json")))

    def test_late_forecast_not_traded(self):
        log = self.go(t(1), seen=t(0.5).timestamp())
        self.assertIn("not committed before", " ".join(log))

    def test_half_done_order_stops_market(self):
        with open(os.path.join(self.d, "orders.jsonl"), "w") as f:
            f.write(json.dumps({"id": "F1:buy", "status": "intent", "side": "buy",
                                "asset": "BTC-USD", "time": ledger.iso(t(1))}) + "\n")
        log = self.go(t(2))
        self.assertIn("half-done", " ".join(log))

    def test_refuses_on_github_actions(self):
        os.environ["GITHUB_ACTIONS"] = "true"
        try:
            self.assertIn("never runs on GitHub", self.go(t(1))[0])
        finally:
            del os.environ["GITHUB_ACTIONS"]

    def test_pause_and_lock_stop_everything(self):
        common = dict(now=t(1), quote_fn=self.quote(t(1)), lines=[self.f],
                      first_seen={"F1": 0}, rules=RULES, paper_dir=self.d)
        self.assertIn("PAUSE", executor.run(manual_pause=True, rules_ok=True, **common)[0])
        self.assertIn("rules.lock", executor.run(manual_pause=False, rules_ok=False,
                                                 **common)[0])


def zigzag_bars(n, start_ts=1_700_000_000, step=3600):
    """Price alternates 100, 110, 100, 110 ... and each bar opens at the
    previous close, so 'buy after a drop' wins every time."""
    closes = [100.0 if i % 2 == 0 else 110.0 for i in range(n)]
    return [(start_ts + i * step, closes[i - 1] if i else closes[0], closes[i])
            for i in range(n)]


def bounce(h, p):
    return ("up", p["prob"]) if h[-1] < h[-2] else ("down", p["prob"])


class ReplayTests(unittest.TestCase):
    CFG = {"train_days": 10, "test_days": 5, "warmup": 50}

    def setUp(self):
        idea_lib.IDEAS["_bounce"] = {"fn": bounce, "text": "test", "grid": [{"prob": 0.56}]}
        self.fees = scorer.fee_model(RULES["markets"]["crypto"]["costs"])
        self.data = {"X-USD": zigzag_bars(24 * 60)}
        self.flat = [(ts, 100.0, 100.0) for ts, _, _ in self.data["X-USD"]]

    def tearDown(self):
        del idea_lib.IDEAS["_bounce"]

    def test_history_cannot_look_ahead(self):
        h = idea_lib.History([1, 2, 3, 4, 5], 2)
        self.assertEqual((h[-1], h[0], len(h), h.window(2)), (3, 1, 3, [2, 3]))
        with self.assertRaises(idea_lib.LookAheadError):
            h[3]
        with self.assertRaises(TypeError):
            h[0:5]

    def test_entry_is_next_open_and_idea_sees_only_past(self):
        seen = []

        def spy(h, p):
            seen.append(len(h))
            return ("up", 0.6)
        idea_lib.IDEAS["_spy"] = {"fn": spy, "text": "t", "grid": [{}]}
        try:
            bars = zigzag_bars(80)
            rows = replay.make_rows("_spy", {}, 1, {"X-USD": bars}, bars, 50)
        finally:
            del idea_lib.IDEAS["_spy"]
        self.assertEqual(seen[0], 51)  # decision at bar 50 sees bars 0..50
        first = rows[0]
        self.assertEqual(first[0], bars[51][0])          # opens at the next bar
        self.assertEqual((first[4], first[5]), (bars[51][1], bars[52][1]))

    def test_fast_downsides_match_slow(self):
        closes = [100 + (i * 7919 % 37) for i in range(300)]
        fast = replay.downsides(closes, 4)
        for i in range(len(closes)):
            slow = idea_lib.typical_move_pct(idea_lib.History(closes, i), 4)
            if slow is None:
                self.assertIsNone(fast[i])
            else:
                self.assertAlmostEqual(fast[i], slow)

    def test_windows_do_not_overlap(self):
        w = replay.windows(0, 86400 * 40, 10, 5)
        self.assertEqual(len(w), 6)
        self.assertTrue(all(w[i][2] <= w[i + 1][2] - 86400 * 5 + 1 for i in range(len(w) - 1)))
        self.assertTrue(all(b - a == 86400 * 10 and c - b == 86400 * 5 for a, b, c in w))

    def test_training_never_sees_test_outcomes(self):
        rows = [(0, 50, 0.6, True, 1, 2, None, None, 0.0),
                (40, 120, 0.6, True, 1, 2, None, None, 0.0)]
        self.assertEqual(len(replay.in_range(rows, 0, 100)), 1)

    def test_real_edge_passes(self):
        res, chosen, _ = replay.walk_forward("_bounce", 1, self.data, self.flat,
                                             self.CFG, self.fees)
        self.assertEqual(res["verdict"], "PASS", res.get("why"))
        self.assertLess(res["brier"]["forecaster"], res["brier"]["coin_flip"])
        self.assertGreater(res["pnl"], 0)

    def test_no_edge_dies(self):
        res, _, _ = replay.walk_forward("drift", 1, self.data, self.flat, self.CFG, self.fees)
        self.assertEqual(res["verdict"], "DEAD")
        self.assertIn("Brier beats all three baselines", res["why"])

    def test_fees_can_kill_a_right_idea(self):
        tiny = {"X-USD": [(ts, 100 + (o - 100) / 1000, 100 + (c - 100) / 1000)
                          for ts, o, c in self.data["X-USD"]]}  # 0.01% swings
        res, _, _ = replay.walk_forward("_bounce", 1, tiny, self.flat, self.CFG, self.fees)
        self.assertEqual(res["verdict"], "DEAD")
        self.assertLess(res["pnl"], 0)

    def test_report_keeps_every_variant_ever_tried(self):
        log = [{"market": "crypto", "idea": "drift", "horizon": 1, "interval": "1h", "run": "1", "verdict": "DEAD"},
               {"market": "crypto", "idea": "drift", "horizon": 1, "interval": "1h", "run": "2", "verdict": "PASS"},
               {"market": "stock", "idea": "trend", "horizon": 5, "interval": "1d", "run": "1", "verdict": "DEAD"}]
        out = replay.latest(log)
        self.assertEqual(len(out), 2)
        self.assertEqual([r["verdict"] for r in out if r["idea"] == "drift"], ["PASS"])

    def test_run_market_and_report(self):
        cfg = dict(self.CFG, interval="1h", days=60, horizons=[1], assets=["X-USD"],
                   benchmark="BTC-USD")
        loader = lambda a, i, d: self.data["X-USD"] if a == "X-USD" else self.flat
        res = replay.run_market("crypto", cfg, RULES, ["_bounce", "drift"], loader)
        self.assertEqual([r["verdict"] for r in res], ["PASS", "DEAD"])
        text = replay.render(res, "now")
        self.assertIn("2 idea/horizon combinations tried, 1 passed", text)


class IdeaTests(unittest.TestCase):
    def call(self, name, closes, **p):
        return idea_lib.call(name, idea_lib.History(closes, len(closes) - 1),
                             dict(p, prob=0.56))

    def test_every_idea_runs_on_every_setting(self):
        import random
        rnd = random.Random(7)
        closes = [100.0]
        for _ in range(700):
            closes.append(closes[-1] * (1 + rnd.gauss(0, 0.02)))
        for name, idea in idea_lib.IDEAS.items():
            for p in idea["grid"]:
                for i in range(0, len(closes), 7):
                    c = idea_lib.call(name, idea_lib.History(closes, i), p)
                    self.assertTrue(c is None or (c[0] in ("up", "down") and 0.5 < c[1] < 1),
                                    (name, p, c))

    def test_new_ideas_fire_when_they_should(self):
        up = [100 + i for i in range(300)]
        self.assertEqual(self.call("long_trend", up, sma=200), ("up", 0.56))
        self.assertIsNone(self.call("long_trend", up[::-1], sma=200))
        calm = [100 * (1.01 if i % 2 else 0.99) for i in range(30)]
        self.assertEqual(self.call("big_drop", calm + [85.0], k=2.5)[0], "up")
        self.assertIsNone(self.call("big_drop", calm + [calm[-1] * 0.98], k=2.5))
        self.assertEqual(self.call("losing_streak", [10, 11, 10, 9, 8], k=3)[0], "up")
        self.assertIsNone(self.call("losing_streak", [10, 11, 10, 9, 9.5], k=3))
        self.assertEqual(self.call("near_high", up, x_pct=3)[0], "up")
        self.assertEqual(self.call("two_clocks", up, long=60, short=10)[0], "up")
        # Squeeze: wide swings, then 10 dead-flat days, then a break above them.
        wide = [100 + (10 if i % 2 else -10) for i in range(100)]
        sq = wide + [100.0] * 10
        self.assertEqual(self.call("squeeze", sq + [101.0], n=10, m=90)[0], "up")
        self.assertIsNone(self.call("squeeze", sq + [99.0], n=10, m=90))

    def test_plain_reason_is_built_from_the_real_prices(self):
        closes = [100.0] * 20 + [110.0]
        h = idea_lib.History(closes, len(closes) - 1)
        p = {"lookback": 20, "prob": 0.52}
        text = idea_lib.explain("momentum", h, p, "up", "SPY", "1 trading days",
                                {"verdict": "DEAD", "pnl_after_costs": -5.0})
        self.assertIn("10.0% higher than 20 trading days ago", text)
        self.assertIn("rises over the next 1 trading days", text)
        self.assertIn("lost money after fees", text)
        self.assertLessEqual(len(text), ledger.MAX_REASON)
        passed = idea_lib.explain("momentum", h, p, "up", "SPY", "1 trading days", {"verdict": "PASS"})
        self.assertNotIn("lost money", passed)
        self.assertIn("passed the past-price test", passed)
        r = idea_lib.explain("reversal", h, {"lookback": 20, "drop_pct": 8, "prob": 0.56},
                             "down", "BTC-USD", "4 hours")
        self.assertIn("jumped 10.0% in 20 hours", r)
        self.assertNotIn("past-price", r)  # no replay record -> no claim either way
        for name, idea in idea_lib.IDEAS.items():  # every idea gets a sentence
            self.assertTrue(idea_lib.explain(name, h, idea["grid"][0], "up", "X", "5 days"))

    def test_zero_price_means_no_call(self):
        self.assertIsNone(self.call("big_drop", [1.0] * 25 + [0.0, 1.0], k=2.5))

    def test_cross_fires_only_on_the_cross_day(self):
        closes = [100.0] * 60 + [100.0 + 2 * i for i in range(1, 30)]
        fired = [i for i in range(len(closes))
                 if idea_lib.call("cross", idea_lib.History(closes, i),
                                  {"fast": 10, "slow": 50, "prob": 0.56})]
        self.assertEqual(len(fired), 1)

    def test_calm_momentum_sits_out_wild_stretches(self):
        calm = [100 * (1.001 if i % 2 else 0.9995) for i in range(260)]
        wild = calm + [calm[-1] * (1.2 if i % 2 else 0.85) for i in range(20)]
        self.assertIsNotNone(self.call("calm_momentum", calm + calm[-20:], ratio=2.0))
        self.assertIsNone(self.call("calm_momentum", wild, ratio=2.0))

    def test_idea_config(self):
        base = replay.settings()
        c = replay.config_for("crypto", base["crypto"], idea_lib.IDEAS["big_drop"])
        self.assertEqual((c["interval"], c["horizons"]), ("1d", [3, 5]))
        c = replay.config_for("stock", base["stock"], idea_lib.IDEAS["losing_streak"])
        self.assertEqual(c["assets"], ["SPY"])
        c = replay.config_for("crypto", base["crypto"], idea_lib.IDEAS["reversal"])
        self.assertEqual(c["interval"], "1h")


class GenerateTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.path = os.path.join(self.d, "forecasts.jsonl")
        self.fwd = {"variants": [{"market": "crypto", "idea": "momentum", "horizon": 4,
                                  "params": {"lookback": 5, "prob": 0.52},
                                  "assets": ["BTC-USD", "ETH-USD"]}]}
        self.now = dt.datetime(2026, 11, 10, 13, 50, tzinfo=UTC)
        start = int(self.now.timestamp()) - 200 * 3600
        self.bars = [(start + i * 3600, 100 + i, 100 + i) for i in range(201)]

    def gen(self, now=None):
        return generate.generate(now=now or self.now, bars_fn=lambda a, i: self.bars,
                                 path=self.path, forward=self.fwd, rules=RULES)

    def test_windows(self):
        o, r = generate.crypto_window(self.now, 4, 20)
        self.assertEqual((o, r), (t(3), t(7)))  # 13:50 + 20 min -> 15:00
        o, r = generate.stock_window(self.now, 1, 20)  # Tue 13:50 UTC = 8:50 NY
        self.assertEqual((o, r), (dt.datetime(2026, 11, 10, 14, 30, tzinfo=UTC),
                                  dt.datetime(2026, 11, 11, 14, 30, tzinfo=UTC)))
        fri = dt.datetime(2026, 11, 13, 22, 0, tzinfo=UTC)
        o, r = generate.stock_window(fri, 1, 20)
        self.assertEqual((o.weekday(), r.weekday()), (0, 1))  # Mon open -> Tue open

    def test_crypto_daily_window(self):
        o, r = generate.crypto_day_window(self.now, 3, 20)
        self.assertEqual((o, r), (dt.datetime(2026, 11, 11, tzinfo=UTC),
                                  dt.datetime(2026, 11, 14, tzinfo=UTC)))
        today = int(dt.datetime(2026, 11, 10, tzinfo=UTC).timestamp())
        bars = [(today - 86400, 1, 1), (today, 2, 2)]
        self.assertEqual(generate.finished(bars, "1d", self.now, "crypto"), bars[:1])

    def test_in_progress_bar_dropped(self):
        bars = [(int(self.now.timestamp()) - 3600, 1, 1), (int(self.now.timestamp()) - 600, 2, 2)]
        self.assertEqual(len(generate.finished(bars, "1h", self.now)), 1)
        # Yesterday's daily stock bar (stamped 14:30 UTC) is finished by 13:50 today;
        # today's isn't (the market hasn't closed).
        y = int(dt.datetime(2026, 11, 9, 14, 30, tzinfo=UTC).timestamp())
        daily = [(y, 1, 1), (y + 86400, 2, 2)]
        self.assertEqual(generate.finished(daily, "1d", self.now), daily[:1])

    def test_writes_valid_forecasts_once(self):
        log = self.gen()
        lines = ledger.read_lines(self.path)
        fc = [l for l in lines if l["kind"] == "forecast"]
        self.assertEqual(len(fc), 2, log)
        self.assertEqual(sum(l["kind"] == "idea" for l in lines), 1)
        self.assertTrue(all(f["direction"] == "up" and f["act"] for f in fc))
        self.assertTrue(all("higher than 5 hours ago" in f["plain_reason"] for f in fc))
        log = self.gen(self.now + dt.timedelta(minutes=30))  # still open: no pile-up
        self.assertEqual(len([l for l in ledger.read_lines(self.path)
                              if l["kind"] == "forecast"]), 2)
        self.assertNotIn("no_trade", [l["kind"] for l in ledger.read_lines(self.path)])
        self.assertIn("still open", " ".join(log))

    def test_no_calls_logs_no_trade(self):
        self.bars = self.bars[:20]  # too short for any call
        self.gen()
        self.assertEqual(ledger.read_lines(self.path)[-1]["kind"], "no_trade")

    def test_missing_forward_and_help_guard(self):
        with self.assertRaises(generate.ForwardMissing):
            generate.load_forward(os.path.join(self.d, "nope.json"))
        for args in (["--help"], ["--bogus"]):
            with self.assertRaises(SystemExit), open(os.devnull, "w") as dn:
                stderr, sys.stderr = sys.stderr, dn
                stdout, sys.stdout = sys.stdout, dn
                try:
                    generate.main(args)
                finally:
                    sys.stderr, sys.stdout = stderr, stdout

    def test_repo_forward_json_is_valid(self):
        fwd = generate.load_forward()
        for v in fwd["variants"]:
            self.assertIn(v["idea"], idea_lib.IDEAS)
            self.assertIn(v["params"], idea_lib.IDEAS[v["idea"]]["grid"])
            self.assertIn(v["market"], ledger.MARKETS)
            self.assertTrue(v["assets"])

    def test_replay_pass_lookup(self):
        log = [{"market": "crypto", "idea": "momentum", "horizon": 4, "verdict": "DEAD", "run": "1"},
               {"market": "crypto", "idea": "momentum", "horizon": 4, "verdict": "PASS", "run": "2"}]
        text = 'replay idea momentum h=4 {"lookback": 5, "prob": 0.52}'
        self.assertTrue(scorer.replay_passed("crypto", text, log))
        self.assertFalse(scorer.replay_passed("stock", text, log))
        self.assertFalse(scorer.replay_passed("crypto", text, log[:1]))


class NoRealMoneyPath(unittest.TestCase):
    def test_no_live_broker_or_keys_in_code(self):
        banned = re.compile(r"moomoo|alpaca|koho|api_key|secret|OpenD|"
                            r"live_auto_trade|place_order|ccxt|binance|kraken",
                            re.I)
        for name in os.listdir(HERE):
            if name.endswith(".py") and not name.startswith("test_"):
                with open(os.path.join(HERE, name)) as f:
                    hits = banned.findall(f.read())
                self.assertEqual(hits, [], f"{name} mentions {hits}")


if __name__ == "__main__":
    unittest.main()
