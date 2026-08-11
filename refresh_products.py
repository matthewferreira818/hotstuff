"""
Pulls currently-trending products from CJ Dropshipping and rewrites products.json.

Usage:
    python refresh_products.py

Requires a .env file (same folder) containing:
    CJ_API_KEY=CJUserNum@api@xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
"""

import hashlib
import json
import math
import os
import re
import time
import urllib.request
import urllib.error
from pathlib import Path

HERE = Path(__file__).parent
ENV_FILE = HERE / ".env"
PRODUCTS_FILE = HERE / "products.json"
HISTORY_FILE = HERE / "rotation-history.json"

AUTH_URL = "https://developers.cjdropshipping.com/api2.0/v1/authentication/getAccessToken"
PRODUCT_LIST_URL = "https://developers.cjdropshipping.com/api2.0/v1/product/listV2"

DISPLAY_COUNT = 120  # products shown on the site each cycle
POOL_SIZE = 800      # trending pool to rotate from, fetched in pages. CJ
                     # serves ~1080 trending products (run measure_pool.py to
                     # re-check). Selection always takes the hottest eligible
                     # items first, so extra depth costs nothing in product
                     # quality — it is headroom that keeps the rotation from
                     # running out of fresh items and collapsing to a shallow
                     # cycle. 300 was the cap that forced the old A/B flip.
PAGE_SIZE = 100      # CJ list-endpoint page max
ROTATION_MEMORY = 4  # cycles an item must sit out before it may return, so
                     # the catalog can't alternate between the same sets
                     # (~12 days at the 3-day cadence). Kept below
                     # POOL_SIZE // DISPLAY_COUNT so the pool can always fill
                     # a catalog with this much held back; select_rotating
                     # forgives the oldest cycles if it ever can't.
MAX_REPEATS = 4      # keep the 4 most-interacted-with items each cycle; the
                     # other 116 fully rotate. "Interacted" = Buy-now clicks
                     # tracked as GoatCounter `buy-<id>` events (script.js);
                     # until click data accrues, the top-trending carry-overs
                     # stand in. (Previous items also backfill if the trending
                     # pool has fewer than DISPLAY_COUNT new products.)
MARKUP_MULTIPLIER = 1.6  # legacy wholesale-only floor (cost * this). Kept as an
                          # extra always-on safety margin on top of the real
                          # profit guarantee below; for cost > ~$16.80 this
                          # multiplier actually becomes the binding floor.

# --- No-loss guarantee -------------------------------------------------
# A sale's true cost has THREE parts, and pricing must cover all three:
#   1. CJ wholesale cost         -- known per product (`cost` below)
#   2. CJ fulfillment shipping   -- auto-charged to the CJ balance per order,
#      NOT known until checkout. We price for a conservative worst case so
#      the real charge can never exceed what we've already priced for.
#   3. Stripe's transaction fee  -- 2.9% of the charge + $0.30 fixed
#
# STRIPE_PCT_FEE / STRIPE_FIXED_FEE: Stripe's published fee schedule.
#
# CJ_SHIPPING_WORST_CASE: conservative ceiling on CJ shipping cost to the
# US/Canada for light trending dropship goods. CJ's standard/ePacket-class
# shipping for small parcels typically runs $2-6, occasionally $6-8 for
# bulkier items, remote provinces, or peak-season surcharges. We price for
# $8.00 -- the top of that observed range -- so real per-order shipping
# charges are covered even in the worst case we've seen.
#
# MIN_NET_MARGIN: minimum guaranteed profit per unit after ALL of the above,
# so "profitable" isn't a razor's-edge $0.01 that rounding/misc fees/exchange
# -rate slop could wipe out.
STRIPE_PCT_FEE = 0.029
STRIPE_FIXED_FEE = 0.30
CJ_SHIPPING_WORST_CASE = 8.00
MIN_NET_MARGIN = 1.00

# Retail-looking price points, raised from the old $4-$25 spread because the
# floor below (shipping + fees + margin, not just wholesale cost) genuinely
# requires it -- at $8 worst-case shipping alone, nothing under ~$9.60 can
# ever be guaranteed profitable, so keeping price points below that would
# just mean they're silently never used. Each product is assigned one
# deterministically from its SKU (so its price is stable across cycles), then
# raised to whichever margin floor is higher if the supplier cost demands it.
PRICE_LADDER = [9.99, 11.99, 13.99, 15.99, 18.99, 21.99, 24.99, 27.99, 31.99, 35.99]

