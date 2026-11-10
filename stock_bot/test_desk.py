"""Offline tests for the Robot Desk (stock_bot/desk.py). No network, no git.

Run: python -m unittest stock_bot/test_desk.py   (from the repo root)
Covers the checks notes/robot-desk.md asks for: the health rules (ran today
in Moncton time, stale, failed), the scoreboard math (one robot by hand),
and STOP -> PAUSE (creates the file, never deletes or overwrites it), plus
guards that the desk can't reach broker code or delete anything.
"""

import datetime as dt
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import desk  # noqa: E402

UTC = dt.timezone.utc
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BOT = {r["id"]: r for r in desk.ROBOTS}


def read(path):
    with open(path) as f:
        return f.read()


def t(s):
    return dt.datetime.fromisoformat(s).replace(tzinfo=UTC)


def run(created, status="completed", conclusion="success"):
    return {"created_at": created, "status": status, "conclusion": conclusion}


def snap(updated, value=1000.0, hold=1000.0, start=1000.0, started="2026-10-01T15:00:00+00:00",
         bench_key="spy_value", benchmark=None):
    s = {"updated": updated, "account": {"value": value, bench_key: hold, "start_cash": start,
                                         "started": started, "fees": 5.0, "trades": 3}}
    if benchmark:
        s["benchmark"] = benchmark
    return s


# Tue Nov 10 2026, 11:00 AM New York = 12:00 PM Moncton = 16:00 UTC (market open).
OPEN = t("2026-11-10T16:00:00")
# Same day 7:00 PM Moncton = 23:00 UTC (market closed).
EVENING = t("2026-11-10T23:00:00")


