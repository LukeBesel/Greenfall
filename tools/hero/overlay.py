#!/usr/bin/env python3
"""[art2] Lumi against the owner's turnaround, by measurement.
Usage: tools/hero/overlay.py OUT.png [RENDER_PREFIX]   (default prefix screenshots/hero/turn_nf)
The five figures are cut out of art/concept/aurora_turnaround.png and out of RENDER_PREFIX_0..4.png
(scenes/hero_preview.tscn --view=turn --no-floor, or tools/hero/quick_views.py for a fast look).

Masks. Concept: the backdrop is modelled per row from the empty columns between the figures (it is
a vertical gradient), a pixel differing from it by more than 10/255 is figure, holes are filled, the
largest blob per figure is kept; the fading glow plume under the hover unit is cut at the bottom of
the lit lower disc (y = 374). Render: --no-floor draws a green key backdrop (hero_preview.gd), or
the mask is taken against the border colour when the backdrop is not green.

Alignment. The antenna and the plume are not used for scale: every figure is scaled so that the
distance from the top of the head SHELL (first row at least 35% as wide as the head) to the bottom
of the hover unit is the same, and centred on the head. So the numbers compare shapes, not poses of
the antenna.

Prints per view: outline overlap (IoU) and where the render is wider (+) or narrower (-) than the
concept per band, as a share of the body height; then per-part measures for the concept and the
render (head height/width, head share of the body height, torso width as a share of head width,
pod width, eye ring diameter and stroke as a share of visor height, ear ring diameter as a share of
head height). Writes a sheet: concept row, render row, overlay row (concept red, render cyan,
overlap white)."""
import sys
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

BODY = 300          # px from head-shell top to pod bottom after scaling
TOP = 70            # room above the head for the antenna
H = BODY + TOP + 6
W = 420
NAMES = ["front", "front 3/4", "side", "back", "back 3/4"]
# Concept sheet layout (px in art/concept/aurora_turnaround.png).
CELLS = [(0, 300), (330, 565), (635, 860), (935, 1170), (1230, 1445)]
GAPS = [(300, 330), (565, 635), (860, 935), (1170, 1230)]
POD_BOTTOM = 374
BANDS = [("head top", 0.0, 0.12), ("head mid", 0.12, 0.38), ("head low", 0.38, 0.52), ("torso", 0.56, 0.80), ("pod", 0.84, 1.0)]


def largest_blob(m):
	"""Keep the largest 4-connected blob (plain flood fill, the images are small)."""
	lab = np.zeros(m.shape, np.int32)
	best, best_n, cur = 0, 0, 0
	hh, ww = m.shape
	for y0, x0 in zip(*np.where(m)):
		if lab[y0, x0]:
			continue
		cur += 1
		stack = [(y0, x0)]
		lab[y0, x0] = cur
		n = 0
		while stack:
			y, x = stack.pop()
			n += 1
			for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
				if 0 <= yy < hh and 0 <= xx < ww and m[yy, xx] and not lab[yy, xx]:
					lab[yy, xx] = cur
					stack.append((yy, xx))
		if n > best_n:
			best, best_n = cur, n
	return lab == best


def fill_holes(m):
	"""Background = what a flood from the border reaches; everything else is figure."""
	pad = np.pad(~m, 1, constant_values=True)
	out = np.zeros(pad.shape, bool)
	hh, ww = pad.shape
	stack = [(0, 0)]
	out[0, 0] = True
	while stack:
		y, x = stack.pop()
		for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
			if 0 <= yy < hh and 0 <= xx < ww and pad[yy, xx] and not out[yy, xx]:
				out[yy, xx] = True
				stack.append((yy, xx))
	return ~out[1:-1, 1:-1]


def clean(m, close=5):
	im = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(close)).filter(ImageFilter.MinFilter(close))
	return fill_holes(largest_blob(np.asarray(im) > 127))


def concept_figures():
	im = Image.open("art/concept/aurora_turnaround.png").convert("RGB")
	a = np.asarray(im.filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32)
	bg = np.median(np.concatenate([a[:, x0:x1] for x0, x1 in GAPS], axis=1), axis=1, keepdims=True)
	m = np.abs(a - bg).max(axis=2) > 10
	m[:32, :460] = False          # the title
	m[POD_BOTTOM + 1:, :] = False  # the plume and the floor reflection
	ImageDraw.Draw(im).rectangle((0, 0, 460, 31), fill=(28, 27, 27))  # the title
	out = []
	for x0, x1 in CELLS:
		out.append((im.crop((x0, 0, x1, 420)), clean(m[:420, x0:x1])))
	return out


