# Claims checker frequency review — November 5, 2026

Branch: `gpt/claims-frequency-2026-11-05`. Claude reviews before master. Nothing is wired into publishing.

## Change

Unsupported posting claims such as “3x a day”, “every hour”, “posts daily” and “every day” now produce `POST_FREQUENCY`. Unnamed posting rates also produce `UNCLEAR_FEED`. Counted/word/Unicode forms, hourly/daily/weekly wording and wrapped caption lines are checked.

The website feed's rate never authorizes a social channel. An active channel is not evidence of a recurring rate. Frequency evidence must match the channel, count, period and review date. Stale facts still require review. Negations and historical wording cannot hide another positive clause; shared subjects must all have evidence.

The optional `posting_frequencies` object is empty in the refreshed snapshot: no social rate is currently supported. To add one after human verification:

```json
{
  "facebook": {
    "posts": 1,
    "per": "day",
    "verified_on": "YYYY-MM-DD",
    "source": "public URL or pinned archive path reviewed for this rate"
  }
}
```

This example is a schema illustration, not real Facebook evidence. Dates must be real ISO dates; counts are positive integers and `per` is `hour`, `day` or `week`. Older snapshots without this field remain readable and supply no social-rate evidence. The site rate continues to use `feed.posts_per_day`, channel status and recent feed dates.

## Facts refreshed

Reviewed public repository state: `b57f903cf890bca58cfc9fa64e1ac2a0d0aed0ef`. Review date is November 5 in America/Moncton, even though GitHub timestamps can show November 6 UTC.

- Feed: 91 dated website cards, August 7–November 5. Thirteen historical `automation/feed/index.json` snapshots cover every date; pinned commits and date ranges are recorded in `tools/claims_facts.json`. This supports the website archive, not social-page delivery, live uptime or publication times.
- Products: 200 entries in `products.json`.
- Scheduled workflows: 15 files declaring schedules, including retry schedules. This count is not successful runs or posts per day.
- Health checks: 15 configured entries in `smoke_test.py`, not evidence they all passed live.
- Facebook: one public November 5 card recorded in `CLAUDE.md`; active for existence, with no supported recurring rate. Other social states remain conservative.
- Catalog: three-day calendar cron setting, with shorter month-boundary intervals; not guaranteed delivery.
- Current Facebook offer: $79 pilot month for the first two businesses, free setup, from `automation/index.html`. Removed the stale $129 tier. `monthly_prices` remains a legacy field name, not proof of agreed renewal pricing. The legacy noindex setup page's $250 is a separate offer and is not the current Facebook-pilot setup fee.
- Paying clients: zero is explicitly identified as owner-reported, not independently audited from payment accounts. No private client records are included.

## Validation

`PYTHONDONTWRITEBYTECODE=1 python3 tools/claims_check_test.py`: 67 tests pass, including the original 49. Frozen historical tests use their own fixture even after the production snapshot changes. CLI cases check supported website daily copy, unsupported hourly/Facebook/generic copy, stale dates and the refreshed offer values. JSON output continues to say `approved: false`.

Two independent read-only passes checked the public evidence and adversarial frequency cases. Tests cover the detected compound-subject, negation, multiplier and wrapped-line bypasses.

## Limits

This is an English rule-based review aid, not a truth certificate. It can conservatively flag ambiguous clauses and cannot fully understand quotation, grammar or future service promises. “Open every day” and “daily specials” without a posting claim are outside this new rule. A configured schedule never proves public posting. Recheck the snapshot for another review date; no automatic approval or network lookup has been added.

## Claude review fix — client offer scope

The reviewed daily Facebook offer is now separate from observed posting history. `offer.posting_frequency` records the offered channel, posts, period, review date and public source. Client-page wording, “for every day of the month”, “I post them, one a day” and “$79 for a month of daily posts” use that offer evidence. They do not require an already-running client account or imply ECS's own Facebook page has posted daily.

Offer evidence must be current and match the stated rate and platform. Hourly, three-per-day, non-Facebook, historical-delivery and mixed own/client claims still need review. Compound subjects retain each client platform so Instagram cannot borrow the website's daily evidence. Missing/malformed/stale offer evidence does not pass. Price and other honesty checks still run independently.

Validation after this fix: 73 tests pass using both `python3 -m unittest tools/claims_check_test.py` and `python3 tools/claims_check_test.py` from the repository root. The original 67 tests remain, with six additional offer/import regression test methods. The four exact phrases in Claude's issue 15 review pass against the current offer snapshot.
