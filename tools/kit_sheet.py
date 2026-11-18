#!/usr/bin/env python3
"""[kit] Contact sheet of kit lineup shots: python3 tools/kit_sheet.py PREFIX [cols]
Reads PREFIX_<item>_<day|night>.png, writes PREFIX_sheet_<day|night>.png (half-size tiles, labelled)."""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont

prefix = sys.argv[1]
cols = int(sys.argv[2]) if len(sys.argv) > 2 else 3
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
for tod in ("day", "night"):
    files = sorted(f for f in glob.glob(f"{prefix}_*_{tod}.png") if "_sheet_" not in f)
    if not files:
        continue
    tiles = []
    for f in files:
        im = Image.open(f).convert("RGB")
        im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
        name = os.path.basename(f)[len(os.path.basename(prefix)) + 1:-len(tod) - 5]
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, 8 + 10 * len(name), 24], fill=(0, 0, 0))
        d.text((5, 3), name, font=font, fill=(255, 255, 255))
        tiles.append(im)
    w, h = tiles[0].size
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (w * cols, h * rows), (20, 20, 20))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * w, (i // cols) * h))
    out = f"{prefix}_sheet_{tod}.png"
    sheet.save(out)
    print("wrote", out)
