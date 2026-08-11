# East Coast Social — hello@eastcoastsocial.ca

Getting a real mailbox on the domain, so replies go out **from** East Coast
Social instead of a personal address. Claude can't do this one — it needs your
Porkbun login and a signup — so this is the exact sequence with the exact
records.

---

## What's already true (checked, not assumed)

| Thing | Current state |
|---|---|
| Registrar / DNS | **Porkbun** (`*.ns.porkbun.com`) |
| MX (mail routing) | `fwd1.porkbun.com` / `fwd2.porkbun.com` — **forwarding only** |
| SPF | `v=spf1 include:_spf.porkbun.com ~all` |
| DMARC | none |
| Web | Porkbun URL forwarding → `findhotstuff.com/automation/` |

So `hello@eastcoastsocial.ca` almost certainly **already receives** mail today —
Porkbun forwarding is free and configured. What it can't do is **send**:
forwarded addresses are receive-only by design. That's exactly the gap the
weekly rhythm keeps flagging.

**Test before you spend anything:** email `hello@eastcoastsocial.ca` from your
phone. If it lands in your personal inbox, forwarding works and this is purely
about sending.

---

## The options, with real prices

| Option | Cost | Sending | Phone access |
|---|---|---|---|
| **Zoho Mail Free** | $0 | ✅ | Zoho's own app only — **no IMAP**, so it will *not* appear in your normal phone mail app |
| **Zoho Mail Lite** | $1/user/month, billed yearly (**$12/yr**) | ✅ | ✅ IMAP — lands in your existing mail app |
| **Porkbun Email** | $3/month (**$36/yr**) | ✅ | ✅ IMAP, and no DNS work — Porkbun wires it up |
| Stay on forwarding | $0 | ❌ | receive only |

**Recommended: start with Zoho Mail Free.** It costs nothing and solves the
actual problem. The one real catch is no IMAP, so it won't show up beside your
other mail — you check it in Zoho's app. If that friction means you miss a
lead reply, upgrading to **Lite at $12/year** is the fix, and it's still a
third of Porkbun's price.

If you'd rather not think about DNS at all, **Porkbun Email at $3/month** is
the no-config path: same company as the domain, records handled for you. Worth
the $24/year difference only if the DNS steps below look like a bad evening.

---

## Setting up Zoho Mail Free

### 1. Sign up
<https://www.zoho.com/mail/> → **Pricing** → **Forever Free Plan** → *Sign up
with a domain I already own* → `eastcoastsocial.ca`.

Use a Google/Gmail login you'll keep. Zoho asks for no card on the free plan.

### 2. Verify the domain
Zoho gives you **one TXT record**. In Porkbun: *Domain Management →
eastcoastsocial.ca → DNS → Add record*.

- Type `TXT`, Host blank (or `@`), Answer = the value Zoho shows.

Wait a few minutes, hit verify in Zoho.

### 3. Create the mailbox
Make `hello` the account name → `hello@eastcoastsocial.ca`. Add `matthew@` too
if you want it; the free plan allows up to 5 users.

### 4. Point mail at Zoho — the step that switches things over
Replace the two Porkbun forwarding MX records with Zoho's:

| Type | Host | Priority | Value |
|---|---|---|---|
| MX | @ | 10 | `mx.zoho.com` |
| MX | @ | 20 | `mx2.zoho.com` |
| MX | @ | 50 | `mx3.zoho.com` |

Use whatever Zoho's setup page shows you — the values are region-specific and
Zoho's own page is authoritative over this table.

**Delete the `fwd1`/`fwd2` MX records** once Zoho's are in. Mail can only route
one place; leaving both is what makes messages vanish intermittently.

### 5. SPF — read this bit twice

A domain may have **exactly one** SPF record. You already have one. Do **not**
add a second — two SPF records is a hard fail, and the symptom is your mail
silently landing in spam.

**Edit** the existing TXT record from:
```
v=spf1 include:_spf.porkbun.com ~all
```
to:
```
v=spf1 include:zoho.com ~all
```

(If you keep any Porkbun forwarding alongside, combine instead of duplicating:
`v=spf1 include:zoho.com include:_spf.porkbun.com ~all`.)

### 6. DKIM
Zoho generates a DKIM key in *Mail Admin → Domains → DKIM*. Add it as a TXT
record with the selector host Zoho names (usually `zoho._domainkey`). Skipping
this is the difference between landing in an inbox and landing in spam.

### 7. DMARC — optional, 2 minutes, worth it
There's no DMARC record today. Add a permissive one so receivers know the
domain is being managed:

| Type | Host | Value |
|---|---|---|
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:hello@eastcoastsocial.ca` |

`p=none` only monitors — it can't cause mail to be rejected. Tighten later if
you ever care.

### 8. Send a real test
From Zoho, email your personal address. Check three things:
- it **arrives**,
- it shows **from hello@eastcoastsocial.ca**,
- it is **not in spam**.

Then reply to it and confirm that lands back in Zoho.

---

## After it works

- Update the X/Facebook/GBP contact fields to `hello@eastcoastsocial.ca`
  (`facebook-page-info.md` is already updated in the repo).
- Set a signature: name, East Coast Social, phone, `eastcoastsocial.ca`.
- Put the Zoho app on your phone, and **turn notifications on** — a lead reply
  you see in an hour is worth several you see tomorrow.

---

## Order of operations for a setup session

Both jobs are independent, but this order wastes the least time:

1. **Email first** (~20 min of work, then waiting on DNS). DNS changes need
   time to propagate, so start it and let it cook.
2. **Google Business Profile** while DNS propagates — see
   [`google-business-profile.md`](google-business-profile.md). Every field is
   pre-written; the one thing to prepare first is the verification step, which
   may be a live video call.
3. **Come back and test email** once records have spread.

---

## Related loose end

Porkbun's **URL forwarding** (the web redirect, separate from email) currently
strips query strings, so `eastcoastsocial.ca/?ref=card` arrives untagged and
the business-card QR traffic is invisible in the traffic check. While you're in
the Porkbun DNS panel anyway, look for a *preserve query string* / *forward
path and query* option on the URL-forwarding record and enable it.