GRADIENTS = [
    "linear-gradient(135deg, #6366f1, #ec4899)",
    "linear-gradient(135deg, #f59e0b, #ef4444)",
    "linear-gradient(135deg, #0ea5e9, #6366f1)",
    "linear-gradient(135deg, #22c55e, #0ea5e9)",
    "linear-gradient(135deg, #ec4899, #f59e0b)",
    "linear-gradient(135deg, #a855f7, #ec4899)",
    "linear-gradient(135deg, #f43f5e, #a855f7)",
    "linear-gradient(135deg, #14b8a6, #6366f1)",
]

# CJ's list endpoint doesn't reliably return category names, so category + emoji
# are both derived from keywords in the product title.
NAME_KEYWORD_CATEGORIES = [
    # Pet stays ahead of Auto so "dog car seat belt"-style items keep the Pet label.
    (("pet", "dog", "cat", "puppy", "kitten"), "Pet", "🐾"),
    (("car", "vehicle", "dashboard", "windshield", "suction"), "Auto", "🚗"),
    (("blender", "juicer", "kitchen", "cup", "mug", "cookware"), "Kitchen", "🍳"),
    (("humidifier", "night light", "lamp", "led", "home", "decor"), "Home", "🏠"),
    (("makeup", "beauty", "skincare", "hair", "cosmetic"), "Beauty", "💄"),
    (("fitness", "gym", "yoga", "muscle", "workout"), "Fitness", "🏋️"),
    (("usb", "charger", "bluetooth", "electronic", "speaker", "earbud"), "Electronics", "🔌"),
    (("toy", "kids", "children", "game"), "Toys", "🧸"),
    (("dress", "shirt", "fashion", "clothing", "jacket"), "Fashion", "👗"),
    (("jewelry", "necklace", "ring", "bracelet"), "Jewelry", "💍"),
    (("outdoor", "camping", "hiking", "tent"), "Outdoor", "🏕️"),
    (("bag", "backpack", "purse"), "Bags", "👜"),
    (("shoe", "sneaker", "sandal", "slipper"), "Footwear", "👟"),
    (("phone", "iphone", "case"), "Phone Accessories", "📱"),
    (("tool", "wrench", "repair"), "Tools", "🛠️"),
    (("glove", "sport", "riding", "motorcycle"), "Sports", "🧤"),
]


def tokenize(name: str) -> tuple[str, set[str]]:
    """Lowercase + pad a name for substring checks, and split it into a word
    set for whole-word checks. Shared by classify_name and describe() so both
    use the same word-boundary-safe matching (see keyword_hit)."""
    name_lower = f" {(name or '').lower()} "
    words = set(re.findall(r"[a-z]+", name_lower))
    return name_lower, words


def keyword_hit(name_lower: str, words: set[str], k: str) -> bool:
    """Whole-word matching (with a simple plural fold) so e.g. "Suction" can
    never match "cup" nor "delicate" match "cat" -- and so a concatenated
    supplier word like "CarWash" can't falsely match "car". Multi-word (or
    space-padded) keywords fall back to substring matching."""
    if " " in k:
        return k in name_lower
    return k in words or k + "s" in words or (k.endswith("s") and k[:-1] in words)


def classify_name(name: str) -> tuple[str, str]:
    name_lower, words = tokenize(name)
    for keywords, category, emoji in NAME_KEYWORD_CATEGORIES:
        if any(keyword_hit(name_lower, words, k) for k in keywords):
            return category, emoji
    return "Trending Finds", "🛍️"


def parse_price(price_str) -> float:
    if not price_str:
        return 0.0
    match = re.search(r"[\d.]+", str(price_str))
    return float(match.group()) if match else 0.0


def product_id(p: dict) -> str:
    return p.get("sku") or p.get("id") or ""


def min_profitable_price(cost: float) -> float:
    """The lowest price that GUARANTEES the store does not lose money on a
    sale, even in the worst case, once every real cost is counted: CJ
    wholesale cost, worst-case CJ shipping, Stripe's fee, and a minimum
    profit cushion. Solves for `price` in:

        price - (price * STRIPE_PCT_FEE + STRIPE_FIXED_FEE)
              - cost - CJ_SHIPPING_WORST_CASE >= MIN_NET_MARGIN
    """
    needed = cost + CJ_SHIPPING_WORST_CASE + STRIPE_FIXED_FEE + MIN_NET_MARGIN
    return needed / (1 - STRIPE_PCT_FEE)


