"""The diffusion process: forward noising, training loss, and DDIM sampling.

Training: take a clean image, add a random amount of noise, ask the U-Net to
predict that noise. Generation: start from pure noise and iteratively remove
the predicted noise — the model "dreams" an image out of static.
"""

import math

import torch
import torch.nn.functional as F


def cosine_alpha_bar(T, s=0.008):
    """Cosine noise schedule (Nichol & Dhariwal) — better than linear for small images."""
    steps = torch.arange(T + 1, dtype=torch.float64)
    f = torch.cos(((steps / T) + s) / (1 + s) * math.pi / 2) ** 2
    ab = (f / f[0]).clamp(1e-8, 1.0)
    return ab[1:].float()  # alpha_bar for t = 1..T


class Diffusion:
    def __init__(self, timesteps=1000, device="cpu"):
        self.T = timesteps
        self.device = device
        self.alpha_bar = cosine_alpha_bar(timesteps).to(device)

    def add_noise(self, x0, t, noise):
        ab = self.alpha_bar[t][:, None, None, None]
        return ab.sqrt() * x0 + (1 - ab).sqrt() * noise

    def loss(self, model, x0):
        """Simple epsilon-prediction MSE — the standard DDPM objective."""
        b = x0.shape[0]
        t = torch.randint(0, self.T, (b,), device=x0.device)
        noise = torch.randn_like(x0)
        x_t = self.add_noise(x0, t, noise)
        pred = model(x_t, t)
        return F.mse_loss(pred, noise)

    @torch.no_grad()
    def sample(self, model, shape, steps=50, eta=0.0, device=None, seed=None):
        """DDIM sampler: walks from pure noise to an image in `steps` jumps."""
        device = device or self.device
        g = torch.Generator(device=device)
        if seed is not None:
            g.manual_seed(seed)
        else:
            g.seed()  # fresh Generators start from a FIXED seed; draw real entropy
        x = torch.randn(shape, generator=g, device=device)

        ts = torch.linspace(self.T - 1, 0, steps, device=device).long()
        for i, t in enumerate(ts):
            t_batch = torch.full((shape[0],), t, device=device, dtype=torch.long)
            eps = model(x, t_batch)
            ab_t = self.alpha_bar[t]
            x0 = (x - (1 - ab_t).sqrt() * eps) / ab_t.sqrt()
            x0 = x0.clamp(-1, 1)

            if i == len(ts) - 1:
                x = x0
                break
            ab_prev = self.alpha_bar[ts[i + 1]]
            sigma = eta * ((1 - ab_prev) / (1 - ab_t) * (1 - ab_t / ab_prev)).sqrt()
            dir_x = (1 - ab_prev - sigma**2).clamp(min=0).sqrt() * eps
            x = ab_prev.sqrt() * x0 + dir_x
            if eta > 0:
                x = x + sigma * torch.randn(shape, generator=g, device=device)
        return x


class EMA:
    """Exponential moving average of model weights — sampling from the EMA copy
    gives visibly cleaner images than the raw training weights."""

    def __init__(self, model, decay=0.999):
        self.decay = decay
        self.updates = 0  # decay warms up so the random init washes out quickly
        self.shadow = {k: v.detach().clone() for k, v in model.state_dict().items()}

    @torch.no_grad()
    def update(self, model):
        self.updates += 1
        decay = min(self.decay, (1 + self.updates) / (10 + self.updates))
        for k, v in model.state_dict().items():
            if v.dtype.is_floating_point:
                self.shadow[k].mul_(decay).add_(v.detach(), alpha=1 - decay)
            else:
                self.shadow[k].copy_(v)

    def copy_to(self, model):
        model.load_state_dict(self.shadow)


@torch.no_grad()
def img2img(diffusion, model, init, strength=0.6, steps=50, seed=None):
    """Reimagine a reference image: noise it partway into the diffusion process,
    then denoise. strength 0 = return the reference, 1 = ignore it entirely."""
    device = init.device
    g = torch.Generator(device=device)
    if seed is not None:
        g.manual_seed(seed)
    else:
        g.seed()

    t_start = min(diffusion.T - 1, max(1, int(diffusion.T * strength)))
    noise = torch.randn(init.shape, generator=g, device=device)
    t0 = torch.full((init.shape[0],), t_start, device=device, dtype=torch.long)
    x = diffusion.add_noise(init, t0, noise)

    ts = torch.linspace(t_start, 0, max(2, int(steps * strength)), device=device).long()
    for i, t in enumerate(ts):
        t_batch = torch.full((init.shape[0],), t, device=device, dtype=torch.long)
        eps = model(x, t_batch)
        ab_t = diffusion.alpha_bar[t]
        x0 = ((x - (1 - ab_t).sqrt() * eps) / ab_t.sqrt()).clamp(-1, 1)
        if i == len(ts) - 1:
            return x0
        ab_prev = diffusion.alpha_bar[ts[i + 1]]
        x = ab_prev.sqrt() * x0 + (1 - ab_prev).sqrt() * eps
    return x
