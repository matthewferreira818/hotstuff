# Close kit (Closer, Local Claude, started Fri Nov 27 2026)

One job: turn a business that showed interest into East Coast Social's **first paying client**.
Roxy finds and writes first touches. This kit starts the moment someone replies.

| File | Use it when |
|---|---|
| [1-reply-playbook.md](1-reply-playbook.md) | a business replied: the 7 most likely replies, each with an answer |
| [2-call-script.md](2-call-script.md) | they want to talk: 10-minute call + what to ask |
| [3-onboarding.md](3-onboarding.md) | they said yes: from "yes" to the first post |
| [4-sample-posts.md](4-sample-posts.md) | making the 7 free sample posts |
| [5-payment-options.md](5-payment-options.md) | collecting the $79 (Matthew decides) |

## The offer, word for word (live on findhotstuff.com/automation, checked Nov 27 2026)
> 7 free sample posts first, then $79 for a first pilot month, then $79 a month, no contract.

Everything a prospect hears must be on that page today. What the page promises:
- samples: free, no card, no account, nothing on file, **nothing goes on their page**, theirs to keep; "within a week"
- pilot: one post a day on their **Facebook** page, $79 CAD, **paid by e-Transfer before the first post**
- they approve every week's posts first; one round of changes a week (up to 3 posts); wrong facts fixed free
- text **STOP** any time and posting stops that day; they add Matthew to their page from their own account; their password never leaves them
- after the pilot: $79 a month, only if both want it

## Words we do NOT use (not on the page, or not true today)
- "free setup" / "free setup for the first two" (the 11-09 council kept the pilot cap out of messages: it reads as fake scarcity, and the page never says "setup")
- "free first week" / "free sample week of posting" (sounds like live posting; samples are private)
- "cancel any month" (old wording; say "no contract")
- "my Facebook page posts every day" (the Page token has been dead since Nov 19). Say: "my own store's feed has published a new post every day" + link /automation
- Instagram, ads, reach, sales, followers, reviews, past clients: none exist yet

## Hard rules (never lifted)
- Nothing is sent to a business without **Roxy OK + Claude OK + Matthew GO**. Closer drafts; Matthew (or C.C on his word) sends.
- No prospect names, contact details, money received or moods in this public repo, the room or the Hotline. Per-business notes live in Helm-Private `ecs/`.
- No payments, logins, passwords or accounts by any Claude. Money is Matthew's.
- A "no" or STOP = never contact again, logged in Helm-Private `ecs/do-not-contact.txt` the same day.
- Claude is not a lawyer or accountant. Tax/EI questions go to Service Canada, CBDC or an accountant.

## Older kits this replaces for replies (they still carry dead wording)
Helm-Private `ecs/reply-kit.md` and `ecs/call-kit.md` say "free setup", "no setup fee", "cancel any month", "first week".
Public `marketing/east-coast-social/reply-playbook.md` still says "setup is free ... cancel any month". Use this kit instead; fixing those is a follow-up.
Still good and reused: Helm-Private `ecs/delivery-kit/` (intake, checklist, approve sheet, invoice draft) and `ecs/first-client-kit/make_invoice.py`.

## Claims check (run Nov 27 2026 on every quoted reply in 1-reply-playbook.md)
`tools/claims_check.py --as-of 2026-11-27` flags STALE_FACTS, STALE_FEED, PRICE_OR_MONEY_PROOF, POST_FREQUENCY, UNCLEAR_FEED, CHANNEL_NOT_LIVE.
Cause: `tools/claims_facts.json` was last verified Nov 5 and doesn't know the pilot-month line yet (board item "Offer wording").
Checked by hand: the site feed has a card for every day through Nov 26 (git log of automation/feed); the offer words match the live page;
"Facebook" in the replies means the client's page (the offer), never ours. Before any reply is sent: a fresh fact pass on the day, as always.
