"""Small helpers shared by training, sampling and the app."""

import numpy as np
import torch
from PIL import Image


def tensor_to_pil(x):
    """[-1,1] CHW tensor -> PIL image."""
    arr = ((x.clamp(-1, 1) + 1) / 2 * 255).byte().permute(1, 2, 0).cpu().numpy()
    return Image.fromarray(arr)


def save_grid(batch, path, cols=4, upscale=4):
    """Save a batch of samples as one PNG grid (nearest-upscaled so 32px is visible)."""
    imgs = [tensor_to_pil(x) for x in batch]
    n = len(imgs)
    rows = (n + cols - 1) // cols
    s = imgs[0].width * upscale
    grid = Image.new("RGB", (cols * s, rows * s), (10, 8, 12))
    for i, im in enumerate(imgs):
        im = im.resize((s, s), Image.NEAREST)
        grid.paste(im, ((i % cols) * s, (i // cols) * s))
    grid.save(path)
    return path
