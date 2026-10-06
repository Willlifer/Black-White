"""PNG frames (from tools/anim_preview.gd, the real Godot renderer) -> GIFs.

    python game/tools/anim_gif.py <frames dir> <out dir> [fps] [scale]

Every sub-folder `anim_<name>` of <frames dir> becomes <out dir>/anim_<name>.gif,
looping, at `fps` (default 30, the rate the frames were captured at).
Palette: one adaptive palette per GIF (the art is black/white/grey plus the
element colour, so 128 colours is plenty and keeps the files small).
"""
import os
import sys

from PIL import Image


def build(src: str, dst: str, fps: float, scale: float = 1.0) -> None:
    files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    if not files:
        print("no frames in", src)
        return
    frames = [Image.open(os.path.join(src, f)).convert("RGB") for f in files]
    if scale != 1.0:
        size = (int(frames[0].width * scale), int(frames[0].height * scale))
        frames = [f.resize(size, Image.LANCZOS) for f in frames]
    # one shared palette from a sample of frames, so colours don't flicker
    sample = Image.new("RGB", (frames[0].width, frames[0].height * 4))
    for i, k in enumerate(range(0, len(frames), max(1, len(frames) // 4))):
        if i < 4:
            sample.paste(frames[k], (0, frames[0].height * i))
    pal = sample.quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    out = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    ms = int(round(1000.0 / fps))
    out[0].save(dst, save_all=True, append_images=out[1:], duration=ms, loop=0, optimize=True, disposal=1)
    print("saved %s (%d frames, %.2f s)" % (dst, len(out), len(out) / fps))


def main() -> None:
    src = sys.argv[1]
    dst = sys.argv[2]
    fps = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0
    scale = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    os.makedirs(dst, exist_ok=True)
    for name in sorted(os.listdir(src)):
        d = os.path.join(src, name)
        if os.path.isdir(d) and name.startswith("anim_"):
            build(d, os.path.join(dst, name + ".gif"), fps, scale)


if __name__ == "__main__":
    main()
