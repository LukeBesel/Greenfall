#!/usr/bin/env python3
"""[art1] Before/after board. Usage: tools/art_board.py OUT.png BEFORE_DIR AFTER_DIR name[:label] ...
One row per view: before left, after right, a caption strip above each row."""
import sys
from PIL import Image, ImageDraw, ImageFont

out, bdir, adir, names = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
W, H, CAP = 800, 450, 30
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
except OSError:
    font = ImageFont.load_default()
board = Image.new("RGB", (W * 2 + 12, (H + CAP) * len(names) + 4), (24, 24, 26))
d = ImageDraw.Draw(board)
for i, n in enumerate(names):
    name, _, label = n.partition(":")
    y = i * (H + CAP)
    d.text((8, y + 5), "%s  ·  before" % (label or name), fill=(230, 230, 230), font=font)
    d.text((W + 20, y + 5), "after", fill=(230, 230, 230), font=font)
    for k, dr in enumerate((bdir, adir)):
        board.paste(Image.open("%s/%s.png" % (dr, name)).convert("RGB").resize((W, H), Image.LANCZOS), (k * (W + 12), y + CAP))
board.save(out)
print(out)
