"""Train Ember from scratch.

CPU proof-of-life (this repo's default):
    python train.py --out runs/xs

GPU scale-up (rented box, same code):
    python train.py --out runs/small --size 64 --base-ch 96 --batch 128 --steps 60000
"""

import argparse
import json
import os
import time

import torch
from torch.utils.data import DataLoader

from ember import EmberUNet, Diffusion, EMA, EmberArtDataset
from ember.utils import save_grid


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="runs/xs")
    p.add_argument("--size", type=int, default=32)
    p.add_argument("--base-ch", type=int, default=48)
    p.add_argument("--batch", type=int, default=32)
    p.add_argument("--steps", type=int, default=3000)
    p.add_argument("--lr", type=float, default=2e-4)
    p.add_argument("--warmup", type=int, default=100)
    p.add_argument("--timesteps", type=int, default=1000)
    p.add_argument("--sample-every", type=int, default=250)
    p.add_argument("--ckpt-every", type=int, default=250)
    p.add_argument("--resume", default=None)
    p.add_argument("--workers", type=int, default=2)
    args = p.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    if device == "cpu":
        torch.set_num_threads(os.cpu_count() or 4)
    os.makedirs(args.out, exist_ok=True)

    model = EmberUNet(base_ch=args.base_ch).to(device)
    n_params = sum(p.numel() for p in model.parameters())
    diffusion = Diffusion(args.timesteps, device=device)
    ema = EMA(model)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.0)

    start_step = 0
    if args.resume:
        ck = torch.load(args.resume, map_location=device)
        model.load_state_dict(ck["model"])
        ema.shadow = ck["ema"]
        ema.updates = ck["step"]
        opt.load_state_dict(ck["opt"])
        start_step = ck["step"]
        print(f"resumed from {args.resume} at step {start_step}")

    config = {k: v for k, v in vars(args).items() if k != "resume"}
    config["params"] = n_params
    with open(os.path.join(args.out, "config.json"), "w") as f:
        json.dump(config, f, indent=2)
    print(f"Ember | {n_params/1e6:.2f}M params | {device} | out={args.out}")

    ds = EmberArtDataset(size=args.size)
    loader = iter(DataLoader(ds, batch_size=args.batch, num_workers=args.workers,
                             persistent_workers=args.workers > 0))

    log_path = os.path.join(args.out, "log.txt")
    t0 = time.time()
    running = 0.0
    for step in range(start_step + 1, args.steps + 1):
        x0 = next(loader).to(device)
        loss = diffusion.loss(model, x0)
        opt.zero_grad(set_to_none=True)
        loss.backward()
        # warmup then constant LR — simple and stable for a run this short
        lr = args.lr * min(1.0, step / max(1, args.warmup))
        for group in opt.param_groups:
            group["lr"] = lr
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        ema.update(model)

        running += loss.item()
        if step % 50 == 0:
            msg = (f"step {step}/{args.steps}  loss {running/50:.4f}  "
                   f"{(time.time()-t0)/(step-start_step)*1000:.0f} ms/step")
            running = 0.0
            print(msg, flush=True)
            with open(log_path, "a") as f:
                f.write(msg + "\n")

        if step % args.ckpt_every == 0 or step == args.steps:
            # write-then-rename so the studio server never reads a half-written file
            ckpt_path = os.path.join(args.out, "ckpt.pt")
            torch.save({"model": model.state_dict(), "ema": ema.shadow,
                        "opt": opt.state_dict(), "step": step,
                        "config": config}, ckpt_path + ".tmp")
            os.replace(ckpt_path + ".tmp", ckpt_path)

        if step % args.sample_every == 0 or step == args.steps:
            sampler = EmberUNet(base_ch=args.base_ch).to(device)
            ema.copy_to(sampler)
            sampler.eval()
            grid = diffusion.sample(sampler, (8, 3, args.size, args.size),
                                    steps=40, seed=7)
            path = save_grid(grid, os.path.join(args.out, f"samples-{step:06d}.png"))
            print(f"  samples -> {path}", flush=True)


if __name__ == "__main__":
    main()
