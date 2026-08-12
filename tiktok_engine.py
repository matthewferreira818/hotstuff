"""
TikTok draft publisher for the HotsTuff Engine app (Content Posting API,
sandbox/draft mode). Two jobs, picked by the first CLI argument:

    connect  - one-time: exchange the OAuth code for tokens. The refresh
               token is delivered to Matthew's phone via the private ntfy
               topic (never printed to logs — this repo is public), and he
               pastes it into the TIKTOK_REFRESH_TOKEN secret box.

    post     - daily: refresh the access token and push today's TikTok
               slide packs into the account as DRAFTS (MEDIA_UPLOAD mode).
               The drafts arrive as TikTok inbox notifications; Matthew
               opens each, adds a sound, and taps Post — he stays the
               publisher, the engine stays the builder.

Env (from GitHub Actions secrets):
    TIKTOK_CLIENT_KEY / TIKTOK_CLIENT_SECRET   sandbox app credentials
    TIKTOK_REFRESH_TOKEN                       after the connect step
    TIKTOK_CODE                                connect mode only
    NTFY_TOPIC                                 token delivery + failure pings

Skips silently (exit 0) when secrets aren't configured yet, like the X
poster. Photo posting is PULL_FROM_URL only, and media URLs must sit under
the TikTok-verified prefix https://findhotstuff.com/ — the daily slide
files do, since the site serves straight from this repo.
"""

import json
import os
import re
import sys
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

HERE = Path(__file__).parent
TOKEN_URL = "https://open.tiktokapis.com/v2/oauth/token/"
CONTENT_INIT_URL = "https://open.tiktokapis.com/v2/post/publish/content/init/"
REDIRECT_URI = "https://findhotstuff.com/tiktok-callback/"
SITE = "https://findhotstuff.com"
SLIDES = "marketing/tiktok/daily"


def http_json(url, data=None, headers=None, form=False):
    body = None
    headers = dict(headers or {})
    if data is not None:
        if form:
            body = urllib.parse.urlencode(data).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            body = json.dumps(data).encode()
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp), resp.status
    except urllib.error.HTTPError as exc:
        try:
            return json.load(exc), exc.code
        except Exception:  # noqa: BLE001
            return {"error": str(exc)}, exc.code


def ntfy(topic, title, message, priority="default", tags="robot"):
    if not topic:
        return
    req = urllib.request.Request(
        f"https://ntfy.sh/{topic}", data=message.encode(),
        headers={"Title": title, "Tags": tags, "Priority": priority})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp.read()
    except Exception as exc:  # noqa: BLE001
        print(f"ntfy failed: {exc}")


def env(name):
    """Secrets arrive via copy-paste; scrub stray whitespace/newlines."""
    return (os.environ.get(name) or "").strip()


def connect():
    key = env("TIKTOK_CLIENT_KEY")
    secret = env("TIKTOK_CLIENT_SECRET")
    code = env("TIKTOK_CODE")
    topic = env("NTFY_TOPIC")
    if not (key and secret and code):
        print("connect needs TIKTOK_CLIENT_KEY, TIKTOK_CLIENT_SECRET and TIKTOK_CODE")
        return 1

    data, status = http_json(TOKEN_URL, form=True, data={
        "client_key": key, "client_secret": secret, "code": code,
        "grant_type": "authorization_code", "redirect_uri": REDIRECT_URI,
    })
    refresh = data.get("refresh_token")
    if not refresh:
        # error details are safe to log; they contain no credentials
        print(f"token exchange failed (HTTP {status}): "
              f"{data.get('error_description') or data.get('error') or data}")
        ntfy(topic, "TikTok connect failed",
             "The code exchange didn't work — codes expire fast, grab a "
             "fresh one and re-run the connect workflow.", "high", "warning")
        return 1

    open_id = data.get("open_id", "?")
    scope = data.get("scope", "?")
    print(f"token exchange OK — account open_id ...{open_id[-6:]}, scope: {scope}")
    print("refresh token delivered via ntfy (not logged — public repo)")
    ntfy(topic, "TikTok connected - one paste left",
         "Refresh token (paste into GitHub secret TIKTOK_REFRESH_TOKEN, "
         "then delete this notification):\n\n" + refresh,
         "high", "white_check_mark")
    return 0