def assign_price(sku: str, cost: float) -> float:
    """Pick a stable, varied retail price for a product from PRICE_LADDER,
    never dropping below whichever margin floor is higher:
      - the legacy wholesale-only floor (cost * MARKUP_MULTIPLIER), or
      - min_profitable_price(cost), which additionally guarantees coverage
        of Stripe's fee and worst-case CJ shipping.
    This is what guarantees every sale is profitable even in the worst case.
    Price is still chosen deterministically from the SKU first (stable
    per-SKU price across refresh cycles), and only bumped up if the floor
    demands it."""
    floor = max(cost * MARKUP_MULTIPLIER, min_profitable_price(cost))
    h = int(hashlib.sha256((sku or "x").encode()).hexdigest(), 16)
    price = PRICE_LADDER[h % len(PRICE_LADDER)]
    if price < floor:
        higher = [p for p in PRICE_LADDER if p >= floor]
        if higher:
            price = higher[0]
        else:
            # Even the top of the ladder can't guarantee a profit on this
            # (unusually expensive) item. Break the ladder rather than ever
            # risk a loss -- round up to the cent so the floor is cleared.
            price = math.ceil(floor * 100) / 100
    return price


def load_previous_ids() -> set[str]:
    if not PRODUCTS_FILE.exists():
        return set()
    try:
        data = json.loads(PRODUCTS_FILE.read_text())
        return {p.get("id") for p in data if isinstance(p, dict)}
    except (json.JSONDecodeError, OSError):
        return set()


def load_history() -> list[list[str]]:
    """Product ids of recent cycles, most recent first.

    Seeded from the live catalog when the file doesn't exist yet, so the
    first run after this lands still knows what's currently on the site.
    """
    if HISTORY_FILE.exists():
        try:
            data = json.loads(HISTORY_FILE.read_text())
            cycles = data.get("cycles", []) if isinstance(data, dict) else data
            return [[str(i) for i in c] for c in cycles if isinstance(c, list)]
        except (json.JSONDecodeError, OSError):
            pass  # unreadable history is not worth failing a refresh over
    prev = sorted(i for i in load_previous_ids() if i)
    return [prev] if prev else []


def save_history(history: list[list[str]], current_ids: list[str]) -> None:
    """Prepend this cycle and keep only what the rotation still consults."""
    cycles = [current_ids] + history
    HISTORY_FILE.write_text(json.dumps(
        {"note": ("Product ids of recent cycles, most recent first. "
                  "refresh_products.py holds these back so the catalog "
                  "cannot ping-pong between the same few sets."),
         "cycles": cycles[:ROTATION_MEMORY]}, indent=2) + "\n")


def buy_clicks(pid: str) -> int:
    """Buy-now clicks for a product, from GoatCounter's public counter
    (script.js logs a `buy-<id>` event per click). 0 on any failure — the
    rotation must never break because analytics hiccuped."""
    url = f"https://theycallmemattyb.goatcounter.com/counter/buy-{pid}.json"
    try:
        with urllib.request.urlopen(url, timeout=8) as r:
            raw = json.load(r).get("count", "0")
        return int(re.sub(r"[^\d]", "", str(raw)) or 0)
    except Exception:  # noqa: BLE001 - analytics is best-effort by design
        return 0


def rank_by_interaction(repeats: list[dict]) -> list[dict]:
    """Order last cycle's still-trending items by real customer interest:
    Buy-now clicks first (fetched concurrently), pool trend order as the
    tiebreak (the sort is stable, so zero-click items keep trend order)."""
    if not repeats:
        return repeats
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(10) as ex:
        clicks = dict(zip((product_id(p) for p in repeats),
                          ex.map(lambda p: buy_clicks(product_id(p)), repeats)))
    return sorted(repeats, key=lambda p: -clicks.get(product_id(p), 0))


