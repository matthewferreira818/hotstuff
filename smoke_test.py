"""
Daily deep smoke test of everything user-facing.

The hourly website watchdog answers "is it up?"; this answers "does it all
still WORK?" — pages carry their critical features, assets resolve, the
checkout worker routes requests, and the lead form's endpoint answers.
Runs from .github/workflows/site-smoke.yml every morning; safe by design:
no Stripe session is ever created (the checkout probe uses a nonexistent
product id) and the lead probe fills the honeypot field, which the worker
drops without storing or notifying.

Green runs stay silent. Failures ntfy-push a high-priority list to the
phone and exit non-zero so the workflow shows red. QUIET=1 skips the push
(for supervised test runs) while still exiting red.

    NTFY_TOPIC=... python smoke_test.py
"""

import json
import os
import sys
import urllib.error
import urllib.request

SITE = "https://findhotstuff.com"
WORKER = "https://wavelist-checkout.wavelist-mf818.workers.dev"
UA = {"User-Agent": "hotstuff-smoke-test"}


def fetch(url, method="GET", data=None, headers=None, timeout=30):
    """Return (status, body-bytes); HTTP errors come back as data, not raises."""
    req = urllib.request.Request(url, method=method, data=data,
                                 headers={**UA, **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def page_has(path, *needles, label=None):
    """A page must be 200 and contain every needle."""
    label = label or path
    try:
        status, body = fetch(f"{SITE}{path}")
    except Exception as exc:  # noqa: BLE001
        return f"{label}: unreachable ({exc})"
    if status != 200:
        return f"{label}: HTTP {status}"
    text = body.decode("utf-8", "replace")
    missing = [n for n in needles if n not in text]
    if missing:
        return f"{label}: missing {', '.join(missing)}"
    return None


def check_catalog():
    try:
        status, body = fetch(f"{SITE}/products.json")
        products = json.loads(body)
    except Exception as exc:  # noqa: BLE001
        return f"products.json: unreadable ({exc})"
    if status != 200 or not isinstance(products, list):
        return f"products.json: HTTP {status} or not a list"
    if len(products) < 20:
        return f"products.json: only {len(products)} products (expected 20+)"
    p = products[0]
    for field in ("id", "name", "price", "image"):
        if not p.get(field):
            return f"products.json: first product missing '{field}'"
    try:
        istatus, _ = fetch(p["image"], method="HEAD", timeout=20)
        if istatus >= 400:
            return f"catalog image: first product image HTTP {istatus} ({p['image'][:80]})"
    except Exception as exc:  # noqa: BLE001
        return f"catalog image: unreachable ({exc})"
    return None


def check_feed():
    try:
        status, body = fetch(f"{SITE}/automation/feed/index.json")
        posts = json.loads(body)
    except Exception as exc:  # noqa: BLE001
        return f"feed index: unreadable ({exc})"
    if status != 200 or not isinstance(posts, list) or not posts:
        return f"feed index: HTTP {status} or empty"
    img = posts[0].get("image", "")
    if not img:
        return "feed index: newest post has no image"
    istatus, _ = fetch(f"{SITE}/automation/feed/{img}", method="HEAD")
    if istatus != 200:
        return f"feed image: newest ({img}) HTTP {istatus}"
    return None


def check_checkout_worker():
    """Route + catalog fetch inside the worker, WITHOUT touching Stripe:
    a nonexistent product id must come back as a clean JSON 404."""
    try:
        status, body = fetch(
            f"{WORKER}/create-checkout-session", method="POST",
            data=json.dumps({"productId": "smoke-test-nonexistent"}).encode(),
            headers={"Content-Type": "application/json", "Origin": SITE},
        )
    except Exception as exc:  # noqa: BLE001
        return f"checkout worker: unreachable ({exc})"
    if status != 404:
        return f"checkout worker: expected 404 for fake product, got {status}"
    try:
        if "product not found" not in json.loads(body).get("error", ""):
            return "checkout worker: 404 but unexpected error body"
    except ValueError:
        return "checkout worker: non-JSON error response"
    return None


def check_lead_endpoint():
    """The lead form's endpoint, probed via the honeypot: the worker answers
    ok:true and (by design) stores nothing and notifies no one."""
    try:
        status, body = fetch(
            f"{WORKER}/lead", method="POST",
            data=json.dumps({"name": "smoke", "contact": "smoke@test.invalid",
                             "website": "smoke-probe"}).encode(),
            headers={"Content-Type": "application/json", "Origin": SITE},
        )
    except Exception as exc:  # noqa: BLE001
        return f"lead endpoint: unreachable ({exc})"
    if status == 404:
        return "lead endpoint: 404 — worker code is outdated (paste the latest checkout-worker/src/index.js)"
    if status != 200:
        return f"lead endpoint: HTTP {status}"
    try:
        if json.loads(body).get("ok") is not True:
            return "lead endpoint: 200 but no ok:true"
    except ValueError:
        return "lead endpoint: non-JSON response"
    return None


CHECKS = [
    lambda: page_has("/", "HotsTuff", "data-goatcounter", "script.js?v=", label="store page"),
    check_catalog,
    lambda: page_has("/sw.js", "VERSION", label="service worker"),
    lambda: page_has("/script.js", "startCheckout", label="script.js"),
    lambda: page_has("/i18n.js", "sheetClose", label="i18n.js"),
    lambda: page_has("/automation/", "lead-form", "week-col", "ecs-feed", label="automation page EN"),
    lambda: page_has("/automation/fr/", "lead-form", "week-col", "ecs-feed", label="automation page FR"),
    check_feed,
    lambda: page_has("/success.html", "", label="success page"),
    lambda: page_has("/privacy/", "Privacy", label="privacy page"),
    lambda: page_has("/terms/", "Terms", label="terms page"),
    lambda: page_has("/tiktok-callback/", "code", label="tiktok callback page"),
    check_checkout_worker,
    check_lead_endpoint,
]


def main() -> None:
    failures = []
    for check in CHECKS:
        try:
            result = check()
        except Exception as exc:  # noqa: BLE001 - a crashed check is a failure
            result = f"check crashed: {exc}"
        if result:
            failures.append(result)
            print(f"FAIL  {result}")
        # quiet on pass; the summary line below tells the whole story

    print(f"\n{len(CHECKS) - len(failures)}/{len(CHECKS)} checks passed")
    if not failures:
        return

    topic = os.environ.get("NTFY_TOPIC")
    if topic and not os.environ.get("QUIET"):
        body = "\n".join(failures)[:3800]
        req = urllib.request.Request(
            f"https://ntfy.sh/{topic}", data=body.encode(),
            headers={"Title": f"Site smoke test FAILED - {len(failures)} check(s)",
                     "Tags": "rotating_light", "Priority": "high"},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                resp.read()
            print("alert pushed")
        except Exception as exc:  # noqa: BLE001
            print(f"ntfy push failed: {exc}")
    sys.exit(1)


if __name__ == "__main__":
    main()
