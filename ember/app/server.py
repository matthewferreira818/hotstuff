"""Ember Studio — the application around the model.

    python app/server.py            # http://localhost:8787
    EMBER_CKPT=runs/xs/ckpt.pt python app/server.py

Serves the UI and a small JSON API. The checkpoint is re-loaded automatically
whenever training writes a newer one, so generations improve live mid-run.
"""

import base64
import io
import os
import sys
import threading

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import numpy as np
import torch
from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from PIL import Image

from ember import EmberUNet, Diffusion, img2img
from ember.utils import tensor_to_pil

_ROOT = os.path.join(os.path.dirname(__file__), "..")
_RUN_CKPT = os.path.join(_ROOT, "runs", "xs", "ckpt.pt")
_SLIM_CKPT = os.path.join(_ROOT, "weights", "ember-xs.pt")
# prefer a live training run; fall back to the committed slim weights
CKPT = os.environ.get("EMBER_CKPT") or (_RUN_CKPT if os.path.exists(_RUN_CKPT) else _SLIM_CKPT)
STATIC = os.path.join(os.path.dirname(__file__), "static")

app = FastAPI(title="Ember Studio")
_state = {"model": None, "diffusion": None, "cfg": None, "mtime": 0, "step": 0}
_lock = threading.RLock()


def _ensure_model():
    with _lock:
        try:
            mtime = os.path.getmtime(CKPT)
            if _state["model"] is None or mtime > _state["mtime"]:
                ck = torch.load(CKPT, map_location="cpu")
                cfg = ck["config"]
                model = EmberUNet(base_ch=cfg["base_ch"])
                model.load_state_dict(ck["ema"])
                model.eval()
                _state.update(model=model, cfg=cfg, mtime=mtime, step=ck["step"],
                              diffusion=Diffusion(cfg["timesteps"]))
        except Exception:
            # a reload hiccup must never kill serving — keep the loaded model
            if _state["model"] is None:
                raise
        return _state


class GenerateReq(BaseModel):
    n: int = 4
    steps: int = 50
    seed: int | None = None
    reference: str | None = None   # base64 data-URL image for img2img
    strength: float = 0.65


def _b64_png(pil_img, upscale=8):
    s = pil_img.width * upscale
    buf = io.BytesIO()
    pil_img.resize((s, s), Image.NEAREST).save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


@app.get("/api/info")
def info():
    st = _ensure_model()
    return {"name": "Ember-XS", "params": st["cfg"]["params"], "size": st["cfg"]["size"],
            "trained_steps": st["step"]}


@app.post("/api/generate")
def generate(req: GenerateReq):
    with _lock:  # one generation at a time on CPU
        st = _ensure_model()
        cfg, model, diffusion = st["cfg"], st["model"], st["diffusion"]
        n = max(1, min(req.n, 8))
        steps = max(10, min(req.steps, 100))

        if req.reference:
            raw = base64.b64decode(req.reference.split(",")[-1])
            ref = Image.open(io.BytesIO(raw)).convert("RGB").resize(
                (cfg["size"], cfg["size"]), Image.LANCZOS)
            t = torch.from_numpy(np.array(ref)).float()
            t = (t / 127.5 - 1).permute(2, 0, 1)[None].repeat(n, 1, 1, 1)
            out = img2img(diffusion, model, t, strength=min(0.95, max(0.05, req.strength)),
                          steps=steps, seed=req.seed)
        else:
            out = diffusion.sample(model, (n, 3, cfg["size"], cfg["size"]),
                                   steps=steps, seed=req.seed)
        return {"images": [_b64_png(tensor_to_pil(x)) for x in out],
                "trained_steps": st["step"]}


@app.get("/")
def index():
    return FileResponse(os.path.join(STATIC, "index.html"))


app.mount("/static", StaticFiles(directory=STATIC), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8787)
