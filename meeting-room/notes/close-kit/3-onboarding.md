# 3. Onboarding: from "yes" to the first post

Who does what: **M** = Matthew only · **C** = a Claude chat drafts/makes it · **A** = automatic (a script or workflow runs it).
The tools already exist in Helm-Private `ecs/delivery-kit/` (intake, checklist, approve sheet, invoice draft) and `ecs/first-client-kit/`.

## What Matthew needs from the client
1. Their **yes in writing** (an email or text reply is enough).
2. **Intake answers** (Helm-Private `ecs/delivery-kit/intake.md`; pre-fill what we know so they only check it): exact business name, page link, who approves, which photos are OK, hours, top items/services, words to never post, best time, anything coming up, address/area and phone to show, logo/colours, English or French.
3. **Facebook access from their own account**: they add Matthew to their page. Never a password.
4. **Week 1 approved** ("All ✅" or ✅ per post).
5. **The $79 paid** before the first post (how: [5-payment-options.md](5-payment-options.md)).

## Step by step

| # | Step | Who | Proof it's done |
|---|---|---|---|
| 1 | Save their written yes in their private folder | C | file in Helm-Private |
| 2 | Pre-fill and draft the intake email | C | draft in Helm-Private |
| 3 | Roxy OK + Claude OK on the draft, then send it | M | Gmail Sent |
| 4 | Intake answers in; copy into their folder | C | file updated |
| 5 | They add Matthew to the page; Matthew accepts the invite | M (+ client) | Matthew sees the page in his account |
| 6 | Make week 1 (7 posts; reuse the free samples where they fit) | A + C | `engine/sample_week.py` cards + captions |
| 7 | Fact pass on every caption against their own page, plus `claims_check` | A + C | check output, 0 open findings |
| 8 | Build the approve page for week 1 | A | `ecs/approval/make_approval_page.py` output |
| 9 | Make the invoice (if the money step uses one) | A | `ecs/first-client-kit/make_invoice.py` output |
| 10 | Send week 1 + invoice / payment note | M | Gmail Sent |
| 11 | Approval in; payment in | M | their reply saved; Matthew says "paid" |
| 12 | **Both in? Only then:** first post goes up, by hand, at their best time | M | live post link |
| 13 | Log it: posts approved, posts up | C | private log |

Step 12 is by hand for the pilot: the page says "for the pilot, I check and post them by hand after you approve them".
The engine's auto-posting is only wired to our own page; don't connect a client's page without a separate GO.

## Every week after (weeks 1-4)
- By Thursday: next week's 7 posts on the approve page (C makes, M sends). Week 4 has 9 posts so the month totals 30.
- Changes: one round a week (up to 3 posts). Wrong facts fixed free, any time.
- Post only approved posts, on the approved days.
- A live post has a mistake: fix it or take it down within 24 hours of hearing.
- **STOP** (any wording): posting stops that day, take down that day's post if they want, reply once to confirm.
- Day 7: a 2-line check-in. Day 28-30: thank-you with only numbers we can see, and "Want to keep going next month?" Ask, don't push.

## How long it takes Matthew (estimate)
The Nov 8 practice run (made-up bakery) estimated about 1.5-2 hours of Matthew's time from yes to the first approved week. Treat it as an estimate, not a measurement.
