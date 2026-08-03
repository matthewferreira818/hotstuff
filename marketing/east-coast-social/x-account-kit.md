# East Coast Social — X (Twitter) account kit

> **Status:** account created — **@ECSocialNB** ✅ (steps 1–2 done).
> Remaining: first posts (step 3) and arming the auto-poster (step 4).

Everything needed to open the ECS X account and arm the daily auto-poster.
The posting engine is already built and live in this repo — it rides the same
daily run that posts to the Facebook Page (9:00 AM Atlantic) and skips
quietly until the keys below are added.

## 1. Create the account (~5 min, on phone or computer)

1. Go to x.com/i/flow/signup (or the X app → Sign up)
2. Email: **ceohotstuff@yahoo.com** · Name: **East Coast Social**
3. Verify with the code X emails you
4. Handle ideas (in order of preference — take the first one free):
   - `@eastcoastsocial`
   - `@ECSocialNB`
   - `@eastcoastsocnb`
   - `@ECS_Moncton`

## 2. Profile setup (~3 min)

- **Profile picture:** `fb-logo.png` (the sunrise — same as TikTok/Facebook)
- **Banner:** `x-banner.png` (1500×500, in this folder)
- **Bio (fits the 160 limit):**
  > Done-for-you social media for local businesses in Sackville, Memramcook
  > & greater Moncton. Your page posts every day — you don't lift a finger.
- **Location:** New Brunswick, Canada
- **Website:** findhotstuff.com/automation

## 3. First three posts (pin the first one)

1. "Every post on this account is written, designed, and published by an
   automation engine I run. No scheduling apps, no VA, no 11pm panic posts.
   I build the same engine for local NB businesses. ➜ findhotstuff.com/automation"
2. "Proof it works: my own store @ [HotsTuff handle] has posted 3× a day for
   weeks without a human touching it. Your bakery/salon/garage page could run
   the same way. Free setup · $79/mo · cancel anytime."
3. "Sackville · Memramcook · greater Moncton — if your business page has been
   quiet since spring, that's exactly who I built this for. DM me or scan the
   site. First month's content plan is free to look at."

## 4. Arm the auto-poster (~10 min, one time)

1. While signed in AS THE NEW ACCOUNT, go to **developer.x.com** → sign up
   for the **Free** tier (it allows posting — that's all the engine needs)
2. Create a Project + App (any names). In the app's **User authentication
   settings**: enable **Read and write**, type "Web App / Bot", website
   `https://findhotstuff.com/automation/`, callback `https://findhotstuff.com/`
3. In **Keys and tokens**, generate all four and copy each one:
   - API Key + API Secret
   - Access Token + Access Token Secret (must say "Read and Write")
4. Add them to GitHub: **github.com/matthewferreira818/hotstuff → Settings →
   Secrets and variables → Actions → New repository secret**, four times:
   - `ECS_X_API_KEY`
   - `ECS_X_API_SECRET`
   - `ECS_X_ACCESS_TOKEN`
   - `ECS_X_ACCESS_TOKEN_SECRET`
   (Paste keys ONLY into the GitHub secret box — never into a chat.)
5. Tell Claude "keys are in" — a test post gets fired and verified, and from
   then on the account posts daily at 9:00 AM Atlantic, forever.

## What's already wired (no action needed)

- `engine/post_to_x.py` — posts the daily card + caption to X
- `.github/workflows/ecs-daily-post.yml` — runs it right after the Facebook
  post each morning; skips silently while the secrets are missing
