title: Getting TikTok's Content Posting API to accept a photo post — JPEG only, no emoji in the title, and the parts the docs skip
description: Four undocumented rules that made TikTok's photo endpoint reject my posts, the exact error strings they return, and why a 200 response still doesn't mean your draft survived.
date: 2026-09-26
draft: true
---

My store posts a three-slide carousel to TikTok every morning without me.
Getting there took a week, and almost all of it was spent on four rules
that the API reference does not mention and the error messages barely hint
at.

This is what each rejection actually said and what fixed it. The error
strings are here verbatim, because they are what you will paste into a
search box at midnight.

## 1. PNG is rejected. The error is `file_format_check_failed`

The photo endpoint takes JPEG. Send it a PNG and the upload is accepted,
then dies during processing with:

```
file_format_check_failed
```

Which reads like a corrupt file, not a format policy. My slides are drawn
with Pillow and saved as PNG, because PNG is the right format for flat
colour and crisp type. So the fix was not to stop making PNGs — it was to
write a JPEG twin of every slide at build time and point the API at those:

```python
def _write_jpeg_twins():
    """JPEG copy of every slide: TikTok's photo API rejects PNG
    (file_format_check_failed), so the draft pusher pulls the .jpg twins."""
```

The PNGs stay for everything else. TikTok gets the twins.

## 2. Emoji in the title field returns `invalid_params`

The photo payload has a `title` and a `description`. Every caption I write
has an emoji in it somewhere, and putting that caption in `title` fails
with a flat:

```
invalid_params
```

No indication of *which* param. The description field accepts emoji fine —
it is only the title that wants plain text. So the title became a short
fixed string and the real caption rides in the description:

```python
def _title(label):
    """TikTok rejects emoji/decorated text in the photo title field
    (invalid_params) — the full caption rides in the description instead."""
```

If you are getting `invalid_params` on a payload that looks correct,
strip every non-ASCII character out of `title` first. That was two days for
me.

## 3. Photo posts are `PULL_FROM_URL` only, and the URL has to be on a verified domain

There is no file upload for photos the way there is for video. You give
TikTok a list of URLs and it fetches them. Which means:

- the images must already be publicly hosted before you call the API
- the domain must be verified in your TikTok developer app first
- a URL that 404s, redirects oddly, or sits behind Cloudflare's bot
  protection will fail during the async fetch, not at request time

Mine are plain static files on GitHub Pages under the verified domain.
Boring, and it works.

## 4. A 200 from the init call means nothing yet

This is the one that cost the most confusion. `POST` to the init endpoint
returns success and hands you a `publish_id`. That is not the post. It is
a *task*. TikTok then downloads your images asynchronously, and that is
where all four of the failures above actually surface.

So the init call succeeds and the draft never appears, with no error
anywhere unless you go looking for it. You have to poll:

```python
def watch_status(access, publish_id, label):
    """The init call only creates a task; the draft can still die during
    TikTok's async download/processing. Poll until a terminal state and
    print the truth (this is where PNG-vs-JPEG or size errors surface)."""
```

Poll until you see a terminal state. `SEND_TO_USER_INBOX` means the draft
landed in the app and is waiting for you. `FAILED` comes with a
`fail_reason` that is the only place the real problem is ever named.

Without that polling loop I had a pipeline that reported success every
morning and produced nothing. That is a worse failure than crashing.

## The payload that works

Probed on 2026-08-12, this is the shape that goes through:

```python
{
    "media_type": "PHOTO",
    "post_mode": "MEDIA_UPLOAD",
    "post_info": {"title": "<plain text, no emoji>",
                  "description": "<caption, emoji fine>",
                  "auto_add_music": True},
    "source_info": {"source": "PULL_FROM_URL",
                    "photo_cover_index": 0,
                    "photo_images": [".../slide-1.jpg", ".../slide-2.jpg"]},
}
```

`post_mode: MEDIA_UPLOAD` puts it in your drafts rather than publishing it.
I want that — I tap Post myself every time, so nothing goes out under my
name that I have not looked at.

## One thing I would tell myself at the start

Every one of these four failures was silent. The API said 200, the workflow
went green, and no post existed. If you build against this endpoint, build
the status poll *first*, before you write a single line of the payload.
Otherwise you will spend your week debugging the wrong layer, as I did.
