# Council decision log

The record of every full council session — newest first. Written by the
Right Hand at the end of each `/council` run; `Matthew's decision` is
updated when he makes the final call. Precedent here feeds future sessions.

Format per entry:

```
## YYYY-MM-DD — <framed decision>
- Seats: Operator GO(4) · Marketer GO-IF(3) · Treasurer NO-GO(4) · Skeptic GO-IF(2) · Customer GO(5)
- Clash: <one line>
- Right Hand's call: <VERDICT — one-line reason>
- Matthew's decision: pending | <what he chose>
- Next moves: <comma-separated>
```

---

## 2026-08-14 — Add one-time downsell offers (week-of-posts ~$49, GBP fix-up ~$75, print bundle ~$99) as verbal fallbacks in ECS sales conversations, and at what prices?
- Seats: Operator NO-GO(4) · Marketer GO-IF(4) · Treasurer GO-IF(4) · Skeptic GO-IF(4) · Customer GO-IF(4)
- Clash: first split council. Operator says the trio shouldn't exist (the $49 week sells what two public surfaces promise free; GBP undeliverable by a novice mid-verification; honest fallback already in the kit: "no contracts = try one month for $79"). The four GO-IFs converge on the same repairs from different angles: no paid line until price objections are actually logged (zero to date — the funnel dies at contact, not price), the paid week must become a LIVE posted "Launch Week" credited toward month one (a deposit, not a downsell), GBP gated behind Matthew's own verification surviving cleanly (2026 video-reverification suspension wave), print bundle killed from the script.
- Right Hand's call: GO-IF — nothing changes in today's conversations (free sample week + "cancel any month" stay the only fallbacks). Two rebuilt offers enter the kit GATED, not live: (1) "Launch Week" $99 one-time — the approved pack POSTED to their real page for 7 days, pay on completion, $99 credited in full against month one if they subscribe within 30 days; unlocks only after 3 logged conversations where a prospect saw their free sample week and declined specifically on price/commitment. (2) "Google fix-up" $99 flat, done-WITH-you (owner keeps the login and does the video verification; written scope cap); unlocks only after Matthew's own GBP listing is verified and survives one edit cycle. Print bundle: never scripted — quote-per-job on request, one all-in prepaid number. Paper before promises: scope/receipt one-pager + e-transfer auto-deposit exist before any paid line is spoken. Every offer/outcome logged in prospects.md (DOWNSELL markers); every one-time buyer logged as a grant customer-reference. Free sample week stays free, first, and unchanged in all public copy; design freeze holds.
- Matthew's decision: pending
- Next moves: today's calls unchanged, gated Fallback Offers section into call-kit.md on Matthew's go, scope/receipt template drafted, Matthew finishes own GBP verification (starts the GBP unlock clock), kill-switch: first two Launch Week buyers 0-for-2 on upgrading = pull the line

## 2026-08-13 — Ship a half-day "credibility surgery" design wave on both live sites this week (then freeze design until Aug 31), rather than leaving them as-is or redesigning?
- Seats: Operator GO-IF(4) · Marketer GO-IF(4) · Treasurer GO-IF(4) · Skeptic GO-IF(4) · Customer GO-IF(4)
- Clash: none on direction — all five converged on the same wounds (stat band over-claims that the page's own odometer fact-checks; price buried 6+ sections deep with CAD/USD ambiguity; EN hero's gold CTA a silent-failing mailto; "written by a machine" proof card scaring the exact audience; FR proof in English). Only tension was scope: Treasurer/Skeptic hard-capped hours (2h/half-day) vs the breadth of combined lists. Resolved: Right Hand executes (Claude-time), founder review ≈ minutes, then hard freeze.
- Right Hand's call: GO-IF — executed same-session: stat band → $79/mo CAD + odometer-backed streak + $0-until-approved; hero text-first with visible number + price in free-week line (EN/FR converged); proof feed curated ("machine" card filtered + pool entry rewritten); FR example posts translated + bilingual-service line; store link demoted into proof figure; theme follows system preference; store "worldwide"→24 countries + hero grammar fix. Deferred: store-live.jpg mobile recrop, FR dynamic feed captions (engine change, post-first-client). DESIGN FROZEN until Aug 31 — remaining founder-hours go to calls.
- Matthew's decision: pending
- Next moves: verify deploy + screenshots, LeBlanc call 2 PM, Léger + A&M callbacks Friday, design freeze

