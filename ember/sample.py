"""Generate images from a trained Ember checkpoint.

    python sample.py --ckpt runs/xs/ckpt.pt --n 8 --out out.png
"""

import argparse

import torch

from ember import EmberUNet, Diffusion
from ember.utils import save_grid


def load_model(ckpt_path, device="cpu"):
    ck = torch.load(ckpt_path, map_location=device)
    cfg = ck["config"]
    model = EmberUNet(base_ch=cfg["base_ch"]).to(device)
    model.load_state_dict(ck["ema"])  # EMA weights sample cleanest
    model.eval()
    return model, cfg


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ckpt", default="runs/xs/ckpt.pt")
    p.add_argument("--n", type=int, default=8)
    p.add_argument("--steps", type=int, default=50)
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("--out", default="samples.png")
    args = p.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model, cfg = load_model(args.ckpt, device)
    diffusion = Diffusion(cfg["timesteps"], device=device)
    grid = diffusion.sample(model, (args.n, 3, cfg["size"], cfg["size"]),
                            steps=args.steps, seed=args.seed)
    print("saved", save_grid(grid, args.out))


if __name__ == "__main__":
    main()
