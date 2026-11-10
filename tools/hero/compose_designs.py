#!/usr/bin/env python3
"""compose_designs.py PREFIX OUT [ids]: the concept sheet's six portraits beside our renders.

PREFIX_<id>.png are portrait renders from scenes/hero_preview.tscn (--variants=...). Writes a sheet
with one column pair per design: the concept portrait (left) and the render (right), three rows of two.
"""
import os
import sys

from PIL import Image, ImageDraw

IDS = ["aurora", "bolt", "sprout", "pixel", "nova", "patch"]
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
CELL_W, CELL_H = 620, 388


def concept(i: int) -> Image.Image:
	sheet = Image.open(os.path.join(ROOT, "art/concept/lumi_concept.png")).convert("RGB")
	w = sheet.width / 3.0
	col, row = i % 3, i // 3
	top = row * 356
	return sheet.crop((int(col * w), top, int((col + 1) * w), top + 349))


def fit(im: Image.Image) -> Image.Image:
	s = max(CELL_W / im.width, CELL_H / im.height)
	im = im.resize((int(im.width * s + 0.5), int(im.height * s + 0.5)), Image.LANCZOS)
	x, y = (im.width - CELL_W) // 2, (im.height - CELL_H) // 2
	return im.crop((x, y, x + CELL_W, y + CELL_H))


def main() -> None:
	prefix, out = sys.argv[1], sys.argv[2]
	ids = sys.argv[3].split(",") if len(sys.argv) > 3 else IDS
	cols = 2
	rows = (len(ids) + cols - 1) // cols
	sheet = Image.new("RGB", (cols * 2 * CELL_W, rows * CELL_H), (12, 12, 12))
	draw = ImageDraw.Draw(sheet)
	for k, id_ in enumerate(ids):
		x, y = (k % cols) * 2 * CELL_W, (k // cols) * CELL_H
		sheet.paste(fit(concept(IDS.index(id_))), (x, y))
		path = "%s_%s.png" % (prefix, id_)
		if os.path.exists(path):
			sheet.paste(fit(Image.open(path).convert("RGB")), (x + CELL_W, y))
		draw.text((x + CELL_W + 8, y + 6), id_.upper() + " (game)", fill=(255, 255, 255))
	sheet.save(out)
	print("wrote", out, sheet.size)


if __name__ == "__main__":
	main()
