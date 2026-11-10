#!/usr/bin/env python3
"""Plain-code ideas: small rules that look at past prices and make a call.
PRACTICE MONEY ONLY.

The SAME functions run in the history replay (replay.py) and in the live
forecaster (generate.py), so what was tested is exactly what forecasts.

An idea gets a History (prices up to the decision bar and NOTHING after it:
asking for a later price raises an error) and its settings, and returns
None (no call) or ("up" | "down", probability the direction is right).

Add a new idea: write the function, add it to IDEAS with a short plain-English
description and a small grid of settings. Optional keys: "interval" ("1h" or
"1d"; default = the market's own), "markets" (default both), "horizons" (in
bars; default = the market's), "assets" (default = the market's list). Every (idea, settings, horizon)
the replay tries is logged and counted.
"""


from itertools import accumulate


class LookAheadError(IndexError):
    pass


class History:
    """Read-only view of closes[0..i]. h[-1] is the decision bar's close.
    Anything after bar i is out of reach on purpose (no peeking)."""

    __slots__ = ("_c", "_i")

    def __init__(self, closes, i):
        self._c, self._i = closes, i

    def __len__(self):
        return self._i + 1

    def __getitem__(self, k):
        if isinstance(k, slice):
            raise TypeError("use window(n)")
        j = self._i + 1 + k if k < 0 else k
        if j < 0:
            raise IndexError("not enough history")
        if j > self._i:
            raise LookAheadError("that price is in the future")
        return self._c[j]

    def window(self, n):
        if n > self._i + 1:
            raise IndexError("not enough history")
        return self._c[self._i + 1 - n:self._i + 1]


def typical_move_pct(h, horizon, samples=20):
    """Average size of a `horizon`-bar move over the last `samples` such
    moves (past only). Used as the expected downside and as the 'stop' for
    the gate's blow-through check."""
    need = samples * horizon + 1
    if len(h) < need:
        return None
    tot = 0.0
    for k in range(samples):
        a, b = h[-1 - (k + 1) * horizon], h[-1 - k * horizon]
        tot += abs(b / a - 1)
    return tot / samples * 100


# ------------------------------------------------------------------ ideas

def momentum(h, p):
    """Up if the price is higher than `lookback` bars ago, else down."""
    L = p["lookback"]
    if len(h) <= L:
        return None
    return ("up" if h[-1] > h[-1 - L] else "down", p["prob"])


def reversal(h, p):
    """After a fall of `drop_pct`+ over `lookback` bars, call a bounce (up);
    after a rise that big, call a pullback (down); otherwise no call."""
    L = p["lookback"]
    if len(h) <= L:
        return None
    chg = (h[-1] / h[-1 - L] - 1) * 100
    if chg <= -p["drop_pct"]:
        return ("up", p["prob"])
    if chg >= p["drop_pct"]:
        return ("down", p["prob"])
    return None


def trend(h, p):
    """Up while the price is above its `sma`-bar average, else down."""
    n = p["sma"]
    if len(h) < n:
        return None
    w = h.window(n)
    return ("up" if h[-1] > sum(w) / n else "down", p["prob"])


def drift(h, p):
    """Always up (markets have tended to rise). The honest 'just hold' idea,
    paying costs every window."""
    return ("up", p["prob"])


def _sma(h, n):
    return sum(h.window(n)) / n


# ---- Friday's list (Helm-Private research-bot/ideas-list.md, 2026-11-10), ideas 1-8.
# 9 (turn of the month: needs dates) and 10 (Bitcoin leads ETH: needs two assets)
# are parked: ideas here only see one asset's closes.

def long_trend(h, p):
    """1. Up while above the long (100/200-bar) average; otherwise no call."""
    n = p["sma"]
    if len(h) < n:
        return None
    return ("up", p["prob"]) if h[-1] > _sma(h, n) else None


def squeeze(h, p):
    """2. The last N closes before today span the narrowest N-bar range of the
    last M bars, and today closes above that range -> up."""
    n, m = p["n"], p["m"]
    if len(h) < m + n + 1:
        return None
    w = h.window(m + n + 1)  # oldest .. today
    today, past = w[-1], w[:-1]
    last = past[-n:]
    width = max(last) - min(last)
    narrowest = min(max(past[k:k + n]) - min(past[k:k + n]) for k in range(len(past) - n + 1))
    return ("up", p["prob"]) if width <= narrowest and today > max(last) else None