class Health(unittest.TestCase):
    def test_ran_today_uses_moncton_date(self):
        # 02:30 UTC Nov 11 is still 10:30 PM Tue Nov 10 in Moncton.
        late = t("2026-11-11T02:30:00")
        h = desk.health(BOT["moonshot-crypto"], late, [run("2026-11-11T01:00:00Z")], snap("2026-11-11T02:00:00Z"), None, False)
        self.assertTrue(h["ran_today"])
        # A run at 03:30 UTC Nov 10 was Mon Nov 9 11:30 PM in Moncton: not today.
        h = desk.health(BOT["stock-bot"], OPEN, [run("2026-11-10T03:30:00Z")], snap("2026-11-10T15:50:00Z"), None, False)
        self.assertFalse(h["ran_today"])
        self.assertEqual(h["state"], "not started")

    def test_ok_running_and_waiting(self):
        h = desk.health(BOT["momentum"], OPEN, [run("2026-11-10T14:30:00Z", "in_progress", None)],
                        snap("2026-11-10T15:59:00Z"), None, False)
        self.assertEqual(h["state"], "running")
        self.assertTrue(h["ran_today"])
        h = desk.health(BOT["momentum"], EVENING, [run("2026-11-10T14:30:00Z")], snap("2026-11-10T21:00:00Z"), None, False)
        self.assertEqual(h["state"], "ok")
        # 9:00 AM New York, before the open, nothing run yet: waiting, not alarming.
        early = t("2026-11-10T14:00:00")
        h = desk.health(BOT["momentum"], early, [], snap("2026-11-09T21:00:00Z"), None, False)
        self.assertEqual(h["state"], "waiting")

    def test_stale_only_while_market_open(self):
        old = snap("2026-11-10T13:30:00Z")  # 2.5 h before OPEN
        h = desk.health(BOT["quality"], OPEN, [run("2026-11-10T13:00:00Z", "in_progress", None)], old, None, False)
        self.assertTrue(h["stale"])
        self.assertEqual(h["state"], "stale")
        self.assertEqual(h["snapshot_age_min"], 150)
        # After the close, a 4 PM snapshot is the last one and is fine.
        h = desk.health(BOT["quality"], EVENING, [run("2026-11-10T13:00:00Z")], snap("2026-11-10T21:00:00Z"), None, False)
        self.assertFalse(h["stale"])
        # 1 h 59 min old during the open: not stale yet.
        h = desk.health(BOT["quality"], OPEN, [run("2026-11-10T13:00:00Z")], snap("2026-11-10T14:01:00Z"), None, False)
        self.assertFalse(h["stale"])
        # No snapshot at all during the open counts as stale.
        h = desk.health(BOT["quality"], OPEN, [run("2026-11-10T13:00:00Z")], None, None, False)
        self.assertTrue(h["stale"])

    def test_crypto_stale_at_any_hour(self):
        night = t("2026-11-15T07:00:00")  # Sunday 3 AM Moncton
        h = desk.health(BOT["moonshot-crypto"], night, [run("2026-11-15T05:00:00Z")], snap("2026-11-15T04:00:00Z"), None, False)
        self.assertTrue(h["stale"])
        h = desk.health(BOT["stock-bot"], night, [], snap("2026-11-13T21:00:00Z"), None, False)
        self.assertFalse(h["stale"])
        self.assertEqual(h["state"], "closed")

    def test_holiday_and_early_close(self):
        thanksgiving = t("2026-11-26T16:00:00")
        h = desk.health(BOT["hot"], thanksgiving, [], snap("2026-11-25T21:00:00Z"), None, False)
        self.assertEqual(h["state"], "closed")
        self.assertFalse(h["stale"])
        # Nov 27 closes at 1 PM New York: at 3 PM the 1 PM snapshot isn't stale.
        h = desk.health(BOT["hot"], t("2026-11-27T20:00:00"), [run("2026-11-27T14:00:00Z")],
                        snap("2026-11-27T18:00:00Z"), None, False)
        self.assertFalse(h["stale"])

    def test_failed_streak_ignores_cancelled(self):
        runs = [run("2026-11-10T15:00:00Z", conclusion="failure"),
                run("2026-11-10T14:40:00Z", conclusion="cancelled"),   # queue swap: ignored
                run("2026-11-10T14:00:00Z", conclusion="timed_out"),
                run("2026-11-09T14:00:00Z", conclusion="success"),
                run("2026-11-08T14:00:00Z", conclusion="failure")]
        h = desk.health(BOT["volatility"], OPEN, runs, snap("2026-11-10T15:50:00Z"), None, False)
        self.assertTrue(h["last_run_failed"])
        self.assertEqual(h["failed_in_a_row"], 2)
        self.assertEqual(h["state"], "failed")
        # A cancelled run alone is not a failure.
        h = desk.health(BOT["volatility"], OPEN, [run("2026-11-10T15:00:00Z", conclusion="cancelled")],
                        snap("2026-11-10T15:50:00Z"), None, False)
        self.assertFalse(h["last_run_failed"])

    def test_trades_today_in_moncton_time(self):
        acct = {"orders": [{"time": "2026-11-10T14:35:00+00:00"},
                           {"time": "2026-11-10T19:59:00+00:00"},
                           {"time": "2026-11-10T03:00:00+00:00"},   # Mon Nov 9, 11 PM Moncton
                           {"time": "2026-11-09T15:00:00+00:00"}]}
        h = desk.health(BOT["hot"], OPEN, [run("2026-11-10T14:00:00Z")], snap("2026-11-10T15:50:00Z"), acct, False)
        self.assertEqual(h["trades_today"], 2)

    def test_paused_wins(self):
        h = desk.health(BOT["hot"], OPEN, [run("2026-11-10T15:00:00Z", conclusion="failure")], None, None, True)
        self.assertEqual(h["state"], "paused")
        self.assertIn("research bot", h["why"])


