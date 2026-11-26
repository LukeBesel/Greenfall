# Paints the litter carpet's atlas: 16 kinds of flat ground litter, each with a torn or cut outline
# in the alpha channel, so one quad per piece reads as paper, cardboard, film, leaves or grit.
#   python3 art/models/junk/build_litter.py   -> litter_atlas.png (RGBA, sRGB), litter_normal.png
# Maps made in code (toggle-studio 04, textures): each kind is a mask (a jittered polygon with a
# noisy edge), a two-tone base with speckle and stains, features (print lines, flutes, tape, veins),
# and a height field (creases, crumple) that gives the normal map and a little baked shading.
# planet/sites/sphere_litter.gd lists the kinds (KINDS) in the same order: 4 columns x 4 rows.
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
C = 256  # cell size in pixels
N = 4
rng = np.random.default_rng(11)


def fbm(scale, octaves=4, seed=0, size=C):
	r = np.random.default_rng(seed)
	out = np.zeros((size, size), dtype=np.float32)
	amp = 1.0
	tot = 0.0
	for o in range(octaves):
		n = max(2, int(scale * 2 ** o))
		g = (r.random((n, n)) * 255).astype(np.uint8)
		up = np.asarray(Image.fromarray(g).resize((size, size), Image.BICUBIC), dtype=np.float32) / 255.0
		out += up * amp
		tot += amp
		amp *= 0.5
	return out / tot


def poly_mask(points, rag=0.0, seed=0, blur=0.0):
	"""points in 0..1; rag = how ragged the edge is (0..1)."""
	im = Image.new("L", (C * 2, C * 2), 0)
	ImageDraw.Draw(im).polygon([(x * C * 2, y * C * 2) for (x, y) in points], fill=255)
	im = im.filter(ImageFilter.GaussianBlur(2.0 + rag * 14.0 + blur * 20.0)).resize((C, C), Image.LANCZOS)
	m = np.asarray(im, dtype=np.float32) / 255.0
	if rag > 0 or blur > 0:
		n = fbm(10, 4, seed + 100) * 0.6 + fbm(40, 2, seed + 200) * 0.4
		m = m + (n - 0.5) * (rag * 0.9 + blur * 0.8)
	return np.clip((m - 0.5) * 12.0 + 0.5, 0.0, 1.0)


def rect(x0, y0, x1, y1, jit=0.0, n=1, seed=0):
	r = np.random.default_rng(seed)
	pts = []
	for (ax, ay, bx, by) in ((x0, y0, x1, y0), (x1, y0, x1, y1), (x1, y1, x0, y1), (x0, y1, x0, y0)):
		for k in range(n):
			t = k / n
			pts.append((ax + (bx - ax) * t + r.uniform(-jit, jit), ay + (by - ay) * t + r.uniform(-jit, jit)))
	return pts


def blob(cx, cy, rx, ry, jit, n=14, seed=0):
	r = np.random.default_rng(seed)
	return [(cx + math.cos(a) * rx * (1 + r.uniform(-jit, jit)), cy + math.sin(a) * ry * (1 + r.uniform(-jit, jit))) for a in [i * math.tau / n for i in range(n)]]


def creases(n, seed, width=2.0, depth=1.0):
	"""A height field of straight folds (valleys and ridges)."""
	r = np.random.default_rng(seed)
	im = Image.new("L", (C, C), 128)
	d = ImageDraw.Draw(im)
	for k in range(n):
		a = r.uniform(0, math.pi)
		cx, cy = r.uniform(0.2, 0.8) * C, r.uniform(0.2, 0.8) * C
		dx, dy = math.cos(a) * C, math.sin(a) * C
		d.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=int(128 + r.choice([-1, 1]) * 110), width=int(width))
	return (np.asarray(im.filter(ImageFilter.GaussianBlur(width * 0.9)), dtype=np.float32) - 128.0) / 110.0 * depth