def render_figure(path):
	im = Image.open(path).convert("RGB")
	a = np.asarray(im).astype(np.float32)
	border = np.concatenate([a[:4].reshape(-1, 3), a[-4:].reshape(-1, 3), a[:, :4].reshape(-1, 3), a[:, -4:].reshape(-1, 3)])
	bg = np.median(border, axis=0)
	if bg[1] > bg[0] + 40 and bg[1] > bg[2] + 40:
		m = ~((a[:, :, 1] > a[:, :, 0] + 22) & (a[:, :, 1] > a[:, :, 2] + 22))  # green key backdrop
	else:
		m = np.abs(a - bg).sum(axis=2) > 36
	return im, clean(m, 3)


def landmarks(m):
	"""Rows of the head-shell top and the bottom, and the head's centre column."""
	w = m.sum(axis=1)
	ys = np.where(w > 0)[0]
	top_any, bottom = ys[0], ys[-1]
	upper = w[top_any:top_any + (bottom - top_any) // 2]
	head_w = upper.max()
	head_top = top_any + int(np.argmax(upper >= 0.35 * head_w))
	# Head centre: mid of the extents over the head's middle rows.
	y0 = head_top + int((bottom - head_top) * 0.15)
	y1 = head_top + int((bottom - head_top) * 0.35)
	xs = np.where(m[y0:y1].any(axis=0))[0]
	return head_top, bottom, 0.5 * (xs[0] + xs[-1])


def normalise(im, m, backdrop=None):
	if backdrop is not None:
		a = np.asarray(im).copy()
		a[~m] = backdrop   # the key backdrop is only for the mask
		im = Image.fromarray(a)
	head_top, bottom, cx = landmarks(m)
	s = BODY / float(bottom - head_top)
	size = (max(1, int(round(im.width * s))), max(1, int(round(im.height * s))))
	im2 = im.resize(size, Image.LANCZOS)
	m2 = Image.fromarray((m * 255).astype(np.uint8)).resize(size, Image.NEAREST)
	ox = int(round(W * 0.5 - cx * s))
	oy = int(round(TOP - head_top * s))
	canvas = Image.new("RGB", (W, H), (10, 10, 12))
	canvas.paste(im2, (ox, oy))
	mc = Image.new("L", (W, H), 0)
	mc.paste(m2, (ox, oy))
	return canvas, np.asarray(mc) > 127


def runs(row):
	"""[(x0, x1)] of the True runs in a row."""
	d = np.diff(np.concatenate([[0], row.astype(np.int8), [0]]))
	return list(zip(np.where(d == 1)[0], np.where(d == -1)[0]))


def cyan(a):
	r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
	return (b > 140) & (g > 130) & (r < g - 25) & (r < b - 25)


def blobs(m, min_px=12):
	"""Bounding boxes (x0, y0, x1, y1, n) of the blobs of a mask."""
	left = m.copy()
	out = []
	while left.any():
		one = largest_blob(left)
		n = int(one.sum())
		if n < min_px:
			break
		ys, xs = np.where(one)
		out.append((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1, n))
		left &= ~one
	return out


def measures(view, im, m):
	"""Per-part measures from a normalised figure (rows TOP .. TOP + BODY)."""
	out = {}
	w = m.sum(axis=1).astype(np.float32)
	a = np.asarray(im).astype(np.float32)
	lo, hi = TOP + int(0.40 * BODY), TOP + int(0.72 * BODY)
	neck = lo + int(np.argmin(w[lo:hi]))
	head_w = float(w[TOP:neck].max())
	out["head h/w"] = (neck - TOP) / head_w
	out["head share"] = (neck - TOP) / float(BODY)
	out["head w"] = head_w / BODY
	if view in (0, 3):
		# Torso: the middle run on rows where the arms stand clear of it (three runs or more).
		tw = []
		for y in range(neck, TOP + int(0.86 * BODY)):
			rr = runs(m[y])
			if len(rr) >= 3:
				mid = min(rr, key=lambda r: abs(0.5 * (r[0] + r[1]) - W * 0.5))
				tw.append(mid[1] - mid[0])
		if tw:
			out["torso/head w"] = float(np.median(tw)) / head_w
		out["arm span/head w"] = float(w[neck:TOP + int(0.9 * BODY)].max()) / head_w
	out["pod/head w"] = float(w[TOP + int(0.9 * BODY):TOP + int(0.97 * BODY)].max()) / head_w
	cy = cyan(a) & m
	if view == 0:
		# Eyes: the two largest cyan blobs in the head's middle; visor = the dark column through an eye.
		head = np.zeros_like(cy)
		head[TOP + 10:neck - 10, int(W * 0.5 - head_w * 0.36):int(W * 0.5 + head_w * 0.36)] = True
		eyes = sorted(blobs(cy & head), key=lambda b: -b[4])[:2]
		if len(eyes) == 2:
			lum = a.mean(axis=2)
			d, st, vh = [], [], []
			for (x0, y0, x1, y1, _n) in eyes:
				d.append(0.5 * ((x1 - x0) + (y1 - y0)))
				ex, ey = (x0 + x1) // 2, (y0 + y1) // 2
				row = runs(cy[ey, max(x0 - 2, 0):x1 + 2])
				col = runs(cy[max(y0 - 2, 0):y1 + 2, ex])
				strokes = [r[1] - r[0] for r in row + col]
				if strokes:
					st.append(float(np.median(strokes)))
				# Visor height: up and down from the eye until the glass ends (a light shell pixel).
				up = ey
				while up > TOP and (lum[up, ex] < 95 or cy[up, ex]):
					up -= 1
				dn = ey
				while dn < neck and (lum[dn, ex] < 95 or cy[dn, ex]):
					dn += 1
				vh.append(dn - up)
			out["eye d/visor h"] = float(np.mean(d)) / float(np.mean(vh))
			if st:
				out["eye stroke/visor h"] = float(np.mean(st)) / float(np.mean(vh))
			out["visor h/head h"] = float(np.mean(vh)) / (neck - TOP)
			out["eye gap/head w"] = abs(0.5 * (eyes[0][0] + eyes[0][2]) - 0.5 * (eyes[1][0] + eyes[1][2])) / head_w
	if view == 1:
		# Ear ring: the tallest cyan blob outside the visor side (the right third of the head).
		side = np.zeros_like(cy)
		side[TOP:neck, int(W * 0.5 + head_w * 0.05):] = True
		ear = sorted(blobs(cy & side), key=lambda b: -(b[3] - b[1]))[:1]
		if ear:
			out["ear d/head h"] = (ear[0][3] - ear[0][1]) / float(neck - TOP)
	return out


def main():
	out_path = sys.argv[1]
	prefix = sys.argv[2] if len(sys.argv) > 2 else "screenshots/hero/turn_nf"
	sheet = Image.new("RGB", (W * 5, H * 3 + 8), (10, 10, 12))
	concept = concept_figures()
	ious = []
	rows = []
	for i in range(5):
		c_im, c_m = normalise(*concept[i])
		r_im, r_m = normalise(*render_figure("%s_%d.png" % (prefix, i)), backdrop=(30, 29, 29))
		iou = (c_m & r_m).sum() / max(1, (c_m | r_m).sum())
		ious.append(iou)
		wc = c_m.sum(axis=1) / float(BODY)
		wr = r_m.sum(axis=1) / float(BODY)
		parts = " ".join("%s %+.2f" % (n, wr[TOP + int(a * BODY):TOP + int(b * BODY)].mean() - wc[TOP + int(a * BODY):TOP + int(b * BODY)].mean()) for n, a, b in BANDS)
		print("%-10s IoU %.2f  width diff: %s" % (NAMES[i], iou, parts))
		rows.append((measures(i, c_im, c_m), measures(i, r_im, r_m)))
		sheet.paste(c_im, (i * W, 0))
		sheet.paste(r_im, (i * W, H + 4))
		ov = np.zeros((H, W, 3), np.uint8)
		ov[c_m] = (220, 60, 60)
		ov[r_m] = (40, 200, 220)
		ov[c_m & r_m] = (235, 235, 235)
		sheet.paste(Image.fromarray(ov), (i * W, H * 2 + 8))
	print("mean IoU %.3f" % (sum(ious) / 5.0))
	print("part measures (concept / render):")
	for i in range(5):
		c, r = rows[i]
		print("  %-10s " % NAMES[i] + "  ".join("%s %.2f/%.2f" % (k, c[k], r.get(k, float("nan"))) for k in c))
	sheet.save(out_path)


if __name__ == "__main__":
	main()
