# 🔥 Ember — our own AI, from scratch

Ember is a generative image model **trained entirely from scratch** — its own
architecture (a diffusion U-Net in pure PyTorch), its own training run, its
own procedurally-generated dataset, and its own application (Ember Studio).
No pretrained weights, no wrapper around someone else's API. The checkpoint
file is ours in every sense, data included.

**Honesty first:** Ember-XS is 7M parameters trained on a laptop-class CPU.
Sora-class models are ~5 orders of magnitude more compute. What Ember gives
us is the real thing at seed stage: the same model family (diffusion) the
frontier labs use, fully owned, and built to scale with whatever compute we
rent next. Every config below runs the *same code* — only the numbers grow.

## What's here

```
ember/
  ember/            the model itself
    model.py        U-Net denoiser (ResBlocks + self-attention, timestep-conditioned)
    diffusion.py    cosine-schedule DDPM training loss, DDIM sampler, EMA, img2img
    data.py         procedural "ember art" dataset — infinite, license-clean, ours
    utils.py        tensor<->PNG helpers
  train.py          training loop (checkpoints, EMA, periodic sample grids)
  sample.py         generate a grid from a checkpoint
  export_weights.py slim fp16 export for sharing / the app
  app/
    server.py       Ember Studio — FastAPI server (auto-reloads newer checkpoints)
    static/         the studio UI
  configs/          preset training runs (CPU proof-of-life, GPU scale-up)
  runs/xs/          the v0.1 training run: config, loss log, sample grids
  weights/          committed slim checkpoint so the app works from a fresh clone
```

## Quickstart

```bash
pip install torch --index-url https://download.pytorch.org/whl/cpu   # or the CUDA build
pip install pillow numpy fastapi uvicorn

cd ember
python sample.py --ckpt weights/ember-xs.pt --n 8 --out mysamples.png   # generate now
python app/server.py                                                    # Ember Studio → http://localhost:8787
sh configs/xs-cpu.sh                                                    # retrain from nothing (~35 min CPU)
```

Ember Studio: pick a count, hit **Generate**, click images to download. Add a
**reference image** and the model reimagines it (img2img) — the
"imagination" slider sets how far it drifts from your reference. The server
watches the checkpoint file, so during training the studio's output visibly
improves as the model learns.

## How it works (one paragraph)

Training repeatedly takes a clean image, mixes in a known amount of random
noise (a cosine schedule over 1,000 steps), and asks the U-Net to predict
that noise from the noisy image + the timestep. Generation runs the process
backwards: start from pure static and iteratively subtract predicted noise
(DDIM, ~50 jumps) until an image remains. Everything the model draws comes
from patterns compressed into its weights during training — that's the whole
trick, and it's the same trick behind Stable Diffusion, FLUX, and Sora.

## The data story

v0.1 trains on `data.py`: an infinite stream of procedurally rendered ember
art (dark canvases, glowing coals, sparks, five palettes). Synthetic data
means zero scraping, zero licensing risk, zero storage — and a distribution
simple enough for a small model to learn convincingly on CPU.

**Swapping in real images later:** replace `EmberArtDataset` with a folder
loader over images we have rights to (own photos, CC0/public-domain sets).
Train on Google-scraped images is technically easy and legally a minefield —
we don't. References at *generation* time (img2img) are different: users can
reimagine any image they hold locally; nothing is stored or trained on.

## Scaling it up (the roadmap)

| Version | Params | Res | Compute | Cost (verify current GPU prices) |
|---|---|---|---|---|
| **v0.1 XS** (this) | 7M | 32px | 4 CPU cores, ~35 min | $0 |
| v0.2 Small | ~28M | 64px | 1× RTX 4090, ~3–6 h | ~$2–5 rented |
| v0.3 Base | ~80M | 128px | 1× 4090/A100, ~1–2 days | ~$20–60 |
| v0.4 Text-conditioned | +cross-attention | 128px+ | needs a captioned dataset | ~$50–200 |
| v0.5 Video | +temporal layers | short clips | multi-GPU territory | hundreds+ |

Each jump reuses this exact codebase — `configs/small-gpu.sh` is the next
step. Rent a box (RunPod / Lambda / Vast, ~$0.30–0.80/hr for a 4090-class
card; check live prices), `git clone`, run the config, `export_weights.py`,
commit the new weights. Text conditioning (v0.4) is where "type a prompt"
begins: add a text encoder + cross-attention and a captioned, licensed
dataset. Video (v0.5) extends the U-Net with temporal attention over frame
stacks — same diffusion math, one more dimension.

## Provenance

Built 2026-08-18 inside the hotstuff repo (branch `claude/ai-project-u15rzy`)
as its own venture — nothing here touches the store or ECS. If it grows,
`ember/` lifts out into its own repository unchanged. "Ember" is a working
name; rename freely.