def lines(y0, y1, step, x0, x1, seed, thick=1, broken=0.5):
	"""Printed text: broken dark lines. Returns a 0..1 ink mask."""
	r = np.random.default_rng(seed)
	im = Image.new("L", (C, C), 0)
	d = ImageDraw.Draw(im)
	y = y0
	while y < y1:
		x = x0
		while x < x1:
			w = r.uniform(0.02, 0.09)
			if r.random() > broken * 0.4:
				d.line([(x * C, y * C), (min(x + w, x1) * C, y * C)], fill=int(r.uniform(120, 230)), width=thick)
			x += w + r.uniform(0.008, 0.02)
		y += step
	return np.asarray(im, dtype=np.float32) / 255.0


def paint(mask, base, alt, seed, speck=0.1, stain=0.3, stain_col=(70, 55, 40), height=None, ink=None, ink_col=(40, 38, 36)):
	base = np.array(base, dtype=np.float32)
	alt = np.array(alt, dtype=np.float32)
	t = np.clip((fbm(4, 3, seed) - 0.35) / 0.35, 0, 1)[..., None]
	col = base * (1 - t) + alt * t
	col *= (1.0 - speck + 2.0 * speck * fbm(60, 2, seed + 1))[..., None]
	if ink is not None:
		col = col * (1 - ink[..., None] * 0.8) + np.array(ink_col, dtype=np.float32) * ink[..., None] * 0.8
	s = np.clip((fbm(5, 4, seed + 2) - (0.62 - stain * 0.3)) / 0.08, 0, 1)[..., None]
	col = col * (1 - s * 0.55) + np.array(stain_col, dtype=np.float32) * s * 0.55
	h = height if height is not None else np.zeros((C, C), dtype=np.float32)
	# baked shading from the height field: light from the upper left, plus a little cavity
	gy, gx = np.gradient(h)
	shade = 1.0 + np.clip((-gx - gy) * 0.9, -0.35, 0.3)
	col *= shade[..., None]
	# the edge of a sheet is a little darker (dirt gathers, the sheet curls)
	edge = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5)), dtype=np.float32) / 255.0
	col *= (0.72 + 0.28 * np.clip(edge * 1.6 - 0.3, 0, 1))[..., None]
	return np.clip(col, 0, 255), h


def cell_paper(seed):
	m = poly_mask(rect(0.14, 0.04, 0.86, 0.96, 0.012, 3, seed), 0.03, seed)
	h = creases(3, seed, 3, 2.5) + fbm(6, 3, seed + 5) * 3.0
	ink = lines(0.12, 0.9, 0.035, 0.22, 0.8, seed)
	return m, *paint(m, (196, 190, 172), (170, 160, 136), seed, 0.06, 0.35, height=h, ink=ink)


def cell_crumpled(seed):
	m = poly_mask(blob(0.5, 0.5, 0.4, 0.38, 0.22, 11, seed), 0.12, seed)
	h = creases(12, seed, 3, 3.5) + fbm(8, 4, seed + 5) * 7.0
	return m, *paint(m, (186, 182, 168), (150, 144, 128), seed, 0.08, 0.3, height=h)


def cell_newspaper(seed):
	m = poly_mask(rect(0.08, 0.05, 0.92, 0.95, 0.02, 4, seed), 0.06, seed)
	h = creases(4, seed, 4, 2.5) + fbm(5, 3, seed + 5) * 4.0
	ink = np.zeros((C, C), dtype=np.float32)
	for k in range(4):
		ink = np.maximum(ink, lines(0.2, 0.92, 0.022, 0.12 + k * 0.2, 0.29 + k * 0.2, seed + k, 1, 0.3) * 0.7)
	ink = np.maximum(ink, lines(0.1, 0.16, 0.05, 0.14, 0.8, seed + 9, 6, 0.1))
	im = Image.new("L", (C, C), 0)
	ImageDraw.Draw(im).rectangle([0.55 * C, 0.25 * C, 0.86 * C, 0.5 * C], fill=120)
	ink = np.maximum(ink, np.asarray(im, dtype=np.float32) / 255.0 * (0.5 + 0.5 * fbm(8, 2, seed + 3)))
	return m, *paint(m, (168, 162, 144), (140, 132, 110), seed, 0.07, 0.45, height=h, ink=ink)


