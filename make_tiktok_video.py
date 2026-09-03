"""Turns the daily TikTok slide packs into actual video.

Why: the engine already renders seven finished 1080x1920 slides every
morning, and then posts them to TikTok as a PHOTO carousel. TikTok is a
video platform and barely distributes photo posts — ref-tiktok has recorded
zero click-throughs in the life of this business. The frames were never the
problem; the missing thing was motion.

So this adds motion rather than generating anything: a slow Ken Burns push
across each slide, crossfaded together, at TikTok's native size. No model,
no API, no subscription — ffmpeg is already on the GitHub runner that builds
the packs, so this costs nothing and adds a few seconds to the morning job.

Zoom direction alternates slide to slide so a four-slide pack doesn't feel
like one continuous push, and each still is upscaled before the zoom because
zoompan on a native-resolution image visibly judders.

    python make_tiktok_video.py            # both packs
    python make_tiktok_video.py product    # one pack
"""

import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
DAILY = HERE / "marketing" / "tiktok" / "daily"

SECONDS_PER_SLIDE = 2.8
CROSSFADE = 0.45
FPS = 24                 # 24 is plenty for a slow pan and is 20% fewer
                         # frames than 30 — this file is committed daily,
                         # so its size compounds in the repo forever.
W, H = 1080, 1920
ZOOM_MAX = 1.12          # gentle. more than this reads as a zoom effect
SUPERSAMPLE = 1.5        # render the pan above target, downscale — kills the
                         # judder. 2x was four times the pixels and pushed a
                         # 10-second render past two minutes on a small box.


def ffmpeg_bin() -> str:
    """System ffmpeg if present (GitHub runners have it), else the one that
    ships inside imageio-ffmpeg so this is runnable on a bare container."""
    found = shutil.which("ffmpeg")
    if found:
        return found
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        raise SystemExit(
            "ffmpeg not found. Install it, or `pip install imageio-ffmpeg`.")


def slides_for(pack: str) -> list[Path]:
    """Slides in poster order. Sorted by name, which is why the QR slide is
    called product-4-qr — it has to stay last."""
    return sorted((DAILY / pack).glob("*.jpg"))


def build_filter(count: int) -> str:
    frames = int(round(SECONDS_PER_SLIDE * FPS))
    big_w, big_h = int(W * SUPERSAMPLE) // 2 * 2, int(H * SUPERSAMPLE) // 2 * 2
    step = (ZOOM_MAX - 1.0) / frames

    parts = []
    for i in range(count):
        if i % 2 == 0:                       # push in
            z = f"min(zoom+{step:.6f},{ZOOM_MAX})"
        else:                                # pull out
            z = f"if(eq(on,1),{ZOOM_MAX},max(zoom-{step:.6f},1.0))"
        parts.append(
            f"[{i}:v]scale={big_w}:{big_h},setsar=1,"
            f"zoompan=z='{z}':d={frames}"
            f":x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
            f":s={W}x{H}:fps={FPS},format=yuv420p[v{i}]"
        )

    if count == 1:
        parts.append("[v0]copy[out]")
        return ";".join(parts)

    # chain the crossfades: each transition starts CROSSFADE early, so every
    # join shortens the timeline and later offsets have to account for all
    # the overlaps before them
    prev, offset = "[v0]", 0.0
    for i in range(1, count):
        offset += SECONDS_PER_SLIDE - CROSSFADE
        label = "[out]" if i == count - 1 else f"[x{i}]"
        parts.append(
            # slideleft, not fade. These slides are mostly large text, and a
            # dissolve ghosts two product names and two prices over each other
            # for half a second. A swipe never overlaps text with text, and it
            # reads like the carousel swipe this pack used to be.
            f"{prev}[v{i}]xfade=transition=slideleft:duration={CROSSFADE}"
            f":offset={offset:.2f}{label}"
        )
        prev = label
    return ";".join(parts)


def render(pack: str) -> Path | None:
    slides = slides_for(pack)
    if not slides:
        print(f"  {pack}: no slides found — skipping")
        return None

    out = DAILY / pack / "pack.mp4"
    length = len(slides) * SECONDS_PER_SLIDE - (len(slides) - 1) * CROSSFADE

    cmd = [ffmpeg_bin(), "-y", "-loglevel", "error"]
    for s in slides:
        cmd += ["-loop", "1", "-t", str(SECONDS_PER_SLIDE), "-i", str(s)]
    # A silent track: some players and uploaders treat a video with no audio
    # stream as malformed. Its length is computed to match the video exactly.
    # Do NOT hand this a short fixed -t and rely on -shortest: that made the
    # audio the shortest stream and truncated a 9.7s pack to 1.0s.
    cmd += ["-f", "lavfi", "-t", f"{length:.2f}", "-i", "anullsrc=r=44100:cl=stereo"]
    cmd += [
        "-filter_complex", build_filter(len(slides)),
        "-map", "[out]", "-map", f"{len(slides)}:a",
        "-c:v", "libx264", "-preset", "slow", "-crf", "26",   # slow preset buys real size back
        "-pix_fmt", "yuv420p", "-r", str(FPS),
        "-c:a", "aac", "-b:a", "64k", "-shortest",
        "-movflags", "+faststart",
        str(out),
    ]
    subprocess.run(cmd, check=True)
    print(f"  {pack}: {len(slides)} slides -> {out.name} "
          f"({length:.1f}s, {out.stat().st_size // 1024} KB)")
    return out


def main():
    which = sys.argv[1:] or ["product", "agent"]
    print(f"Building TikTok video packs ({', '.join(which)})...")
    for pack in which:
        render(pack)


if __name__ == "__main__":
    main()