def select_rotating(pool: list[dict], history: list[list[str]]) -> list[dict]:
    """Choose DISPLAY_COUNT products from the trending pool, holding back
    everything shown in the last ROTATION_MEMORY cycles so an item cannot
    return until it has genuinely sat out.

    Excluding only the previous cycle is what made the catalog alternate
    between two fixed sets: the pool is sorted by trend, so as soon as last
    cycle's items became eligible again the selection snapped straight back
    to the top of that order (A -> B -> A -> B).

    If the pool is too small to fill a catalog with that much held back, the
    oldest remembered cycle is forgiven one at a time — the rotation gets
    shallower rather than failing. At most MAX_REPEATS items carry over from
    the immediately previous cycle, chosen by real customer interest.
    """
    prev_ids = set(history[0]) if history else set()
    depth = min(len(history), ROTATION_MEMORY)
    while True:
        held = {pid for cycle in history[:depth] for pid in cycle}
        fresh = [p for p in pool if product_id(p) not in held]
        if len(fresh) >= DISPLAY_COUNT - MAX_REPEATS or depth == 0:
            break
        depth -= 1

    repeats = rank_by_interaction([p for p in pool if product_id(p) in prev_ids])
    kept_repeats = repeats[:MAX_REPEATS]           # the most-interacted-with carry-overs
    kept_ids = {product_id(p) for p in kept_repeats}
    fresh = [p for p in fresh if product_id(p) not in kept_ids]

    chosen = fresh[: DISPLAY_COUNT - len(kept_repeats)] + kept_repeats
    print(f"Rotation: held back {len(held)} ids from the last {depth} cycle(s); "
          f"{len(fresh)} eligible.")

    if len(chosen) < DISPLAY_COUNT:                # pool smaller than expected — backfill
        chosen_ids = {product_id(p) for p in chosen}
        extra = [p for p in pool if product_id(p) not in chosen_ids]
        chosen += extra[: DISPLAY_COUNT - len(chosen)]

    return chosen[:DISPLAY_COUNT]


MAX_NAME_LENGTH = 52  # tight enough to read cleanly in two lines on mobile cards

# Pure marketing/SEO puffery that never describes the physical product.
# Dropped from titles (case-insensitive, whole words).
FILLER_WORDS = {
    "hot", "selling", "sale", "hotsale", "wholesale", "fashion",
    "trendy", "brand", "quality", "product", "products", "item",
    "new", "arrival", "arrivals", "style", "ins", "creative",
    "dropshipping", "explosive", "amazon", "aliexpress",
    "2024", "2025", "2026",
}

# Words that read as dangling clutter at the END of a name ("...Holder For",
# "...Gloves Touch And") — stripped after cleaning/truncation so every name
# ends on a real word.
TRAILING_CONNECTORS = {"for", "with", "and", "the", "of", "to", "in", "on",
                       "or", "a", "an", "&"}


def _dedupe_key(word: str) -> str:
    """Normalize a word for duplicate detection: lowercase, strip trailing
    punctuation, and fold simple plurals so 'Jacket' == 'Jackets'."""
    w = word.lower().strip(".,;:")
    if len(w) > 3 and w.endswith("s"):
        w = w[:-1]
    return w


def _tidy_case(word: str) -> str:
    """Soften supplier SHOUTING: long ALL-CAPS words become Title Case, but
    short acronyms like USB / LED / RGB keep their caps."""
    if len(word) > 3 and word.isupper():
        return word.capitalize()
    return word


def _strip_trailing_connectors(words: list[str]) -> list[str]:
    while len(words) > 1 and words[-1].lower().strip(".,;:") in TRAILING_CONNECTORS:
        words.pop()
    return words


def clean_name(name: str) -> str:
    words = " ".join((name or "").split()).split(" ")
    out, seen = [], set()
    for w in words:
        key = _dedupe_key(w)
        if not key or key in FILLER_WORDS or key in seen:
            continue  # drop filler puffery and repeated words (incl. plurals)
        seen.add(key)
        out.append(_tidy_case(w))

    out = _strip_trailing_connectors(out)
    cleaned = " ".join(out).strip() or " ".join((name or "").split())
    if len(cleaned) <= MAX_NAME_LENGTH:
        return cleaned
    truncated = cleaned[:MAX_NAME_LENGTH].rsplit(" ", 1)[0]
    truncated = " ".join(_strip_trailing_connectors(truncated.split(" ")))
    return truncated


