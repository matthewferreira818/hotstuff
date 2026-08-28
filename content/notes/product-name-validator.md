title: I sold a roll of wallpaper as a pet bed, so I built a validator that can veto my own product names
description: Supplier product titles are keyword soup. Cleaning them up with AI is easy and dangerous. Here is the rule I wrote so a display name can never say something the supplier's title didn't.
date: 2026-08-27
draft: false
---

A dropshipping supplier's product title looks like this:

```
Pet Dog Cat Bed Warm Soft Plush Comfortable Sleeping Mat Puppy
Kennel Washable Nest Cushion Pad Four Seasons Universal 2024 New
```

That is not a name. It's every search term the seller could think of,
stapled together and run through a translator. You cannot put it on a
storefront.

The obvious fix is to have a model rewrite it into something readable. I
did that. And a while later my store was selling a roll of wallpaper,
listed as a pet bed.

## How that happens

Nobody hallucinated a lie on purpose. The supplier title mentioned a mat, a
pattern and a room; the rewrite reached for the most product-shaped noun in
the pile and picked wrong. Once it's written down as a clean, confident,
four-word product name, nothing about it looks generated. It looks like a
decision someone made.

That's the real hazard. A messy title is obviously messy. A tidy name is
trusted, and if it's wrong, the trust is what does the damage — the
customer doesn't find out until a roll of wallpaper arrives.

## The rule

So the display name is not allowed to be *creative*. It's allowed to be an
**edit**.

> Every word in the display name must already appear in the supplier's real
> title. Reorder, trim, re-case. Never add.

That's it. It rules out the entire class of error above, because a word
that isn't in the source can't appear in the output, so there's nothing for
a wrong guess to be made *of*.

## Making it a gate, not a guideline

A rule that lives in a prompt is a suggestion. This one runs as code, after
generation, and any name that fails is thrown away and replaced by the
mechanical cleanup:

```python
def honest_name(candidate: str, source: str) -> bool:
    """True iff every word of candidate already appears in source."""
    vocab = _honest_vocab(source)
    for chunk in (candidate or "").split():
        for w in chunk.split("-"):
            key = _honest_key(w)
            if key and key not in vocab and key not in GLUE_WORDS:
                return False
    return True
```

Two details did most of the work in practice:

**Normalisation.** Comparing raw words rejects far too much. `Women's`
should satisfy `female`; `Stones` should satisfy `stone`. So each word is
folded first — lowercased, stripped of punctuation and possessives, simple
plurals removed, and a tiny equivalence table maps `female`/`woman` to
`women` and `male`/`man` to `men`. Without that fold the validator rejects
good names and you learn to ignore it, which is worse than not having it.

**Glue words.** `and`, `with`, `for`, `the`, `of` are exempt. They carry no
product claim, and forbidding them produces names that read like a telegram.

## What it changed

I ran all 120 display names in the catalogue through it. The validator is
the reason I can state plainly, on a storefront that rebuilds itself every
three days with no human in the loop, that no product name says anything
the supplier didn't. Not because I check them — because a name that says
something new cannot survive the build.

There are eight exceptions in the current catalogue, and I'd rather write
them down than let you discover them: eight items got one noun added that
I confirmed from the supplier's own product photo. Each one was a judgment
call I made by looking at the picture, and they're the only names in the
shop that a machine didn't have to approve.

## The part I'd tell anyone building the same thing

The temptation with AI in a pipeline is to make the prompt better. Better
instructions, more examples, sterner warnings. It genuinely helps, and it
is not a guarantee, because the failure you care about is the confident
one — and a confident wrong answer is exactly what a well-written prompt
produces more of.

The thing that actually holds is a check that runs afterwards and doesn't
care how good the output sounded. Give it a rule narrow enough to be
mechanical — "no new words" is mechanical; "be accurate" is not — and let
it throw work away. Mine throws away perfectly nice product names on a
regular basis. That's the feature.