class Scoreboard(unittest.TestCase):
    def test_momentum_by_hand(self):
        # Momentum's real 4 PM numbers on Nov 10: $1,027.15 vs holding SPY $1,049.79, $1,070.30 put in.
        s = snap("2026-11-10T21:00:08Z", value=1027.15, hold=1049.79, start=1070.3,
                 started="2026-09-28T15:02:28+00:00")
        row = desk.score(BOT["momentum"], EVENING, s)
        self.assertEqual(row["vs_hold"], -22.64)                # 1027.15 - 1049.79
        self.assertEqual(row["vs_hold_pct"], -2.12)             # -22.64 / 1070.30 = -2.115%
        self.assertFalse(row["beats_holding"])
        self.assertEqual(row["days"], 43)
        self.assertFalse(row["too_early"])
        self.assertEqual(row["benchmark"], "SPY")

    def test_young_winner_is_labelled_too_early(self):
        s = snap("2026-11-10T21:00:00Z", value=1073.19, hold=1020.31, started="2026-11-05T18:06:17+00:00")
        row = desk.score(BOT["volatility"], EVENING, s)
        self.assertTrue(row["beats_holding"])
        self.assertTrue(row["too_early"])

    def test_moonshot_uses_its_own_benchmark(self):
        s = snap("2026-11-10T23:04:51Z", value=965.75, hold=914.41, bench_key="bench_value", benchmark="Bitcoin")
        row = desk.score(BOT["moonshot-crypto"], EVENING, s)
        self.assertEqual(row["vs_hold"], 51.34)
        self.assertEqual(row["benchmark"], "Bitcoin")

    def test_missing_numbers_mean_unknown_not_a_loss(self):
        row = desk.score(BOT["hot"], EVENING, None)
        self.assertIsNone(row["beats_holding"])
        self.assertIsNone(row["vs_hold"])


def fleet(now, value=1000.0, trades_each=0, failures=None, updated="2026-11-10T15:50:00Z"):
    runs, snaps, accts = {}, {}, {}
    for rb in desk.ROBOTS:
        rid = rb["id"]
        runs[rid] = [run("2026-11-10T14:00:00Z", conclusion="failure")] * (failures or {}).get(rid, 0) or \
            [run("2026-11-10T14:00:00Z")]
        snaps[rid] = snap(updated, value=value, hold=1000.0)
        accts[rid] = {"orders": [{"time": "2026-11-10T15:00:00+00:00"}] * trades_each}
    return runs, snaps, accts


class StopRules(unittest.TestCase):
    def test_quiet_day_no_stop(self):
        d = desk.build(OPEN, *fleet(OPEN, trades_each=2), prev_desk=None, paused=False)
        self.assertEqual(d["stop_reasons"], [])
        self.assertTrue(d["paper"])
        self.assertIn("as_of", d)
        self.assertEqual(d["desk"]["ran_today"], 7)
        self.assertIn("7/7 ran today", d["line"])
        self.assertIn("paused: no", d["line"])

    def test_too_many_trades(self):
        d = desk.build(OPEN, *fleet(OPEN, trades_each=6), prev_desk=None, paused=False)  # 42 > 40
        self.assertEqual(len(d["stop_reasons"]), 1)
        self.assertIn("42 practice trades", d["stop_reasons"][0])

    def test_three_failed_runs_in_a_row(self):
        d = desk.build(OPEN, *fleet(OPEN, failures={"hot": 3}), prev_desk=None, paused=False)
        self.assertTrue(any("Hot hands" in r for r in d["stop_reasons"]))
        d = desk.build(OPEN, *fleet(OPEN, failures={"hot": 2}), prev_desk=None, paused=False)
        self.assertEqual(d["stop_reasons"], [])

    def test_desk_day_drop(self):
        prev = {"day_open": {"date": "2026-11-10", "total": 7000.0}}
        d = desk.build(OPEN, *fleet(OPEN, value=940.0), prev_desk=prev, paused=False)  # 6580 = -6.0%
        self.assertTrue(any("down 6.0%" in r for r in d["stop_reasons"]))
        d = desk.build(OPEN, *fleet(OPEN, value=960.0), prev_desk=prev, paused=False)  # 6720 = -4.0%
        self.assertEqual(d["stop_reasons"], [])

    def test_baseline_resets_each_moncton_day(self):
        prev = {"day_open": {"date": "2026-11-09", "total": 9000.0}}
        d = desk.build(OPEN, *fleet(OPEN, value=1000.0), prev_desk=prev, paused=False)
        self.assertEqual(d["day_open"], {"date": "2026-11-10", "total": 7000.0})
        self.assertEqual(d["stop_reasons"], [])

    def test_missing_robot_skips_the_drop_check(self):
        prev = {"day_open": {"date": "2026-11-10", "total": 7000.0}}
        runs, snaps, accts = fleet(OPEN, value=500.0)
        snaps["hot"] = None
        d = desk.build(OPEN, runs, snaps, accts, prev, False)
        self.assertIsNone(d["desk"]["total_value"])
        self.assertEqual(d["stop_reasons"], [])


