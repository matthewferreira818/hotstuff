# 5. Collecting the $79 (Matthew's call only)

No Claude takes, moves, asks for or handles money. This page lists options. **Matthew picks.**

## What's already promised in public
The live /automation page says: **"Paid by e-Transfer before the first post."** So option A is already the public promise.
Any other option means changing the page first (a public change: Matthew's GO).

## Gate before any money is asked for
The private notes say Matthew's **Service Canada (EI) question must be settled before any payment request**.
Until he says it's settled: free samples only, no invoice, no payment ask, no paid start date.
HST: Claude is not an accountant. A "small supplier" under $30,000 a year usually doesn't register, but confirm with CBDC or an accountant. Every dollar gets recorded for EI and taxes.

## Options

| | A. Interac e-Transfer (recommended) | B. Card payment link | C. Cash or cheque in person |
|---|---|---|---|
| Matches the live page | ✅ yes, word for word | ❌ page change needed | ❌ page change needed |
| Fees | none for a normal personal account (check his bank) | card fees on every payment | none |
| Setup | turn on auto-deposit for the receiving email (his bank, his login) | a payment link in the existing Stripe account (his login) | nothing |
| Client effort | from their banking app, 2 minutes | tap a link, enter card | meet up |
| Monthly after the pilot | they send it each month (reminder email) | could become a subscription later | each month in person |
| Record | the bank's e-Transfer notice + invoice number | Stripe receipt | handwritten receipt |
| Risk | low; wrong address = money waits | card disputes, a public page change | slow, nothing automatic |

**Closer's pick: A.** It's what the page already promises, it costs nothing, it needs no new accounts, and the invoice script already writes an e-Transfer line. B makes sense later, once there are several monthly clients.

## What Matthew decides (for option A)
1. **Settled with Service Canada?** Yes / not yet. Nothing moves until yes.
2. **Which email receives e-Transfers?** The business inbox or a personal one. (Answer privately; never in this repo or the room.) The invoice script still defaults to a different address than everything else, so pass the right one each time until it's changed.
3. **Auto-deposit on** for that email (his bank, his hands).
4. **Invoice or no invoice?** An invoice (one command, `make_invoice.py`) looks more professional and gives a number for records. Without one, the payment note in the week-1 email is enough.

## How it would run (option A, once decided)
1. Client approves week 1.
2. Matthew sends the invoice / payment note: "$79 CAD for your pilot month, by e-Transfer to [his chosen address], invoice number in the message."
3. Matthew sees the deposit and says "paid" in his private notes. Claude never checks his bank.
4. First post goes up.
5. Month 2: about day 28, a short email: "Want to keep going? Same $79 by e-Transfer." Only if they say yes.
