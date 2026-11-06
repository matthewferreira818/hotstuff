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
        rates = facts.get("posting_frequencies", {})
        if not isinstance(rates, dict):
            raise ValueError("posting_frequencies must be a scoped object")
        for channel, evidence in rates.items():
            if channel not in {"x", "facebook", "instagram", "tiktok", "pinterest"}:
                raise ValueError("Frequency evidence must name a social channel; site rates use feed")
            _integer(evidence["posts"], "posting frequency", 1)
            if evidence["per"] not in {"hour", "day", "week"}:
                raise ValueError("Frequency evidence must use hour, day or week")
            if _date(evidence["verified_on"], "frequency verification") > verified:
                raise ValueError("Frequency evidence cannot be newer than the snapshot")
            if not isinstance(evidence["source"], str) or not evidence["source"].strip():
                raise ValueError("Frequency evidence needs a reviewed source")
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
        _integer(offer["setup_total"], "offer.setup_total")
        if "posting_frequency" in offer:
            rate = offer["posting_frequency"]
            if rate["channel"] not in {"facebook", "instagram", "x", "tiktok", "pinterest"}:
                raise ValueError("The offer rate must name a social channel")
            _integer(rate["posts"], "offer posting frequency", 1)
            if rate["per"] not in {"hour", "day", "week"}:
                raise ValueError("The offer rate must use hour, day or week")
            if _date(rate["verified_on"], "offer rate verification") > verified:
                raise ValueError("The offer rate cannot be newer than the snapshot")
            if not isinstance(rate["source"], str) or not rate["source"].strip():
                raise ValueError("The offer rate needs a reviewed source")
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
# Rates are not channel status: a single public post or a schedule is not proof
# that a channel actually publishes at a recurring frequency.
FREQUENCY = re.compile(
    rf"\b(?:(?P<count>{NUMBER})\s*(?:times?|posts?|[x×])?\s*"
    rf"(?:(?:a|an|per|each|every)\s+|/\s*)(?P<count_unit>hours?|days?|weeks?)"
    rf"|(?P<adverb_count>{NUMBER})\s*(?:[x×]|times?|posts?)?\s*(?P<count_adverb>hourly|daily|weekly)"
    rf"|(?:every|each)\s+(?:single\s+)?(?:(?P<interval>{NUMBER})\s+)?(?P<interval_unit>hours?|days?|weeks?)"
    rf"|(?P<adverb>hourly|daily|weekly|day after day))\b",
    re.IGNORECASE,
)
SITE_FEED = r"\b(?:(?:my|our) (?:own )?store['’]s feed|(?:my|our) (?:own )?(?:site|website)(?:['’]s)? feed|(?:site|website)[ -]feed)\b"
CLIENT_PAGE = r"\byour\s+(?:(?:facebook|instagram|x|twitter|tik\s*tok|pinterest)\s+)?(?:business|page|feed)\b"
OWN_PAGE = r"\b(?:my|our)\s+(?:own\s+)?(?:business|page|feed|account)\b"
OFFER_WORDING = rf"{CLIENT_PAGE}|\bfor every day of (?:the )?month\b|\bi post them\b|\bfor a month of daily posts\b"
DELIVERY_HISTORY = r"\b(?:posted|published|already|since|yesterday|today)\b"


def _number(s: str) -> int:
    return WORDS[s.lower()] if s.lower() in WORDS else int(s.replace(",", ""))


def _sentences(text: str) -> list[str]:
    return [s.strip() for s in re.split(r"[.!?](?:\s+|$)|;", text) if s.strip()]


def _rate(match: re.Match) -> tuple[int, str, int]:
    """Return posts, time unit, interval without inferring hourly distribution."""
    adverbs = {"hourly": "hour", "daily": "day", "weekly": "week", "day after day": "day"}
    if match["count"]:
        return _number(match["count"]), match["count_unit"].rstrip("s"), 1
    if match["adverb_count"]:
        return _number(match["adverb_count"]), adverbs[match["count_adverb"]], 1
    if match["interval_unit"]:
        return 1, match["interval_unit"].rstrip("s"), _number(match["interval"] or "one")
    return 1, adverbs[match["adverb"]], 1


