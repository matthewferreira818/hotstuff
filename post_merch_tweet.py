"""One-off: post the custom-printing showcase tweet (ad card + QR reply).

Runs in GitHub Actions where the X_* secrets live. Writes the outcome to
marketing/merch-tweet-result.txt so the result is visible from the repo
without needing access to the workflow logs.
"""
import os
from pathlib import Path

HERE = Path(__file__).parent
CARD = HERE / "marketing" / "merch-tweet-card.png"
RESULT = HERE / "marketing" / "merch-tweet-result.txt"
CREDS = ["X_API_KEY", "X_API_SECRET", "X_ACCESS_TOKEN", "X_ACCESS_TOKEN_SECRET"]

# Launch copy 2026-08-06 — pop-up store live (replaces the ad-manager-approved
# July "drops soon" tease).
TWEET = (
    "The flame drop is LIVE \U0001F525 HotsTuff logo tee, crewneck, embroidered "
    "cap, mug & sticker — printed to order. Or upload your own art and we'll "
    "put it on a tee for $32.99, shipping included. "
    "https://findhotstuff.com/?ref=x#merch"
)


def post(session, text, media_id=None, reply_to=None):
    payload = {"text": text}
    if media_id:
        payload["media"] = {"media_ids": [media_id]}
    if reply_to:
        payload["reply"] = {"in_reply_to_tweet_id": reply_to}
    return session.post("https://api.x.com/2/tweets", json=payload, timeout=30)


def finish(line):
    print(line)
    RESULT.write_text(line + "\n", encoding="utf-8")
    return 0  # never fail the workflow over a tweet


def main():
    missing = [c for c in CREDS if not os.environ.get(c)]
    if missing:
        return finish(f"SKIPPED: X credentials not configured ({', '.join(missing)})")

    from requests_oauthlib import OAuth1Session

    from tweet_media import build_qr_card, upload_media

    session = OAuth1Session(
        os.environ["X_API_KEY"],
        client_secret=os.environ["X_API_SECRET"],
        resource_owner_key=os.environ["X_ACCESS_TOKEN"],
        resource_owner_secret=os.environ["X_ACCESS_TOKEN_SECRET"],
    )

    media_id = None
    try:
        media_id = upload_media(session, CARD.read_bytes())
    except Exception as exc:  # noqa: BLE001 - never block the tweet on media
        print(f"ad card skipped ({exc}) - posting text-only")

    resp = post(session, TWEET, media_id=media_id)
    if resp.status_code == 402:
        return finish("X_CREDITS_DEPLETED: top up at console.x.com, then re-run this workflow")
    if resp.status_code not in (200, 201):
        return finish(f"FAILED: HTTP {resp.status_code}: {resp.text[:200]}")
    tweet_id = resp.json().get("data", {}).get("id")

    # house style: reply with the QR card so the shop is one scan away
    qr_id = None
    try:
        qr_id = upload_media(session, build_qr_card())
    except Exception as exc:  # noqa: BLE001
        print(f"QR card skipped ({exc}) - replying with link only")
    post(session, "Tap or scan to shop \U0001F447\nhttps://findhotstuff.com/?ref=x",
         media_id=qr_id, reply_to=tweet_id)

    return finish(f"POSTED: https://x.com/hotstuff2213/status/{tweet_id}")


if __name__ == "__main__":
    raise SystemExit(main())
