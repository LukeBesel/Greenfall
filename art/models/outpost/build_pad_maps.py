#!/usr/bin/env python3
"""[art4] The start pad's surface, painted in code (numpy + PIL): python3 art/models/outpost/build_pad_maps.py

Writes, next to this file:
  pad_albedo.png   colour (sRGB)
  pad_normal.png   OpenGL normal map from the painted height
  pad_orm.png      R = occlusion, G = roughness, B = metallic
  pad_detail.png   a tiling micro tile: RG = normal, B = roughness jitter, A = value jitter

The picture covers the whole 21 x 21 m pad (x east = right, z south = down), about 1 cm a pixel.
Layers, each a named step (ToggleOps toggle-studio 04, "build in layers"):
  alloy deck panels at three scales (3.3 m panels with real gaps in the mesh, 1.65 m scored
  plates, fastener rows and tie-down cups), an anti-slip coat worn through where feet and wheels
  go, painted landing marks worn by use, tyre and skid marks, engine scorch with heat tint, oil,
  dust drifted against the kerb, the grated cable tray and the painted kerb beam round the edge.
The mesh that carries it: build_pad.py. Layout numbers are shared with it (PAD below).
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
N = 2048
PAD = {"size": 21.0, "kerb_in": 10.2, "tray_in": 9.9, "pitch": 3.3, "gap": 0.05,
	"circle": (0.0, -6.5), "circle_r": 3.0, "ramp_half": 2.5}
S = PAD["size"]
PPM = N / S
SS = 2  # supersample for vector shapes
FONT = os.path.join(HERE, "..", "..", "..", "ui", "fonts", "AnonymousPro-Bold.ttf")

xs = (np.arange(N, dtype=np.float32) + 0.5) / N * S - S / 2
X, Z = np.meshgrid(xs, xs)
EDGE = np.maximum(np.abs(X), np.abs(Z))


def sm(e0, e1, x):
	t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


def vnoise(cx, cy, seed, n=N):
	r = np.random.default_rng(seed).random((max(2, int(cy)) + 1, max(2, int(cx)) + 1), dtype=np.float32)
	return np.asarray(Image.fromarray(r, "F").resize((n, n), Image.BICUBIC), dtype=np.float32).clip(0, 1)


def fbm(cells, octaves, seed, gain=0.5, n=N):
	out = np.zeros((n, n), np.float32)
	amp, tot = 1.0, 0.0
	for o in range(octaves):
		out += amp * vnoise(cells * 2 ** o, cells * 2 ** o, seed + o * 13, n)
		tot += amp
		amp *= gain
	return out / tot


def blur(a, sigma_m):
	fy = np.fft.fftfreq(a.shape[0])[:, None]
	fx = np.fft.rfftfreq(a.shape[1])[None, :]
	g = np.exp(-2.0 * (math.pi * sigma_m * PPM) ** 2 * (fx * fx + fy * fy))
	return np.fft.irfft2(np.fft.rfft2(a) * g, s=a.shape).astype(np.float32)


class Canvas:
	"""Vector shapes in pad metres, antialiased by supersampling."""

	def __init__(self):
		self.im = Image.new("L", (N * SS, N * SS), 0)
		self.d = ImageDraw.Draw(self.im)

	def px(self, x, z):
		return ((x + S / 2) * PPM * SS, (z + S / 2) * PPM * SS)

	def line(self, pts, w, v=255):
		self.d.line([self.px(*p) for p in pts], fill=v, width=max(1, int(round(w * PPM * SS))), joint="curve")

	def dot(self, x, z, r, v=255):
		cx, cy = self.px(x, z)
		rr = r * PPM * SS
		self.d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=v)

	def ring(self, x, z, r, w, v=255):
		cx, cy = self.px(x, z)
		ro = (r + w / 2) * PPM * SS
		self.d.ellipse([cx - ro, cy - ro, cx + ro, cy + ro], outline=v, width=max(1, int(round(w * PPM * SS))))

	def rect(self, x0, z0, x1, z1, v=255):
		self.d.rectangle([self.px(x0, z0), self.px(x1, z1)], fill=v)

	def poly(self, pts, v=255):
		self.d.polygon([self.px(*p) for p in pts], fill=v)

	def text(self, s, x, z, h, v=255):
		f = ImageFont.truetype(FONT, int(h * PPM * SS * 1.25))
		cx, cy = self.px(x, z)
		self.d.text((cx, cy), s, font=f, fill=v, anchor="mm")

	def get(self):
		return np.asarray(self.im.resize((N, N), Image.LANCZOS), dtype=np.float32) / 255.0


def bezier(p0, p1, p2, p3, n=60):
	t = np.linspace(0, 1, n)[:, None]
	p = ((1 - t) ** 3) * np.array(p0) + 3 * ((1 - t) ** 2) * t * np.array(p1) + 3 * (1 - t) * t * t * np.array(p2) + t ** 3 * np.array(p3)
	return [tuple(q) for q in p]


def offset(pts, d):
	out = []
	for i, p in enumerate(pts):
		a = pts[max(i - 1, 0)]
		b = pts[min(i + 1, len(pts) - 1)]
		tx, tz = b[0] - a[0], b[1] - a[1]
		ln = math.hypot(tx, tz) or 1.0
		out.append((p[0] - tz / ln * d, p[1] + tx / ln * d))
	return out


# ---------------------------------------------------------------- zones
kerb = (EDGE > PAD["kerb_in"]).astype(np.float32)
tray = ((EDGE > PAD["tray_in"]) & (EDGE <= PAD["kerb_in"])).astype(np.float32)
deck = (EDGE <= PAD["tray_in"]).astype(np.float32)
ramp = ((np.abs(X) < PAD["ramp_half"]) & (Z < -PAD["tray_in"])).astype(np.float32)  # the way out north
kerb *= 1.0 - ramp
tray *= 1.0 - ramp

P = PAD["pitch"]
lu = np.mod(X + PAD["tray_in"], P)
lv = np.mod(Z + PAD["tray_in"], P)
ix = np.clip(np.floor((X + PAD["tray_in"]) / P), 0, 5).astype(int)
iz = np.clip(np.floor((Z + PAD["tray_in"]) / P), 0, 5).astype(int)
gap_d = np.minimum(np.minimum(lu, P - lu), np.minimum(lv, P - lv))  # metres to the nearest panel joint
gap = (gap_d < PAD["gap"] * 0.5).astype(np.float32) * deck
sub_d = np.minimum(np.abs(lu - P / 2), np.abs(lv - P / 2))  # the scored 1.65 m plates
seam = (1.0 - sm(0.004, 0.012, sub_d)) * deck * (1.0 - gap)

rng = np.random.default_rng(4471)
tone = rng.uniform(-1.0, 1.0, (6, 6)).astype(np.float32)
fresh = np.zeros((6, 6), np.float32)  # panels swapped for new ones: cleaner, lighter
for (a, b) in [(1, 4), (4, 1), (3, 3), (0, 1)]:
	fresh[b, a] = 1.0
ptone = tone[iz, ix]
pfresh = fresh[iz, ix]
grain_dir = ((ix + iz) % 2).astype(np.float32)  # brushed grain turns from panel to panel

n_big = fbm(3, 5, 11)
n_mid = fbm(12, 4, 23)
n_fine = fbm(96, 3, 37)
n_speck = vnoise(700, 700, 41)
streak_x = vnoise(14, 900, 53)
streak_z = vnoise(900, 14, 59)
brushed = streak_x * grain_dir + streak_z * (1.0 - grain_dir)

# ---------------------------------------------------------------- hardware drawn as shapes
c = Canvas()  # fasteners along every panel edge
for i in range(6):
	for j in range(6):
		x0 = -PAD["tray_in"] + i * P
		z0 = -PAD["tray_in"] + j * P
		for k in range(8):
			t = 0.21 + k * 0.4114
			for (fx, fz) in [(x0 + t, z0 + 0.11), (x0 + t, z0 + P - 0.11), (x0 + 0.11, z0 + t), (x0 + P - 0.11, z0 + t)]:
				c.dot(fx, fz, 0.017)
		for (fx, fz) in [(x0 + P / 2, z0 + P / 2)]:
			for (ox, oz) in [(-0.1, -0.1), (0.1, -0.1), (-0.1, 0.1), (0.1, 0.1)]:
				c.dot(fx + ox, fz + oz, 0.015)
bolts = c.get() * deck

c = Canvas()  # tie-down cups: four to a panel
cups_xy = []
for i in range(6):
	for j in range(6):
		for (ox, oz) in [(0.825, 0.825), (2.475, 0.825), (0.825, 2.475), (2.475, 2.475)]:
			cx_, cz_ = -PAD["tray_in"] + i * P + ox, -PAD["tray_in"] + j * P + oz
			cups_xy.append((cx_, cz_))
			c.dot(cx_, cz_, 0.075)
cup = c.get()
c = Canvas()
for (cx_, cz_) in cups_xy:
	c.dot(cx_, cz_, 0.105)
cup_rim = np.clip(c.get() - cup, 0, 1)
c = Canvas()
for n_, (cx_, cz_) in enumerate(cups_xy):
	a = 0.0 if n_ % 2 == 0 else math.pi / 2
	c.line([(cx_ - math.cos(a) * 0.075, cz_ - math.sin(a) * 0.075), (cx_ + math.cos(a) * 0.075, cz_ + math.sin(a) * 0.075)], 0.022)
cup_bar = c.get() * cup

# the tray: grated cover plates, slots across the run
tray_run = np.where(np.abs(X) > np.abs(Z), Z, X)  # along the edge
tray_in_d = EDGE - PAD["tray_in"]  # 0 .. 0.3 across the tray
slot = ((np.mod(tray_run, 0.075) < 0.03) & (tray_in_d > 0.06) & (tray_in_d < 0.24)).astype(np.float32) * tray
plate_break = (np.mod(tray_run + 0.01, 1.65) < 0.02).astype(np.float32) * tray
slot *= 1.0 - (np.mod(tray_run + 0.12, 1.65) < 0.24)  # solid ends where the plate bolts down
corner = ((np.abs(X) > PAD["tray_in"]) & (np.abs(Z) > PAD["tray_in"])).astype(np.float32)
slot *= 1.0 - corner
LIGHTS = []  # deck edge lights, in the tray at every panel joint (shared with build_pad.py)
for k in range(7):
	t = -PAD["tray_in"] + k * P
	for sgn in (-1.0, 1.0):
		if not (sgn < 0 and abs(t) < PAD["ramp_half"] + 0.3):
			LIGHTS.append((t, sgn * (PAD["tray_in"] + 0.15), 0))
		LIGHTS.append((sgn * (PAD["tray_in"] + 0.15), t, 1))
c = Canvas()
for (lx, lz, turn) in LIGHTS:
	hw, hd = (0.17, 0.1) if turn == 0 else (0.1, 0.17)
	c.rect(lx - hw, lz - hd, lx + hw, lz + hd)
light_house = c.get()
slot *= 1.0 - light_house

# the kerb beam: bolts down its middle
c = Canvas()
for k in range(-19, 20):
	t = k * 0.55
	for sgn in (-1.0, 1.0):
		c.dot(t, sgn * (PAD["kerb_in"] + 0.15), 0.022)
		c.dot(sgn * (PAD["kerb_in"] + 0.15), t, 0.022)
kerb_bolt = c.get() * kerb
ramp_rib = ((np.mod(Z, 0.09) < 0.035) & (np.abs(X) < PAD["ramp_half"] - 0.2)).astype(np.float32) * ramp

# ---------------------------------------------------------------- use: where feet and wheels go
c = Canvas()
PATHS = [
	[(0, 6), (-3, 6.6), (-5.6, 7.2)], [(0, 6), (-3.4, 3.2), (-5.7, 1.6), (-5.8, -1.4)],
	[(0, 6.5), (0, 0), (0.2, -4), (0, -10.5)], [(0, 3), (3.5, 5), (6.2, 7.2)], [(0, 1), (4, 0.4), (7.2, 0.2)],
	[(-5.7, 1.4), (-3.5, -4.5), (-1.2, -10.5)], [(0.5, -3), (4.5, -6), (7.6, -7.4)], [(0, 6.5), (0, 8.4)],
]
for pth in PATHS:
	c.line(pth, 0.9, 150)
for (ex, ez) in [(-5.6, 7.3), (-5.8, 1.9), (-5.8, -1.3), (6.3, 7.3), (7.3, 0.2), (0, 6), (7.8, -7.4)]:
	c.dot(ex, ez, 0.75, 220)  # where Lumi stands to use a machine
traffic = blur(c.get(), 0.42)
traffic = np.clip(traffic * (0.55 + 0.9 * n_mid), 0, 1)

c = Canvas()  # hauler tyre tracks: pairs of thin lines on slow curves
TRACKS = [
	bezier((0.5, -10.5), (0.9, -5.0), (-2.0, 0.5), (-5.9, 1.9)),
	bezier((10.5, 3.2), (5.0, 3.6), (-1.0, 4.4), (-5.9, 2.3)),
	bezier((-0.6, -10.5), (-1.4, -3.0), (2.5, 2.0), (6.0, 6.6)),
	bezier((-5.6, 0.6), (-1.5, -1.5), (3.0, -1.0), (10.5, -2.6)),
	bezier((2.0, 10.4), (3.2, 6.0), (0.5, 3.0), (-5.4, 2.6)),
]
for n_, tr in enumerate(TRACKS):
	for side in (-0.27, 0.27):
		c.line(offset(tr, side), 0.075, 110 + 25 * (n_ % 3))
tyres = c.get()
tyres = np.clip(tyres * sm(0.3, 0.62, vnoise(40, 40, 71)) * 1.25, 0, 1)  # tracks come and go
tread = 0.75 + 0.25 * (np.mod(X * 9.0 + Z * 9.0, 1.0) < 0.5)
tyres *= tread

c = Canvas()  # scratches and drag marks
r2 = np.random.default_rng(99)
for _ in range(240):
	x0, z0 = r2.uniform(-9.8, 9.8, 2)
	a = r2.uniform(0, math.pi)
	ln = r2.uniform(0.15, 1.3) * (1.0 if r2.random() < 0.85 else 2.5)
	c.line([(x0, z0), (x0 + math.cos(a) * ln, z0 + math.sin(a) * ln)], 0.012, int(r2.uniform(90, 255)))
for (gx, gz, a) in [(-6.4, 5.6, 0.3), (-6.0, -0.2, 1.4), (6.6, 6.2, 2.6), (-0.6, -4.9, 1.0), (0.9, -5.6, 2.2)]:  # dragged crates
	for o in (0.0, 0.33):
		c.line([(gx + o * math.sin(a), gz - o * math.cos(a)), (gx + math.cos(a) * 1.9 + o * math.sin(a), gz + math.sin(a) * 1.9 - o * math.cos(a))], 0.03, 230)
scratch = c.get() * deck

# ---------------------------------------------------------------- the quay's concrete: cracks, patches, plates
c = Canvas()  # cracks: random walks that start on a joint
r3 = np.random.default_rng(321)
for n_ in range(34):
	x0 = -PAD["tray_in"] + r3.integers(0, 7) * P if n_ % 2 == 0 else r3.uniform(-9.8, 9.8)
	z0 = r3.uniform(-9.8, 9.8) if n_ % 2 == 0 else -PAD["tray_in"] + r3.integers(0, 7) * P
	a = r3.uniform(0, 2 * math.pi)
	pts = [(x0, z0)]
	for s_ in range(int(r3.integers(10, 46))):
		a += r3.normal(0, 0.42)
		x0 += math.cos(a) * 0.14
		z0 += math.sin(a) * 0.14
		pts.append((x0, z0))
		if s_ > 6 and r3.random() < 0.06:  # a branch
			b = a + r3.choice([-1, 1]) * 0.9
			c.line([(x0, z0), (x0 + math.cos(b) * 0.3, z0 + math.sin(b) * 0.3), (x0 + math.cos(b + 0.3) * 0.62, z0 + math.sin(b + 0.3) * 0.62)], 0.012, 200)
	c.line(pts, 0.016 if n_ % 3 else 0.026, int(r3.uniform(170, 255)))
crack = c.get() * deck
crack_soft = blur(crack, 0.03)

c = Canvas()  # steel road plates bolted over broken slabs (hand repairs)
PLATES = [(2.3, 2.7, 1.7, 1.15), (-3.3, -8.0, 1.25, 1.25), (6.9, -2.6, 1.1, 1.5)]
for (px_, pz_, w, d) in PLATES:
	c.rect(px_ - w / 2, pz_ - d / 2, px_ + w / 2, pz_ + d / 2)
plate = c.get()
c = Canvas()
for (px_, pz_, w, d) in PLATES:
	for sx in (-1, 1):
		for sz in (-1, 1):
			c.dot(px_ + sx * (w / 2 - 0.09), pz_ + sz * (d / 2 - 0.09), 0.03)
		c.dot(px_ + sx * (w / 2 - 0.09), pz_, 0.03)
plate_bolt = c.get()
plate_tread = ((np.mod((X + Z) * 14.0, 1.0) < 0.22) | (np.mod((X - Z) * 14.0, 1.0) < 0.22)).astype(np.float32) * plate

c = Canvas()  # mortar patches: newer, paler concrete trowelled into holes
for (mx, mz, r) in [(-2.2, 4.1, 0.6), (4.4, 6.3, 0.45), (-6.8, -6.2, 0.7), (1.4, -1.6, 0.4), (7.6, 3.4, 0.55), (-1.2, 8.3, 0.5), (3.6, -8.6, 0.5)]:
	c.dot(mx, mz, r)
patch = sm(0.5, 0.56, blur(c.get(), 0.3) * 1.5 + (n_mid - 0.5) * 0.9 + (n_fine - 0.5) * 0.25) * deck * (1.0 - gap)

cups_keep = ((lu < P / 2) & (lv < P / 2)).astype(np.float32)  # one iron tie ring a slab is enough on a quay
cup *= cups_keep
cup_rim *= cups_keep
cup_bar *= cups_keep

# ---------------------------------------------------------------- water: damp ground and standing puddles
low = fbm(5, 4, 777)  # where the slabs dip
kd = PAD["kerb_in"] - EDGE  # metres in from the kerb's inner face
wet = low * 0.9 + (1.0 - sm(0.0, 0.5, gap_d)) * 0.06 + (1.0 - sm(0.0, 1.6, kd)) * 0.1 + crack_soft * 0.25 - pfresh * 0.06
wet = np.where(EDGE < PAD["kerb_in"], wet, 0.0)
puddle = sm(0.585, 0.6, wet) * (1.0 - plate) * (1.0 - ramp)
damp = sm(0.44, 0.6, wet) * (1.0 - ramp)
cx0, cz0 = PAD["circle"]
RC = np.hypot(X - cx0, Z - cz0)
TH = np.arctan2(Z - cz0, X - cx0)
dry = 1.0 - sm(1.2, 3.4, RC)  # the engine bakes the ring dry
puddle *= 1.0 - dry
damp *= 1.0 - dry * 0.8

# ---------------------------------------------------------------- painted marks, worn by use
c = Canvas()  # white: the landing ring, its ticks, the pad number, the bars that count down to it
c.ring(cx0, cz0, PAD["circle_r"], 0.2)
for k in range(4):
	a = k * math.pi / 2
	c.line([(cx0 + math.cos(a) * 2.35, cz0 + math.sin(a) * 2.35), (cx0 + math.cos(a) * 2.9, cz0 + math.sin(a) * 2.9)], 0.14)
c.ring(cx0, cz0, 0.5, 0.09)
c.text("01", 5.3, -3.55, 1.25)
for k in range(5):
	z = 4.6 - k * 1.45
	c.rect(-0.55 + k * 0.06, z - 0.11, 0.55 - k * 0.06, z + 0.11)
for (bx, bz, w, d) in [(-7.9, 7.5, 3.9, 3.1)]:  # corner brackets of the bench bay
	for sx in (-1, 1):
		for sz in (-1, 1):
			px_, pz_ = bx + sx * w / 2, bz + sz * d / 2
			c.line([(px_, pz_), (px_ - sx * 0.7, pz_)], 0.09)
			c.line([(px_, pz_), (px_, pz_ - sz * 0.7)], 0.09)
white = c.get() * deck

c = Canvas()  # yellow: the three touchdown feet, arrows into the bin bay
for k in range(3):
	a = -math.pi / 2 + k * 2 * math.pi / 3
	c.ring(cx0 + math.cos(a) * 1.75, cz0 + math.sin(a) * 1.75, 0.34, 0.08)
for az in (0.3, 2.0):
	c.poly([(-4.5, az - 0.32), (-5.25, az), (-4.5, az + 0.32), (-4.5, az + 0.12), (-3.6, az + 0.12), (-3.6, az - 0.12), (-4.5, az - 0.12)])
yellow = c.get() * deck

c = Canvas()  # hazard bands: the bin bay on three sides, and the quay's edge all the way round
BAY = (-9.9, -3.5, -5.7, 4.2)
bw = 0.24
c.rect(BAY[0], BAY[1], BAY[2], BAY[1] + bw)
c.rect(BAY[0], BAY[3] - bw, BAY[2], BAY[3])
c.rect(BAY[2] - bw, BAY[1], BAY[2], BAY[3])
e0, e1 = 9.42, 9.72
c.rect(-e1, -e1, e1, -e0)
c.rect(-e1, e0, e1, e1)
c.rect(-e1, -e1, -e0, e1)
c.rect(e0, -e1, e1, e1)
c.rect(-PAD["ramp_half"], -e1 - 0.02, PAD["ramp_half"], -e0 + 0.02, 0)  # open at the way out
hazard = c.get() * deck
stripe = (np.mod((X + Z) * 2.2, 1.0) < 0.5).astype(np.float32)

edge_wear = (1.0 - sm(0.02, 0.1, gap_d)) * (0.35 + 0.65 * n_mid)
mark_wear = np.clip(traffic * 1.1 + (n_mid - 0.5) * 1.0 + (n_fine - 0.5) * 0.7 + edge_wear * 0.4 + crack_soft * 0.8 + (n_big - 0.5) * 0.5, 0, 1)
mark_keep = (1.0 - sm(0.36, 0.58, mark_wear * 0.8 + (vnoise(160, 160, 515) - 0.5) * 0.45 + 0.08)) * (1.0 - scratch) * (1.0 - gap) * (1.0 - patch) * (1.0 - plate)
mark_keep *= 0.7 + 0.3 * n_speck  # paint sits on the high grains only
white *= mark_keep
yellow *= mark_keep
hazard *= mark_keep * (0.75 + 0.25 * n_mid)

# ---------------------------------------------------------------- scorch, oil, rust, dirt and moss
ang = np.interp((TH + math.pi) / (2 * math.pi) * 96.0, np.arange(97), np.r_[np.random.default_rng(5).random(96), 0.0]).astype(np.float32)
ang2 = np.interp((TH + math.pi) / (2 * math.pi) * 31.0, np.arange(32), np.r_[np.random.default_rng(6).random(31), 0.0]).astype(np.float32)
radial = 0.35 + 0.65 * (0.6 * ang + 0.4 * ang2)
soot = sm(0.3, 1.3, RC) * (1.0 - sm(1.6, 4.3 * (0.6 + 0.5 * radial), RC)) * (0.45 + 0.55 * n_mid) * radial
soot = np.clip(soot * 1.2, 0, 1) * deck
pod_soot = (1.0 - sm(0.8, 3.4, np.hypot(X - 0.0, Z - 9.8))) * (0.3 + 0.7 * n_mid) * 0.7
soot = np.maximum(soot, pod_soot * (EDGE < PAD["kerb_in"]))
bleach = (1.0 - sm(0.0, 1.0, RC)) * 0.6  # heat-bleached concrete right under the engine

c = Canvas()
for (ox, oz, r) in [(-6.3, 6.4, 0.38), (-6.0, 6.9, 0.2), (-6.2, 1.0, 0.33), (-5.9, -2.2, 0.26), (6.4, 6.6, 0.3), (1.1, -5.9, 0.24), (-0.8, -7.4, 0.2), (3.1, 1.2, 0.17)]:
	c.dot(ox, oz, r)
oil = blur(c.get(), 0.1) * sm(0.25, 0.6, n_mid + n_fine * 0.4) * 1.3
oil = np.clip(oil, 0, 1) * deck

iron = np.clip(cup + cup_rim + plate, 0, 1)
rust_stain = np.clip(blur(iron, 0.14) * 2.2 - iron, 0, 1) * (0.4 + 0.6 * n_mid) * (EDGE < PAD["kerb_in"])
rust_stain = np.maximum(rust_stain, (1.0 - sm(0.0, 0.22, np.abs(kd + 0.15) - 0.15)) * 0.35 * n_mid * (EDGE < PAD["kerb_in"] + 0.02))

drift = (1.0 - sm(0.0, 1.3 * (0.3 + 1.3 * n_big), kd)) * (EDGE < PAD["kerb_in"])
cornerness = sm(6.0, 10.2, np.minimum(np.abs(X), np.abs(Z)))
wind = 0.55 + 0.45 * sm(-10, 10, -X * 0.7 + Z * 0.7)  # the prevailing wind piles it south-west
dirt = drift * (0.5 + 0.5 * cornerness) * wind * 1.15
dirt += (1.0 - sm(0.0, 0.07, gap_d)) * 0.75 * (0.4 + 0.6 * n_mid) * deck
dirt += crack_soft * 0.5 + blur(cup, 0.05) * 0.4
dirt += sm(0.55, 0.85, n_big) * 0.2 + 0.05
dirt += kerb * (0.2 + 0.45 * sm(PAD["kerb_in"] + 0.12, S / 2, EDGE)) * (0.5 + n_mid)
dirt += ramp * 0.3 * (0.5 + n_mid)
dirt -= traffic * 0.3 + tyres * 0.35
dirt = np.clip(dirt * (0.75 + 0.5 * n_fine), 0, 1) * (1.0 - pfresh * 0.4)
moss = np.clip(dirt * 1.6 - 0.55, 0, 1) * sm(0.4, 0.6, vnoise(30, 30, 404)) * (1.0 - sm(0.2, 0.5, traffic))
moss *= 1.0 - dry

# ---------------------------------------------------------------- albedo
def col(r, g, b):
	return np.array([r, g, b], np.float32)


def lay(base, colour, mask):
	return base * (1.0 - mask[..., None]) + colour * mask[..., None]


conc = col(0.2, 0.193, 0.18) * (1.0 + 0.12 * ptone[..., None]) + pfresh[..., None] * col(0.045, 0.045, 0.04)
conc = conc * (0.82 + 0.36 * n_mid[..., None]) * (0.9 + 0.2 * n_big[..., None])
warm = sm(0.35, 0.75, vnoise(9, 9, 88))[..., None]
conc = conc * (1.0 - warm * 0.5) + conc * col(1.1, 1.0, 0.86) * warm * 0.5  # warm and cool regions
agg = sm(0.72, 0.9, n_speck)[..., None]  # aggregate showing where the surface has worn
conc = conc * (1.0 - agg * 0.35) + col(0.36, 0.345, 0.32) * agg * 0.35
conc = conc * (1.0 - 0.14 * sm(0.3, 0.8, traffic)[..., None]) + 0.03 * sm(0.3, 0.8, traffic)[..., None]  # polished by feet
alb = conc
alb = lay(alb, col(0.27, 0.265, 0.25) * (0.9 + 0.2 * n_fine[..., None]), patch * 0.85)
alb = lay(alb, alb * 0.8 + 0.2 * col(0.45, 0.44, 0.41), bleach * deck)
alb = lay(alb, col(0.66, 0.65, 0.6) * (0.85 + 0.3 * n_fine[..., None]), white * 0.92)
alb = lay(alb, col(0.74, 0.52, 0.09) * (0.85 + 0.3 * n_fine[..., None]), yellow * 0.92)
haz_col = np.where(stripe[..., None] > 0.5, col(0.74, 0.52, 0.09), col(0.075, 0.075, 0.08))
alb = lay(alb, haz_col * (0.85 + 0.3 * n_fine[..., None]), hazard * 0.92)

# steel road plates
rust_n = sm(0.35, 0.7, vnoise(50, 50, 91) * 0.6 + n_fine * 0.5)[..., None]
steel = col(0.2, 0.2, 0.21) * (1.0 - rust_n) + col(0.3, 0.16, 0.08) * rust_n
steel = steel * (0.85 + 0.35 * plate_tread[..., None])
alb = lay(alb, steel, plate)
alb = lay(alb, col(0.36, 0.36, 0.38), plate_bolt)

# the drain channel and the kerb stones
iron_col = col(0.11, 0.1, 0.095) * (1.0 - rust_n) + col(0.27, 0.14, 0.07) * rust_n
alb = lay(alb, iron_col * (0.85 + 0.3 * n_fine[..., None]), tray)
kerb_run = np.where(np.abs(X) > np.abs(Z), Z, X)
stone_id = np.floor((kerb_run + 20.0) / 1.1)
stone_tone = (np.mod(np.sin(stone_id * 12.9898 + np.where(np.abs(X) > np.abs(Z), np.sign(X) * 3.1, np.sign(Z) * 7.7)) * 43758.5453, 1.0) - 0.5).astype(np.float32)
stone_joint = (np.mod(kerb_run + 20.0, 1.1) < 0.022).astype(np.float32) * kerb
kerb_col = col(0.3, 0.292, 0.275) * (1.0 + 0.2 * stone_tone[..., None]) * (0.8 + 0.4 * n_mid[..., None]) * (0.92 + 0.16 * n_speck[..., None])
kerb_in_d = EDGE - PAD["kerb_in"]
kerb_haz = (kerb_in_d < 0.19).astype(np.float32) * kerb
kerb_keep = (1.0 - sm(0.36, 0.58, n_mid * 0.7 + n_fine * 0.5 + (1.0 - sm(0.0, 0.04, kerb_in_d)) * 0.35)) * (0.6 + 0.4 * n_speck)
kerb_col = lay(kerb_col, haz_col * (0.85 + 0.3 * n_fine[..., None]), kerb_haz * kerb_keep * 0.93)
alb = lay(alb, kerb_col, kerb)
ramp_col = (0.2 + 0.07 * ramp_rib)[..., None] * col(1.0, 1.0, 1.03) * (0.85 + 0.3 * n_fine[..., None])
ramp_col = ramp_col * (1.0 - rust_n * 0.6) + col(0.3, 0.16, 0.08) * rust_n * 0.6
ramp_edge = (np.abs(X) > PAD["ramp_half"] - 0.22).astype(np.float32)
ramp_col = lay(ramp_col, haz_col * (0.85 + 0.3 * n_fine[..., None]), ramp_edge * (1.0 - sm(0.45, 0.65, n_mid)))
alb = lay(alb, ramp_col, ramp)

# hardware tones
alb = lay(alb, col(0.04, 0.04, 0.045), cup)
alb = lay(alb, col(0.26, 0.17, 0.11), cup_bar)
alb = lay(alb, col(0.2, 0.15, 0.11), cup_rim * 0.9)
alb = lay(alb, col(0.02, 0.02, 0.022), slot)
alb = lay(alb, col(0.05, 0.05, 0.05), plate_break * 0.9)
alb = lay(alb, col(0.13, 0.135, 0.145), light_house)
alb *= (1.0 - 0.45 * seam)[..., None]
alb = lay(alb, col(0.05, 0.048, 0.045), np.clip(crack * 1.1, 0, 1))
alb = lay(alb, col(0.06, 0.055, 0.05), stone_joint)

# use and weather on top
alb = lay(alb, col(0.36, 0.2, 0.1), rust_stain * 0.55)
alb = lay(alb, col(0.04, 0.04, 0.045), np.clip(tyres * 0.6, 0, 1) * (1.0 - gap))
alb = lay(alb, col(0.06, 0.06, 0.062), np.clip(soot * 0.8, 0, 1))
alb = lay(alb, alb * 0.4, oil * 0.85)
alb = lay(alb, col(0.36, 0.35, 0.33), scratch * (1.0 - soot * 0.5) * 0.22)
dirt_col = col(0.15, 0.125, 0.09) * (0.8 + 0.4 * n_fine[..., None])
alb = lay(alb, dirt_col, np.clip(dirt, 0, 0.9))
alb = lay(alb, col(0.1, 0.14, 0.055) * (0.7 + 0.6 * n_fine[..., None]), moss * 0.85)
alb = lay(alb, col(0.03, 0.028, 0.025), gap * (1.0 - 0.4 * dirt))
alb *= (0.94 + 0.12 * n_speck)[..., None]
alb = lay(alb, alb * 0.62, damp * 0.8)  # wet concrete is darker
alb = lay(alb, alb * 0.68 + col(0.016, 0.018, 0.022), puddle)
alb = np.maximum(alb, 0.05)  # nothing on the quay is pure black: night frames crushed (tools/frame_stats.py)

# ---------------------------------------------------------------- height -> normal, occlusion, roughness, metal
h = np.zeros((N, N), np.float32)
h += (n_speck - 0.5) * 0.0016 + (n_fine - 0.5) * 0.003
h += (white + yellow + hazard) * 0.0005
h += patch * 0.002
h -= seam * 0.004
h -= crack * 0.01 + crack_soft * 0.003
h -= cup * 0.024
h += cup_bar * 0.016 + cup_rim * 0.003
h -= slot * 0.02
h -= plate_break * 0.004
h -= light_house * 0.004
h += plate * 0.012 + plate_tread * 0.003 + plate_bolt * 0.006
h += ramp_rib * 0.006
h -= stone_joint * 0.012
h += kerb * (n_mid - 0.5) * 0.01
h -= scratch * 0.001
h += (low - 0.5) * 0.02 * deck  # the dips the water finds
h = h * (1.0 - 0.5 * np.clip(dirt, 0, 1)) + blur(np.clip(dirt, 0, 1), 0.03) * 0.006 + (dirt + moss) * (n_fine - 0.5) * 0.006
h -= gap * 0.03
h = h * (1.0 - puddle) + puddle * float((h * puddle).sum() / max(puddle.sum(), 1.0))  # water lies flat
gy, gx = np.gradient(h, S / N)
k_n = 1.5
nx, ny = -gx * k_n, gy * k_n
nz = np.ones_like(nx)
ln = np.sqrt(nx * nx + ny * ny + nz * nz)
nrm = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5

ao = np.ones((N, N), np.float32)
ao -= blur(cup, 0.02) * 0.75
ao -= blur(gap, 0.035) * 0.6
ao -= seam * 0.2 + slot * 0.75 + blur(slot, 0.02) * 0.2 + crack * 0.5 + stone_joint * 0.5
ao -= (1.0 - sm(0.0, 0.14, kd)) * (EDGE < PAD["kerb_in"]) * 0.4 * (1.0 - ramp)  # under the kerb's inner face
ao -= np.clip(blur(plate, 0.03) - plate, 0, 1) * 0.8
ao = np.clip(ao, 0.12, 1.0)


def lay1(base, v, mask):
	return base * (1.0 - mask) + v * mask


rough = 0.8 + 0.12 * (n_fine - 0.5) + 0.1 * (n_speck - 0.5) - 0.12 * sm(0.3, 0.8, traffic)
metal = np.zeros((N, N), np.float32)
rough = lay1(rough, 0.7, np.clip(white + yellow + hazard, 0, 1))
rough = lay1(rough, 0.55 + 0.25 * rust_n[..., 0], np.clip(plate + tray, 0, 1))
metal = lay1(metal, 0.75 * (1.0 - rust_n[..., 0]), np.clip(plate + tray * (1.0 - slot), 0, 1))
rough = lay1(rough, 0.5, ramp)
metal = lay1(metal, 0.6, ramp * (1.0 - ramp_edge))
rough = lay1(rough, 0.82, np.clip(tyres * 0.6, 0, 1))
rough = lay1(rough, 0.95, np.clip(soot, 0, 1))
rough = lay1(rough, 0.22, oil * 0.8)
rough = lay1(rough, 0.95, np.clip(dirt * 1.1, 0, 1))
rough = lay1(rough, 0.98, moss)
metal = lay1(metal, 0.0, np.clip(dirt * 1.3 + moss, 0, 1))
rough = lay1(rough, 0.34 + 0.2 * (n_fine - 0.5), damp * (1.0 - moss * 0.5))  # damp: a dull sheen
rough = lay1(rough, 0.04, puddle)  # standing water: a mirror
metal = lay1(metal, 0.0, puddle)
rough = lay1(rough, 0.9, np.clip(gap + slot + cup, 0, 1) * (1.0 - puddle))
rough = lay1(rough, 0.4, light_house)
metal = lay1(metal, 0.0, light_house)
print("puddle %.1f%%  damp %.1f%%  marks kept %.0f%%" % (puddle.mean() * 100, damp.mean() * 100, 100 * mark_keep[deck > 0].mean()))


def save(name, arr):
	a = (np.clip(arr, 0, 1) * 255.0 + 0.5).astype(np.uint8)
	Image.fromarray(a, "RGB").save(os.path.join(HERE, name), optimize=True)
	print(name, a.shape, "mean", a.reshape(-1, 3).mean(0).round(1))


save("pad_albedo.png", alb)
save("pad_normal.png", nrm)
save("pad_orm.png", np.stack([ao, np.clip(rough, 0.04, 1.0), metal], -1))

# ---------------------------------------------------------------- the micro tile (periodic: built by FFT)
M = 512
rg = np.random.default_rng(3)
f = np.fft.fftfreq(M)[:, None] ** 2 + np.fft.fftfreq(M)[None, :] ** 2


def spec(seed, lo, hi):
	w = np.random.default_rng(seed).normal(size=(M, M))
	F = np.fft.fft2(w) * ((f > lo * lo) & (f < hi * hi))
	out = np.real(np.fft.ifft2(F))
	return (out / (out.std() + 1e-9)).astype(np.float32)


grit = spec(1, 0.06, 0.35)  # anti-slip grit
soft = spec(2, 0.004, 0.03)
fa = np.fft.fftfreq(M)[:, None]
fb = np.fft.fftfreq(M)[None, :]
wn = np.random.default_rng(8).normal(size=(M, M))
brush = np.real(np.fft.ifft2(np.fft.fft2(wn) * ((np.abs(fa) > 0.05) & (np.abs(fb) < 0.012))))
brush = (brush / brush.std()).astype(np.float32)
hh = grit * 0.55 + soft * 0.6
dy, dx = np.gradient(hh)
dnx, dny = -dx * 0.9, dy * 0.9
dl = np.sqrt(dnx * dnx + dny * dny + 1.0)
det = np.stack([dnx / dl * 0.5 + 0.5, dny / dl * 0.5 + 0.5, np.clip(0.5 + 0.18 * grit + 0.16 * brush, 0, 1), np.clip(0.5 + 0.2 * soft + 0.1 * brush, 0, 1)], -1)
Image.fromarray((np.clip(det, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(HERE, "pad_detail.png"), optimize=True)
print("pad_detail.png", det.shape)

# layout for build_pad.py
import json
json.dump({"pad": PAD, "lights": LIGHTS}, open(os.path.join(HERE, "pad_layout.json"), "w"), indent=1)
