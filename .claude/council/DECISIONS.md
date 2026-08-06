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

## 2026-08-06 — Take the Printify logo-merch pop-up store fully live and announce it this August, rather than deferring?
- Seats: Operator GO-IF(4) · Marketer GO-IF(4) · Treasurer GO(4) · Skeptic GO-IF(4) · Customer GO-IF(4)
- Clash: no seat wants to defer — the fight is over sequencing. The site already claims the lineup is "live now" but all five Printify product pages dead-end at "coming soon" with no Add to Cart, so the current half-launched state is the worst of the three worlds; announcement must come after publish + verification, not before.
- Right Hand's call: GO-IF — finish the launch this month: publish the five products and complete Stripe payout verification in Printify, place one real test order (the sticker), and land the repo fix commit (merch click instrumentation, ?ref-tagged links via findhotstuff.com/#merch, sticker price sync, README update + Merchant-of-Record tax note, tweet copy, sw.js VERSION bump, standing merch slots in rotation packs) BEFORE firing any announcement. Hard fallback: if Printify can't publish in August, revert the "live now" copy immediately.
- Matthew's decision: GO (2026-08-06) — purchase test already cleared; launch-prep prompt saved to `.claude/prompts/printify-launch-prep.md`; announcement still gated on product pages verifying purchasable + wearable sample before the full blast
- Next moves: run the launch-prep prompt, verify the 5 product pages transact (they showed "coming soon" on Aug 6 checks), fire merch-tweet workflow_dispatch when green, hold 4-channel blast until sample passes
- Update (2026-08-06, via Printify API): all five products are correct product-side — visible, unlocked, priced, variants enabled (tee has Black+White, cap has Black/Royal/Grey; sticker really is from $3.49, so the site copy needs no price fix). The sole blocker is store-level: the Pop-Up Store sits in "coming soon" until payout setup (Stripe identity/bank verification) is completed in the Printify dashboard — owner-only (KYC). After that: sticker test order, then the remaining launch commit (free-shipping carve-out, README + Merchant-of-Record note, live tweet copy, rotation pack slots).
