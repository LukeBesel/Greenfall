#!/usr/bin/env python3
"""[kit] Generates the art kit decal images (art/kit/decals/*.png). Re-run after editing.
Decals are images on quads (never 3D text): stencil arrows, warning signs, bay numbers, logo."""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random

OUT = os.path.join(os.path.dirname(__file__), "..", "art", "kit", "decals")
os.makedirs(OUT, exist_ok=True)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
CREAM = (238, 230, 210, 255)
YEL = (250, 196, 40, 255)
DARK = (28, 28, 30, 255)


def wear(img, amt=0.18, seed=1):
    """Stencil wear: punch small random holes in the alpha so decals don't look printed-on."""
    rnd = random.Random(seed)
    w, h = img.size
    mask = Image.new("L", img.size, 255)
    d = ImageDraw.Draw(mask)
    for _ in range(int(w * h * amt / 900)):
        x, y, r = rnd.randrange(w), rnd.randrange(h), rnd.randint(2, 9)
        d.ellipse([x - r, y - r, x + r, y + r], fill=0)
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    a = img.getchannel("A")
    img.putalpha(Image.composite(a, Image.new("L", img.size, 0), mask))
    return img


def save(img, name):
    img.save(os.path.join(OUT, name + ".png"))


S = 256
# arrow
im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
d.polygon([(128, 20), (230, 130), (168, 130), (168, 236), (88, 236), (88, 130), (26, 130)], fill=CREAM)
save(wear(im, 0.2, 2), "arrow")
# chevrons
im = Image.new("RGBA", (S, S // 2), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
for i in range(3):
    x = 30 + i * 70
    d.polygon([(x, 10), (x + 40, 64), (x, 118), (x + 30, 118), (x + 70, 64), (x + 30, 10)], fill=YEL)
save(wear(im, 0.15, 3), "chevrons")
# warning triangle
im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
d.polygon([(128, 14), (246, 228), (10, 228)], fill=DARK)
d.polygon([(128, 40), (222, 214), (34, 214)], fill=YEL)
d.rectangle([116, 90, 140, 165], fill=DARK)
d.ellipse([114, 178, 142, 204], fill=DARK)
save(wear(im, 0.12, 4), "warn")
# bolt / power sign
im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
d.ellipse([8, 8, 248, 248], fill=DARK)
d.ellipse([22, 22, 234, 234], fill=YEL)
d.polygon([(146, 36), (78, 140), (124, 140), (104, 222), (180, 112), (134, 112)], fill=DARK)
save(wear(im, 0.12, 5), "power")
# logo: leaf in a ring (Greenfall restoration crew)
im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
d.ellipse([10, 10, 246, 246], outline=CREAM, width=18)
d.chord([60, 50, 220, 210], 200, 20, fill=CREAM)
d.chord([36, 46, 196, 206], 20, 200, fill=CREAM)
d.line([(72, 196), (190, 72)], fill=(0, 0, 0, 0), width=10)
save(wear(im, 0.15, 6), "logo")
# bay numbers
font = ImageFont.truetype(FONT, 170)
for n in range(1, 7):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    t = "%02d" % n
    bb = d.textbbox((0, 0), t, font=font)
    d.text(((S - (bb[2] - bb[0])) / 2 - bb[0], (S - (bb[3] - bb[1])) / 2 - bb[1]), t, font=font, fill=CREAM)
    # stencil bridges
    d.rectangle([0, 122, S, 132], fill=(0, 0, 0, 0))
    save(wear(im, 0.18, 10 + n), "num_%02d" % n)
# label plates (short words as images)
font2 = ImageFont.truetype(FONT, 64)
for word in ["HUB", "POWER", "WATER", "DOCK", "SCRAP", "SEEDS"]:
    im = Image.new("RGBA", (512, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([4, 4, 508, 124], 18, fill=DARK)
    d.rounded_rectangle([14, 14, 498, 114], 12, outline=YEL, width=5)
    bb = d.textbbox((0, 0), word, font=font2)
    d.text(((512 - (bb[2] - bb[0])) / 2 - bb[0], (128 - (bb[3] - bb[1])) / 2 - bb[1]), word, font=font2, fill=CREAM)
    save(wear(im, 0.1, sum(map(ord, word))), "label_" + word.lower())
# solar cells (opaque, tiled)
im = Image.new("RGBA", (S, S), (20, 34, 70, 255))
d = ImageDraw.Draw(im)
for i in range(4):
    for j in range(4):
        x, y = i * 64, j * 64
        d.rectangle([x + 3, y + 3, x + 61, y + 61], fill=(30, 52, 110, 255))
        for k in range(1, 4):
            d.line([(x + 3, y + k * 16), (x + 61, y + k * 16)], fill=(70, 90, 140, 255), width=1)
        d.line([(x + 32, y + 3), (x + 32, y + 61)], fill=(150, 160, 180, 255), width=2)
save(im, "solar_cells")
# vent grille (dark slots)
im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
for k in range(8):
    d.rounded_rectangle([20, 20 + k * 28, 236, 36 + k * 28], 6, fill=(16, 16, 18, 255))
save(im, "grille")
print("decals written to", os.path.abspath(OUT))