def big_drop(h, p):
    """3. A 1-bar drop bigger than K x the typical 1-bar move -> bounce (up)."""
    if len(h) < 23:
        return None
    w = h.window(22)
    moves = [abs(w[k] / w[k - 1] - 1) for k in range(1, 21)]  # the 20 moves before today
    typical = sum(moves) / 20
    drop = 1 - w[-1] / w[-2]
    return ("up", p["prob"]) if typical > 0 and drop > p["k"] * typical else None


def near_high(h, p):
    """4. Within X% of the highest close of the last 252 bars -> up."""
    if len(h) < 252:
        return None
    return ("up", p["prob"]) if h[-1] >= max(h.window(252)) * (1 - p["x_pct"] / 100) else None


def two_clocks(h, p):
    """5. Up only if both the long and the short returns are positive."""
    long_, short = p["long"], p["short"]
    if len(h) <= long_:
        return None
    return ("up", p["prob"]) if h[-1] > h[-1 - long_] and h[-1] > h[-1 - short] else None


def calm_momentum(h, p):
    """6. 20-bar momentum, but no call when the 20-bar volatility (average size
    of a 1-bar move) is above `ratio` x its median over the last 250 bars."""
    if len(h) < 271:
        return None
    w = h.window(271)
    a = [abs(w[k] / w[k - 1] - 1) for k in range(1, 271)]  # 270 one-bar moves
    sums = list(accumulate(a))
    vols = [(sums[k] - (sums[k - 20] if k >= 20 else 0)) / 20 for k in range(19, 270)]
    now = vols[-1]
    med = sorted(vols[-250:])[125]
    if now > p["ratio"] * med:
        return None
    return ("up" if h[-1] > h[-21] else "down", p["prob"])


def losing_streak(h, p):
    """7. After K down closes in a row -> up."""
    k = p["k"]
    if len(h) < k + 2:
        return None
    w = h.window(k + 1)
    return ("up", p["prob"]) if all(w[i] < w[i - 1] for i in range(1, k + 1)) else None


def cross(h, p):
    """8. Up only on the bar where the fast average crosses above the slow one."""
    f, s = p["fast"], p["slow"]
    if len(h) < s + 1:
        return None
    now = _sma(h, f) > _sma(h, s)
    w = h.window(s + 1)[:-1]
    before = sum(w[-f:]) / f > sum(w) / s
    return ("up", p["prob"]) if now and not before else None


PROBS = (0.52, 0.56)
BOTH = ("stock", "crypto")

