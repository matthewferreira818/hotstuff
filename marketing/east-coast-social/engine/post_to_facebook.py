"""
Publishes the generated daily card + caption to the East Coast Social
Facebook Page via the Graph API.

Env (GitHub Actions secrets / local .env):
    FB_PAGE_ID     numeric Page id
    FB_PAGE_TOKEN  long-lived Page access token (pages_manage_posts)

Skips quietly when unset so the scheduled workflow stays green until the
Meta app is configured. Fails loudly on real API errors.
"""

import json
import os
import sys
import urllib.request
from pathlib import Path

GRAPH = "https://graph.facebook.com/v21.0"


def post_photo(page_id: str, token: str, image_path: Path, caption: str) -> str:
    boundary = "ECSBOUNDARY"
    img = image_path.read_bytes()
    parts = []
    for name, value in (("caption", caption), ("access_token", token)):
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; "
                     f"name=\"{name}\"\r\n\r\n{value}\r\n".encode())
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; "
                 f"name=\"source\"; filename=\"card.png\"\r\n"
                 f"Content-Type: image/png\r\n\r\n".encode() + img + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)
    req = urllib.request.Request(
        f"{GRAPH}/{page_id}/photos", data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp).get("post_id") or json.load(resp).get("id", "?")


def main():
    page_id = os.environ.get("FB_PAGE_ID")
    token = os.environ.get("FB_PAGE_TOKEN")
    if not page_id or not token:
        print("FB_PAGE_ID / FB_PAGE_TOKEN not set; skipping (engine not armed yet)")
        return
    out = Path(__file__).parent / "out"
    caption = (out / "caption.txt").read_text(encoding="utf-8")
    post_id = post_photo(page_id, token, out / "card.png", caption)
    print(f"posted: {post_id}")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        print("Graph API error:", e.read().decode()[:500], file=sys.stderr)
        sys.exit(1)
