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
from pathlib import Path

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
    ("x-qr", "X QR replies"),
    ("pin", "Pinterest product pins"),
    ("pin-ecs", "Pinterest ECS pins"),
    ("ecs", "ECS daily caption"),
    ("fb", "Facebook posts/groups"),
    ("fb-ad", "Moncton group ad slot"),
    ("gbp", "Google Business Profile"),
    ("tt", "TikTok product QR"),
    ("tt-ecs", "TikTok agent QR"),
    ("print", "Print QR (flyers)"),
    ("card", "Business cards"),
    ("sample", "Sample-pack QR (generic)"),
    ("merch", "Merch QR (the sweater)"),
]

# Own-visit exclusion took effect Aug 12 (laptop toggled out of GoatCounter);
# numbers before this date include Matthew's own browsing. Channel windows
# never reach back past it, so the phone ping stays decision-grade.
CLEAN_BASELINE = dt.date(2026, 8, 12)


def window_start(today: dt.date) -> dt.date:
    """Rolling 7-day window, clipped so it never includes pre-baseline days."""
    return max(today - dt.timedelta(days=7), CLEAN_BASELINE)


def sample_slugs() -> list[str]:
    """Per-prospect sample-pack slugs (ref-sample-<slug> events), from the
    registry sample_week.py maintains. Missing registry = no packs yet."""
    import json as _json
    reg = (Path(__file__).parent / "marketing" / "east-coast-social"
           / "engine" / "samples" / "registry.json")
    try:
        return list(_json.loads(reg.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        return []


def staleness_alerts(today: dt.date) -> list[str]:
    """Watchdog for the two assets that must never silently rot: the store
    catalog (refreshes every 3 days) and the ECS proof feed (daily post)."""
    import json as _json
    import subprocess
    alerts = []
    root = Path(__file__).parent

    try:
        entries = _json.loads((root / "automation" / "feed" / "index.json")
                              .read_text(encoding="utf-8"))
        newest = dt.date.fromisoformat(entries[0]["date"])
        age = (today - newest).days
        if age >= 2:
            alerts.append(f"ECS proof feed stale: newest post {newest} ({age} days old)")
    except (OSError, ValueError, KeyError, IndexError) as exc:
        alerts.append(f"ECS proof feed unreadable: {exc}")

    try:
        out = subprocess.run(
            ["git", "log", "-1", "--format=%ct", "--", "products.json"],
            cwd=root, capture_output=True, text=True, timeout=30)
        ts = int(out.stdout.strip() or 0)
        if ts:
            age_days = (dt.datetime.now(dt.timezone.utc).timestamp() - ts) / 86400
            if age_days > 4:
                alerts.append(f"Catalog stale: products.json last refreshed {age_days:.1f} days ago")
        # empty ts = shallow checkout without the file's history; stay quiet
        # rather than cry wolf (the workflow fetches enough depth normally)
    except (OSError, ValueError, subprocess.SubprocessError):
        pass

    return alerts

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
    # channel attribution — always from the public counters, token or not.
    # Windowed to the last 7 clean days so the ping reflects what's pulling
    # NOW, not inflated all-time history.
    wstart = window_start(atlantic_now.date())
    rows = channel_breakdown(start=wstart)
    rows_all = channel_breakdown()
    if any(n for _, _, n in rows_all):
        print(f"channels (since {wstart}): " + (" · ".join(f"{tag}={n}" for tag, _, n in rows if n) or "none"))
        print("channels (all-time):  " + " · ".join(f"{tag}={n}" for tag, _, n in rows_all if n))
    else:
        print("channels: no ref- events recorded yet (no tagged visits)")
    if any(n for _, _, n in rows):
        top_tag, top_label, top_n = rows[0]
        msg += f" · top channel 7d: {top_label} ({top_n})"

    # per-prospect sample packs — a scan is the highest-intent signal there is
    scans = [(slug, public_path_count(f"ref-sample-{slug}", start=wstart))
             for slug in sample_slugs()]
    hot = [(slug, n) for slug, n in scans if n]
    if hot:
        print("sample-pack scans (7d): " + " · ".join(f"{s}={n}" for s, n in hot))
        msg += " · 📦 pack scanned: " + ", ".join(s for s, _ in hot)

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

    # watchdog: separate, loud ping only when a proof asset has gone stale
    alerts = staleness_alerts(atlantic_now.date())
    if alerts:
        body = "\n".join(alerts)
        print("WATCHDOG: " + " | ".join(alerts))
        wreq = urllib.request.Request(
            f"https://ntfy.sh/{topic}",
            data=body.encode(),
            headers={"Title": "Engine watchdog - something is stale",
                     "Tags": "warning", "Priority": "high"},
        )
        with urllib.request.urlopen(wreq, timeout=30) as resp:
            resp.read()


if __name__ == "__main__":
    main()
