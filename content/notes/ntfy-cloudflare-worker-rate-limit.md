title: Why ntfy.sh 429s your Cloudflare Worker, and the GitHub relay that fixes it for free
description: Cloudflare Workers share egress addresses with the whole internet, so ntfy's per-source rate limit sees them as one very noisy caller. Here is the relay I used instead, and the privacy trap it has.
date: 2026-09-26
draft: true
---

My store's checkout runs on a Cloudflare Worker. When an order or a lead
comes in, I want my phone to buzz. [ntfy.sh](https://ntfy.sh) is the
obvious free way to do that — one HTTP POST, no account needed.

It does not work from a Worker. Here is why, and what I did instead.

## The failure

Calling ntfy from the Worker returns **429 Too Many Requests**, more or
less permanently, even on the first push of the day.

The reason is not your code. ntfy rate-limits by source IP address on its
free tier. **Cloudflare Workers do not have your IP address** — they share
a pool of egress addresses with every other Worker on the platform. From
ntfy's side, your one message a day arrives from an address that is also
sending traffic for a large slice of the internet.

So you are not being limited for what you sent. You are being limited for
what strangers sharing your exit node sent. No amount of backoff fixes
that, because the budget was spent before your request existed.

## What does not fix it

- **Retrying.** The limit is not about you, so waiting does not help.
- **Spacing the messages out.** Same reason.
- **A different free push service.** Most of them rate-limit the same way,
  and you will rediscover this from scratch.

Paying for an ntfy account with a reserved topic would fix it properly.
I am running this business at zero a month, so that was out.

## The fix: let something with its own IP do the sending

GitHub Actions runners have ordinary egress addresses, and their pushes to
ntfy go through every time. So the Worker stopped calling ntfy and started
handing the message to GitHub instead:

1. The Worker fires a `repository_dispatch` at my repo with the message in
   the payload.
2. A workflow listens for that event type and does the actual ntfy POST.

The Worker needs a fine-grained personal access token with Contents
read/write on that one repo, nothing more. The workflow is about fifteen
lines.

Direct ntfy stays in the code as a fallback for when the token is missing,
which also makes a silent phone diagnose itself — the function returns a
status string, so `no-relay-token` and `relay-http-404` tell you whether
the secret never reached the code or the token lacks repo access.

The round trip adds a few seconds. For an order alert that is nothing.

## The trap, and it is a serious one

**My repo is public, which means every workflow run log is public.**

The payload going through that relay can contain a customer's name, email
and address. Workflow logs render inputs. One `echo` for debugging, or one
step that prints the event payload, and a lead's contact details are on the
public internet with a permanent URL.

So the workflow carries this at the top, and I mean it as a rule rather
than a comment:

```
# PRIVACY: this is a public repo, so its run logs are public. The payload
# can contain a lead's name and contact info — it must NEVER be echoed.
# Values only flow through env vars into a silent curl; do not add any step
# that prints the payload.
```

Every value moves from `client_payload` into an env var and from there
into a curl. Nothing is interpolated into a shell line where it could be
logged. If you copy this pattern into a public repo, copy that constraint
with it — it is the part that actually matters.

## Would I do it this way again

Yes, with one caveat. It is a genuinely odd shape — a payment worker
asking a CI system to send a push notification — and if you are already
paying for anything that can send a message, use that instead.

But it costs nothing, it has not missed a push, and the failure mode is
visible rather than silent. For a business that has to run at zero a
month, that is the trade.
