# TikTok direct posting: app review prep (council 2026-11-05, ALTER 3). Prepared, NOT submitted.

_Claude, Thu Nov 5 2026 night. Sources: developers.tiktok.com/doc/content-sharing-guidelines and
/doc/content-posting-api-get-started (both "last updated Aug 4, 2026"). The audit form page itself needs a login
(it returned 401 to us), so its exact questions are UNKNOWN until Matthew opens it._

## Today
- Our engine pushes ONE draft a day (product pack) into Matthew's TikTok inbox (MEDIA_UPLOAD mode). He adds a sound and taps Post.
- He hasn't been posting them, so the council asked: can TikTok post by itself?

## What TikTok's rules say (quotes)
- Unaudited apps: "all content uploaded via this endpoint will be restricted to private viewing mode" (SELF_ONLY), up to 5 users a day.
- Direct Post needs an audit, and the app must show, for EVERY post: the creator's nickname; a privacy dropdown with
  "no default value"; Comment/Duet/Stitch switches where "none should be checked by default"; a commercial-content toggle
  ("Your brand" -> labelled "Promotional content"); a preview; the line "By posting, you agree to TikTok's Music Usage
  Confirmation"; and "API Clients must only start sending content materials to TikTok after the user has expressly
  consent to the upload."
- Apps "should be intended for a wide audience, not limited to internal groups/private use."

## Honest read
- A schedule that posts with nobody pressing anything does not fit those rules (each post needs a person's choices and
  consent). That's our reading; the pages don't say "scheduled" in so many words. So "TikTok posts by itself" is not
  realistic, and we should not tell anyone it is.
- An app used only by us is also a weak fit for "a wide audience".
- What WOULD fit: a "Post to TikTok" page (in The Helm or a private web page) where Matthew sees the preview, picks the
  privacy, the switches and "Your brand", agrees, and taps Post. That's about as much work for him as the inbox draft.

## Recommendation
- Don't submit the Direct Post review now. Keep one draft a day; the cost to Matthew is ~1 minute (sound + Post).
- If he wants it anyway: build the page above first, record the demo of that exact flow, then he submits. What to have
  ready: app name "HotsTuff Engine", use case ("a small store owner posts his own store's daily product video to his own
  account, choosing privacy and settings each time"), the demo video of the full flow, privacy policy and terms URLs
  (findhotstuff.com/privacy/, /terms/), the verified domain. Usage estimate: 1 creator, 1 post a day.
- Matthew submits it himself (his account, his name).
