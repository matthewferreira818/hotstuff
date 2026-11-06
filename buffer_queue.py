"""Queue this cycle's TikTok videos in Buffer (GraphQL API, free plan).

Reads the newest marketing/tiktok/buffer/<cycle>/plan.json written by
make_buffer_cycle.py and, for each slot not yet queued, calls createPost
with the video's public findhotstuff.com URL and an exact dueAt. Buffer then
auto-publishes to the connected TikTok business profile. Post ids are
written back into plan.json so a re-run never double-queues.

OFF unless BOTH are set:
    BUFFER_POSTING=on   repo variable (Settings -> Variables), Matthew's switch
    BUFFER_API_KEY      repo secret, Matthew pastes it there himself
With either missing it prints what it WOULD queue and exits 0.

Optional: BUFFER_CHANNEL_ID (repo variable) if more than one TikTok channel
is ever connected. Otherwise the single TikTok channel is found by service.

Docs read 2026-11-05 on developers.buffer.com: guides/authentication,
guides/posts-and-scheduling, guides/hosting-media, guides/api-limits,
examples/create-video-post. Free plan: 1 API key, 150 requests / 15 min.
Buffer has no upload endpoint and fetches the URL when the post goes out,
so the file must stay at that URL until then (it does: the folder is only
deleted by the NEXT cycle, after every slot in this one has passed).
"""

from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests

HERE = Path(__file__).parent
ROOT = HERE / "marketing" / "tiktok" / "buffer"
API = "https://api.buffer.com"
URL_WAIT = 15 * 60          # Pages deploy after the commit, normally ~1-2 min


def latest_plan() -> Path | None:
    plans = sorted(ROOT.glob("20*/plan.json"))
    return plans[-1] if plans else None


def gql(key: str, query: str) -> dict:
    for attempt in range(4):
        r = requests.post(API, json={"query": query}, timeout=60,
                          headers={"Authorization": f"Bearer {key}",
                                   "Content-Type": "application/json"})
        if r.status_code == 429 and attempt < 3:
            wait = min(int(r.headers.get("Retry-After", "60")), 900)
            print(f"  rate limited, waiting {wait}s")
            time.sleep(wait + 2)
            continue
        if r.status_code == 401:
            raise SystemExit("Buffer said 401: BUFFER_API_KEY is wrong or revoked.")
        r.raise_for_status()
        body = r.json()
        if body.get("errors"):
            raise SystemExit(f"Buffer GraphQL error: {body['errors']}")
        return body["data"]
    raise SystemExit("Buffer kept rate-limiting; giving up for this run.")


def tiktok_channel(key: str) -> str:
    chosen = os.environ.get("BUFFER_CHANNEL_ID", "").strip()
    if chosen:
        return chosen
    orgs = gql(key, "query { account { organizations { id } } }")["account"]["organizations"]
    found = []
    for org in orgs:
        q = 'query { channels(input: {organizationId: %s}) { id service isQueuePaused } }' \
            % json.dumps(org["id"])
        for ch in gql(key, q)["channels"]:
            if str(ch.get("service", "")).lower() == "tiktok":
                found.append(ch)
    if len(found) != 1:
        raise SystemExit(f"Expected exactly 1 TikTok channel in Buffer, found {len(found)}. "
                         "Connect it (or set the BUFFER_CHANNEL_ID variable).")
    if found[0].get("isQueuePaused"):
        print("  NOTE: the TikTok queue is paused in Buffer; posts will wait there.")
    return found[0]["id"]


def wait_for(url: str) -> None:
    """Buffer fetches the file itself, so it must be live on the site first."""
    deadline = time.time() + URL_WAIT
    while True:
        try:
            r = requests.head(url, timeout=30, allow_redirects=False)
            if r.status_code == 200 and "video" in r.headers.get("Content-Type", ""):
                return
            status = r.status_code
        except requests.RequestException as exc:
            status = exc.__class__.__name__
        if time.time() > deadline:
            raise SystemExit(f"{url} still not live after {URL_WAIT // 60} min ({status}).")
        time.sleep(30)


def create_post(key: str, channel: str, day: dict) -> str:
    q = """mutation { createPost(input: {
      text: %s, channelId: %s, schedulingType: automatic,
      mode: customScheduled, dueAt: %s,
      assets: [{ video: { url: %s, metadata: { thumbnailOffset: 500 } } }]
    }) {
      ... on PostActionSuccess { post { id dueAt } }
      ... on MutationError { message }
    } }""" % (json.dumps(day["caption"], ensure_ascii=False), json.dumps(channel),
              json.dumps(day["due_at"]), json.dumps(day["url"]))
    res = gql(key, q)["createPost"]
    if "post" not in res:
        raise SystemExit(f"Buffer refused slot {day['slot']}: {res.get('message')}")
    return res["post"]["id"]


def key_check(key: str) -> None:
    """Dry-run proof that the secret is wired up, without revealing it: say
    whether it exists, then make READ-ONLY calls (account -> channels) to
    show it works and a TikTok channel is connected. Never creates posts,
    never prints the key or any id."""
    if not key:
        print("BUFFER_API_KEY secret: MISSING")
        return
    print("BUFFER_API_KEY secret: present")
    try:
        tiktok_channel(key)
        print("Buffer key check (read-only): key works, exactly 1 TikTok channel connected")
    except SystemExit as exc:
        print(f"Buffer key check (read-only) FAILED: {exc}")
    except requests.RequestException as exc:
        print(f"Buffer key check (read-only) FAILED: {exc.__class__.__name__}")


def main():
    plan_file = latest_plan()
    if not plan_file:
        print("No plan.json yet. Nothing to queue.")
        if os.environ.get("BUFFER_POSTING", "").strip().lower() != "on":
            key_check(os.environ.get("BUFFER_API_KEY", "").strip())
        return
    plan = json.loads(plan_file.read_text(encoding="utf-8"))
    now = datetime.now(timezone.utc)
    todo = [d for d in plan["days"] if not d.get("buffer_post_id")
            and datetime.fromisoformat(d["due_at"].replace("Z", "+00:00"))
            > now + timedelta(minutes=10)]

    posting = os.environ.get("BUFFER_POSTING", "").strip().lower() == "on"
    key = os.environ.get("BUFFER_API_KEY", "").strip()
    if not (posting and key):
        why = "BUFFER_POSTING is not 'on'" if not posting else "BUFFER_API_KEY is not set"
        print(f"POSTING OFF ({why}). Would queue {len(todo)} video(s):")
        for d in todo:
            print(f"  {d['due_at']}  {d['url']}\n    {d['caption']}")
        key_check(key)
        return

    if not todo:
        print("Everything in this cycle is already queued (or its time has passed).")
        return
    channel = tiktok_channel(key)
    for d in todo:
        wait_for(d["url"])
        d["buffer_post_id"] = create_post(key, channel, d)
        print(f"  queued slot {d['slot']} for {d['due_at']}")
        plan_file.write_text(json.dumps(plan, indent=2, ensure_ascii=False) + "\n",
                             encoding="utf-8")
    print(f"Queued {len(todo)} video(s) in Buffer.")


if __name__ == "__main__":
    sys.exit(main())
