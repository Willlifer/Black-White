"""D425-D432: frames from tools/kit2_shots.gd -> design/art/kit2_<mode>_strip.png.

    python tools/kit2_strip.py <shots dir> [out dir] [N]

Takes N (default 6) frames spread over each <shots>/kit2_frames/<mode>/,
crops the middle of each (the HUD panels sit at the edges) and lays them out
left to right, two rows when N > 4, with the frame index in a corner.
"""
import os
import sys

from PIL import Image, ImageDraw


def strip(frames_dir: str, out_png: str, n: int = 6) -> None:
    files = sorted(f for f in os.listdir(frames_dir) if f.endswith(".png"))
    if not files:
        return
    picks = [files[round(i * (len(files) - 1) / max(n - 1, 1))] for i in range(n)]
    tiles = []
    for f in picks:
        im = Image.open(os.path.join(frames_dir, f)).convert("RGB")
        w, h = im.size
        im = im.crop((int(w * 0.12), int(h * 0.12), int(w * 0.88), int(h * 0.72)))
        im = im.resize((im.width * 640 // im.width, im.height * 640 // im.width))
        ImageDraw.Draw(im).text((8, 6), f[:-4], fill=(0, 0, 0))
        tiles.append(im)
    cols = n if n <= 4 else (n + 1) // 2
    rows = (n + cols - 1) // cols
    tw, th = tiles[0].size
    sheet = Image.new("RGB", (cols * tw + (cols - 1) * 6, rows * th + (rows - 1) * 6), (20, 20, 22))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * (tw + 6), (i // cols) * (th + 6)))
    sheet.save(out_png)
    print("strip", out_png)


if __name__ == "__main__":
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "..", "design", "art")
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    root = os.path.join(src, "kit2_frames")
    for mode in sorted(os.listdir(root)):
        strip(os.path.join(root, mode), os.path.join(out, "kit2_%s_strip.png" % mode), n)