def load_api_key() -> str:
    env_key = os.environ.get("CJ_API_KEY")
    if env_key:
        return env_key
    if not ENV_FILE.exists():
        raise SystemExit(
            f"CJ_API_KEY not set. Set it as an environment variable, "
            f"or add a line to {ENV_FILE}: CJ_API_KEY=your-key"
        )
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if line.startswith("CJ_API_KEY="):
            return line.split("=", 1)[1].strip()
    raise SystemExit(f"CJ_API_KEY not found in {ENV_FILE}")


def post_json(url: str, payload: dict, headers: dict | None = None) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.loads(res.read().decode("utf-8"))


def get_json(url: str, headers: dict | None = None) -> dict:
    req = urllib.request.Request(url, method="GET")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.loads(res.read().decode("utf-8"))


def get_access_token(api_key: str) -> str:
    resp = post_json(AUTH_URL, {"apiKey": api_key})
    if resp.get("code") != 200 or not resp.get("result"):
        raise SystemExit(f"CJ auth failed: {resp.get('message', resp)}")
    return resp["data"]["accessToken"]


def fetch_trending_products(access_token: str) -> list[dict]:
    """Pull the trending pool, paging through CJ's list endpoint (100/page max)."""
    pool, seen = [], set()
    pages = math.ceil(POOL_SIZE / PAGE_SIZE)
    for page in range(1, pages + 1):
        params = {
            "productFlag": 0,   # trending
            "orderBy": 1,       # sort by listing count (sales-volume proxy)
            "sort": "desc",
            "page": page,
            "size": PAGE_SIZE,
        }
        query = "&".join(f"{k}={v}" for k, v in params.items())
        url = f"{PRODUCT_LIST_URL}?{query}"
        resp = get_json(url, headers={"CJ-Access-Token": access_token})
        if resp.get("code") != 200:
            raise SystemExit(f"CJ product query failed: {resp.get('message', resp)}")
        content = resp["data"]["content"]
        batch = content[0].get("productList", []) if content else []
        if not batch:
            break
        for p in batch:
            key = p.get("sku") or p.get("id") or json.dumps(p, sort_keys=True)[:80]
            if key not in seen:
                seen.add(key)
                pool.append(p)
        if len(pool) >= POOL_SIZE:
            break
        time.sleep(1.2)  # stay under CJ's per-endpoint rate limit
    return pool[:POOL_SIZE]


def normalize_trend_score(listed_num: int, all_listed_nums: list[int]) -> int:
    if not all_listed_nums or max(all_listed_nums) == 0:
        return 50
    lo, hi = min(all_listed_nums), max(all_listed_nums)
    if hi == lo:
        return 90
    scaled = 60 + (listed_num - lo) / (hi - lo) * 39  # keep scores in a believable 60-99 band
    return round(scaled)