def cell_cardboard(seed, pts, rag, flutes=True, tape=False, wet=0.5):
	m = poly_mask(pts, rag, seed)
	h = creases(2, seed, 5, 3.0) + fbm(5, 3, seed + 5) * 3.0
	if flutes:
		xx = np.arange(C, dtype=np.float32)[None, :].repeat(C, 0)
		h = h + np.sin(xx * 0.9) * 0.35
	col, h = paint(m, (150, 114, 74), (122, 90, 56), seed, 0.08, wet, (58, 42, 28), height=h)
	if tape:
		im = Image.new("L", (C, C), 0)
		ImageDraw.Draw(im).rectangle([0.44 * C, 0.0, 0.56 * C, C], fill=255)
		t = (np.asarray(im, dtype=np.float32) / 255.0)[..., None] * 0.7
		col = col * (1 - t) + np.array((172, 150, 104), dtype=np.float32) * t
	return m, col, h


def cell_film(seed, base, alt, rag):
	m = poly_mask(blob(0.5, 0.5, 0.42, 0.36, 0.3, 12, seed), rag, seed)
	h = creases(16, seed, 3, 3.0) + fbm(10, 4, seed + 5) * 6.0
	col, h = paint(m, base, alt, seed, 0.05, 0.25, (60, 55, 48), height=h)
	# highlights on the wrinkle ridges: film is shiny
	gy, gx = np.gradient(h)
	hl = np.clip((-gx - gy) * 1.2 - 0.25, 0, 1)[..., None]
	col = np.clip(col + hl * 70.0, 0, 255)
	return m, col, h


def cell_wrapper(seed):
	m = poly_mask(rect(0.1, 0.22, 0.9, 0.78, 0.03, 4, seed), 0.05, seed)
	h = creases(9, seed, 3, 3.0) + fbm(8, 3, seed + 5) * 4.0
	col, h = paint(m, (150, 62, 50), (120, 50, 44), seed, 0.06, 0.2, height=h)
	yy = np.arange(C, dtype=np.float32)[:, None].repeat(C, 1) / C
	band = ((yy > 0.42) & (yy < 0.56)).astype(np.float32)[..., None]
	col = col * (1 - band * 0.8) + np.array((176, 170, 150), dtype=np.float32) * band * 0.8
	xx = np.arange(C, dtype=np.float32)[None, :].repeat(C, 0) / C
	end = ((xx < 0.17) | (xx > 0.83)).astype(np.float32)[..., None]
	col = col * (1 - end * 0.8) + np.array((150, 152, 150), dtype=np.float32) * end * 0.8
	return m, col, h


def leaf_shape(cx, cy, l, w, ang):
	pts = []
	for i in range(12):
		t = i / 11.0
		pts.append((t * l, math.sin(t * math.pi) ** 0.8 * w * (1.0 + 0.2 * math.sin(t * 22.0))))
	pts += [(x, -y) for (x, y) in reversed(pts)]
	ca, sa = math.cos(ang), math.sin(ang)
	return [(cx + (x - l * 0.5) * ca - y * sa, cy + (x - l * 0.5) * sa + y * ca) for (x, y) in pts]


