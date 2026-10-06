"""Crit-flash review strip + GIF from tools/present_shots.gd MODE=crit frames.

    python tools/present_strip.py <frames dir> <out dir> [slow]

Finds the flash by brightness: one frame before it (the frozen impact),
the white, samples through the collapse and the line, and two after.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageStat


def lum(im):
    return ImageStat.Stat(im.convert("L").resize((160, 90))).mean[0]


def main():
    src, dst = sys.argv[1], sys.argv[2]
    files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    frames = [Image.open(os.path.join(src, f)).convert("RGB") for f in files]
    L = [lum(f) for f in frames]
    base = L[0]
    first = next(i for i, v in enumerate(L) if v > 240)
    end = next(i for i in range(first, len(L)) if L[i] < base + 2.0)   # the band is gone: the line
    def near(target):
        cand = [i for i in range(first, end) if L[i] < 250]
        return min(cand, key=lambda i: abs(L[i] - target)) if cand else first
    pick = [max(first - 1, 0), first, near(200), near(130), near(75), end, end + 2, min(end + 10, len(frames) - 1)]
    w = 640
    h = int(frames[0].height * w / frames[0].width)
    labels = ["impact (frozen)", "white", "collapse", "collapse", "collapse", "line", "line out", "impact plays"]
    cols = 4
    rows = (len(pick) + cols - 1) // cols
    strip = Image.new("RGB", (w * cols, (h + 28) * rows), (20, 20, 22))
    d = ImageDraw.Draw(strip)
    for n, i in enumerate(pick):
        x, y = (n % cols) * w, (n // cols) * (h + 28)
        strip.paste(frames[i].resize((w, h), Image.LANCZOS), (x, y + 28))
        d.text((x + 8, y + 6), "%d  %s" % (n + 1, labels[n] if n < len(labels) else ""), fill=(235, 235, 235))
    strip.save(os.path.join(dst, "present_crit_strip.png"))
    gw = 800
    gh = int(frames[0].height * gw / frames[0].width)
    seq = [frames[i].resize((gw, gh), Image.LANCZOS) for i in range(max(first - 8, 0), min(end + 25, len(frames)))]
    pal = seq[len(seq) // 2].quantize(colors=128)
    out = [f.quantize(palette=pal) for f in seq]
    out[0].save(os.path.join(dst, "present_crit_flash.gif"), save_all=True, append_images=out[1:], duration=60, loop=0)
    print("strip frames", pick)


main()