# Warm, benefit-led descriptions keyed to what the product actually IS, with a
# handful of variants each so the cards rarely repeat one. The variant is
# chosen deterministically per SKU (same hashing style as assign_price), so a
# given product's copy stays stable across refreshes. Matching uses the same
# whole-word logic as classify_name (see keyword_hit/tokenize) so a stray
# substring -- e.g. "car" inside a concatenated "CarWash" -- can't pull in an
# unrelated blurb. First matching keyword group wins.
KEYWORD_DESCRIPTIONS = [
    (("fetal", "pregnancy", "prenatal", "expecting"),
     ["A sweet way to feel a little closer during pregnancy.",
      "A gentle keepsake for an exciting stage of the wait.",
      "A thoughtful pick for parents-to-be.",
      "Small moments made a little more special before baby arrives.",
      "A caring little extra for the nine-month countdown."]),
    (("necklace", "pendant", "bracelet", " ring", "jewelry", "clover", "zodiac", "constellation"),
     ["Everyday sparkle that makes an easy, giftable win.",
      "A dainty little piece people keep adding to cart.",
      "Wear-anywhere shine — and it gives beautifully, too.",
      "Simple, pretty, and easy to layer with anything.",
      "A little extra shine for an everyday outfit."]),
    (("leggings", "yoga", "fitness", "trainer", "workout", "grip", " abs", "muscle", "seamless"),
     ["Gear up — a fitness favorite shoppers keep coming back for.",
      "The kind of workout upgrade that actually gets used.",
      "Move better, feel better — a trending fitness pick.",
      "Built for the gym, comfy enough for the couch after.",
      "An easy way to make workouts feel more solid."]),
    (("dog", "cat", "pet", "puppy", "kitten"),
     ["A pet-parent favorite your furry friend will love.",
      "Spoil the good boy (or girl) — pet owners can't get enough.",
      "Made for happy pets and easier pet-parenting.",
      "A little extra comfort for your best friend.",
      "Pet-approved, parent-approved."]),
    (("phone", "case", "charger", "wireless", "magnetic", "airpod", "apple"),
     ["A handy phone upgrade that smooths out your day.",
      "Small accessory, surprisingly big daily payoff.",
      "The phone add-on you'll wonder how you lived without.",
      "Keeps your phone charged, protected, or both.",
      "An easy fix for one of your most-used gadgets."]),
    (("humidifier", "diffuser", "aromatherapy", "essential oil"),
     ["Turn any room into a calm, better-smelling space.",
      "Set the mood — soft mist, softer vibes.",
      "A little spa energy for your home or desk.",
      "An easy way to freshen up any room.",
      "Quiet, simple, and nice to come home to."]),
    (("led", "light", "lamp", "lantern", "candle", "fairy", "glow", "luminous"),
     ["Set the mood with a warm, ambient glow.",
      "Instant cozy — lighting that transforms a room.",
      "Soft light that makes any corner feel special.",
      "An easy plug-in upgrade for any room's vibe.",
      "Bright idea, warm feeling."]),
    (("blender", "juicer", "mixer", "stirrer", "kitchen", "coffee", "milk"),
     ["A clever kitchen helper that earns its counter space.",
      "Small gadget, big everyday kitchen win.",
      "Makes the daily routine quicker and a little more fun.",
      "An easy upgrade for your morning routine.",
      "Simple kitchen gear that actually gets used."]),
    (("vacuum", "cleaner", "dredger", "sewer", "remover", "lint"),
     ["Turns an annoying chore into a quick, satisfying job.",
      "The satisfying little fix for an everyday mess.",
      "Cleaning up just got weirdly enjoyable.",
      "A small tool that handles a surprisingly big mess.",
      "Makes tidying up faster and way less annoying."]),
    (("baby", "newborn", "kids", "jumper", "children"),
     ["Adorable and practical — an easy pick for the little ones.",
      "Cute meets useful for babies and toddlers.",
      "The kind of thing new parents quietly love.",
      "Soft, simple, and made with little ones in mind.",
      "A sweet, easy pick for baby's everyday routine."]),
    (("glove", "winter", "warm", "scarf"),
     ["Cozy, practical, and right on time for the season.",
      "Beat the chill in style — a seasonal favorite.",
      "Warm hands, happy you.",
      "An easy layer for cold-weather days.",
      "Keeps you comfortable when the temperature drops."]),
    (("toy", "plush", "teddy", "drawing", "educational", "bear"),
     ["Hours of fun — and it makes a great gift, too.",
      "Playtime sorted; smiles guaranteed.",
      "A crowd-pleaser for kids and the young at heart.",
      "Easy fun that keeps little hands busy.",
      "A simple toy that gets played with, not shelved."]),
    (("hose", "nozzle", "sprayer", "blaster", "garden", "lawn"),
     ["Hooks up in seconds for an easy yard or car-wash boost.",
      "Turns hose duty into a quick, satisfying job.",
      "A yard-day upgrade — more spray, less hassle.",
      "Makes watering, washing, and rinsing genuinely easier.",
      "Built for the yard, handy for the driveway too."]),
    (("car", "vehicle", "dashboard", "tracker", "gps", "seat belt", "holder"),
     ["A smart little upgrade for your daily drive.",
      "Ride smarter — a favorite for the daily commute.",
      "Fixes a real car annoyance you didn't know you could.",
      "Makes every drive a little easier.",
      "A simple add-on your car has been missing."]),
    (("shower", "finder", "bluetooth", "ruler", "measuring", "instrument", "tape", "socket", "led "),
     ["Smart, useful tech that solves a real everyday annoyance.",
      "The clever little fix that just makes sense.",
      "Practical tech people wish they'd bought sooner.",
      "Handy tech for a job you didn't want to do by hand.",
      "A small gadget that earns its keep fast."]),
    (("crystal", "stone", "healing", "moon", "tree of life"),
     ["A calming little talisman with serious shelf appeal.",
      "Good-vibes decor that doubles as a thoughtful gift.",
      "Natural, pretty, and quietly trending.",
      "A pretty little pick-me-up for a shelf or desk.",
      "Simple, natural style that's easy to love."]),
    (("shoe", "sneaker", "sandal", "slipper"),
     ["Easy-wear style that goes with almost everything.",
      "Comfortable enough for all-day, cute enough for anywhere.",
      "A shoe upgrade that's easy to reach for daily.",
      "Step out in something new without overthinking it.",
      "Comfy first, stylish always."]),
    (("bag", "backpack", "purse", "handbag", "tote"),
     ["Room for everything, without looking like it.",
      "An easy grab-and-go for daily errands.",
      "Fits the essentials and still looks put-together.",
      "A bag that pulls its weight every single day.",
      "Simple, roomy, and easy to style."]),
    (("wrench", "tool", "repair", "screwdriver", "drill"),
     ["A handy fix-it upgrade for the toolbox.",
      "Makes a fiddly job noticeably faster.",
      "Practical gear that earns a spot in the garage.",
      "The kind of tool you reach for more than expected.",
      "Simple, sturdy, and genuinely useful."]),
    (("shaper", "shaping", "compression", "slimming", "shapewear", "strapless bra", "push up"),
     ["An easy, comfy layer under any outfit.",
      "Smooths things out without a second thought.",
      "A go-to layering piece for under everyday looks.",
      "Simple support that fits under whatever you're wearing.",
      "An easy wardrobe helper for a polished look."]),
    (("knee pad", "knee brace", "elbow pad", "wrist brace"),
     ["Extra padding for whatever activity you're into.",
      "Built to take a knock so you don't have to.",
      "Simple protection that doesn't slow you down.",
      "An easy add for active days.",
      "Practical padding for sports, work, or play."]),
]

