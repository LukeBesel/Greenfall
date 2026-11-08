"""v2 review sheets: concept vs render for portrait, turnaround, head close-up, chest/claws close-up, blink."""
import sys
from PIL import Image, ImageDraw

import os
SP = os.environ.get("CONCEPT_DIR", "art/concept")
OUT = sys.argv[1]


def label(im, text):
	d = ImageDraw.Draw(im)
	d.rectangle((0, 0, 12 + 7 * len(text), 22), fill=(0, 0, 0))
	d.text((6, 5), text, fill=(255, 255, 255))
	return im


def side(left, right, h, t1, t2):
	a = left.resize((int(left.width * h / left.height), h))
	b = right.resize((int(right.width * h / right.height), h))
	out = Image.new("RGB", (a.width + b.width + 8, h), (0, 0, 0))
	out.paste(label(a, t1), (0, 0))
	out.paste(label(b, t2), (a.width + 8, 0))
	return out


def stack(top, bottom, w, t1, t2):
	a = top.resize((w, int(top.height * w / top.width)))
	b = bottom.resize((w, int(bottom.height * w / bottom.width)))
	out = Image.new("RGB", (w, a.height + b.height + 8), (0, 0, 0))
	out.paste(label(a, t1), (0, 0))
	out.paste(label(b, t2), (0, a.height + 8))
	return out


concept = Image.open(SP + "/aurora_portrait.png").convert("RGB")
what = sys.argv[2]
if what == "portrait":
	r = Image.open(OUT + "/portrait_v2.png").convert("RGB")
	side(concept, r, 700, "concept portrait", "Godot render v2").save(OUT + "/compare_portrait_v2.png")
elif what == "head":
	r = Image.open(OUT + "/head_v2.png").convert("RGB")
	side(concept.crop((180, 20, 720, 420)), r, 600, "concept (head crop)", "Godot render v2").save(OUT + "/compare_head_v2.png")
elif what == "chest":
	r = Image.open(OUT + "/chest_v2.png").convert("RGB")
	side(concept.crop((170, 300, 760, 620)), r, 520, "concept (body crop)", "Godot render v2").save(OUT + "/compare_chest_v2.png")
elif what == "turn":
	ims = [Image.open("%s/turn_v2_%d.png" % (OUT, i)).convert("RGB") for i in range(5)]
	ims = [im.crop((int(im.width * 0.1), int(im.height * 0.04), int(im.width * 0.9), int(im.height * 0.88))) for im in ims]
	w, h = ims[0].size
	strip = Image.new("RGB", (w * 5, h), (16, 16, 18))
	for i, im in enumerate(ims):
		strip.paste(im, (i * w, 0))
	strip.save(OUT + "/turnaround_strip_v2.png")
	tc = Image.open(SP + "/aurora_turnaround.png").convert("RGB")
	stack(tc, strip, 1520, "concept turnaround", "Godot render v2").save(OUT + "/compare_turnaround_v2.png")
