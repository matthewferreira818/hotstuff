#!/usr/bin/env python3
"""Plain-code ideas: small rules that look at past prices and make a call.
PRACTICE MONEY ONLY.

The SAME functions run in the history replay (replay.py) and in the live
forecaster (generate.py), so what was tested is exactly what forecasts.

An idea gets a History (prices up to the decision bar and NOTHING after it:
asking for a later price raises an error) and its settings, and returns
None (no call) or ("up" | "down", probability the direction is right).

Add a new idea: write the function, add it to IDEAS with a short plain-English
description and a small grid of settings. Every (idea, settings, horizon)
the replay tries is logged and counted.
"""


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
}


def call(name, h, params):
    return IDEAS[name]["fn"](h, params)
