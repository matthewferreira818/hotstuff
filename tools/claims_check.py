#!/usr/bin/env python3
"""Offline English marketing-claim review helper. Never publishes anything.

Run: python3 tools/claims_check.py --text "draft text" --as-of 2026-10-05
Or pass a draft on stdin. --facts accepts another reviewed JSON snapshot.
Exit 0: no recognized problem (NOT proof of truth); 1: review findings; 2: bad
input/facts. Uses only the standard library and local files. It does not fetch,
log drafts, change files, run other programs or connect to a posting workflow.
A rule-based checker cannot understand every claim, quote or negation.
Claude reviews findings and refreshes facts; there is no automatic approval.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from datetime import date, timedelta
from pathlib import Path

DEFAULT_FACTS = Path(__file__).with_name("claims_facts.json")


@dataclass(frozen=True)
class Finding:
    code: str
    message: str


def _integer(value: object, name: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ValueError(f"{name} must be an integer of at least {minimum}")
    return value


def _date(value: object, name: str) -> date:
    if not isinstance(value, str):
        raise ValueError(f"{name} must use YYYY-MM-DD")
    try:
        parsed = date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"{name} must use YYYY-MM-DD") from exc
    if parsed.isoformat() != value:
        raise ValueError(f"{name} must use YYYY-MM-DD")
    return parsed


def validate_facts(facts: object) -> dict:
    """Reject invalid snapshots, rather than quietly trusting invented facts."""
    if not isinstance(facts, dict):
        raise ValueError("Facts must be a JSON object")
    try:
        verified = _date(facts["verified_on"], "verified_on")
        feed = facts["feed"]
        since, last = _date(feed["since"], "feed.since"), _date(feed["last"], "feed.last")
        history = _date(feed["website_history_since"], "feed.website_history_since")
        if not since <= history <= last <= verified:
            raise ValueError("Feed dates must be in order and no later than verification")
        total = _integer(feed["total"], "feed.total", 1)
        if total > (last - since).days + 1:
            raise ValueError("Distinct-day total exceeds the feed's calendar span")
        _integer(feed["posts_per_day"], "feed.posts_per_day", 1)
        days = _integer(feed["website_history_days"], "feed.website_history_days", 1)
        if days > (last - history).days + 1:
            raise ValueError("Website history count exceeds its calendar span")
        if not isinstance(feed["full_streak_confirmed"], bool):
            raise ValueError("full_streak_confirmed must be true or false")
        if feed["full_streak_confirmed"] and (history != since or days != total):
            raise ValueError("Full streak confirmation needs history covering the full count")
        channels = facts["channels"]
        for name in ("site_feed", "x", "facebook", "instagram", "tiktok", "pinterest"):
            if channels[name] not in {"active", "off", "pending", "drafts_only", "packs_only"}:
                raise ValueError("Channel state is not recognized")
        for key in ("products", "scheduled_jobs", "health_checks", "paying_clients"):
            _integer(facts["counts"][key], f"counts.{key}")
        _integer(facts["catalog_refresh_days"], "catalog_refresh_days", 1)
        offer = facts["offer"]
        if offer["currency"] != "CAD":
            raise ValueError("This offer snapshot must explicitly use CAD")
        if not isinstance(offer["monthly_prices"], list) or not offer["monthly_prices"]:
            raise ValueError("monthly_prices must be a nonempty list")
        for price in offer["monthly_prices"]:
            _integer(price, "monthly price", 1)
        _integer(offer["setup_total"], "offer.setup_total", 1)
        for key in ("approved_statistics", "approved_testimonials"):
            if not isinstance(facts[key], list) or any(not isinstance(s, str) or not s.strip() for s in facts[key]):
                raise ValueError(f"{key} must contain only nonempty, reviewed public phrases")
    except (KeyError, TypeError, AttributeError) as exc:
        raise ValueError("Facts are missing required fields or have the wrong shape") from exc
    return facts


def load_facts(path: Path = DEFAULT_FACTS) -> dict:
    return validate_facts(json.loads(path.read_text(encoding="utf-8")))


WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
         "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
         "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
         "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
         "nineteen": 19, "twenty": 20, "once": 1, "twice": 2, "thrice": 3}
NUMBER = r"(?:\d+(?:,\d{3})*|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|once|twice|thrice)"
CHANNELS = {"x": r"\bx\b|\btwitter\b", "facebook": r"\bfacebook\b|\bfb\b",
            "instagram": r"\binstagram\b", "tiktok": r"\btik\s*tok\b",
            "pinterest": r"\bpinterest\b"}
POSTING = r"\b(?:post(?:s|ed|ing)?|publish(?:es|ed|ing)?|autopost(?:s|ed|ing)?|auto-post(?:s|ed|ing)?|shar(?:e|es|ed|ing)|runs?)\b"
FREQUENCY = r"\b(?:daily|every (?:single )?day|each day|per day|a day|day after day|\d+\s*[x×])\b"
SITE_FEED = r"\b(?:(?:my|our) (?:own )?store['’]s feed|(?:my|our) (?:own )?(?:site|website)(?:['’]s)? feed|(?:site|website)[ -]feed)\b"


def _number(s: str) -> int:
    return WORDS[s.lower()] if s.lower() in WORDS else int(s.replace(",", ""))


def _sentences(text: str) -> list[str]:
    return [s.strip() for s in re.split(r"[.!?](?:\s+|$)|;", text) if s.strip()]


def check_text(text: str, facts: dict, as_of: date | None = None) -> list[Finding]:
    """Find known contradictions and claims needing proof; never certify a draft."""
    validate_facts(facts)
    if not isinstance(text, str) or not text.strip():
        raise ValueError("Post text is empty")
    as_of = as_of or date.today()
    if not isinstance(as_of, date):
        raise ValueError("as_of must be a date")
    findings: list[Finding] = []

    def add(code: str, message: str) -> None:
        finding = Finding(code, message)
        if finding not in findings:
            findings.append(finding)

    verified = _date(facts["verified_on"], "verified_on")
    feed = facts["feed"]
    since, last = _date(feed["since"], "feed.since"), _date(feed["last"], "feed.last")
    span = (last - since).days + 1
    if verified != as_of:
        add("STALE_FACTS", "Facts were not verified for the review date. Recheck them before using any current claim.")
    if last < as_of - timedelta(days=1):
        add("STALE_FEED", "The latest feed date is older than yesterday; it cannot support a current daily streak.")

    for original in _sentences(text):
        s = original.lower().replace("’", "'")
        known_stat = original.strip() in facts["approved_statistics"]
        known_quote = original.strip() in facts["approved_testimonials"]
        site = bool(re.search(SITE_FEED, s))
        posting = bool(re.search(POSTING, s))
        frequency = bool(re.search(FREQUENCY, s))
        # These local denials are exempt; one denial must not excuse other clauses.
        denial = bool(re.search(r"\b(?:do not|don't|does not|doesn't|never|not yet|no longer)\s+(?:auto[- ]?)?(?:post(?:s|ed)?|publish(?:es|ed)?|shar(?:e|es|ed))\b", s))
        if re.search(r"\b(?:and|but|while|although)\b|,", s):
            denial = False  # A mixed clause needs review; do not hide a positive claim.
        past = bool(re.search(r"\b(?:used to|previously|in the past|stopped|paused|shelved)\b", s))
        drafting = bool(re.search(r"\b(?:drafts?|drafting|packs? only|sample(?:s)? only)\b", s))
        has_channel = False
        for channel, pattern in CHANNELS.items():
            if not re.search(pattern, s):
                continue
            has_channel = True
            if posting and not denial and not past:
                state = facts["channels"][channel]
                if state != "active" and not (drafting and not frequency and not re.search(r"\b(?:public|live)\b", s) and state in {"drafts_only", "packs_only"}):
                    add("CHANNEL_NOT_LIVE", f"{channel} is {state}; do not claim live public posting on that channel.")
        if re.search(r"\b(?:every|all)\s+(?:social )?(?:platforms?|channels?)\b|\beverywhere\b", s) and posting and not denial:
            if any(v != "active" for k, v in facts["channels"].items() if k != "site_feed"):
                add("ALL_CHANNELS", "Several social channels are off or awaiting setup; posting everywhere is unsupported.")
        if posting and frequency and not site and not has_channel and not denial and not past:
            add("UNCLEAR_FEED", "Daily posting must name the own store's site feed; a generic page or unnamed channel is not proven.")
        if site and posting and not denial:
            if facts["channels"]["site_feed"] != "active":
                add("FEED_NOT_LIVE", "The site-feed channel is not confirmed active.")
            for m in re.finditer(rf"\b({NUMBER})\s*(?:times|posts|x|×)?\s*(?:a|per|each|every)\s+day\b", s):
                if _number(m.group(1)) != feed["posts_per_day"]:
                    add("POST_FREQUENCY", "The site feed publishes one card per dated day; this daily frequency does not match.")
            for m in re.finditer(rf"\b({NUMBER})\s*[x×]\s*(?:daily|a day|per day)\b", s):
                if _number(m.group(1)) != feed["posts_per_day"]:
                    add("POST_FREQUENCY", "The site's claimed posts-per-day number does not match the facts.")
        for m in re.finditer(rf"\b(?:every (?:single )?day|daily|consecutive(?:ly)?|straight)\s+(?:for\s+)?({NUMBER})\s+days\b|\b({NUMBER})\s+(?:consecutive|straight)\s+days\b|\bfor\s+({NUMBER})\s+days\s+(?:straight|in a row)\b", s):
            n = _number(next(g for g in m.groups() if g is not None))
            if n != feed["total"]:
                add("STREAK_COUNT", "Claimed streak days do not match the live-feed counter snapshot.")
            if feed["total"] != span:
                add("FEED_GAPS", "The counter is smaller than the calendar span; it does not prove an unbroken streak.")
            if not site:
                add("STREAK_SCOPE", "The counter belongs to the own store's site feed, not a social page or account.")
            if not feed["full_streak_confirmed"]:
                add("STREAK_EVIDENCE", "Full website-feed history is not confirmed. Claude must resolve the counter's earlier three days before a full-streak claim.")
        if site and posting and re.search(r"\bsince\s+(?:august|aug)\s+4(?:th)?\b|\bsince\s+2026-08-04\b", s) and not feed["full_streak_confirmed"]:
            add("STREAK_EVIDENCE", "A website-feed streak since August 4 lacks full archive evidence; check with Claude.")
        if re.search(r"\b(?:posted|published)\b.*\btoday\b", s) and (site or "feed" in s) and last != as_of:
            add("NOT_POSTED_TODAY", "The snapshot's latest feed entry is not dated today.")
        for m in re.finditer(rf"\b({NUMBER})\s+(?:automatically\s+)?posts?\s+(?:published|generated|since|on our feed)\b|\b(?:posted|published|generated)\s+({NUMBER})\s+posts?\b", s):
            if _number(next(g for g in m.groups() if g is not None)) != feed["total"]:
                add("FEED_COUNT", "The claimed total does not match the live-feed counter.")
        if re.search(r"\b(?:restocked|restocks|refreshes|refreshed|refresh|rotates)\s+(?:daily|every day|each day)\b|\bdaily\s+(?:restock|catalog refresh)\b", s):
            add("CATALOG_FREQUENCY", "The catalog refresh is scheduled every three days, not daily.")
        for m in re.finditer(rf"\b(?:catalog|catalogue|lineup|store)\b.*?\bevery\s+({NUMBER})\s+days\b", s):
            if _number(m.group(1)) != facts["catalog_refresh_days"]:
                add("CATALOG_FREQUENCY", "Claimed catalog refresh interval does not match the configured schedule.")
        count_patterns = {"products": rf"\b({NUMBER})\+?\s+(?:live |current )?products?\b",
                          "scheduled_jobs": rf"\b({NUMBER})\s+scheduled\s+(?:jobs?|workflows?)\b",
                          "health_checks": rf"\b({NUMBER})\s+health\s+checks?\b",
                          "paying_clients": rf"\b({NUMBER})\+?\s+(?:paying |happy |satisfied )?(?:clients?|customers?)\b"}
        for key, pattern in count_patterns.items():
            for m in re.finditer(pattern, s):
                n = _number(m.group(1))
                # ~200 describes a 199-product snapshot honestly; exact 200 does not.
                rounded = key == "products" and n == 200 and abs(facts["counts"][key] - n) <= 5 and bool(re.search(r"(?:~|about\s+|roughly\s+|approximately\s+)$", s[:m.start()]))
                if n != facts["counts"][key] and not rounded and not known_stat:
                    add("UNSUPPORTED_COUNT", f"The {key.replace('_', ' ')} number does not match the reviewed snapshot.")
        testimonial = re.search(r"\b(?:testimonials?|five[- ]star|5[- ]star|rated|google review|customers? (?:say|said|love|recommend)|clients? (?:say|said|love|recommend)|happy customers?|trusted by|people (?:actually )?love|most[- ](?:loved|picked)|flying off the shelves|best[- ]selling)\b|[★⭐]{2,}|[\"“][^\"”]+[\"”]\s*[—-]", s)
        no_quote = re.search(r"\b(?:no|zero|don't have|do not have|without)\s+(?:customer )?(?:reviews?|testimonials?)\b", s)
        if testimonial and not no_quote and not known_quote:
            add("TESTIMONIAL_PROOF", "A quote, rating or customer-approval claim needs a genuine reviewed public source; fiction is not customer proof.")
        if re.search(r"\b(?:never fails?|never misses?|never (?:gets busy|takes a vacation|forgets)|cannot fail|can't fail|no missed days|guaranteed results|always posts|posts itself forever)\b", s):
            add("ABSOLUTE_PROMISE", "The workflow has needed retries; absolute reliability or guaranteed results are not proven.")
        if re.search(r"\b(?:search volume|sell[- ]through|social velocity)\b", s) and re.search(r"\b(?:score|ranked|blend|tracks|watch)\b", s):
            add("TREND_FORMULA", "The current score uses CJ listing counts, not a measured search/social/sell-through blend.")
        if re.search(r"\b(?:free shipping|ships free)\b.*\b(?:every|all)\b", s):
            add("SHIPPING_SCOPE", "Logo merch can have a shipping charge; free shipping cannot be promised on every order.")
        if re.search(r"\$\s*0\s*(?:/\s*(?:month|mo)|per month|a month)|\bzero (?:operating )?cost\b", s) and not re.search(r"\b(?:infrastructure|hosting|domain|transaction|per[- ]order)\b", s):
            add("COST_SCOPE", "Zero-cost wording must explain the domain bill and per-order costs.")
        # Unsupported statistics/outcomes, not dates, URLs or the listed offer.
        if not known_stat and re.search(r"\d+(?:\.\d+)?\s*(?:%|percent|[x×]\s+(?:more|sales|growth))|\b(?:doubled|tripled)\b.*\b(?:sales|revenue|clients|customers)\b", s):
            add("STATISTIC_PROOF", "The percentage, multiplier or business result has no reviewed evidence in the facts.")
        for m in re.finditer(r"\$\s*(\d+(?:\.\d{1,2})?)", s):
            value = float(m.group(1))
            context = s[max(0, m.start()-30):m.end()+50]
            monthly = bool(re.search(r"/\s*(?:mo(?:nth)?s?)\b|\b(?:per|a) month\b|\bmonthly\b", context))
            known_price = value in facts["offer"]["monthly_prices"] if monthly else value in {0, facts["offer"]["setup_total"]}
            if not known_price and not known_stat:
                add("PRICE_OR_MONEY_PROOF", "The money amount is not a reviewed offer price or supported statistic.")
            if monthly and known_price and re.search(r"\busd\b|\bus dollars?\b", context):
                add("WRONG_CURRENCY", "ECS monthly prices are CAD, not USD.")
        if not known_stat and re.search(r"\b\d[\d,]*\s+(?:reviews?|followers?|orders?|sales|businesses|stores|subscribers|views|likes|leads|years)\b", s):
            add("STATISTIC_PROOF", "The audience, order, experience or business count has no reviewed evidence.")
    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--text", help="Draft to inspect; defaults to standard input")
    parser.add_argument("--facts", type=Path, default=DEFAULT_FACTS)
    parser.add_argument("--as-of", type=date.fromisoformat, default=date.today(), help="Review date; defaults to this machine's date")
    parser.add_argument("--json", action="store_true", help="Print findings without repeating the draft")
    args = parser.parse_args(argv)
    try:
        findings = check_text(args.text if args.text is not None else sys.stdin.read(), load_facts(args.facts), args.as_of)
    except (OSError, ValueError) as exc:
        # No file contents or draft text in errors.
        print("Cannot check: invalid/empty text or unreadable/invalid facts. Review the input and facts file.", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps({"findings": [asdict(f) for f in findings], "approved": False}, ensure_ascii=False))
    elif findings:
        for finding in findings:
            print(f"{finding.code}: {finding.message}")
    else:
        print("No recognized problem. This is not proof that the post is true; Claude still reviews it.")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
