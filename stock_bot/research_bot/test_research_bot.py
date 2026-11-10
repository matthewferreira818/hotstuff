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
        self.assertFalse(all(bar.values()))
        self.assertFalse(bar["client #1 has paid - human check"])
        self.assertIn("NOT MET", scorer.render(card))

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
             "equity": [(t(1), 1000.0)], "seen_ids": set(), "new_orders_today": 0}
        c.update(kw)
        return c

    BUY = {"id": "F1:buy", "side": "buy", "asset": "BTC-USD", "market": "crypto",
           "dollars": 100.0, "forecast_id": "F1"}

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

    def quote(self, now):
        return lambda a: {"price": self.price, "time": now, "price_ago": self.price}

    def go(self, now, dry=False, seen=0.0):
        return executor.run(
            now=now, quote_fn=self.quote(now), dry_run=dry, lines=[self.f],
            first_seen={"F1": seen}, rules=RULES, rules_ok=True, manual_pause=False,
            paper_dir=self.d, orders_path=os.path.join(self.d, "orders.jsonl"),
            equity_path=os.path.join(self.d, "equity.jsonl"),
            auto_pause_path=os.path.join(self.d, "AUTO_PAUSE"))

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
