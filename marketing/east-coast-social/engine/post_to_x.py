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
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))  # repo root

SITE = "https://findhotstuff.com/automation/"
CREDS = ["ECS_X_API_KEY", "ECS_X_API_SECRET",
         "ECS_X_ACCESS_TOKEN", "ECS_X_ACCESS_TOKEN_SECRET"]


def x_text(caption: str) -> str:
    """Fit the caption into a tweet; X counts any URL as 23 chars."""
    if len(caption) <= 270:
        return caption
    trimmed = caption[:230].rsplit(" ", 1)[0].rstrip(" ,.;—-")
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
    if resp.status_code not in (200, 201):
        print(f"X post failed: {resp.status_code} {resp.text[:300]}", file=sys.stderr)
        sys.exit(1)
    print(f"posted to X: {resp.json().get('data', {}).get('id', '?')}")


if __name__ == "__main__":
    main()
