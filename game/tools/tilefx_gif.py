"""Tile FX review GIFs from real-renderer frames (tools/tilefx_review.gd gif).

    python game/tools/tilefx_gif.py <frames dir> <out dir> [fps]

Every sub-folder <element> of <frames dir> becomes <out dir>/tilefx_<element>.gif,
looping, at `fps` (default 20, the --fixed-fps the frames were captured at).
One shared adaptive palette per GIF, sampled across the whole clip so the
element colours that only appear at tier 3 are in it.
"""
import os
import sys

from PIL import Image


def build(src: str, dst: str, fps: float) -> None:
    files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    if not files:
        print("no frames in", src)
        return
    frames = [Image.open(os.path.join(src, f)).convert("RGB") for f in files]
    w, h = frames[0].size
    picks = [frames[k] for k in range(0, len(frames), max(1, len(frames) // 6))][:6]
    sample = Image.new("RGB", (w, h * len(picks)))
    for i, f in enumerate(picks):
        sample.paste(f, (0, h * i))
    pal = sample.quantize(colors=192, method=Image.Quantize.MEDIANCUT)
    out = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    out[0].save(dst, save_all=True, append_images=out[1:], duration=int(1000 / fps), loop=0, optimize=True)
    print("wrote", dst, len(out), "frames")


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    fps = float(sys.argv[3]) if len(sys.argv) > 3 else 20.0
    os.makedirs(dst, exist_ok=True)
    for d in sorted(os.listdir(src)):
        p = os.path.join(src, d)
        if os.path.isdir(p):
            build(p, os.path.join(dst, "tilefx_%s.gif" % d), fps)


if __name__ == "__main__":
    main()
