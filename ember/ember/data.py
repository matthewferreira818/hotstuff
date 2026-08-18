"""Procedural "ember art" training data.

Instead of scraping images (licensing headaches, downloads, storage), we
synthesize an infinite dataset: dark canvases with glowing radial embers,
sparks and smoke-like gradients. The distribution is rich enough to be
interesting and simple enough for a small model to learn on CPU. Because the
generator is code we own, the trained model is 100% ours — data included.
"""

import math
import random

import numpy as np
import torch
from torch.utils.data import IterableDataset

# Warm ember palette with occasional cool "spirit flame" outliers.
PALETTES = [
    [(255, 96, 32), (255, 180, 64), (255, 235, 160)],   # classic fire
    [(255, 48, 48), (255, 128, 32), (255, 220, 120)],   # red-hot
    [(255, 140, 26), (255, 200, 90), (255, 250, 200)],  # amber
    [(64, 156, 255), (140, 210, 255), (230, 245, 255)], # blue flame
    [(190, 96, 255), (235, 160, 255), (250, 230, 255)], # violet flame
]
COOL_CHANCE = 0.18  # how often the cool palettes appear


def _radial_glow(canvas, cx, cy, radius, color, intensity, yy, xx):
    d2 = (xx - cx) ** 2 + (yy - cy) ** 2
    glow = np.exp(-d2 / (2 * radius**2)) * intensity
    for c in range(3):
        canvas[:, :, c] += glow * (color[c] / 255.0)


def render_ember(size, rng):
    """One training image: dark ground + 2-5 glows + sparks, as float [0,1]."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    canvas = np.zeros((size, size, 3), dtype=np.float32)

    # dark background with a slight vertical gradient (smoke)
    base = rng.uniform(0.01, 0.06)
    canvas += base * (1 - yy / size)[:, :, None] * np.array([0.8, 0.7, 1.0])

    if rng.random() < COOL_CHANCE:
        palette = PALETTES[rng.randrange(3, 5)]
    else:
        palette = PALETTES[rng.randrange(0, 3)]

    # main glows: biased low on the canvas, like coals
    for _ in range(rng.randint(2, 5)):
        cx = rng.uniform(0.15, 0.85) * size
        cy = rng.uniform(0.35, 0.9) * size
        radius = rng.uniform(0.08, 0.28) * size
        color = palette[rng.randrange(len(palette))]
        _radial_glow(canvas, cx, cy, radius, color, rng.uniform(0.5, 1.1), yy, xx)

    # sparks: small bright points drifting upward
    for _ in range(rng.randint(3, 12)):
        cx = rng.uniform(0, 1) * size
        cy = rng.uniform(0, 0.7) * size
        radius = rng.uniform(0.006, 0.02) * size + 0.5
        color = palette[-1]
        _radial_glow(canvas, cx, cy, radius, color, rng.uniform(0.4, 1.0), yy, xx)

    # soft tone-map to keep highlights from clipping harshly
    canvas = 1.0 - np.exp(-canvas * 1.8)
    return np.clip(canvas, 0, 1)


class EmberArtDataset(IterableDataset):
    """Infinite stream of procedurally generated ember art, in [-1, 1]."""

    def __init__(self, size=32, seed=0):
        self.size = size
        self.seed = seed

    def __iter__(self):
        info = torch.utils.data.get_worker_info()
        wid = info.id if info else 0
        rng = random.Random(self.seed + 1000 * wid)
        while True:
            img = render_ember(self.size, rng)
            yield torch.from_numpy(img).permute(2, 0, 1) * 2 - 1