class PauseSwitch(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.pause = os.path.join(self.dir.name, "PAUSE")

    def tearDown(self):
        self.dir.cleanup()

    def test_creates_pause_with_reason(self):
        self.assertTrue(desk.create_pause(self.pause, ["42 practice trades today"], OPEN))
        text = read(self.pause)
        self.assertIn("42 practice trades today", text)
        self.assertIn("Matthew deletes it", text)
        self.assertIn("research bot", text)

    def test_never_overwrites_existing_pause(self):
        with open(self.pause, "w") as f:
            f.write("Matthew's own pause\n")
        self.assertFalse(desk.create_pause(self.pause, ["anything"], OPEN))
        self.assertEqual(read(self.pause), "Matthew's own pause\n")

    def test_main_creates_pause_on_stop_and_keeps_it(self):
        runs, snaps, accts = fleet(OPEN, trades_each=6)
        d = desk.build(OPEN, runs, snaps, accts, None, False)
        self.assertTrue(d["stop_reasons"])
        self.assertTrue(desk.create_pause(self.pause, d["stop_reasons"], OPEN))
        # Next run, all quiet again: the desk reports paused and leaves the file alone.
        d2 = desk.build(OPEN, *fleet(OPEN), prev_desk=d, paused=os.path.exists(self.pause))
        self.assertEqual(d2["stop_reasons"], [])
        self.assertTrue(d2["paused"])
        self.assertTrue(os.path.exists(self.pause))
        self.assertIn("paused: YES", d2["line"])


class HardLines(unittest.TestCase):
    """The desk can't reach broker code, can't delete, can't force-push."""

    def setUp(self):
        self.src = read(os.path.join(HERE, "desk.py"))
        self.code = re.sub(r'"""[\s\S]*?"""', "", self.src)  # code without docstrings
        self.yml = read(os.path.join(ROOT, ".github", "workflows", "robot-desk.yml"))

    def test_no_broker_or_order_code(self):
        for bad in ("moomoo", "paper_broker", "alpaca", "place_order", "submit_order", "buy(", "sell(",
                    "live_auto_trade", "workflow run", "workflow_dispatch", "/dispatches"):
            self.assertNotIn(bad, self.code.lower(), bad)

    def test_never_deletes_files(self):
        for bad in ("os.remove", "shutil", "rmtree", "os.rename", "os.replace", "truncate", '"rm"', "git rm"):
            self.assertNotIn(bad, self.code, bad)
        # The only unlink is its own temp file in publish().
        self.assertEqual(re.findall(r"\bunlink\(([^)]*)\)", self.code), ["f.name"])
        # PAUSE is only ever opened in create-only mode.
        self.assertIn('open(path, "x")', self.code)
        self.assertNotRegex(self.code, r"open\(PAUSE_FILE")

    def test_writes_only_desk_json(self):
        writes = re.findall(r'open\(([^)]*),\s*"[wax]"\)', self.code)
        self.assertEqual(sorted(writes), ["DESK_FILE", "path"])

    def test_never_force_pushes(self):
        for text in (self.code, self.yml):
            pushes = re.findall(r"push[^\n]*", text)
            self.assertTrue(pushes)
            for line in pushes:
                self.assertNotRegex(line, r"(\s|\")-f\b|--force|\+[\w{]", line)

    def test_workflow_commits_only_pause(self):
        adds = re.findall(r"git add ([^\n]*)", self.yml)
        self.assertEqual(adds, ["stock_bot/PAUSE"])
        self.assertNotIn("git rm", self.yml)
        self.assertNotIn("rm ", self.yml)
        self.assertNotIn("${{ secrets", self.yml)

    def test_seven_robots(self):
        self.assertEqual([r["id"] for r in desk.ROBOTS],
                         ["stock-bot", "momentum", "hot", "moonshot", "moonshot-crypto", "quality", "volatility"])
        for r in desk.ROBOTS:
            self.assertTrue(os.path.exists(os.path.join(ROOT, ".github", "workflows", r["workflow"])), r["workflow"])
            self.assertTrue(os.path.exists(os.path.join(HERE, r["account"])), r["account"])


if __name__ == "__main__":
    unittest.main()