## 2026-08-12 — Which 2-4 items make up the next website build wave (backlog + new ideas) toward a first ECS client by Aug 31?
- Seats: Operator GO-IF(4) · Marketer GO(4) · Treasurer GO-IF(4) · Skeptic GO-IF(4) · Customer GO-IF(4)
- Clash: everyone wants a wave, but the seats split on the odometer (3 want it gated-honest, Skeptic says not until ~30 days of artifacts, Operator offers the "N posts since Aug 7" stored-counter compromise) and on store-side polish (Customer wants trust line + countdown; Treasurer kills them on collapsed EV; Skeptic bans public copy changes during the clean-baseline week). Unanimous cross-seat finding: the UNDEPLOYED worker order-alert is worth more than any new item.
- Right Hand's call: GO-IF — wave = (0) Matthew deploys the worker alert + NTFY_TOPIC before Friday's ad [gate, non-negotiable]; (1) traffic_report.py fixes: 7-day window (line-128 bug, channel_breakdown called with no start) + missing tags fb/fb-ad/card/gbp/x-qr — before Fri Aug 15; (2) proof-asset armor: backup crons + gate for ecs-daily-post.yml + staleness watchdog in traffic-report.yml (newest feed entry silently stale is the existential failure); (3) per-prospect sample-pack QR (ref=sample-<slug>, slug ≤17 chars) ready before the next pack prints. Odometer deferred to next wave in Operator's honest form only; trust strip/chips/badges/dates/countdown killed or deferred per Treasurer. Build capped ~4h; calls outrank commits.
- Matthew's decision: pending
- Next moves: Matthew worker paste-deploy + NTFY_TOPIC (10 min), Claude ships items 1-3 today, Léger call 1-2 PM unaffected, odometer revisited after watchdog runs clean

## 2026-08-06 — Take the Printify logo-merch pop-up store fully live and announce it this August, rather than deferring?
- Seats: Operator GO-IF(4) · Marketer GO-IF(4) · Treasurer GO(4) · Skeptic GO-IF(4) · Customer GO-IF(4)
- Clash: no seat wants to defer — the fight is over sequencing. The site already claims the lineup is "live now" but all five Printify product pages dead-end at "coming soon" with no Add to Cart, so the current half-launched state is the worst of the three worlds; announcement must come after publish + verification, not before.
- Right Hand's call: GO-IF — finish the launch this month: publish the five products and complete Stripe payout verification in Printify, place one real test order (the sticker), and land the repo fix commit (merch click instrumentation, ?ref-tagged links via findhotstuff.com/#merch, sticker price sync, README update + Merchant-of-Record tax note, tweet copy, sw.js VERSION bump, standing merch slots in rotation packs) BEFORE firing any announcement. Hard fallback: if Printify can't publish in August, revert the "live now" copy immediately.
- Matthew's decision: GO (2026-08-06) — purchase test already cleared; launch-prep prompt saved to `.claude/prompts/printify-launch-prep.md`; announcement still gated on product pages verifying purchasable + wearable sample before the full blast
- Next moves: run the launch-prep prompt, verify the 5 product pages transact (they showed "coming soon" on Aug 6 checks), fire merch-tweet workflow_dispatch when green, hold 4-channel blast until sample passes
- Update (2026-08-06, later): STORE IS LIVE — Matthew completed Stripe verification and all five product pages now show Add to Cart. Launch commit landed: shipping carve-out (EN/FR), README flip + Merchant-of-Record note, live tweet copy + regenerated card (new `make_merch_card.py` generator), standing merch slots in the Pinterest and X packs, sw.js v12. Remaining: Matthew's $3.49 sticker test order, fire the merch-tweet workflow_dispatch, tee sample before the full multi-channel blast, revoke the Printify API token.
- Update (2026-08-06, via Printify API): all five products are correct product-side — visible, unlocked, priced, variants enabled (tee has Black+White, cap has Black/Royal/Grey; sticker really is from $3.49, so the site copy needs no price fix). The sole blocker is store-level: the Pop-Up Store sits in "coming soon" until payout setup (Stripe identity/bank verification) is completed in the Printify dashboard — owner-only (KYC). After that: sticker test order, then the remaining launch commit (free-shipping carve-out, README + Merchant-of-Record note, live tweet copy, rotation pack slots).
