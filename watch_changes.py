"""
Change watcher: pings the phone ONLY when something newsworthy changes.

The other monitors cover breakage (watchdog = uptime, smoke test = features).
This one covers the signals worth interrupting a workday for, none of which
are failures:

  - a Buy-now click on any current product (buy-<id> events)
  - the first visit from a tagged channel (ref-<tag> events, incl. per-prospect
    sample tags from the engine's registry)
  - a completed checkout (/success.html count rising)
  - a traffic spike (today >= SPIKE_MIN and >= SPIKE_FACTOR x the 7-day pace)
  - a stale catalog (no "Refresh:" commit for STALE_DAYS — the rotation's
    backup crons all failing is otherwise invisible while the site looks fine)

State lives in watch-state.json, cached between runs by the workflow
(actions/cache). No state file = first run: seed silently, alert nothing —
a fresh cache after eviction must not replay old news. Everything here reads
public endpoints; the only secret is the ntfy topic.

    NTFY_TOPIC=... python watch_changes.py          # normal
    QUIET=1 python watch_changes.py                  # log only, no pushes

Runs every 2 hours (offset from the traffic report). GoatCounter's counter
endpoints are day-precision and cached ~15 min upstream, which is plenty.

Note: Matthew's laptop is excluded from GoatCounter but his phone is not, so
a burst of his own phone visits can trip the spike/buy alerts. Known cost of
free analytics; ignore alerts you caused yourself.
"""

import datetime as dt
import json
import os
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent
STATE_FILE = HERE / "watch-state.json"
GC = "https://theycallmemattyb.goatcounter.com"
SITE = "https://findhotstuff.com"
SAMPLE_REGISTRY = HERE / "marketing" / "east-coast-social" / "engine" / "samples" / "registry.json"

REF_TAGS = ["x", "x-qr", "pin", "pin-ecs", "ecs", "tt", "tt-ecs",
            "gbp", "print", "card", "fb", "tt-bio", "ig"]
CHANNEL_LABELS = {
    "x": "X posts", "x-qr": "X QR card", "pin": "Pinterest pins",
    "pin-ecs": "Pinterest ECS pins", "ecs": "ECS daily caption",
    "tt": "TikTok QR", "tt-ecs": "TikTok agent QR", "gbp": "Google Business",
    "print": "print flyer QR", "card": "business card QR",
    "tt-bio": "TikTok bio", "ig": "Instagram", "fb": "Facebook",
}

SPIKE_FACTOR = 3.0   # today >= this x the 7-day daily pace ...
SPIKE_MIN = 15       # ... and at least this many, so small numbers can't trip it
STALE_DAYS = 4.0     # rotation cadence is 3 days + backup crons; 4 means broken


def counter(path: str, start: dt.date | None = None) -> int:
    url = f"{GC}/counter/{urllib.parse.quote(path, safe='')}.json"
    if start:
        url += f"?start={start.isoformat()}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=20) as r:
            return int(json.load(r)["count"])
    except Exception:  # noqa: BLE001 - a missing counter reads as zero
        return 0


def product_catalog() -> list[dict]:
    try:
        with urllib.request.urlopen(f"{SITE}/products.json", timeout=20) as r:
            return json.load(r)
    except Exception:  # noqa: BLE001
        return []


def ref_tags() -> list[str]:
    tags = list(REF_TAGS)
    try:
        for slug in json.loads(SAMPLE_REGISTRY.read_text()):
            tags.append(f"sample-{slug}")
    except (OSError, ValueError):
        pass
    return tags


def catalog_age_days() -> float | None:
    """Days since the last rotation commit, from the checked-out git history."""
    try:
        out = subprocess.run(
            ["git", "log", "-1", "--format=%ct", "--grep", "Refresh: trending products"],
            capture_output=True, text=True, cwd=HERE, check=True).stdout.strip()
        if not out:
            return None
        return (dt.datetime.now(dt.timezone.utc)
                - dt.datetime.fromtimestamp(int(out), dt.timezone.utc)).total_seconds() / 86400
    except Exception:  # noqa: BLE001 - shallow clone etc.; skip the check
        return None


def gather() -> dict:
    products = product_catalog()
    names = {p["id"]: p.get("name", p["id"]) for p in products}
    prices = {p["id"]: p.get("price") for p in products}

    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(8) as ex:
        buy = dict(zip(names, ex.map(lambda i: counter(f"buy-{i}"), names)))
        tags = ref_tags()
        ref = dict(zip(tags, ex.map(lambda t: counter(f"ref-{t}"), tags)))

    now = dt.datetime.now(dt.timezone.utc)
    atlantic_today = (now - dt.timedelta(hours=3)).date()
    return {
        "buy": {k: v for k, v in buy.items() if v},
        "ref": {k: v for k, v in ref.items() if v},
        "success": counter("/success.html"),
        "today": counter("TOTAL", start=atlantic_today),
        "week": counter("TOTAL", start=atlantic_today - dt.timedelta(days=7)),
        "names": names, "prices": prices,
        "today_str": atlantic_today.isoformat(),
    }


