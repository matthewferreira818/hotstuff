"""
One-shot setup for @ECSocialNB's profile: display name, bio, website,
location, avatar (sunrise logo), and banner. Uses the same OAuth1 user
credentials as the daily poster. Safe to re-run — it just overwrites the
profile with the same values.

Env: ECS_X_API_KEY / ECS_X_API_SECRET / ECS_X_ACCESS_TOKEN / ECS_X_ACCESS_TOKEN_SECRET
"""

import os
import sys
from pathlib import Path

CREDS = ["ECS_X_API_KEY", "ECS_X_API_SECRET",
         "ECS_X_ACCESS_TOKEN", "ECS_X_ACCESS_TOKEN_SECRET"]

BIO = ("Done-for-you social media for local businesses in Sackville, "
       "Memramcook & greater Moncton. Your page posts every day — "
       "you don't lift a finger.")


def main():
    missing = [c for c in CREDS if not os.environ.get(c)]
    if missing:
        print(f"{'/'.join(missing)} not set; skipping")
        return

    from requests_oauthlib import OAuth1Session

    session = OAuth1Session(
        os.environ["ECS_X_API_KEY"],
        client_secret=os.environ["ECS_X_API_SECRET"],
        resource_owner_key=os.environ["ECS_X_ACCESS_TOKEN"],
        resource_owner_secret=os.environ["ECS_X_ACCESS_TOKEN_SECRET"],
    )
    assets = Path(__file__).resolve().parents[1]  # marketing/east-coast-social

    r1 = session.post(
        "https://api.twitter.com/1.1/account/update_profile.json",
        data={"name": "East Coast Social", "description": BIO,
              "url": "https://findhotstuff.com/automation/",
              "location": "New Brunswick, Canada"},
        timeout=30)
    print(f"profile text: {r1.status_code}" +
          ("" if r1.status_code == 200 else f" {r1.text[:250]}"))

    with open(assets / "fb-logo.png", "rb") as f:
        r2 = session.post(
            "https://api.twitter.com/1.1/account/update_profile_image.json",
            files={"image": f}, timeout=60)
    print(f"avatar: {r2.status_code}" +
          ("" if r2.status_code == 200 else f" {r2.text[:250]}"))

    with open(assets / "x-banner.png", "rb") as f:
        r3 = session.post(
            "https://api.twitter.com/1.1/account/update_profile_banner.json",
            files={"banner": f}, timeout=60)
    print(f"banner: {r3.status_code}" +
          ("" if r3.status_code in (200, 201, 202) else f" {r3.text[:250]}"))

    if not all(s in (200, 201, 202) for s in (r1.status_code, r2.status_code, r3.status_code)):
        sys.exit(1)
    print("profile fully set")


if __name__ == "__main__":
    main()
