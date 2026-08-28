"""
Publishes the generated daily card + caption to the East Coast Social
X (Twitter) account — the same card the Facebook poster uses, so one
engine feeds both channels.

Env (GitHub Actions secrets):
    ECS_X_API_KEY             app "API Key" (consumer key)
    ECS_X_API_SECRET          app "API Secret"
    ECS_X_ACCESS_TOKEN        user access token for the @ECS account
    ECS_X_ACCESS_TOKEN_SECRET user access token secret

Skips quietly when unset so the scheduled workflow stays green until the
X app is configured. Fails loudly on real API errors.
"""

import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))  # repo root

from ecs_site import ecs_url  # noqa: E402

SITE = ecs_url("ecs")
CREDS = ["ECS_X_API_KEY", "ECS_X_API_SECRET",
         "ECS_X_ACCESS_TOKEN", "ECS_X_ACCESS_TOKEN_SECRET"]

# X's pay-per-use tier bills a tweet containing a URL at ~13x the linkless
# rate ($0.20 vs $0.015), so by default the daily post drops the site link —
# the card's QR and the profile bio carry it instead. Set X_LINKLESS=0 to
# put the URL back if the economics ever change.
LINKLESS = os.environ.get("X_LINKLESS", "1").strip() != "0"


def strip_links(text: str) -> str:
    """Remove the site URL (and its arrow) so X doesn't detect a link."""
    text = re.sub(r"[➜→]?\s*(https?://)?\S*findhotstuff\.com\S*", "", text)
    return text.strip(" ,.;—-") + " · link in bio"


def x_text(caption: str) -> str:
    """Fit the caption into a tweet; X counts any URL as 23 chars."""
    if LINKLESS:
        caption = strip_links(caption)
    if len(caption) <= 270:
        return caption
    trimmed = caption[:230].rsplit(" ", 1)[0].rstrip(" ,.;—-")
    if LINKLESS:
        return f"{trimmed}… (link in bio)"
    return f"{trimmed}… ➜ {SITE}"


def main():
    missing = [c for c in CREDS if not os.environ.get(c)]
    if missing:
        print(f"{'/'.join(missing)} not set; skipping (X account not armed yet)")
        return

    from requests_oauthlib import OAuth1Session
    from tweet_media import upload_media

    session = OAuth1Session(
        os.environ["ECS_X_API_KEY"],
        client_secret=os.environ["ECS_X_API_SECRET"],
        resource_owner_key=os.environ["ECS_X_ACCESS_TOKEN"],
        resource_owner_secret=os.environ["ECS_X_ACCESS_TOKEN_SECRET"],
    )

    out = Path(__file__).parent / "out"
    caption = (out / "caption.txt").read_text(encoding="utf-8")
    media_id = upload_media(session, (out / "card.png").read_bytes())

    payload = {"text": x_text(caption)}
    if media_id:
        payload["media"] = {"media_ids": [str(media_id)]}
    resp = session.post("https://api.x.com/2/tweets", json=payload, timeout=30)
    if resp.status_code == 402:
        # Pay-per-use developer account with an empty credit balance: not a
        # code failure, so don't turn the whole daily workflow red — skip
        # politely until credits are added in the X developer console.
        print("X developer account has no credits — skipping today's X post "
              "(add credits at developer.x.com to arm this channel).")
        return
    if resp.status_code not in (200, 201):
        print(f"X post failed: {resp.status_code} {resp.text[:300]}", file=sys.stderr)
        sys.exit(1)
    print(f"posted to X: {resp.json().get('data', {}).get('id', '?')}")


if __name__ == "__main__":
    main()
