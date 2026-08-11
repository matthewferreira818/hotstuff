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
import urllib.parse
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


def public_path_count(path: str, start: dt.date | None = None) -> int:
    """Unique count for one tracked path/event via the public counter API."""
    url = f"{SITE}/counter/{urllib.parse.quote(path, safe='')}.json"
    if start:
        url += f"?start={start.isoformat()}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=30) as resp:
            return int(json.load(resp)["count_unique"])
    except Exception:  # noqa: BLE001 - a missing counter is a zero, not a failure
        return 0


# Channel tags fired as "ref-<tag>" events by the pages (see the attribution
# snippet in index.html). ?ref= alone never lands in GoatCounter's path list —
# it is GoatCounter's own referrer-override parameter.
REF_CHANNELS = [
    ("x", "X posts"),
    ("pin", "Pinterest product pins"),
    ("pin-ecs", "Pinterest ECS pins"),
    ("ecs", "ECS daily caption"),
    ("tt", "TikTok product QR"),
    ("tt-ecs", "TikTok agent QR"),
    ("print", "Print QR (flyers/cards)"),
    ("sample", "Sample-pack QR"),
]

# Contact-tap events fired by the automation pages (sms:/tel:/mailto: links).
# At this traffic level a tap IS the conversion — report them alongside views.
CTA_EVENTS = [
    ("cta-text", "Text taps"),
    ("cta-call", "Call taps"),
    ("cta-email", "Email taps"),
]


def channel_breakdown(start: dt.date | None = None) -> list[tuple[str, str, int]]:
    rows = [(tag, label, public_path_count(f"ref-{tag}", start)) for tag, label in REF_CHANNELS]
    return sorted(rows, key=lambda r: -r[2])


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
    # channel attribution — always from the public counters, token or not
    rows = channel_breakdown()
    if any(n for _, _, n in rows):
        print("channels (all-time):  " + " · ".join(f"{tag}={n}" for tag, _, n in rows if n))
        top_tag, top_label, top_n = rows[0]
        msg += f" · top channel: {top_label} ({top_n})"
    else:
        print("channels: no ref- events recorded yet (tracking just added, or no tagged visits)")

    # contact taps — the ECS conversion signal. A tap today belongs in the ping.
    taps_today = [(t, lbl, public_path_count(t, start=atlantic_now.date())) for t, lbl in CTA_EVENTS]
    taps_all = [(t, lbl, public_path_count(t)) for t, lbl in CTA_EVENTS]
    if any(n for _, _, n in taps_all):
        print("contact taps (all-time): " + " · ".join(f"{t}={n}" for t, _, n in taps_all if n))
    today_taps = sum(n for _, _, n in taps_today)
    if today_taps:
        msg += f" · 🎯 {today_taps} contact tap{'s' if today_taps != 1 else ''} today!"

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
