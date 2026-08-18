"""Export a slim, shareable checkpoint: EMA weights in fp16 + config, no
optimizer state. ~4x smaller than the training checkpoint — this is the file
we commit so the app works from a fresh clone.

    python export_weights.py --ckpt runs/xs/ckpt.pt --out weights/ember-xs.pt
"""

import argparse
import os

import torch


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ckpt", default="runs/xs/ckpt.pt")
    p.add_argument("--out", default="weights/ember-xs.pt")
    args = p.parse_args()

    ck = torch.load(args.ckpt, map_location="cpu")
    slim = {
        "ema": {k: (v.half() if v.dtype.is_floating_point else v)
                for k, v in ck["ema"].items()},
        "config": ck["config"],
        "step": ck["step"],
    }
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    torch.save(slim, args.out)
    print(f"{args.out}: {os.path.getsize(args.out)/1e6:.1f} MB (from {os.path.getsize(args.ckpt)/1e6:.1f} MB)")


if __name__ == "__main__":
    main()
