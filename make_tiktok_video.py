"""Turns the daily TikTok slide packs into actual video.

Why: the engine already renders seven finished 1080x1920 slides every
morning, and then posts them to TikTok as a PHOTO carousel. TikTok is a
video platform and barely distributes photo posts — ref-tiktok has recorded
zero click-throughs in the life of this business. The frames were never the
problem; the missing thing was motion.

So this adds motion rather than generating anything: each slide is held
still and the pack glides from one to the next, at TikTok's native size. No
model, no API, no subscription — ffmpeg is already on the GitHub runner that
builds the packs, so this costs nothing and adds a few seconds to the job.

There is deliberately NO zoom. An earlier version pushed slowly into each
slide (Ken Burns); on slides that are mostly large text it read as drift
rather than motion, and it fought the swipe. Holding each slide still makes
the swipe the only movement, which is what a carousel is supposed to feel
like. Removing it also dropped the render from a supersampled zoompan to a
plain scale, so the job is faster and the file smaller.

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
SWIPE = 0.90             # the whole animation now, so it carries all of the
                         # smoothness on its own.
FPS = 60                 # NOT a nicety — it is the whole fix for the judder.
                         # A slide moves the full 1080px frame width, so the
                         # per-frame jump is 1080/(SWIPE*FPS):
                         #   24fps / 0.70s = 64px a frame  <- visibly steps
                         #   60fps / 0.90s = 20px a frame  <- reads as motion
                         # The static holds cost almost nothing at any frame
                         # rate, so the extra frames are spent where they are
                         # actually seen.                 # 24 is plenty for a slow pan and is 20% fewer
                         # frames than 30 — this file is committed daily,
                         # so its size compounds in the repo forever.
W, H = 1080, 1920


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
    """Each slide is a still; the only motion is the swipe between them."""
    parts = [
        f"[{i}:v]scale={W}:{H},setsar=1,format=yuv420p[v{i}]"
        for i in range(count)
    ]

    if count == 1:
        parts.append("[v0]copy[out]")
        return ";".join(parts)

    # Chain the swipes. Each transition starts SWIPE early, so every join
    # shortens the timeline and later offsets must account for all the
    # overlaps before them — not just their own.
    prev, offset = "[v0]", 0.0
    for i in range(1, count):
        offset += SECONDS_PER_SLIDE - SWIPE
        label = "[out]" if i == count - 1 else f"[x{i}]"
        parts.append(
            # slideleft carries both frames together, like a thumb swipe.
            # A dissolve would ghost two product names and two prices over
            # each other, which is why this is not a fade.
            f"{prev}[v{i}]xfade=transition=slideleft:duration={SWIPE}"
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
    length = len(slides) * SECONDS_PER_SLIDE - (len(slides) - 1) * SWIPE

    cmd = [ffmpeg_bin(), "-y", "-loglevel", "error"]
    for s in slides:
        # -framerate is REQUIRED here and is easy to miss. Without it ffmpeg
        # reads a looped still at its default 25fps, so xfade only ever has 25
        # real frames a second to slide with and the 60fps output is padded
        # with duplicates. Measured per-frame shift was [0, 47, 0, 0, 47, ...]
        # — the frame sitting still and then jumping half an inch, which is
        # exactly what "jittery" looks like. With it, every output frame is a
        # genuine new position.
        cmd += ["-loop", "1", "-framerate", str(FPS),
                "-t", str(SECONDS_PER_SLIDE), "-i", str(s)]
    # A silent track: some players and uploaders treat a video with no audio
    # stream as malformed. Its length is computed to match the video exactly.
    # Do NOT hand this a short fixed -t and rely on -shortest: that made the
    # audio the shortest stream and truncated a 9.7s pack to 1.0s.
    cmd += ["-f", "lavfi", "-t", f"{length:.2f}", "-i", "anullsrc=r=44100:cl=stereo"]
    cmd += [
        "-filter_complex", build_filter(len(slides)),
        "-map", "[out]", "-map", f"{len(slides)}:a",
        "-c:v", "libx264", # CRF 26 was fine for still slides but blocks up on a fast
        # horizontal pan, and blocking on a moving frame reads as more
        # judder. 21 spends the bits where the motion is.
        "-preset", "slow", "-crf", "21",
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