def _named_channels(text: str) -> set[str]:
    # The x in "one x a day" is a multiplier, not the X social account.
    without_rates = FREQUENCY.sub(" ", text)
    return {name for name, pattern in CHANNELS.items() if re.search(pattern, without_rates)}


def _client_offer_scopes(clause: str) -> set[str]:
    targets = set()
    for target in re.findall(CLIENT_PAGE, clause):
        targets |= _named_channels(target)
    return {f"client_offer:{target}" for target in targets} if targets else {"client_offer"}


def _subject_scopes(clause: str) -> set[str]:
    """Recognize subject-only list items, never whole statements like 'X is off'."""
    if re.fullmatch(r"i post them", clause.strip()):
        return {"client_offer"}  # "I post them, one a day."
    own_text = re.sub(CLIENT_PAGE, "", clause)
    scopes = _named_channels(own_text) | ({"site_feed"} if re.search(SITE_FEED, clause) else set())
    if re.search(OWN_PAGE, clause):
        scopes.add("unnamed_own_page")
    if re.search(CLIENT_PAGE, clause):
        scopes |= _client_offer_scopes(clause)
    rest = re.sub(SITE_FEED, "", own_text)
    for pattern in CHANNELS.values():
        rest = re.sub(pattern, "", rest)
    rest = re.sub(r"\b(?:my|our|the|own|page|pages|feed|feeds|account|accounts|both|on|'s)\b", "", rest)
    return scopes if not re.search(r"\w", rest) else set()


