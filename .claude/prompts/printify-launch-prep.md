# Printify merch launch prep — repo-side commit

Paste this into a Claude Code session in the hotstuff repo:

---

The Printify logo-merch pop-up store (hotstuff-store.printify.me) is going
fully live this month. The council session of 2026-08-06 (see
`.claude/council/DECISIONS.md`) set the launch conditions and a real
purchase test has already cleared. Your job is the repo-side launch commit.
Do NOT fire any announcement workflow in this session.

1. **Verify the store actually transacts — before anything else.** Fetch
   each product page:
   - https://hotstuff-store.printify.me/product/30344866 (Classic Tee, site says $24.99)
   - https://hotstuff-store.printify.me/product/30344867 (Crewneck, $39.99)
   - https://hotstuff-store.printify.me/product/30344868 (Cap, $29.99)
   - https://hotstuff-store.printify.me/product/30345175 (Mug, $16.99)
   - https://hotstuff-store.printify.me/product/30345176 (Sticker, site says "From $3.49")

   Each must show a real price and Add to Cart — NOT "This product is
   coming soon!" with a Notify-me button (that's what they showed on
   Aug 6). Note each product's store price and available colours (the site
   tiles show a black tee and black crewneck — confirm the store sells
   black). **If ANY product still dead-ends at coming-soon: do steps 2 and
   7 only, leave all copy untouched, and report — the site must not
   announce what can't be bought.**

2. **Instrument merch clicks.** In `script.js`, add GoatCounter click
   events on the five merch cards (`merch-tee`, `merch-crewneck`,
   `merch-cap`, `merch-mug`, `merch-sticker`), mirroring the existing
   `buy-<id>` event pattern in `startCheckout`. Fire-and-forget — never
   delay or block the navigation to Printify.

3. **Sync the site with store reality** (as confirmed in step 1): the
   sticker price in `index.html` AND `i18n.js` ($3.49 on the site vs $3.99
   in the store — match the store); any tile-image/colour-variant
   mismatches; and scope the "Free shipping on every order" promise
   (announce bar + trust strip) so merch is excluded — extend the
   merch-note: merch ships from the print partner, shipping calculated at
   checkout.

4. **README.md**: update the line (~191) saying logo-merch tiles are
   "Coming soon" until the pop-up is live, and add to Known limitations:
   pop-up merch sales make the owner the Merchant of Record — Printify
   does not collect or remit sales tax on them.

5. **Announcement copy**: in `post_merch_tweet.py`, replace the
   "logo merch drops soon" copy with a live announcement. All links go to
   `https://findhotstuff.com/?ref=x#merch` — the `?ref=` query must come
   BEFORE the `#merch` fragment or GoatCounter never sees it; never link
   printify.me directly (unmeasured domain). Check whether
   `marketing/merch-tweet-card.png` has "soon" baked into the image and
   regenerate it via the card generator if so. Do NOT edit
   `.github/workflows/merch-tweet.yml` — pushes touching that file
   auto-fire the tweet. Matthew dispatches the workflow manually later.

6. **Standing merch slot in the rotation packs**, so the machine
   re-markets merch every 3 days for free: one merch pin per cycle in
   `make_pinterest_pins.py` (link `https://findhotstuff.com/?ref=pin#merch`)
   and one merch line per cycle in `generate_posts.py` /
   `marketing/latest-posts.md`. Follow each generator's existing style and
   ref-tag scheme exactly.

7. **Bump `VERSION` in `sw.js`** — required by the README for any
   `index.html`/`styles.css`/`script.js` change, or installed PWAs keep
   serving the stale shell.

8. Sanity-check locally (`npx serve .`, load the page, click a merch card,
   confirm the GoatCounter event fires and the console is clean), then
   commit everything as one commit and push to the current branch.
   Report back: per-product verification results from step 1, files
   changed, and what's left for Matthew — fire the merch-tweet
   `workflow_dispatch` once step 1 is green, and hold the full
   multi-channel blast until a wearable sample has arrived and passed
   inspection.