def cell_leaves(seed, n):
	r = np.random.default_rng(seed)
	m = np.zeros((C, C), dtype=np.float32)
	col = np.zeros((C, C, 3), dtype=np.float32)
	h = np.zeros((C, C), dtype=np.float32)
	tones = [(120, 82, 38), (96, 62, 30), (140, 104, 44), (84, 70, 34), (110, 54, 30)]
	for k in range(n):
		if n == 1:
			cx, cy, l, w, a = 0.5, 0.5, 0.8, 0.26, 0.2
		else:
			cx, cy, l, w, a = r.uniform(0.2, 0.8), r.uniform(0.2, 0.8), r.uniform(0.22, 0.36), r.uniform(0.07, 0.11), r.uniform(0, math.tau)
		lm = poly_mask(leaf_shape(cx, cy, l, w, a), 0.02, seed + k)
		im = Image.new("L", (C, C), 0)
		ca, sa = math.cos(a), math.sin(a)
		ImageDraw.Draw(im).line([((cx - l * 0.5 * ca) * C, (cy - l * 0.5 * sa) * C), ((cx + l * 0.5 * ca) * C, (cy + l * 0.5 * sa) * C)], fill=255, width=2)
		vein = np.asarray(im.filter(ImageFilter.GaussianBlur(1.0)), dtype=np.float32) / 255.0
		c, _ = paint(lm, tones[k % len(tones)], tones[(k + 2) % len(tones)], seed + k * 7, 0.1, 0.3, (40, 30, 20))
		c *= (1.0 - vein * 0.35)[..., None]
		col = col * (1 - lm[..., None]) + c * lm[..., None]
		h = h * (1 - lm) + (fbm(6, 2, seed + k) * 3.0 - vein * 1.5 + k * 0.3) * lm
		m = np.maximum(m, lm)
	return m, col, h


def cell_can(seed):
	m = poly_mask(blob(0.5, 0.5, 0.42, 0.24, 0.06, 16, seed), 0.02, seed)
	h = creases(5, seed, 4, 3.0) + fbm(6, 3, seed + 5) * 3.0
	col, h = paint(m, (150, 152, 152), (120, 118, 112), seed, 0.06, 0.3, (80, 52, 34), height=h)
	xx = np.arange(C, dtype=np.float32)[None, :].repeat(C, 0) / C
	lab = ((xx > 0.3) & (xx < 0.72)).astype(np.float32)[..., None] * (0.5 + 0.5 * fbm(9, 2, seed + 8))[..., None]
	col = col * (1 - lab * 0.85) + np.array((132, 46, 40), dtype=np.float32) * lab * 0.85
	return m, col, h


def cell_debris(seed):
	r = np.random.default_rng(seed)
	m = np.zeros((C, C), dtype=np.float32)
	col = np.zeros((C, C, 3), dtype=np.float32)
	h = np.zeros((C, C), dtype=np.float32)
	tones = [(60, 58, 55), (150, 140, 120), (96, 70, 44), (52, 74, 96), (120, 124, 120), (130, 52, 42), (40, 40, 42), (166, 150, 96)]
	for k in range(26):
		cx, cy = r.uniform(0.1, 0.9), r.uniform(0.1, 0.9)
		rr = r.uniform(0.018, 0.055)
		lm = poly_mask(blob(cx, cy, rr, rr * r.uniform(0.5, 1.0), 0.25, 8, seed + k), 0.0, seed + k)
		c, _ = paint(lm, tones[k % len(tones)], tones[(k + 3) % len(tones)], seed + k * 5, 0.1, 0.2)
		col = col * (1 - lm[..., None]) + c * lm[..., None]
		h = h * (1 - lm) + 4.0 * lm
		m = np.maximum(m, lm)
	return m, col, h


def cell_rag(seed):
	m = poly_mask(blob(0.5, 0.5, 0.42, 0.33, 0.25, 10, seed), 0.1, seed)
	h = creases(8, seed, 7, 4.0) + fbm(5, 3, seed + 5) * 8.0
	xx = np.arange(C, dtype=np.float32)[None, :].repeat(C, 0)
	yy = np.arange(C, dtype=np.float32)[:, None].repeat(C, 1)
	h = h + (np.sin(xx * 1.6) + np.sin(yy * 1.6)) * 0.12
	return m, *paint(m, (70, 86, 104), (58, 66, 74), seed, 0.08, 0.5, (50, 44, 36), height=h)


