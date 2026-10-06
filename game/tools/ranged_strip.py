"""D164-D166: frame strips and GIFs from tools/ranged_shots.gd captures.

    python tools/ranged_strip.py <frames dir> <out base> [cells] [crop x0,y0,x1,y1] [gif_every]

<out base>.png: `cells` frames picked evenly (each scaled to 480 wide), in rows of 4,
each labelled with its frame number; <out base>.gif: every `gif_every`-th frame.
"""
import os
import sys
from PIL import Image, ImageDraw


def main():
    src, base = sys.argv[1], sys.argv[2]
    cells = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    crop = tuple(int(v) for v in sys.argv[4].split(",")) if len(sys.argv) > 4 and sys.argv[4] != "-" else None
    every = int(sys.argv[5]) if len(sys.argv) > 5 else 2
    files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    if not files:
        sys.exit("no frames in " + src)
    frames = [Image.open(os.path.join(src, f)).convert("RGB") for f in files]
    if crop:
        frames = [f.crop(crop) for f in frames]
    w = 480
    h = int(frames[0].height * w / frames[0].width)
    pick = [round(i * (len(frames) - 1) / max(cells - 1, 1)) for i in range(cells)]
    per = 4
    rows = (len(pick) + per - 1) // per
    sheet = Image.new("RGB", (per * w, rows * (h + 18)), (240, 240, 240))
    d = ImageDraw.Draw(sheet)
    for n, i in enumerate(pick):
        x, y = (n % per) * w, (n // per) * (h + 18)
        sheet.paste(frames[i].resize((w, h), Image.LANCZOS), (x, y + 18))
        d.text((x + 4, y + 3), "frame %d / %d" % (i, len(frames) - 1), fill=(0, 0, 0))
    sheet.save(base + ".png")
    g = [f.resize((w * 4 // 3, h * 4 // 3), Image.LANCZOS) for f in frames[::every]]
    g[0].save(base + ".gif", save_all=True, append_images=g[1:], duration=int(1000 / 30 * every), loop=0, optimize=True)
    print("saved", base + ".png", base + ".gif", len(frames), "frames")


if __name__ == "__main__":
    main()
