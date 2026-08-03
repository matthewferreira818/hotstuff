"""
Pushes a website-traffic snapshot to Matthew's phone via ntfy.

Pulls pageview counts from GoatCounter (last 3 hours + today so far) and
posts a short notification to the private ntfy topic. Runs every 3 hours
from .github/workflows/traffic-report.yml; safe to run by hand:

    GOATCOUNTER_TOKEN=... NTFY_TOPIC=... python traffic_report.py

Without GOATCOUNTER_TOKEN it falls back to the site's public visitor-counter
endpoint, which needs no auth but only has day precision — the ping then
shows today/this-week instead of a 3-hour window.

Failures exit non-zero so the workflow shows red instead of silently dying.
"""

import datetime as dt
import json
import os
import sys
import urllib.request

SITE = "https://theycallmemattyb.goatcounter.com"


def gc_total(token: str, start: dt.datetime, end: dt.datetime) -> int:
    """Total pageview count between two UTC datetimes."""
    qs = (f"start={start.strftime('%Y-%m-%dT%H:%M:%SZ')}"
          f"&end={end.strftime('%Y-%m-%dT%H:%M:%SZ')}")
    req = urllib.request.Request(
        f"{SITE}/api/v0/stats/total?{qs}",
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)["total"]


def public_count(start: dt.date | None = None) -> int:
    """Site-wide unique-visitor count from the public counter API (no token).

    Counts GoatCounter's special TOTAL path (= whole site); day precision.
    """
    url = f"{SITE}/counter/TOTAL.json"
    if start:
        url += f"?start={start.isoformat()}"
    with urllib.request.urlopen(urllib.request.Request(url), timeout=30) as resp:
        return int(json.load(resp)["count_unique"])


def main() -> None:
    token = os.environ.get("GOATCOUNTER_TOKEN")
    topic = os.environ.get("NTFY_TOPIC")
    if not topic:
        # secret not configured yet -- skip quietly so scheduled runs stay
        # green until setup is finished, instead of spamming red failures
        print("NTFY_TOPIC not set; skipping")
        return

    now = dt.datetime.now(dt.timezone.utc)
    # "today" in Atlantic time, where Matthew and most customers are
    atlantic_now = now - dt.timedelta(hours=3)  # ADT = UTC-3

    if token:
        last3h = gc_total(token, now - dt.timedelta(hours=3), now)
        midnight_utc = (atlantic_now.replace(hour=0, minute=0, second=0)
                        + dt.timedelta(hours=3))
        today = gc_total(token, midnight_utc, now)

        # fuller totals for the workflow log (the phone ping stays short)
        week = gc_total(token, now - dt.timedelta(days=7), now)
        alltime = gc_total(token, dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc), now)
        print(f"totals: all-time={alltime} · 7d={week} · today={today} · last3h={last3h}")

        msg = f"{last3h} views in the last 3h · {today} so far today"
        busy = last3h
    else:
        today = public_count(start=atlantic_now.date())
        week = public_count(start=(now - dt.timedelta(days=7)).date())
        alltime = public_count()
        print(f"totals (public counter): all-time={alltime} · 7d={week} · today={today}")

        msg = f"{today} visitors so far today · {week} this week"
        busy = today
    req = urllib.request.Request(
        f"https://ntfy.sh/{topic}",
        data=msg.encode(),
        headers={"Title": "HotsTuff traffic", "Tags": "fire",
                 "Priority": "default" if busy else "min"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()
    print(f"sent: {msg}")


if __name__ == "__main__":
    main()
