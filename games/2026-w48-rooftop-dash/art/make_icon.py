"""Draws icon.png (256 px) from the courier sprite in art.gd: the runner
mid-jump over a rooftop at night. Run: python3 art/make_icon.py (needs Pillow)."""
import os
import re

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "..", "art.gd")).read()
pal = {k: v for k, v in re.findall(r'"(\w)": Color\("(\w{6})"\)', src)}


def rows(const):
    block = re.search(const + r" := \[(.*?)\n\]", src, re.S).group(1)
    return re.findall(r'"([^"]*)"', block)


legs = re.search(r'"jump": \[(.*?)\]', src, re.S).group(1)
sprite = rows("TOP_ARM") + re.findall(r'"([^"]*)"', legs)

S = 12  # one sprite pixel = 12 icon pixels
img = Image.new("RGB", (256, 256), "#0f1534")
d = ImageDraw.Draw(img)
for i, c in enumerate(["#0a0d22", "#0f1534", "#151d47", "#1d2459", "#2a2a66", "#40306c"]):
    d.rectangle([0, i * 32, 256, 256], fill=c)
d.ellipse([168, 20, 232, 84], fill="#ffe9c4")
d.rectangle([0, 200, 256, 256], fill="#080b1f")
d.rectangle([0, 196, 256, 204], fill="#3d56a8")
d.rectangle([0, 196, 256, 198], fill="#8aa6ff")
for x in range(16, 256, 40):
    d.rectangle([x, 220, x + 12, 236], fill="#ffb347" if (x // 40) % 2 else "#161c3e")
ox, oy = 56, 6
for y, row in enumerate(sprite):
    for x, ch in enumerate(row):
        if ch in pal:
            d.rectangle([ox + x * S, oy + y * S, ox + x * S + S - 1, oy + y * S + S - 1], fill="#" + pal[ch])
img.save(os.path.join(HERE, "..", "icon.png"))
print("wrote icon.png")