IDEAS = {
    "momentum": {"fn": momentum, "text": "Up if higher than N bars ago, else down",
                 "grid": [{"lookback": L, "prob": pr} for L in (5, 20) for pr in (0.52, 0.56)]},
    "reversal": {"fn": reversal, "text": "Bounce after a big drop, pullback after a big rise",
                 "grid": [{"lookback": L, "drop_pct": d, "prob": pr}
                          for L in (5, 20) for d in (3, 8) for pr in (0.52, 0.56)]},
    "trend": {"fn": trend, "text": "Up while above its N-bar average, else down",
              "grid": [{"sma": n, "prob": pr} for n in (20, 50) for pr in (0.52, 0.56)]},
    "drift": {"fn": drift, "text": "Always up (hold in pieces, paying costs each time)",
              "grid": [{"prob": pr} for pr in (0.52, 0.56)]},
    # Friday's ideas: daily bars in both markets, their own horizons (in bars).
    "long_trend": {"fn": long_trend, "text": "Up while above its 100/200-bar average, else no call",
                   "interval": "1d", "markets": BOTH, "horizons": [10, 20],
                   "grid": [{"sma": n, "prob": pr} for n in (100, 200) for pr in PROBS]},
    "squeeze": {"fn": squeeze, "text": "Narrowest range in 90 bars, then a close above it -> up",
                "interval": "1d", "markets": ("crypto",), "horizons": [3, 5],
                "grid": [{"n": n, "m": 90, "prob": pr} for n in (10, 20) for pr in PROBS]},
    "big_drop": {"fn": big_drop, "text": "A 1-bar drop over K x the typical move -> bounce",
                 "interval": "1d", "markets": ("crypto",), "horizons": [3, 5],
                 "grid": [{"k": k, "prob": pr} for k in (2.5, 3.5) for pr in PROBS]},
    "near_high": {"fn": near_high, "text": "Within X% of the 1-year high -> up",
                  "interval": "1d", "markets": ("stock",), "horizons": [20],
                  "grid": [{"x_pct": x, "prob": pr} for x in (3, 5) for pr in PROBS]},
    "two_clocks": {"fn": two_clocks, "text": "Up only if long AND short returns are both up",
                   "interval": "1d", "markets": BOTH, "horizons": [10],
                   "grid": [{"long": a, "short": b, "prob": pr}
                            for a, b in ((60, 10), (90, 20)) for pr in PROBS]},
    "calm_momentum": {"fn": calm_momentum, "text": "20-bar momentum, sitting out wild stretches",
                      "interval": "1d", "markets": BOTH, "horizons": [10],
                      "grid": [{"ratio": r, "prob": pr} for r in (1.5, 2.0) for pr in PROBS]},
    "losing_streak": {"fn": losing_streak, "text": "After K down closes in a row -> up (SPY)",
                      "interval": "1d", "markets": ("stock",), "horizons": [5], "assets": ["SPY"],
                      "grid": [{"k": k, "prob": pr} for k in (3, 4) for pr in PROBS]},
    "cross": {"fn": cross, "text": "Up only on the day the fast average crosses above the slow",
              "interval": "1d", "markets": BOTH, "horizons": [20],
              "grid": [{"fast": f, "slow": s, "prob": pr}
                       for f, s in ((10, 50), (20, 100)) for pr in PROBS]},
}


def _pct(a, b):
    return (a / b - 1) * 100


def explain(name, h, params, direction, asset, horizon_text, replay=None):
    """A short, plain-English reason built from the SAME prices the idea just
    used (never invented). The technical `reason` stays for auditing."""
    p = params
    unit = "hours" if "hour" in horizon_text else ("trading days" if "trading" in horizon_text else "days")
    bet = f"so this rule bets it {'rises' if direction == 'up' else 'falls'} over the next {horizon_text}"
    try:
        if name == "momentum":
            c = _pct(h[-1], h[-1 - p["lookback"]])
            why = f"{asset} is {abs(c):.1f}% {'higher' if c > 0 else 'lower'} than {p['lookback']} {unit} ago, {bet}"
        elif name == "reversal":
            c = _pct(h[-1], h[-1 - p["lookback"]])
            why = (f"{asset} {'jumped' if c > 0 else 'dropped'} {abs(c):.1f}% in {p['lookback']} {unit} "
                   f"(more than {p['drop_pct']}%), {bet} as it snaps back")
        elif name == "trend":
            c = _pct(h[-1], sum(h.window(p["sma"])) / p["sma"])
            why = f"{asset} is {abs(c):.1f}% {'above' if c > 0 else 'below'} its {p['sma']}-{unit.split()[-1][:-1]} average, {bet}"
        elif name == "drift":
            why = f"This rule always bets {asset} rises over the next {horizon_text}"
        else:
            why = f"{asset}: {IDEAS[name]['text'].rstrip('.')}, {bet}"
    except (IndexError, ZeroDivisionError):
        why = f"{asset}: {IDEAS[name]['text'].rstrip('.')}, {bet}"
    replay = replay or {}
    if replay.get("verdict") == "PASS":
        tested = " It passed the past-price test."
    elif replay.get("pnl_after_costs") is not None and replay["pnl_after_costs"] < 0:
        tested = " In past-price tests it lost money after fees."
    elif replay.get("verdict") == "DEAD":
        tested = " It failed the past-price test."
    else:
        tested = ""
    return (f"{why}. The rule's set confidence is {round(p['prob'] * 100)}%.{tested} Practice only.")


def call(name, h, params):
    """A bad price in the data (a zero close) means no call, never a crash."""
    try:
        return IDEAS[name]["fn"](h, params)
    except ZeroDivisionError:
        return None
