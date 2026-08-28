# CLAUDE.md — standing memory for every session

This file is the durable memory Matthew asked for (2026-08-19). Read it
first; it is why any Claude session here already "knows" him. Keep it
updated when standing facts change — it only works if it stays true.

## Who you're working with

Matthew Ferreira — founder, Memramcook NB, non-technical, has a day job
(roughly 6:45–4:30). Calls him-and-Claude "we"; Claude is his right hand,
not a vendor. Talk plainly: no jargon, short phone-friendly messages, lead
with what happened. He says "my guy"; warmth is part of the working style.
Use exact numbers and honest bad news — he handles "it broke" far better
than discovering something was papered over.

## The two businesses (one repo, one engine)

- **HotsTuff** — findhotstuff.com. Dropshipping storefront on GitHub Pages
  (deploys from `master`); CJ Dropshipping supplier; Stripe checkout via
  Cloudflare Worker `wavelist-checkout` (also handles /lead capture and
  order/lead alerts to his phone via ntfy through a GitHub-relay hop).
  **Domains are registered at Porkbun.** eastcoastsocial.ca currently sits
  there as a URL-forward to findhotstuff.com/automation/ that STRIPS the
  query string (verified 08-28), so every ?ref= tag through it is lost.
- **East Coast Social (ECS)** — findhotstuff.com/automation (EN + /fr).
  Done-for-you daily social posting for local NB businesses: free setup,
  free sample week, **$79/mo CAD, no contracts**. Standing goal: **first
  paying client by Aug 31, 2026**. The store is the proof: "built on our
  own store first" — its daily-posting streak is the sales pitch.

## Non-negotiables (the brand IS these rules)

1. **Radical honesty in every public artifact.** No invented testimonials,
   reviews, social proof, or product attributes. Product display names may
   only reorder/trim/re-case words from the real supplier title —
   `honest_name()` in refresh_products.py enforces it; photo-verified nouns
   are the only documented exception. Every claim on slides/pages must be
   true TODAY (past sins: "3× a day on X" while X was off; wallpaper sold
   as a pet bed; "180 posts a month"). When a claim's basis stops, the
   claim comes down the same day.
   **The odometer measures the SITE FEED, not any social page.** It counts
   daily cards published to automation/feed. Never phrase it as "my page
   has posted N days straight" — in a Facebook group that reads as the
   Facebook page, and the ECS page was silent 07-29 to 08-19. Say "my own
   store's feed has published a new post every day for N days" and link
   findhotstuff.com/automation, where the reader can verify it.
2. **Secrets never appear in chat.** API keys/tokens go straight into
   GitHub secret boxes or the Cloudflare dashboard, pasted by Matthew only.
   Claude never reads, types, or transcribes a secret value. The ntfy
   topic name is itself a secret (visible on his screen, never written
   here). Workflows must never echo payloads containing lead PII (public
   repo logs). One exception: URL-verification signature files are public
   tokens and may be copied in full.
3. **Matthew clicks every final button** — Send/Post/Publish/Pay/Submit,
   on every platform. Claude (and Chrome-extension Claude, "C.C") preps
   everything and stops before submission. OS file dialogs are his.
4. **No fake documents, ever** — he once asked for a fake certificate; the
   answer was and remains no, and he accepted it. Same rule as #1.

## Money mode (as of 2026-08-19)

Frugal until client #1: paid items are SHELVED (Anthropic API key for the
name polisher, X API credits, hoodie sample). Don't pitch paid anything in
briefs until Matthew says the first invoice cleared. Everything currently
running costs $0/month. Free unlocks still open: Meta/Facebook auto-post
hookup, TikTok app review, Zoho mail. GBP: fields done 08-19, verification video
filmed 08-26 but NOT yet submitted through Google's flow.

## Where the real ledgers live (read before answering "what's next")

- `marketing/east-coast-social/call-kit.md` — prospect ledger + call log.
- `.claude/council/DECISIONS.md` — council verdicts. Standing: design
  freeze on both sites until Aug 31 (photo block exempt); one-time
  downsell offers exist but are GATED (2026-08-14 entry has the gates).
- `marketing/east-coast-social/weekly-rhythm.md` — the daily/weekly ritual.
- `marketing/east-coast-social/leblanc-yes-runbook.md` — live-deal playbook.
- `marketing/daily-post-session-prompt.md` — C.C's daily posting session.
- `marketing/passive/month-1-plan.md` — the passive-income track and
  its status. Content pieces live in `content/notes/*.md` (rendered by
  `make_notes.py`); category pages + sitemap come from
  `make_category_pages.py`, which the 3-day refresh workflow runs.
- Morning brief fires as a scheduled trigger; it verifies TikTok drafts
  (both packs SEND_TO_USER_INBOX), reads GoatCounter public counters, and
  lists callbacks due.

## Hard-won operational lore (believe it)

- **The container reverts.** The workspace rolls back to stale commits
  mid-session, repeatedly. Before ANY edit: `git fetch origin -q && git
  checkout -q -B <session-branch> origin/master && git checkout -q
  origin/master -- .` — origin is truth; local never is. `git reset
  --hard` is blocked by the permission layer; use targeted checkout.
- **Anything not pushed dies.** Commit+push in the same breath as
  creating. Rendered assets (sample packs, merch art) were lost twice by
  living only on a container's disk — force-add gitignored deliverables.
- **Push pattern:** commit → `git pull --rebase origin master` → push the
  session branch (`--force-with-lease`) → push `<branch>:master` (the site
  deploys from master). On "stale info": fetch and retry.
- pip loses pillow/segno between containers; scratchpad gets wiped.
- GitHub MCP `actions_list` responses overflow — parse the saved JSON file
  with python. Anonymous api.github.com calls fail through the proxy.
- ntfy.sh from Cloudflare Workers gets rate-limited (shared egress IPs) —
  that's why worker alerts hop through a GitHub repository_dispatch relay.
- raw.githubusercontent caches ~5 min — cache-bust paste links; GitHub
  Pages deploys in ~20–80s (poll with `?nc=$RANDOM`).

## How decisions get made

Big calls go to the council (`/council`: Operator, Marketer, Treasurer,
Skeptic, Customer — five parallel agents, Right-Hand synthesis, logged and
pushed). Matthew decides; log his decision when he makes it. Small
reversible things: just do them and push. Calls outrank commits — never
let engineering eat his selling hours.
