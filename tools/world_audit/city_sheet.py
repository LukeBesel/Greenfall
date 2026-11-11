#!/usr/bin/env python3
"""Contact sheet of city renders: python3 tools/world_audit/city_sheet.py OUT.png [--cols=N] "label=path.png" ...
Half-size tiles in rows of N (default 4), each under its label. A missing picture is a dark tile
that says so, so a sheet never hides a render that failed."""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
cols = 4
items = []
for a in sys.argv[2:]:
    if a.startswith("--cols="):
        cols = int(a.split("=", 1)[1])
    else:
        label, path = a.rsplit("=", 1)
        items.append((label, path))
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
tw, th, bar = 640, 360, 24
rows = (len(items) + cols - 1) // cols
sheet = Image.new("RGB", (tw * cols, (th + bar) * rows), (14, 16, 22))
draw = ImageDraw.Draw(sheet)
for i, (label, path) in enumerate(items):
    x, y = (i % cols) * tw, (i // cols) * (th + bar)
    if os.path.exists(path):
        sheet.paste(Image.open(path).convert("RGB").resize((tw, th), Image.LANCZOS), (x, y + bar))
    else:
        label += "  (render missing)"
    draw.text((x + 6, y + 4), label, font=font, fill=(240, 240, 235))
sheet.save(out)
print("wrote", out, f"{len(items)} tiles")