def refresh_access_token(key, secret, refresh_token, topic):
    data, status = http_json(TOKEN_URL, form=True, data={
        "client_key": key, "client_secret": secret,
        "grant_type": "refresh_token", "refresh_token": refresh_token,
    })
    access = data.get("access_token")
    if not access:
        print(f"token refresh failed (HTTP {status}): "
              f"{data.get('error_description') or data.get('error') or data}")
        ntfy(topic, "TikTok drafts broken - reconnect needed",
             "The stored TikTok token stopped working. Re-run the connect "
             "flow (authorize link + connect workflow) to fix drafts.",
             "high", "warning")
        return None
    # TikTok can rotate the refresh token; ours lives in a GitHub secret we
    # can't rewrite from here, so shout if the stored one goes stale.
    new_refresh = data.get("refresh_token")
    if new_refresh and new_refresh != refresh_token:
        ntfy(topic, "TikTok refresh token rotated - update the secret",
             "Paste this new value into the TIKTOK_REFRESH_TOKEN secret "
             "(the old one may stop working):\n\n" + new_refresh,
             "high", "warning")
    return access


def todays_captions():
    """Product + agent captions from the pack's captions.md code fences."""
    text = (HERE / SLIDES / "captions.md").read_text(encoding="utf-8")
    fences = re.findall(r"```\n(.*?)\n```", text, re.S)
    product = fences[0].strip() if fences else "today's finds"
    agent = fences[1].strip() if len(fences) > 1 else ""
    return product, agent


def push_draft(access, image_urls, caption, label, topic):
    payload = {
        "media_type": "PHOTO",
        "post_mode": "MEDIA_UPLOAD",
        "post_info": {
            "title": caption[:90],
            "description": caption[:4000],
        },
        "source_info": {
            "source": "PULL_FROM_URL",
            "photo_cover_index": 0,
            "photo_images": image_urls,
        },
    }
    data, status = http_json(CONTENT_INIT_URL, data=payload,
                             headers={"Authorization": f"Bearer {access}"})
    err = (data.get("error") or {})
    code = err.get("code", "")
    if status == 200 and code in ("ok", ""):
        publish_id = (data.get("data") or {}).get("publish_id", "?")
        print(f"{label}: draft pushed (publish_id {publish_id})")
        return True
    if code == "spam_risk_too_many_pending_share":
        print(f"{label}: skipped — 5 unposted drafts are already waiting in TikTok")
        ntfy(topic, "TikTok drafts piling up",
             "5 unposted drafts are waiting in your TikTok inbox — post or "
             "discard some so new ones can arrive.", "default", "warning")
        return False
    print(f"{label}: draft failed (HTTP {status}): {err.get('message') or data}")
    return False


def post():
    key = env("TIKTOK_CLIENT_KEY")
    secret = env("TIKTOK_CLIENT_SECRET")
    refresh = env("TIKTOK_REFRESH_TOKEN")
    topic = env("NTFY_TOPIC")
    missing = [n for n, v in [("TIKTOK_CLIENT_KEY", key),
                              ("TIKTOK_CLIENT_SECRET", secret),
                              ("TIKTOK_REFRESH_TOKEN", refresh)] if not v]
    if missing:
        print(f"TikTok secrets not configured ({', '.join(missing)}) - skipping.")
        return 0

    access = refresh_access_token(key, secret, refresh, topic)
    if not access:
        return 1

    product_caption, agent_caption = todays_captions()
    stamp = date.today().isoformat()

    ok = push_draft(
        access,
        [f"{SITE}/{SLIDES}/product/product-{n}.png" for n in (1, 2, 3)]
        + [f"{SITE}/{SLIDES}/product/product-4-qr.png"],
        product_caption, "product pack", topic)

    ok2 = True
    if agent_caption:
        ok2 = push_draft(
            access,
            [f"{SITE}/{SLIDES}/agent/agent-{n}.png" for n in (1, 2, 3)],
            agent_caption, "agent pack", topic)

    if ok and ok2:
        ntfy(topic, "TikTok drafts ready",
             f"Both of today's packs ({stamp}) are in your TikTok inbox as "
             "drafts. Open the notification in TikTok, add a sound, tap Post.",
             "default", "rocket")
    return 0


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "post"
    if mode == "connect":
        return connect()
    return post()


if __name__ == "__main__":
    sys.exit(main())
