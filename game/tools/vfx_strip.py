"""Frame strips for the cast / spectacle VFX review (D167-D170).

    python tools/vfx_strip.py <frames dir> [out dir]

Reads the folders tools/vfx_shots.gd writes (<frames dir>/<mode>/NN.png) and
writes one strip per mode, casts_<mode>.png, to <out dir> (default
design/art): the frames side by side at game scale (each frame scaled to a
fixed width, time order left to right, labelled). The elements folder becomes
a 7-panel sheet, each panel a crop round the release, named.
"""
import os
import sys

from PIL import Image, ImageDraw

W = 560  # each frame's width in the strip (a 1600x900 frame at ~1/3: game scale on a laptop)


def label(im, text):
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 8 + 7 * len(text), 18], fill=(0, 0, 0))
    d.text((4, 3), text, fill=(255, 255, 255))


def strip(src, dst, name):
    files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    if not files:
        return
    frames = []
    for i, f in enumerate(files):
        im = Image.open(os.path.join(src, f)).convert("RGB")
        h = int(im.height * W / im.width)
        im = im.resize((W, h), Image.LANCZOS)
        label(im, "%s %d" % (name, i + 1))
        frames.append(im)
    cols = 4 if len(frames) > 4 else len(frames)
    rows = (len(frames) + cols - 1) // cols
    h = frames[0].height
    sheet = Image.new("RGB", (cols * W + (cols - 1) * 4, rows * h + (rows - 1) * 4), (40, 40, 40))
    for i, im in enumerate(frames):
        sheet.paste(im, ((i % cols) * (W + 4), (i // cols) * (h + 4)))
    out = os.path.join(dst, "casts_%s.png" % name)
    sheet.save(out)
    print("wrote", out)


def elements(src, dst):
    files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    panels = []
    for f in files:
        im = Image.open(os.path.join(src, f)).convert("RGB")
        cw, ch = int(im.width * 0.34), int(im.height * 0.86)
        x0 = (im.width - cw) // 2
        y0 = int(im.height * 0.04)
        p = im.crop((x0, y0, x0 + cw, y0 + ch))
        p = p.resize((300, int(300 * ch / cw)), Image.LANCZOS)
        label(p, f.split("_", 1)[1][:-4].upper())
        panels.append(p)
    if not panels:
        return
    h = panels[0].height
    sheet = Image.new("RGB", (len(panels) * 304 - 4, h), (40, 40, 40))
    for i, p in enumerate(panels):
        sheet.paste(p, (i * 304, 0))
    out = os.path.join(dst, "casts_elements.png")
    sheet.save(out)
    print("wrote", out)


def main():
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "..", "design", "art")
    for name in sorted(os.listdir(src)):
        d = os.path.join(src, name)
        if not os.path.isdir(d):
            continue
        if name == "elements":
            elements(d, dst)
        else:
            strip(d, dst, name)


if __name__ == "__main__":
    main()