CATEGORY_DESCRIPTIONS = {
    "Fashion": ["A trending wardrobe win that's flying off the shelves.",
                "Easy style upgrade shoppers are loving right now.",
                "A simple way to freshen up your everyday look.",
                "Wardrobe-ready and easy to style multiple ways."],
    "Beauty": ["A small beauty win that becomes a daily go-to.",
               "The kind of self-care buy people rave about.",
               "An easy add to your everyday routine.",
               "Simple beauty gear that actually gets used."],
    "Home": ["A cozy home upgrade with big everyday payoff.",
             "Little touch, big difference in your space.",
             "An easy way to make your space feel more finished.",
             "Simple home gear that quietly earns its keep."],
    "Kitchen": ["A handy kitchen helper worth the counter space.",
                "Makes cooking (and cleanup) a little easier.",
                "Small kitchen gear, surprisingly big payoff.",
                "An easy upgrade for everyday meals."],
    "Electronics": ["Clever tech that solves a real everyday problem.",
                    "Useful gadgetry people keep coming back for.",
                    "Small tech, surprisingly handy day to day.",
                    "Practical gear for the gadget drawer."],
    "Pet": ["A pet-parent favorite for happier furry friends.",
            "Because the good pets deserve nice things.",
            "An easy win for pets and their people.",
            "Simple pet gear that gets used daily."],
    "Fitness": ["A trending fitness pick that actually gets used.",
                "Level up the routine — a workout favorite.",
                "Simple gear that makes workouts a little easier.",
                "An easy add to any fitness routine."],
    "Toys": ["Fun for the kids and an easy gift-time win.",
             "Playtime, sorted — and it's trending for a reason.",
             "An easy pick for keeping little hands busy.",
             "Simple fun that holds attention."],
    "Jewelry": ["Everyday sparkle that gives beautifully, too.",
                "A dainty piece people keep adding to cart.",
                "Simple shine that goes with everything.",
                "An easy little extra for any outfit."],
    "Phone Accessories": ["A handy phone upgrade that smooths out your day.",
                          "Small add-on, surprisingly big daily payoff.",
                          "An easy fix for one of your most-used gadgets.",
                          "Practical gear for the phone you use nonstop."],
    "Sports": ["Trending gear for getting after it outdoors.",
               "The kind of kit that makes an active day better.",
               "Simple gear built for actually getting used.",
               "An easy add for active days."],
    "Auto": ["A small car upgrade that makes every drive nicer.",
             "Practical kit your car will thank you for.",
             "An easy fix for a small daily driving annoyance.",
             "Simple gear that makes commuting a little smoother."],
    "Outdoor": ["Trending gear for wherever the trail takes you.",
                "Simple kit that makes time outside easier.",
                "An easy upgrade for camping, hiking, or the yard.",
                "Built for outside, easy enough for everyday use."],
    "Bags": ["Room for everything, without looking like it.",
             "An easy grab-and-go for daily errands.",
             "Fits the essentials and still looks put-together.",
             "Simple, roomy, and easy to style."],
    "Footwear": ["Easy-wear style that goes with almost everything.",
                 "Comfortable enough for all-day, cute enough for anywhere.",
                 "A shoe upgrade that's easy to reach for daily.",
                 "Comfy first, stylish always."],
    "Tools": ["A handy fix-it upgrade for the toolbox.",
              "Makes a fiddly job noticeably faster.",
              "Practical gear that earns a spot in the garage.",
              "Simple, sturdy, and genuinely useful."],
    "Trending Finds": ["A shopper favorite that's having a real moment.",
                        "Simple, useful, and easy to see why it's trending.",
                        "An easy pick that's earning repeat buyers.",
                        "Practical, well-priced, and quietly popular.",
                        "The kind of find that over-delivers for the price.",
                        "A small daily upgrade worth trying.",
                        "Handy, simple, and easy to love.",
                        "One of this week's most-loved trending finds."],
}

