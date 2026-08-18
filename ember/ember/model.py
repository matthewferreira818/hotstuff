"""Ember — a from-scratch diffusion model.

This is the U-Net denoiser: the network that looks at a noisy image plus a
timestep and predicts the noise that was added. Everything here is plain
PyTorch — no pretrained weights, no diffusers — so the trained checkpoint is
entirely ours.
"""

import math

import torch
import torch.nn as nn
import torch.nn.functional as F


def timestep_embedding(t, dim):
    """Sinusoidal embedding of diffusion timesteps (same trick as Transformers)."""
    half = dim // 2
    freqs = torch.exp(-math.log(10000) * torch.arange(half, device=t.device) / half)
    args = t[:, None].float() * freqs[None]
    return torch.cat([torch.cos(args), torch.sin(args)], dim=-1)


class ResBlock(nn.Module):
    """Residual block with the timestep embedding injected between convs."""

    def __init__(self, in_ch, out_ch, emb_dim, dropout=0.0):
        super().__init__()
        self.norm1 = nn.GroupNorm(8, in_ch)
        self.conv1 = nn.Conv2d(in_ch, out_ch, 3, padding=1)
        self.emb_proj = nn.Linear(emb_dim, out_ch)
        self.norm2 = nn.GroupNorm(8, out_ch)
        self.dropout = nn.Dropout(dropout)
        self.conv2 = nn.Conv2d(out_ch, out_ch, 3, padding=1)
        self.skip = nn.Conv2d(in_ch, out_ch, 1) if in_ch != out_ch else nn.Identity()

    def forward(self, x, emb):
        h = self.conv1(F.silu(self.norm1(x)))
        h = h + self.emb_proj(F.silu(emb))[:, :, None, None]
        h = self.conv2(self.dropout(F.silu(self.norm2(h))))
        return h + self.skip(x)


class Attention(nn.Module):
    """Self-attention over spatial positions, used at low resolutions."""

    def __init__(self, ch):
        super().__init__()
        self.norm = nn.GroupNorm(8, ch)
        self.qkv = nn.Conv2d(ch, ch * 3, 1)
        self.out = nn.Conv2d(ch, ch, 1)

    def forward(self, x):
        b, c, h, w = x.shape
        q, k, v = self.qkv(self.norm(x)).reshape(b, 3, c, h * w).unbind(1)
        attn = torch.softmax(q.transpose(1, 2) @ k / math.sqrt(c), dim=-1)
        out = (v @ attn.transpose(1, 2)).reshape(b, c, h, w)
        return x + self.out(out)


class EmberUNet(nn.Module):
    """The denoiser. Size is set by `base_ch` and `ch_mults` — the XS config is
    ~2M params (CPU-trainable); scale both up for GPU runs."""

    def __init__(self, img_ch=3, base_ch=48, ch_mults=(1, 2, 4), emb_dim=192,
                 attn_levels=(2,), dropout=0.0):
        super().__init__()
        self.time_mlp = nn.Sequential(
            nn.Linear(emb_dim, emb_dim * 4), nn.SiLU(), nn.Linear(emb_dim * 4, emb_dim)
        )
        self.emb_dim = emb_dim
        self.stem = nn.Conv2d(img_ch, base_ch, 3, padding=1)

        chans = [base_ch * m for m in ch_mults]
        self.downs = nn.ModuleList()
        skip_chans = [base_ch]
        in_ch = base_ch
        for level, out_ch in enumerate(chans):
            block = nn.ModuleDict({
                "res1": ResBlock(in_ch, out_ch, emb_dim, dropout),
                "res2": ResBlock(out_ch, out_ch, emb_dim, dropout),
                "attn": Attention(out_ch) if level in attn_levels else nn.Identity(),
                "down": nn.Conv2d(out_ch, out_ch, 3, stride=2, padding=1)
                        if level < len(chans) - 1 else nn.Identity(),
            })
            self.downs.append(block)
            skip_chans += [out_ch, out_ch]
            in_ch = out_ch

        self.mid1 = ResBlock(in_ch, in_ch, emb_dim, dropout)
        self.mid_attn = Attention(in_ch)
        self.mid2 = ResBlock(in_ch, in_ch, emb_dim, dropout)

        self.ups = nn.ModuleList()
        for level, out_ch in reversed(list(enumerate(chans))):
            block = nn.ModuleDict({
                "res1": ResBlock(in_ch + skip_chans.pop(), out_ch, emb_dim, dropout),
                "res2": ResBlock(out_ch + skip_chans.pop(), out_ch, emb_dim, dropout),
                "attn": Attention(out_ch) if level in attn_levels else nn.Identity(),
                "up": nn.Upsample(scale_factor=2, mode="nearest") if level > 0 else nn.Identity(),
            })
            self.ups.append(block)
            in_ch = out_ch
        self.skip_stem = skip_chans.pop()

        self.head_norm = nn.GroupNorm(8, base_ch)
        self.head = nn.Conv2d(base_ch, img_ch, 3, padding=1)
        nn.init.zeros_(self.head.weight)
        nn.init.zeros_(self.head.bias)

    def forward(self, x, t):
        emb = self.time_mlp(timestep_embedding(t, self.emb_dim))
        h = self.stem(x)
        skips = [h]
        for blk in self.downs:
            h = blk["res1"](h, emb)
            skips.append(h)
            h = blk["res2"](h, emb)
            h = blk["attn"](h)
            skips.append(h)
            h = blk["down"](h)

        h = self.mid2(self.mid_attn(self.mid1(h, emb)), emb)

        for blk in self.ups:
            h = blk["res1"](torch.cat([h, skips.pop()], dim=1), emb)
            h = blk["res2"](torch.cat([h, skips.pop()], dim=1), emb)
            h = blk["attn"](h)
            h = blk["up"](h)

        return self.head(F.silu(self.head_norm(h)))