def cell_receipt(seed):
	m = poly_mask(rect(0.34, 0.04, 0.66, 0.96, 0.012, 5, seed), 0.02, seed)
	h = creases(5, seed, 3, 2.5) + fbm(6, 3, seed + 5) * 3.0
	ink = lines(0.1, 0.9, 0.04, 0.38, 0.62, seed, 1, 0.6)
	return m, *paint(m, (190, 186, 172), (160, 152, 132), seed, 0.05, 0.3, height=h, ink=ink)


def cell_grit(seed):
	m = poly_mask(blob(0.5, 0.5, 0.36, 0.36, 0.3, 9, seed), 0.0, seed, blur=0.75)
	h = fbm(30, 3, seed + 5) * 6.0
	col, h = paint(m, (52, 47, 41), (36, 33, 30), seed, 0.22, 0.2, (24, 22, 20), height=h)
	peb = np.clip((fbm(46, 2, seed + 9) - 0.62) * 12.0, 0, 1)[..., None]
	col = col * (1 - peb * 0.7) + np.array((104, 98, 88), dtype=np.float32) * peb * 0.7
	return m, col, h


CELLS = [
	lambda: cell_paper(1), lambda: cell_crumpled(2), lambda: cell_newspaper(3),
	lambda: cell_cardboard(4, blob(0.5, 0.5, 0.42, 0.36, 0.28, 9, 4), 0.1),
	lambda: cell_cardboard(5, rect(0.06, 0.08, 0.94, 0.92, 0.02, 3, 5), 0.04, True, True, 0.6),
	lambda: cell_cardboard(6, blob(0.5, 0.5, 0.38, 0.3, 0.35, 7, 6), 0.12, True, False, 0.7),
	lambda: cell_film(7, (150, 152, 148), (112, 114, 110), 0.14), lambda: cell_film(8, (30, 30, 32), (20, 20, 22), 0.12),
	lambda: cell_wrapper(9), lambda: cell_leaves(10, 7), lambda: cell_leaves(11, 1), lambda: cell_can(12),
	lambda: cell_debris(13), lambda: cell_rag(14), lambda: cell_receipt(15), lambda: cell_grit(16),
]

atlas = np.zeros((C * N, C * N, 4), dtype=np.float32)
height = np.zeros((C * N, C * N), dtype=np.float32)
for i, fn in enumerate(CELLS):
	m, col, h = fn()
	y0, x0 = (i // N) * C, (i % N) * C
	# colour is bled past the outline so mip levels do not pull in black
	solid = m > 0.5
	mean = col[solid].mean(axis=0) if solid.any() else np.array((90.0, 80.0, 70.0))
	col = np.where(m[..., None] > 0.2, col, mean[None, None, :])
	# a margin of empty alpha so neighbours never bleed in
	edge = np.zeros((C, C), dtype=np.float32)
	edge[6:-6, 6:-6] = 1.0
	atlas[y0:y0 + C, x0:x0 + C, :3] = col
	atlas[y0:y0 + C, x0:x0 + C, 3] = m * edge * 255.0
	height[y0:y0 + C, x0:x0 + C] = h * m
	print("[litter] cell %d: cover %.0f%%, mean colour %s" % (i, 100.0 * solid.mean(), np.round(mean).astype(int).tolist()))

Image.fromarray(np.clip(atlas, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(HERE, "litter_atlas.png"))
gy, gx = np.gradient(height)
k = 0.55
nx, ny, nz = -gx * k, -gy * k, np.ones_like(gx)
ln = np.sqrt(nx * nx + ny * ny + nz * nz)
nrm = np.stack([(nx / ln) * 0.5 + 0.5, (-ny / ln) * 0.5 + 0.5, (nz / ln) * 0.5 + 0.5], axis=2)  # OpenGL: +Y up (image rows go down)
Image.fromarray(np.clip(nrm * 255.0, 0, 255).astype(np.uint8), "RGB").save(os.path.join(HERE, "litter_normal.png"))
print("[litter] wrote litter_atlas.png and litter_normal.png (%d px)" % (C * N))