def _frequency_findings(text: str, facts: dict, as_of: date) -> list[Finding]:
    findings = []
    # Preserve line-wrapped rates ("every\nhour"), but keep separate caption lines scoped.
    text = FREQUENCY.sub(lambda m: re.sub(r"\s+", " ", m[0]), text)
    verb = r"(?:auto[- ]?)?(?:post(?:s|ed|ing)?|publish(?:es|ed|ing)?|shar(?:e|es|ed|ing))"
    historical = rf"\b(?:used to|previously|in the past(?: we| it| they| i)?|stopped|paused|shelved)\s+{verb}\b"
    pending_scopes: set[str] = set()
    # Evidence and negations belong to a clause, never to the whole paragraph.
    clauses = [c.strip() for c in re.split(r",|\n+|\b(?:and|but|while|although|however)\b", text) if c.strip()]
    for i, clause in enumerate(clauses):
        mentions = list(FREQUENCY.finditer(clause))
        offer_scope = bool(re.search(OFFER_WORDING, clause)) and not re.search(DELIVERY_HISTORY, clause)
        channels = _named_channels(re.sub(CLIENT_PAGE, "", clause) if offer_scope else clause)
        site = bool(re.search(SITE_FEED, clause))
        scopes = channels | ({"site_feed"} if site else set())
        if re.search(OWN_PAGE, clause):
            scopes.add("unnamed_own_page")
        if offer_scope:
            scopes |= _client_offer_scopes(clause)
        if not mentions:
            # Keep compound subjects: "Facebook and our site feed post daily".
            # An unrelated complete clause ("Facebook is off") must not carry over.
            subjects = _subject_scopes(clause)
            if subjects:
                pending_scopes |= subjects
            else:
                pending_scopes.clear()
            continue
        scopes |= pending_scopes
        pending_scopes.clear()
        # A rate can precede the final subject: "post daily on Facebook and Instagram".
        for following in clauses[i + 1:]:
            subjects = _subject_scopes(following)
            if not subjects:
                break
            scopes |= subjects
        remainder = FREQUENCY.sub("", clause).strip(" .!:?—-()")
        if not (re.search(POSTING, clause) or scopes or not remainder):
            continue  # "Open every day" and "daily specials" are not posting claims.
        if len(re.findall(rf"\b{verb}\b", clause)) == 1 and re.search(rf"\b(?:do not|don't|does not|doesn't|never|not yet|no longer)\s+{verb}\b|{historical}", clause):
            continue
        fresh = _date(facts["verified_on"], "verified_on") == as_of
        for mention in mentions:
            rate = _rate(mention)
            supported = bool(scopes)
            for scope in scopes:
                if scope == "unnamed_own_page":
                    supported = False
                elif scope == "client_offer" or scope.startswith("client_offer:"):
                    evidence = facts["offer"].get("posting_frequency")
                    target = scope.partition(":")[2]
                    supported &= bool(evidence) and fresh and (
                        evidence["verified_on"] == as_of.isoformat()
                        and not re.search(DELIVERY_HISTORY, clause)
                        and rate == (evidence["posts"], evidence["per"], 1)
                        and (not target or target == evidence["channel"])
                    )
                elif scope == "site_feed":
                    live = facts["channels"][scope] == "active"
                    recent = _date(facts["feed"]["last"], "feed.last") >= as_of - timedelta(days=1)
                    supported &= fresh and live and recent and rate == (facts["feed"]["posts_per_day"], "day", 1)
                else:
                    live = facts["channels"][scope] == "active"
                    evidence = facts.get("posting_frequencies", {}).get(scope)
                    supported &= bool(evidence) and fresh and live and (
                        evidence["verified_on"] == as_of.isoformat()
                        and rate == (evidence["posts"], evidence["per"], 1)
                    )
            if not supported:
                findings.append(Finding("POST_FREQUENCY", "The posting frequency lacks matching, current evidence for the stated feed, channel or client offer. Review the facts and scope."))
            if not scopes or "unnamed_own_page" in scopes:
                findings.append(Finding("UNCLEAR_FEED", "Name the feed or channel; an unnamed page has no reviewed posting frequency."))
    return findings


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
        frequency = bool(FREQUENCY.search(s))
        for finding in _frequency_findings(s, facts, as_of):
            add(finding.code, finding.message)
        # These local denials are exempt; one denial must not excuse other clauses.
        denial = bool(re.search(r"\b(?:do not|don't|does not|doesn't|never|not yet|no longer)\s+(?:auto[- ]?)?(?:post(?:s|ed)?|publish(?:es|ed)?|shar(?:e|es|ed))\b", s))
        if re.search(r"\b(?:and|but|while|although)\b|,", s):
            denial = False  # A mixed clause needs review; do not hide a positive claim.
        past = bool(re.search(r"\b(?:used to|previously|in the past|stopped|paused|shelved)\b", s))
        drafting = bool(re.search(r"\b(?:drafts?|drafting|packs? only|sample(?:s)? only)\b", s))
        named_channels = _named_channels(re.sub(CLIENT_PAGE, "", s))
        for channel in CHANNELS:
            if channel not in named_channels:
                continue
            if posting and not denial and not past:
                state = facts["channels"][channel]
                if state != "active" and not (drafting and not frequency and not re.search(r"\b(?:public|live)\b", s) and state in {"drafts_only", "packs_only"}):
                    add("CHANNEL_NOT_LIVE", f"{channel} is {state}; do not claim live public posting on that channel.")
        if re.search(r"\b(?:every|all)\s+(?:social )?(?:platforms?|channels?)\b|\beverywhere\b", s) and posting and not denial:
            if any(v != "active" for k, v in facts["channels"].items() if k != "site_feed"):
                add("ALL_CHANNELS", "Several social channels are off or awaiting setup; posting everywhere is unsupported.")
        if site and posting and not denial:
            if facts["channels"]["site_feed"] != "active":
                add("FEED_NOT_LIVE", "The site-feed channel is not confirmed active.")
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

