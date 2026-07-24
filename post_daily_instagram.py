"""
Posts one product photo + caption to Instagram per day via Meta's official
Graph API content publishing flow (business/creator accounts only).

Features the SAME product as the daily X spotlight (same day-ordinal pick), so
the brand shows one coherent "product of the day" across platforms.

Skips silently (exit 0) until the IG_* secrets are configured:
    IG_USER_ID      - the Instagram business account's numeric ID
    IG_ACCESS_TOKEN - a long-lived access token with instagram_content_publish
"""

import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

HERE = Path(__file__).parent
PRODUCTS_FILE = HERE / "products.json"
GRAPH = "https://graph.facebook.com/v21.0"


def api(path, params):
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(f"{GRAPH}/{path}", data=data, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            return json.loads(res.read().decode()), None
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}: {e.read().decode()[:300]}"


def pick_product():
    products = json.loads(PRODUCTS_FILE.read_text(encoding="utf-8"))
    ranked = sorted(products, key=lambda x: x.get("trendScore", 0), reverse=True)
    return ranked[date.today().toordinal() % len(ranked)]


def compose_caption(p):
    from generate_posts import ad_name, flavor, pick, HOOKS

    name = ad_name(p.get("name", ""), p.get("category", ""))
    hook = pick(flavor(HOOKS, p.get("category", "*")), p["id"] + "ig")
    price = f"${float(p['price']):.2f}"
    return (
        f"{hook} {p.get('emoji', '')}\n\n"
        f"{name} — {price} \U0001F525 Link in bio to grab it before it rotates out \U0001F440\n\n"
        f"#trendingproducts #tiktokmademebuyit #onlineshopping #hotstuff "
        f"#{(p.get('category') or 'finds').lower().replace(' ', '')}"
    )


def main():
    user_id = os.environ.get("IG_USER_ID")
    token = os.environ.get("IG_ACCESS_TOKEN")
    if not user_id or not token:
        print("IG credentials not configured (IG_USER_ID / IG_ACCESS_TOKEN) - skipping Instagram post.")
        return 0

    p = pick_product()
    image_url = p.get("image")
    if not image_url:
        print(f"Product {p.get('id')} has no image URL - skipping Instagram post.")
        return 0

    caption = compose_caption(p)
    print("Posting to Instagram:\n" + caption)

    container, err = api(f"{user_id}/media", {
        "image_url": image_url,
        "caption": caption,
        "access_token": token,
    })
    if err or "id" not in (container or {}):
        print(f"IG container failed: {err or container}")
        return 0

    published, err = api(f"{user_id}/media_publish", {
        "creation_id": container["id"],
        "access_token": token,
    })
    if err:
        print(f"IG publish failed: {err}")
    else:
        print("Instagram post published:", published.get("id"))
    return 0  # never fail the workflow over a social post


if __name__ == "__main__":
    sys.exit(main())