DEFAULT_DESCRIPTIONS = [
    "One of this week's most-loved trending finds.",
    "A shopper favorite that's having a real moment.",
    "Trending hard right now — and easy to see why.",
    "Simple, useful, and easy to see why it's trending.",
    "An easy pick that's earning repeat buyers.",
]


def describe(name: str, category: str, sku: str) -> str:
    """A warm, benefit-led one-liner keyed to the product. Deterministic per
    SKU so copy stays stable across refreshes — no more identical templates."""
    name_lower, words = tokenize(name)
    variants = None
    for keywords, options in KEYWORD_DESCRIPTIONS:
        if any(keyword_hit(name_lower, words, k) for k in keywords):
            variants = options
            break
    if variants is None:
        variants = CATEGORY_DESCRIPTIONS.get(category, DEFAULT_DESCRIPTIONS)
    idx = int(hashlib.sha256((sku or "x").encode()).hexdigest(), 16) % len(variants)
    return variants[idx]


def to_site_products(cj_products: list[dict]) -> list[dict]:
    listed_nums = [int(p.get("listedNum", 0)) for p in cj_products]
    site_products = []
    for i, p in enumerate(cj_products):
        category, emoji = classify_name(p.get("nameEn", ""))
        cost_price = parse_price(p.get("nowPrice") or p.get("sellPrice"))
        sku = product_id(p) or f"cj{i}"
        site_products.append({
            "id": sku,
            "name": clean_name(p.get("nameEn", "Untitled product")),
            "category": category,
            "price": assign_price(sku, cost_price),
            "trendScore": normalize_trend_score(int(p.get("listedNum", 0)), listed_nums),
            "badge": "🔥 Trending",
            "emoji": emoji,
            "image": p.get("bigImage") or None,
            "gradient": GRADIENTS[i % len(GRADIENTS)],
            "description": describe(clean_name(p.get("nameEn", "")), category, sku),
        })
    return site_products


def main():
    api_key = load_api_key()
    print("Authenticating with CJ Dropshipping...")
    try:
        access_token = get_access_token(api_key)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"CJ auth request failed: HTTP {e.code} {e.reason}")

    print(f"Fetching a pool of {POOL_SIZE} trending products...")
    try:
        pool = fetch_trending_products(access_token)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"CJ product request failed: HTTP {e.code} {e.reason}")

    if not pool:
        raise SystemExit("CJ returned no trending products — leaving products.json untouched.")

    history = load_history()
    prev_ids = set(history[0]) if history else set()
    selected = select_rotating(pool, history)

    changed = sum(1 for p in selected if product_id(p) not in prev_ids)
    print(f"Selected {len(selected)} products ({changed} new vs. last cycle).")

    site_products = to_site_products(selected)
    PRODUCTS_FILE.write_text(json.dumps(site_products, indent=2) + "\n")
    print(f"Wrote {len(site_products)} products to {PRODUCTS_FILE}")

    save_history(history, [p["id"] for p in site_products])
    print(f"Rotation history now spans {min(len(history) + 1, ROTATION_MEMORY)} "
          f"cycle(s) -> {HISTORY_FILE.name}")


if __name__ == "__main__":
    main()