def diff_alerts(prev: dict, cur: dict) -> list[tuple[str, str, str]]:
    """(title, body, priority) for each newsworthy change since last run."""
    alerts = []

    for pid, n in sorted(cur["buy"].items()):
        old = prev.get("buy", {}).get(pid, 0)
        if n > old:
            name = cur["names"].get(pid, pid)
            price = cur["prices"].get(pid)
            body = f"{name}" + (f" (${price})" if price else "") + f" — {n} click(s) total"
            alerts.append(("🛒 Buy click!", body, "high"))

    for tag, n in sorted(cur["ref"].items()):
        old = prev.get("ref", {}).get(tag, 0)
        if n > old:
            label = CHANNEL_LABELS.get(tag, tag)
            first = " — first ever from this channel!" if old == 0 else ""
            alerts.append(("📈 Tagged visit", f"{label} (ref-{tag}): {n} total{first}",
                           "high" if old == 0 else "default"))

    if cur["success"] > prev.get("success", 0):
        alerts.append(("🎉 CHECKOUT COMPLETED",
                       f"success page views: {prev.get('success', 0)} -> {cur['success']}. "
                       f"Check Stripe + the /orders dashboard.", "urgent"))

    pace = max(cur["week"] / 7.0, 1.0)
    if (cur["today"] >= SPIKE_MIN and cur["today"] >= SPIKE_FACTOR * pace
            and prev.get("spike_day") != cur["today_str"]):
        alerts.append(("📊 Traffic spike",
                       f"{cur['today']} visits today vs ~{pace:.0f}/day pace. "
                       f"Check the GoatCounter dashboard for the source.", "default"))
        cur["spike_day"] = cur["today_str"]
    else:
        cur["spike_day"] = prev.get("spike_day")

    age = catalog_age_days()
    if age is not None and age > STALE_DAYS:
        marker = f"stale-{int(age)}"
        if prev.get("stale_marker") != marker:
            alerts.append(("⏰ Catalog stale",
                           f"Last rotation was {age:.1f} days ago (cadence is 3). "
                           f"Check the refresh workflow.", "high"))
        cur["stale_marker"] = marker
    else:
        cur["stale_marker"] = None

    return alerts


PRIORITY_NUM = {"min": 1, "low": 2, "default": 3, "high": 4, "urgent": 5}


def push(topic: str, title: str, body: str, priority: str) -> None:
    """Publish via ntfy's JSON endpoint. The header style used elsewhere in
    this repo can't carry the emoji in these titles — HTTP headers are
    latin-1 and urllib refuses — but a JSON body is plain UTF-8."""
    payload = json.dumps({
        "topic": topic, "title": title, "message": body,
        "priority": PRIORITY_NUM.get(priority, 3), "tags": ["eyes"],
    }).encode()
    req = urllib.request.Request(
        "https://ntfy.sh", data=payload,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        r.read()


def main() -> None:
    cur = gather()
    print(f"observed: buy={cur['buy']} ref={cur['ref']} success={cur['success']} "
          f"today={cur['today']} week={cur['week']}")

    if STATE_FILE.exists():
        prev = json.loads(STATE_FILE.read_text())
        alerts = diff_alerts(prev, cur)
    else:
        # first run (or cache evicted): seed silently so old news can't replay
        print("no previous state — seeding silently")
        diff_alerts(cur, cur)   # still populates spike/stale markers
        alerts = []

    state = {k: cur[k] for k in ("buy", "ref", "success", "spike_day", "stale_marker")}
    STATE_FILE.write_text(json.dumps(state, indent=1) + "\n")

    if os.environ.get("TEST_ALERT"):
        # end-to-end pipe check: workflow -> secret -> ntfy -> phone
        alerts.append(("🔔 Change watcher test",
                       "The pipe works. Real pings only happen on: buy click, "
                       "tagged visit, checkout, traffic spike, stale catalog.",
                       "default"))

    if not alerts:
        print("no changes worth a ping")
        return

    topic = os.environ.get("NTFY_TOPIC")
    quiet = bool(os.environ.get("QUIET"))
    for title, body, priority in alerts:
        print(f"ALERT [{priority}] {title}: {body}")
        if topic and not quiet:
            push(topic, title, body, priority)
    if not topic:
        print("(NTFY_TOPIC not set — alerts logged only)")


if __name__ == "__main__":
    main()
