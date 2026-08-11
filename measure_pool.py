"""
Diagnostic: how many DISTINCT trending products will CJ actually serve?

The rotation can only show as many non-overlapping catalogs as the pool
supports: with DISPLAY_COUNT items per cycle, a pool of N unique products
yields at most N // DISPLAY_COUNT distinct cycles before items must repeat.
When that number is small the catalog visibly ping-pongs between the same
sets, so this is the number to check before tuning POOL_SIZE,
DISPLAY_COUNT, or ROTATION_MEMORY in refresh_products.py.

Pages until CJ stops returning new products (or MAX_PAGES), counting
uniques by the same key the refresh uses. Read-only — touches nothing.

    CJ_API_KEY=... python measure_pool.py [max_pages]
"""

import sys
import time
import urllib.error

from refresh_products import (
    DISPLAY_COUNT,
    PAGE_SIZE,
    POOL_SIZE,
    PRODUCT_LIST_URL,
    get_access_token,
    get_json,
    load_api_key,
    product_id,
)

MAX_PAGES = 30  # 3000 products at PAGE_SIZE=100 — far past any plausible pool


def measure(access_token: str, max_pages: int) -> tuple[set[str], int]:
    """Page until exhaustion; returns (unique ids, pages actually fetched)."""
    seen: set[str] = set()
    pages_read = 0
    for page in range(1, max_pages + 1):
        params = {
            "productFlag": 0,   # trending — same query the refresh uses
            "orderBy": 1,
            "sort": "desc",
            "page": page,
            "size": PAGE_SIZE,
        }
        query = "&".join(f"{k}={v}" for k, v in params.items())
        resp = get_json(f"{PRODUCT_LIST_URL}?{query}",
                        headers={"CJ-Access-Token": access_token})
        if resp.get("code") != 200:
            print(f"  page {page}: CJ error — {resp.get('message', resp)}")
            break

        content = resp["data"]["content"]
        batch = content[0].get("productList", []) if content else []
        pages_read = page
        if not batch:
            print(f"  page {page}: empty — pool exhausted")
            break

        before = len(seen)
        seen.update(product_id(p) for p in batch if product_id(p))
        new = len(seen) - before
        print(f"  page {page}: {len(batch)} returned, {new} new "
              f"(running total {len(seen)})")
        if new == 0:
            print(f"  page {page}: all duplicates — pool exhausted")
            break
        time.sleep(1.2)  # stay under CJ's per-endpoint rate limit
    return seen, pages_read


def main() -> None:
    max_pages = int(sys.argv[1]) if len(sys.argv) > 1 else MAX_PAGES
    token = get_access_token(load_api_key())
    print(f"Paging CJ trending products (up to {max_pages} pages "
          f"x {PAGE_SIZE})...")
    try:
        unique, pages = measure(token, max_pages)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"CJ request failed: HTTP {e.code} {e.reason}")

    total = len(unique)
    cycles = total // DISPLAY_COUNT if DISPLAY_COUNT else 0
    print()
    print(f"RESULT: {total} unique trending products across {pages} page(s)")
    print(f"  current POOL_SIZE={POOL_SIZE}, DISPLAY_COUNT={DISPLAY_COUNT}")
    print(f"  distinct non-overlapping catalogs possible: {cycles}")
    print(f"  -> ROTATION_MEMORY can be at most {max(cycles - 1, 0)} "
          f"(cycles remembered before an item may return)")
    if cycles < 2:
        print("  WARNING: pool cannot fill two distinct catalogs — every "
              "refresh must reuse items.")
    elif cycles == 2:
        print("  NOTE: exactly two distinct catalogs — the site will "
              "alternate A/B/A/B. Lower DISPLAY_COUNT for more variety.")


if __name__ == "__main__":
    main()
