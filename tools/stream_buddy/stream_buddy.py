#!/usr/bin/env python3
"""Stream buddy: a free AI that watches Matthew's Twitch stream and comments
in text, one line at a time.

Runs on his Mac. Frames come from the live Twitch stream (streamlink +
ffmpeg). A vision model running locally in Ollama looks at each frame, and
a one-line comment prints in this window. Free: nothing is paid for, nothing
is posted anywhere, and no picture leaves the Mac. Setup: SETUP.md, next to
this file.

    python3 stream_buddy.py                        # watch, a frame every 20 s
    python3 stream_buddy.py --every 30             # slower Mac? look less often
    python3 stream_buddy.py --model qwen2.5vl:3b   # try another free model

Stop it with Ctrl+C.
"""

import argparse
import base64
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

CHANNEL = "theycallmemattyb"
OLLAMA = "http://localhost:11434"
QUALITY = "480p,360p,worst"   # small frames: faster for the model, less data

PROMPT = """You are watching a live Minecraft Dungeons II stream by TheyCallMeMattyB.
He plays a soul-damage glass cannon: Sculker's Bane dagger with Soul Blast,
artifacts that spend souls (Soul Harvester, Battle Banner, Corrupted Beacon).
Look at this frame and reply with ONE short line, at most 20 words:
what's happening, plus a quick tip only if something matters right now
(low health, full soul meter so use artifacts, loot on the ground, a boss).
If he's in a menu or inventory, say which screen and anything worth noticing.
If nothing changed since your last lines, reply exactly: nothing new
Your last lines were: {recent}"""


def ffmpeg_exe():
    try:
        import imageio_ffmpeg  # pip install imageio-ffmpeg (brings its own ffmpeg)
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        exe = shutil.which("ffmpeg")
        if not exe:
            sys.exit("No ffmpeg. Run: python3 -m pip install --user imageio-ffmpeg")
        return exe


def stream_url(channel):
    """The live video address for the channel, or None if it can't get one.
    Prints streamlink's own reason, so "not live" never hides a real error.
    (No --twitch-disable-ads: newer streamlink dropped that option and skips
    ads by itself; passing it made every lookup fail.)"""
    cmd = [sys.executable, "-m", "streamlink", "--stream-url",
           f"twitch.tv/{channel}", QUALITY]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    url = out.stdout.strip()
    if url.startswith("http"):
        return url
    why = " ".join((out.stdout + " " + out.stderr).split())
    if "No module named streamlink" in why:
        sys.exit("No streamlink. Run: python3 -m pip install --user streamlink")
    say(f"Couldn't open the stream: {why[:200] or 'no reason given'}")
    return None


def start_grabber(source, every, frame_path):
    """ffmpeg keeps one frame file up to date: a new picture every N seconds."""
    live_speed = [] if source.startswith("http") else ["-re"]  # files play in real time
    return subprocess.Popen(
        [ffmpeg_exe(), "-loglevel", "error", *live_speed, "-i", source,
         "-vf", f"fps=1/{every},scale=768:-2", "-q:v", "4",
         "-update", "1", "-y", frame_path],
        stdin=subprocess.DEVNULL)


def ask(model, image_bytes, recent):
    body = {"model": model, "stream": False, "keep_alive": "15m",
            "prompt": PROMPT.format(recent=" | ".join(recent) or "none yet"),
            "images": [base64.b64encode(image_bytes).decode()],
            "options": {"num_predict": 60, "temperature": 0.4}}
    req = urllib.request.Request(f"{OLLAMA}/api/generate",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return " ".join(json.load(r).get("response", "").split())


def check_ollama(model):
    try:
        with urllib.request.urlopen(f"{OLLAMA}/api/tags", timeout=5) as r:
            names = {m["name"] for m in json.load(r).get("models", [])}
    except (urllib.error.URLError, OSError):
        sys.exit("Ollama isn't running. Open the Ollama app, then try again.")
    if model not in names and f"{model}:latest" not in names:
        sys.exit(f"Model '{model}' isn't downloaded. Run: ollama pull {model}")


def say(text):
    print(f"[{dt.datetime.now():%H:%M:%S}] {text}", flush=True)


def main():
    ap = argparse.ArgumentParser(description="Free AI that watches your stream.")
    ap.add_argument("--channel", default=CHANNEL)
    ap.add_argument("--every", type=int, default=20, help="seconds between looks")
    ap.add_argument("--model", default="gemma3:4b")
    ap.add_argument("--source", help="a video file or URL instead of Twitch (testing)")
    ap.add_argument("--max-looks", type=int, default=0, help=argparse.SUPPRESS)
    args = ap.parse_args()

    check_ollama(args.model)
    frame = os.path.join(tempfile.mkdtemp(), "frame.jpg")
    recent, looks, last_seen, grabber = [], 0, 0.0, None
    say(f"Stream buddy on: watching {args.source or 'twitch.tv/' + args.channel} "
        f"every {args.every}s with {args.model}. Ctrl+C to stop.")
    try:
        while True:
            if grabber is None or grabber.poll() is not None:
                src = args.source or stream_url(args.channel)
                if not src:
                    say("Checking again in 30 s.")
                    time.sleep(30)
                    continue
                grabber = start_grabber(src, args.every, frame)
            if os.path.exists(frame) and os.path.getmtime(frame) > last_seen:
                last_seen = os.path.getmtime(frame)
                time.sleep(0.3)  # let ffmpeg finish writing the picture
                with open(frame, "rb") as f:
                    img = f.read()
                try:
                    line = ask(args.model, img, recent[-3:])
                except (urllib.error.URLError, OSError, ValueError) as e:
                    say(f"(the model didn't answer: {type(e).__name__})")
                    line = ""
                if line and line.lower().strip(" .") != "nothing new" \
                        and line not in recent[-3:]:
                    say(line)
                    recent.append(line)
                looks += 1
                if args.max_looks and looks >= args.max_looks:
                    break
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        if grabber and grabber.poll() is None:
            grabber.terminate()
        say("Stream buddy off.")


if __name__ == "__main__":
    main()
