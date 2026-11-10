# Design add-ons for designs.glb (Bolt, Sprout, Pixel, Nova, Patch), to the owner's concept sheet
# (art/concept/lumi_concept.png). exec()'d by build_aurora.py with DESIGNS=1, AFTER the hero is built,
# so every position here comes from the live hero: the head constants (HC, HA, HB, HCZ), the head
# shell's ray-casts (shell_hit / on_shell), the side-module centre (SM_Y, SM_Z), the fin base, the
# torso and chest plate (TW, TD, PL_C, ICON_P) and the shoulder pivot S. Nothing is frozen.
# Same kit, same paint materials and baked vertex colours as the hero; exported to designs.glb so the
# hero mesh is untouched. Pivots: head add-ons use HEAD_P or their own attachment point (PatchModel
# parents them to the head), pads the shoulder pivot, held props the point the claw grips, chest
# icons the plate's icon point.
import random


def leaf(name, length, width, center, material, rot=(0, 0, 0), cup=0.25, curl=0.12, thick=0.005, vein=None):
	"""A leaf blade along +Y: pointed tip, rounded base, cupped across, curling back at the tip.
	vein = a material name adds a raised midrib and side veins on both faces."""
	bm = bmesh.new()
	nu, nv = 18, 8
	grid = []
	for i in range(nu + 1):
		u = i / nu
		w = width * (math.sin(math.pi * min(u * 1.04, 1.0)) ** 0.7) * (1.0 - 0.1 * u) + 0.002
		row = []
		for j in range(nv + 1):
			v = j / nv * 2 - 1
			x = v * w * 0.5
			z = cup * w * v * v - curl * length * u * u - 0.012 * (1 - abs(v)) * 0.3
			row.append(bm.verts.new((x, u * length, z)))
		grid.append(row)
	for i in range(nu):
		for j in range(nv):
			bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	obj = from_bm(bm, name, material)
	md = obj.modifiers.new("sol", 'SOLIDIFY')
	md.thickness = thick
	md.offset = 0.0
	md = obj.modifiers.new("sub", 'SUBSURF')
	md.levels = 1
	apply_mods(obj)
	if vein:
		ribs = [tube(name + "_rib", [(0, u * length, -curl * length * u * u - 0.001) for u in (0.0, 0.25, 0.5, 0.75, 0.96)], thick * 0.62, vein, sides=6, r_end=thick * 0.3)]
		for k, u in enumerate((0.22, 0.4, 0.58, 0.74)):
			w = width * (math.sin(math.pi * min(u * 1.04, 1.0)) ** 0.7) * 0.42
			for sx in (-1, 1):
				ribs.append(tube(name + "_vein", [(0, u * length, -curl * length * u * u), (sx * w * 0.55, (u + 0.07) * length, cup * w * 0.3 - curl * length * (u + 0.07) ** 2),
					(sx * w, (u + 0.12) * length, cup * w - curl * length * (u + 0.12) ** 2)], thick * 0.42, vein, sides=5, r_end=thick * 0.2))
		obj = join(name, [obj] + ribs)
	xform(obj, center, rot)
	return smooth(obj)


def heart_pts(size, n=40):
	out = []
	for i in range(n):
		t = 2 * math.pi * i / n
		x = 16 * math.sin(t) ** 3
		y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
		out.append((x / 34.0 * size, (y + 2.5) / 34.0 * size))
	return list(reversed(out))


def rounded_tri(base, height, r, n=8, apex_x=0.08):
	"""Rounded triangle (cat ear outline), base on y=0, apex up."""
	cs = [(-base * 0.5, 0.0), (base * 0.5, 0.0), (base * apex_x, height)]
	out = []
	for k in range(3):
		p = Vector(cs[k] + (0,))
		a = Vector(cs[k - 1] + (0,))
		b = Vector(cs[(k + 1) % 3] + (0,))
		da = (a - p).normalized()
		db = (b - p).normalized()
		rr = r * (0.55 if k == 2 else 1.0)
		for i in range(n + 1):
			t = i / n
			q = p + da * rr * (1 - t) ** 1.4 + db * rr * t ** 1.4
			out.append((q.x, q.y))
	return out


def ngon(r, n, phase=0.0):
	return [(math.cos(phase + 2 * math.pi * k / n) * r, math.sin(phase + 2 * math.pi * k / n) * r) for k in range(n)]


def blob(name, r, center, normal, material, squash=0.45, rng=None, sub=1):
	"""A lumpy flattened clump (moss), squashed along the surface normal and sunk a little into it."""
	bm = bmesh.new()
	bmesh.ops.create_icosphere(bm, subdivisions=sub + 1, radius=r)
	for v in bm.verts:
		v.co *= 1.0 + (rng.random() - 0.5) * 0.45
	obj = from_bm(bm, name, material)
	n = Vector(normal).normalized()
	q = n.to_track_quat('Z', 'Y').to_matrix().to_4x4()
	obj.data.transform(Matrix.Translation(Vector(center) + n * (r * squash * 0.35)) @ q @ Matrix.Diagonal((1.0, 1.0, squash, 1.0)))
	return smooth(obj)


def crown(x, z):
	"""Point and normal on the head's top surface above (x, z)."""
	return shell_hit((x, 3.0, z), (0, -1, 0))


def side(y, z, s=1):
	"""Point and normal on the head's side surface at (y, z), on the +X (s=1) or -X side."""
	return shell_hit((s * 2.0, y, z), (-s, 0, 0))


def face_out(obj, s):
	"""Turn a part modelled facing -Z (front) to face outward on the +X (s=1) / -X side."""
	obj.data.transform(Matrix.Rotation(math.radians(-90 * s), 4, 'Y'))
	return obj


ACC = {}
RNG = random.Random(7)
SH_L = Vector((-S.x, S.y, S.z))
# The side modules' lens face (build_aurora.py: lathe y 0.05 .. 0.058 along the outward axis).
EAR_X = HA - 0.022 + 0.062
EAR_C = Vector((EAR_X, SM_Y, SM_Z))

# ------------------------------------------------------------------------------------------ SPROUT
# A two-leaf seedling growing from a soil-filled socket where the fin sits on the other designs
# (back of the crown, toward the right side), with two broad veined leaves, and moss grown in thick
# tufts on the crown (a separate, static part: the seedling sways, the moss does not).
p, n = crown(0.12, 0.13)
SPROUT_P = Vector(p) - Vector(n) * 0.004
sp = [
	lathe("sp_socket", [(0.036, 0.012), (0.043, 0.008), (0.045, -0.002), (0.043, -0.02), (0.0, -0.02)], "dark", segs=28),
	torus("sp_socket_rim", 0.04, 0.0048, (0, 0.01, 0), "steel", major=28, minor=6),
	lathe("sp_soil", [(0.0, 0.017), (0.022, 0.016), (0.036, 0.011), (0.038, 0.006)], "moss", segs=24),
	tube("sp_stem", [(0, 0.008, 0), (0.007, 0.035, 0.004), (-0.003, 0.065, 0.0), (0.0, 0.092, -0.004)], 0.0095, "leaf", sides=10, r_end=0.0065),
	leaf("sp_leaf_a", 0.25, 0.135, (0.002, 0.088, -0.004), "leaf", rot=(32, 18, -70), cup=0.2, curl=0.09, thick=0.006, vein="leaf_vein"),
	leaf("sp_leaf_b", 0.215, 0.12, (-0.002, 0.09, -0.004), "leaf", rot=(26, -22, 38), cup=0.2, curl=0.07, thick=0.006, vein="leaf_vein"),
]
for k in range(7):
	a = 2 * math.pi * k / 7 + 0.3
	sp.append(blob("sp_clump", 0.013, (math.cos(a) * 0.032, 0.014, math.sin(a) * 0.032), (0, 1, 0), "moss", squash=0.6, rng=RNG, sub=0))
for o in sp:
	o.data.transform(Matrix.Translation(SPROUT_P))
ACC["acc_sprout"] = (join("acc_sprout", sp), SPROUT_P)


def moss_patch(cx, cz, sx, sz, count, r0=0.011, r1=0.017):
	"""A dense tuft: overlapping lumpy clumps, thickest in the middle, thinning at the rim."""
	out = []
	for _k in range(count):
		gx, gz = RNG.gauss(0, 1), RNG.gauss(0, 1)
		q, qn = crown(cx + gx * sx, cz + gz * sz)
		if q is None or qn.y < 0.3:
			continue
		fall = math.exp(-(gx * gx + gz * gz) * 0.35)
		r = (r0 + RNG.random() ** 2 * r1) * (0.55 + 0.6 * fall)
		out.append(blob("moss_clump", r, q - qn * 0.002, qn, "moss", squash=0.42 + 0.3 * fall, rng=RNG, sub=1 if r > 0.016 else 0))
	return out


# The sheet: one thick tuft on the crown's front left, a little round the seedling, a wisp on the right edge.
moss = moss_patch(-0.17, -0.1, 0.085, 0.05, 130) + moss_patch(0.12, 0.13, 0.05, 0.04, 40, 0.008, 0.012) + moss_patch(0.31, -0.03, 0.025, 0.06, 26, 0.007, 0.011)
ACC["acc_moss"] = (join("acc_moss", moss), HEAD_P)

# Chest icon: a tall leaf and a smaller one sprouting from a short stem (the sheet's eco plate).
ic = [
	leaf("ic_leaf_r", 0.088, 0.058, (0.004, -0.036, 0.0), "glow", rot=(0, 0, 20), cup=0.0, curl=0.0, thick=0.006),
	leaf("ic_leaf_l", 0.064, 0.046, (0.0, -0.034, 0.0), "glow", rot=(0, 0, -52), cup=0.0, curl=0.0, thick=0.006),
	rbox("ic_stem", (0.008, 0.026, 0.006), (0.002, -0.044, 0), 0.002, "glow", sub=0, segs=1),
]
for o in ic:
	o.data.transform(Matrix.Scale(0.5, 4, Vector((0, 0, 1))))
	o.data.transform(Matrix.Translation(ICON_P + Vector((0, 0.004, -0.001))))
ACC["acc_icon_leaf"] = (join("acc_icon_leaf", ic), ICON_P)

# Ear emblems: a small glowing sign on each side lens.
def ear_emblem(name, parts_fn):
	out = []
	for s_ in (1, -1):
		parts = parts_fn()
		o = join(name + ("_r" if s_ > 0 else "_l"), parts)
		face_out(o, s_)
		o.data.transform(Matrix.Translation(Vector((s_ * EAR_X, SM_Y, SM_Z))))
		out.append(o)
	return join(name, out)


def _leaf_emblem():
	a = leaf("el_leaf", 0.092, 0.06, (0, -0.044, -0.006), "glow", rot=(0, 0, -20), cup=0.0, curl=0.0, thick=0.012)
	return [a, tube("el_vein", [(0.01, -0.036, -0.013), (-0.002, 0.0, -0.013), (-0.015, 0.036, -0.013)], 0.0022, "dark", sides=5)]


ACC["acc_ear_leaf"] = (ear_emblem("acc_ear_leaf", _leaf_emblem), HEAD_P)

# Plastic bottle held in the left claw (origin = the grip, round its lower third), with three
# glowing pickup-beam bands round it (the sheet's green beam).
bt = [
	lathe("bt_body", [(0.0, 0.13), (0.012, 0.13), (0.016, 0.115), (0.02, 0.1), (0.036, 0.075), (0.05, 0.05), (0.052, 0.03), (0.047, 0.02),
		(0.052, 0.008), (0.047, -0.004), (0.052, -0.016), (0.047, -0.03), (0.052, -0.044), (0.052, -0.09), (0.048, -0.1), (0.04, -0.106), (0.0, -0.103)], "bottle", segs=40),
	lathe("bt_cap", [(0.0, 0.158), (0.016, 0.158), (0.018, 0.152), (0.018, 0.132), (0.014, 0.13), (0.0, 0.13)], "bottle_cap", segs=24),
	torus("bt_ring", 0.0185, 0.003, (0, 0.127, 0), "bottle_cap", major=24, minor=6),
]
for k, (y, tilt) in enumerate(((-0.055, 8), (-0.005, -6), (0.045, 10))):
	r = torus("bt_beam", 0.062 - k * 0.002, 0.0036, (0, 0, 0), "glow", major=56, minor=8)
	xform(r, (0, y, 0), (tilt, 0, tilt * 0.6))
	bt.append(r)
bottle = join("acc_bottle", bt)
bottle.data.transform(Matrix.Translation(Vector((0, 0.07, 0))) @ Matrix.Scale(1.9, 4))
ACC["acc_bottle"] = (bottle, Vector((0, 0, 0)))


# --------------------------------------------------------------------------------------------- NOVA
# Cat-ear fins on the head's top corners, leaning out and turned to face outward a little, each a
# thick shell with a recessed dark panel edged by a glowing violet V, in a dark collar on the shell.
ears = []
for s_ in (-1, 1):
	x0 = s_ * 0.275
	p, n = crown(x0, 0.01)
	c = Vector((x0, p.y - 0.055, 0.01))
	rot = (5, s_ * -24, s_ * -21)
	ax = s_ * -0.1
	# Modelled upright at the origin (front face at z = -0.035), then turned and moved as one.
	ear = [
		prism("cat_ear", rounded_tri(0.29, 0.34, 0.05, apex_x=ax), 0.074, (0, 0, 0), "paint", bevel=0.019, segs=3, sub=1),
		prism("cat_ear_rim", rounded_tri(0.215, 0.26, 0.036, apex_x=ax), 0.01, (0, 0.016, -0.036), "dark", bevel=0.003, segs=2, sub=1),
		prism("cat_ear_in", rounded_tri(0.175, 0.215, 0.03, apex_x=ax), 0.01, (0, 0.032, -0.041), "glow", bevel=0.003, segs=2, sub=1),
		prism("cat_ear_core", rounded_tri(0.118, 0.15, 0.022, apex_x=ax), 0.01, (0, 0.05, -0.0445), "trim", bevel=0.003, segs=2, sub=1),
	]
	for o in ear:
		xform(o, c, rot)
	ears += ear
	ears.append(lathe("cat_ear_collar", [(0.0, 0.03), (0.115, 0.03), (0.13, 0.018), (0.136, -0.012), (0.0, -0.012)], "dark", segs=40, center=(x0, p.y - 0.04, 0.01)))
	for dz in (-0.085, 0.1):
		q, qn = crown(x0 - s_ * 0.085, dz)
		if q is not None:
			ears.append(screw(q, qn, r=0.006))
ACC["acc_catears"] = (join("acc_catears", ears), HEAD_P)

# Seam glow: light lines lying in the head's panel grooves (the ring behind the side modules and
# the crown panel), so the dark shell reads as lit from inside.
seams = []
ring = []
for k in range(41):
	t = math.pi * (-0.2 + 1.4 * k / 40)
	q, qn = shell_hit((math.cos(t) * 2.0, HC + math.sin(t) * 2.0, 0.15), (-math.cos(t), -math.sin(t), 0))
	if q is not None:
		ring.append(q + qn * 0.0005)
seams.append(tube("seam_ring", ring, 0.005, "glow", sides=5))
for s_ in (-1, 1):
	line = []
	for k in range(15):
		q, qn = crown(s_ * 0.165, -0.085 + 0.225 * k / 14)
		line.append(q + qn * 0.0005)
	seams.append(tube("seam_crown", line, 0.0048, "glow", sides=6))
line = []
for k in range(13):
	q, qn = crown(-0.165 + 0.33 * k / 12, -0.09)
	line.append(q + qn * 0.0005)
seams.append(tube("seam_crown_f", line, 0.0048, "glow", sides=6))
ACC["acc_seams"] = (join("acc_seams", seams), HEAD_P)

# Holographic data panel (origin = its centre, facing -Z): a light frame, a faint pane, the
# recycling sign, a rising bar chart, text lines and a small status ring.
HW_, HH_ = 0.23, 0.175
frame = []
for (cx, cy, a0) in ((HW_ - 0.03, -HH_ + 0.03, -90), (HW_ - 0.03, HH_ - 0.03, 0), (-HW_ + 0.03, HH_ - 0.03, 90), (-HW_ + 0.03, -HH_ + 0.03, 180)):
	for k in range(8):
		a = math.radians(a0 + 90 * k / 8)
		frame.append((cx + math.cos(a) * 0.03, cy + math.sin(a) * 0.03, 0.0))
holo = [
	loop_tube("holo_frame", frame, 0.0034, "holo", sides=6),
	rbox("holo_pane", (HW_ * 2 - 0.01, HH_ * 2 - 0.01, 0.001), (0, 0, 0.001), 0.0, "holo_fill", sub=0),
	recycle_icon("holo_icon", 0.15, (-0.035, 0.035, -0.002), "holo"),
	torus("holo_ring", 0.02, 0.0035, (0.165, 0.125, -0.002), "holo", axis='Z', major=24, minor=6),
	rbox("holo_head", (0.1, 0.01, 0.002), (0.085, 0.125, -0.002), 0.0, "holo", sub=0),
	rbox("holo_base", (0.19, 0.004, 0.002), (0.1, -0.132, -0.002), 0.0, "holo", sub=0),
]
for k, h in enumerate((0.03, 0.045, 0.04, 0.07, 0.095, 0.125)):
	holo.append(rbox("holo_bar", (0.02, h, 0.002), (0.02 + k * 0.03, -0.128 + h * 0.5, -0.002), 0.0, "holo", sub=0))
for k, ln in enumerate((0.1, 0.075, 0.09, 0.06, 0.085, 0.05, 0.07)):
	holo.append(rbox("holo_line", (ln, 0.006, 0.002), (0.2 - 0.105 + ln * 0.5 - 0.02, 0.085 - k * 0.019, -0.002), 0.0, "holo", sub=0))
for k, ln in enumerate((0.12, 0.09, 0.11)):
	holo.append(rbox("holo_line", (ln, 0.006, 0.002), (-0.2 + ln * 0.5, -0.09 - k * 0.019, -0.002), 0.0, "holo", sub=0))
ACC["acc_holo"] = (join("acc_holo", holo), Vector((0, 0, 0)))


# -------------------------------------------------------------------------------------------- PIXEL
# Wing fins on the head's upper sides (the sheet's portrait): broad, thick blades that reach out,
# up a little and back past the head, the tip drooping, red with a cream flash along the top, each
# on a faired root; and (a separate piece) a cream lower head.
WING = [(-0.06, -0.08), (0.08, -0.1), (0.2, -0.092), (0.3, -0.05), (0.35, 0.014), (0.325, 0.07), (0.22, 0.094), (0.08, 0.096), (-0.06, 0.082)]
FLASH = [(0.03, -0.036), (0.19, -0.04), (0.285, -0.012), (0.292, 0.022), (0.2, 0.042), (0.03, 0.036)]


def wing_blade(name, pts, thick, material, bevel, sub):
	"""Outline in (out, back) with the thickness up; thinner and drooping toward the tip."""
	o = prism(name, pts, thick, (0, 0, 0), material, bevel=bevel, segs=3, sub=sub)
	for v in o.data.vertices:
		t = min(max(v.co.x / 0.34, 0.0), 1.0)
		v.co.z *= 1.0 - 0.5 * t
		v.co.z += 0.05 * t * t
	o.data.transform(Matrix.Rotation(math.radians(90), 4, 'X'))
	return o


wings = []
for s_ in (-1, 1):
	p, n = crown(s_ * 0.325, 0.03)
	root = Vector((s_ * 0.325, p.y - 0.04, 0.03))
	# Rolled forward so the broad top face (and its flash) shows from the front, not just an edge.
	rot = (-42, s_ * -26, s_ * 16)
	blade = wing_blade("wing_fin", WING, 0.074, "paint", 0.02, 1)
	flash = wing_blade("wing_flash", FLASH, 0.082, "accent", 0.004, 0)
	fair = rbox("wing_root", (0.11, 0.075, 0.2), (0.0, -0.005, 0.005), 0.03, "paint", segs=3, sub=1)
	lip = rbox("wing_root_lip", (0.125, 0.02, 0.215), (0.0, -0.04, 0.005), 0.008, "trim", segs=2, sub=1)
	for o in (blade, flash, fair, lip):
		if s_ < 0:
			o.data.transform(Matrix.Scale(-1, 4, Vector((1, 0, 0))))
			o.data.flip_normals()
		xform(o, root, rot)
	wings += [blade, flash, fair, lip]
	for dz in (-0.1, 0.14):
		q, qn = crown(s_ * 0.24, dz)
		if q is not None:
			wings.append(screw(q, qn, r=0.006))
ACC["acc_pixel"] = (join("acc_pixel", wings), HEAD_P)

# Cream lower head: the shell below the cap, pushed out 4 mm and given a 3 mm thickness.
band = capsule("pixel_band", "accent", nu=56, nv=112)
CAP_Y = HC + 0.11
bm = bmesh.new()
bm.from_mesh(band.data)
bm.normal_update()
kill = []
for f in bm.faces:
	c = f.calc_center_median()
	if c.y > CAP_Y + 0.02 * math.cos(math.atan2(c.x, -c.z)):
		kill.append(f)
		continue
	if c.z < 0:
		g = 0.018
		ox, oy = abs(c.x) / (VA + g), abs(c.y - VCY) / (VB + g)
		if ox ** VN + oy ** VN < 1.0:
			kill.append(f)
			continue
	if abs(c.x) < 0.24 and c.y < HC - HB + 0.12 and c.z > -0.07:   # neck opening (build_aurora neck_cut)
		kill.append(f)
		continue
	if abs(c.x) < 0.27 and abs(c.y - (HC + 0.15)) < 0.07 and c.z > 0.1:  # back vent slot
		kill.append(f)
bmesh.ops.delete(bm, geom=kill, context='FACES')
for v in bm.verts:
	v.co += v.normal * 0.004
bm.to_mesh(band.data)
bm.free()
md = band.modifiers.new("sol", 'SOLIDIFY')
md.thickness = 0.003
md.offset = 1.0
apply_mods(band)
smooth(band)
band.name = "acc_twotone"
ACC["acc_twotone"] = (band, HEAD_P)


def _heart_emblem():
	return [prism("el_heart", heart_pts(0.1), 0.012, (0, -0.005, 0), "glow", bevel=0.004, segs=2, sub=1)]


ACC["acc_ear_heart"] = (ear_emblem("acc_ear_heart", _heart_emblem), HEAD_P)

# Chest icon: a heart filling the plate.
ACC["acc_icon_heart"] = (prism("acc_icon_heart", heart_pts(0.135), 0.008, ICON_P + Vector((0, 0.002, 0)), "glow", bevel=0.003, segs=2, sub=1), ICON_P)

# Butterfly companion (Pixel): one wing (PatchModel mirrors and flaps it) and a body.
w_pts = [(0.0, 0.0)]
for i in range(41):
	t = -math.pi * 0.5 + math.pi * i / 40
	fore = t > -0.15
	r = (0.062 * (0.75 + 0.25 * math.sin((t + 0.15) * 2.0)) if fore else 0.045 * (0.8 + 0.2 * math.cos(t * 2.0)))
	w_pts.append((math.cos(t) * r + 0.003, math.sin(t) * r))
ACC["acc_wing"] = (prism("acc_wing", w_pts, 0.0025, (0, 0, 0), "wing", bevel=0.0, sub=0, rot=(90, 0, 0)), Vector((0, 0, 0)))
ACC["acc_bfly_body"] = (join("acc_bfly_body", [
	rbox("bf_body", (0.012, 0.012, 0.05), (0, 0, 0), 0.0059, "dark", sub=1),
	tube("bf_ant", [(-0.003, 0.0, -0.024), (-0.008, 0.012, -0.04), (-0.012, 0.016, -0.046)], 0.0012, "dark", sides=5),
	tube("bf_ant", [(0.003, 0.0, -0.024), (0.008, 0.012, -0.04), (0.012, 0.016, -0.046)], 0.0012, "dark", sides=5),
]), Vector((0, 0, 0)))


# --------------------------------------------------------------------------------------------- BOLT
# Chunky hazard shoulder pads (pivot = shoulder): a big armour block over the shoulder with dark
# recessed panels on its outer and front faces, an amber hex-nut emblem, steel bolts and a dark lip.
def pad(name):
	c = S + Vector((0.105, 0.03, 0.0))
	rot = (0, 0, -10)
	parts = [
		rbox("pad_shell", (0.19, 0.215, 0.27), c, 0.04, "paint", segs=4, sub=2, rot=rot),
		rbox("pad_lip", (0.196, 0.034, 0.276), c + Vector((0.004, -0.105, 0)), 0.013, "trim", segs=2, sub=1, rot=rot),
		rbox("pad_top", (0.12, 0.012, 0.19), c + Vector((-0.018, 0.106, 0)), 0.005, "trim", segs=2, sub=1, rot=rot),
	]
	fx = c + Vector((0.096, 0.012, 0.0))
	parts.append(rbox("pad_face", (0.012, 0.15, 0.2), fx + Vector((-0.002, 0.004, 0.0)), 0.014, "trim", segs=2, sub=1, rot=rot))
	parts.append(rbox("pad_badge", (0.012, 0.09, 0.09), fx + Vector((0.003, 0.004, 0.0)), 0.014, "dark", segs=2, sub=1, rot=rot))
	nut = prism("pad_nut", ngon(0.03, 6, math.pi / 6), 0.008, (0, 0, 0), "lamp_accent", bevel=0.002, segs=1, sub=0)
	boolean(nut, cyl("nut_hole", 0.013, 0.04, (0, 0, 0), "lamp_accent", axis='Z', verts=20))
	face_out(nut, 1)
	xform(nut, fx + Vector((0.01, 0.004, 0.0)), rot)
	parts.append(nut)
	for y in (0.066, -0.058):
		for z in (-0.085, 0.085):
			parts.append(cyl("pad_bolt", 0.009, 0.012, fx + Vector((0.004, y + 0.004, z)), "steel", axis='X', verts=12, bevel=0.003, rot=(0, 90, rot[2])))
	# Front face: a dark inset with two steel bolts (the face the player sees most).
	ff = c + Vector((0.0, 0.008, -0.136))
	parts.append(rbox("pad_front", (0.13, 0.14, 0.012), ff, 0.012, "trim", segs=2, sub=1, rot=rot))
	parts.append(rbox("pad_front_slot", (0.085, 0.022, 0.012), ff + Vector((0, 0.03, -0.003)), 0.006, "dark", segs=2, sub=0, rot=rot))
	parts.append(rbox("pad_front_lamp", (0.05, 0.014, 0.012), ff + Vector((0, -0.03, -0.003)), 0.005, "lamp_accent", segs=2, sub=0, rot=rot))
	return join(name, parts)


ACC["acc_pad_r"] = (pad("acc_pad_r"), S)
ACC["acc_pad_l"] = (mirror_x(ACC["acc_pad_r"][0], "acc_pad_l"), SH_L)


def _nut_emblem():
	# A square armoured bezel over the round lens (paint frame, dark face) carrying an amber hex nut.
	o = prism("el_nut", ngon(0.046, 6, math.pi / 6), 0.012, (0, 0, -0.016), "lamp_accent", bevel=0.003, segs=2, sub=0)
	boolean(o, cyl("el_nut_hole", 0.021, 0.06, (0, 0, -0.016), "lamp_accent", axis='Z', verts=24))
	return [o, torus("el_nut_ring", 0.021, 0.0035, (0, 0, -0.018), "dark", axis='Z', major=24, minor=6),
		rbox("el_bezel", (0.275, 0.275, 0.04), (0, 0, 0.014), 0.055, "paint", segs=3, sub=1),
		rbox("el_bezel_face", (0.2, 0.2, 0.02), (0, 0, -0.004), 0.04, "trim", segs=3, sub=1),
		rbox("el_bezel_core", (0.135, 0.135, 0.02), (0, 0, -0.009), 0.03, "dark", segs=3, sub=1)] + [
		screw((sx * 0.112, sy * 0.112, -0.006), (0, 0, -1), r=0.007) for sx in (-1, 1) for sy in (-1, 1)]


ACC["acc_ear_nut"] = (ear_emblem("acc_ear_nut", _nut_emblem), HEAD_P)

# Dark panels (hazard pattern): a black plate over the crown and a strip down the back of the head.
dp = capsule("panels_dark", "cable", nu=56, nv=112)   # the matte black rubberised paint of the cable sleeves
bm = bmesh.new()
bm.from_mesh(dp.data)
bm.normal_update()
kill = []
for f in bm.faces:
	c = f.calc_center_median()
	crown_p = abs(c.x) < 0.158 and -0.2 < c.z < 0.1 and c.y > HC
	side_p = 0.2 < abs(c.x) < 0.3 and -0.17 < c.z < 0.1 and c.y > HC + HB * 0.55
	if not (crown_p or side_p):
		kill.append(f)
bmesh.ops.delete(bm, geom=kill, context='FACES')
for v in bm.verts:
	v.co += v.normal * 0.003
bm.to_mesh(dp.data)
bm.free()
md = dp.modifiers.new("sol", 'SOLIDIFY')
md.thickness = 0.004
md.offset = 1.0
apply_mods(dp)
smooth(dp)
dp.name = "acc_panels"
ACC["acc_panels"] = (dp, HEAD_P)

# A big rusty ring gear (held in the left claw by its rim; origin = the grip point on the rim).
g_pts = []
TEETH = 14
G_R = 0.118
for k in range(TEETH):
	a0 = 2 * math.pi * k / TEETH
	for (da, r) in ((-0.5, G_R), (-0.3, G_R + 0.03), (0.3, G_R + 0.03), (0.5, G_R)):
		a = a0 + da * 2 * math.pi / TEETH / 2
		g_pts.append((math.cos(a) * r, math.sin(a) * r))
gear = prism("gear", g_pts, 0.04, (0, 0, 0), "rust", bevel=0.006, segs=2, sub=0)
gear.data.use_auto_smooth = True
boolean(gear, cyl("gear_bore", 0.062, 0.08, (0, 0, 0), "rust", axis='Z', verts=40))
gear = join("acc_gear", [gear, torus("gear_lip", 0.07, 0.008, (0, 0, 0.02), "rust", axis='Z', major=40, minor=6),
	torus("gear_lip_b", 0.07, 0.008, (0, 0, -0.02), "rust", axis='Z', major=40, minor=6)])
gear.data.transform(Matrix.Scale(1.15, 4) @ Matrix.Translation(Vector((0, G_R * 0.78, 0))))
ACC["acc_gear"] = (gear, Vector((0, 0, 0)))


# -------------------------------------------------------------------------------------------- PATCH
# Medic satchel behind the right arm (origin = its centre): a rounded orange bag turned to face
# front-right, with a dark strap band, a flap, a cream patch carrying an orange cross, a side
# pocket, steel buckles, a top bracket and a strap up to the back.
TB = Vector((TW * 0.5 + 0.15, 0.37, 0.17))
tb = [
	rbox("tb_bag", (0.14, 0.26, 0.23), (0, 0, 0), 0.05, "accent", segs=3, sub=2),
	rbox("tb_flap", (0.148, 0.07, 0.236), (0.002, 0.095, 0), 0.024, "accent", segs=3, sub=1),
	rbox("tb_band", (0.15, 0.03, 0.238), (0.002, 0.052, 0), 0.008, "trim", sub=1, segs=2),
	rbox("tb_pocket", (0.05, 0.11, 0.1), (0.0, -0.04, 0.125), 0.016, "accent", segs=2, sub=1),
	rbox("tb_cross_h", (0.014, 0.032, 0.1), (0.068, -0.035, 0), 0.004, "decal", sub=0, segs=1),
	rbox("tb_cross_v", (0.014, 0.1, 0.032), (0.068, -0.035, 0), 0.004, "decal", sub=0, segs=1),
	rbox("tb_bracket", (0.07, 0.03, 0.13), (0.0, 0.14, 0), 0.01, "trim", sub=1, segs=2),
	cyl("tb_pin", 0.012, 0.16, (0.0, 0.15, 0), "steel", axis='Z', verts=12, bevel=0.003),
]
for z in (-0.07, 0.07):
	tb.append(rbox("tb_buckle", (0.012, 0.04, 0.028), (0.074, 0.052, z), 0.004, "steel", sub=0, segs=1))
for o in tb:
	xform(o, TB, (0, 32, 0))
tb.append(tube("tb_strap", [TB + Vector((-0.02, 0.15, -0.02)), Vector((TW * 0.5 + 0.03, 0.555, 0.12)), Vector((TW * 0.5 - 0.09, 0.575, 0.15))], 0.011, "trim", sides=8))
ACC["acc_toolbox"] = (join("acc_toolbox", tb), TB)

# Carry case (left claw grips the handle; origin = the handle's grip point): a weathered orange
# box with a lid seam, dark corner guards, steel latches and a white recycling emblem.
case = [
	rbox("cs_body", (0.27, 0.19, 0.12), (0, -0.135, 0), 0.022, "case", segs=3, sub=2),
	rbox("cs_lid", (0.275, 0.05, 0.125), (0, -0.06, 0), 0.02, "case", segs=3, sub=1),
	rbox("cs_seam", (0.277, 0.008, 0.127), (0, -0.087, 0), 0.003, "trim", sub=0, segs=1),
	tube("cs_handle", [(-0.06, -0.035, 0), (-0.05, 0.0, 0), (0.05, 0.0, 0), (0.06, -0.035, 0)], 0.01, "steel", sides=10),
]
for x in (-0.135, 0.135):
	for y in (-0.05, -0.225):
		case.append(rbox("cs_corner", (0.03, 0.03, 0.13), (x * 0.97, y, 0), 0.008, "trim", sub=1, segs=2))
	case.append(rbox("cs_latch", (0.026, 0.034, 0.012), (x * 0.62, -0.085, -0.063), 0.004, "steel", sub=0, segs=1))
	case.append(rbox("cs_hinge", (0.02, 0.014, 0.02), (x * 0.45, -0.036, 0), 0.004, "steel", sub=0, segs=1))
for zs in (-1, 1):
	ic = recycle_icon("cs_icon", 0.095, (0, -0.15, zs * 0.0615), "decal")
	if zs > 0:
		ic.data.transform(Matrix.Translation(Vector((0, -0.15, 0.0615))) @ Matrix.Rotation(math.pi, 4, 'Y') @ Matrix.Translation(-Vector((0, -0.15, 0.0615))))
	case.append(ic)
case = join("acc_case", case)
case.data.transform(Matrix.Scale(1.3, 4))
ACC["acc_case"] = (case, Vector((0, 0, 0)))

# Chest icon: the medic cross filling the plate.
ACC["acc_icon_cross"] = (join("acc_icon_cross", [
	rbox("ic_h", (0.11, 0.036, 0.008), ICON_P + Vector((0, 0.004, 0)), 0.005, "glow", sub=1),
	rbox("ic_v", (0.036, 0.11, 0.008), ICON_P + Vector((0, 0.004, 0)), 0.005, "glow", sub=1),
]), ICON_P)

# Field radio clipped to the right side of the head, behind the side module: a dark box with an
# amber display, a speaker grille, a knob, a whip antenna and a steel bracket into the shell.
p, n = side(SM_Y + 0.05, 0.2, 1)
RD = Vector((p.x + 0.048, SM_Y + 0.05, 0.2))
rd = [
	rbox("rd_box", (0.08, 0.16, 0.115), RD, 0.018, "trim", segs=3, sub=1),
	rbox("rd_face", (0.008, 0.13, 0.092), RD + Vector((0.04, 0.0, 0.0)), 0.006, "dark", segs=2, sub=0),
	rbox("rd_screen", (0.006, 0.042, 0.062), RD + Vector((0.043, 0.038, 0.0)), 0.004, "lamp_accent", sub=0, segs=1),
	cyl("rd_knob", 0.013, 0.014, RD + Vector((0.047, -0.042, 0.026)), "steel", axis='X', verts=14, bevel=0.003),
	rbox("rd_bracket", (0.05, 0.03, 0.05), (p.x + 0.008, RD.y, RD.z), 0.008, "steel", sub=0, segs=2),
	cyl("rd_ant_base", 0.009, 0.02, RD + Vector((0.0, 0.088, -0.03)), "dark", verts=12, bevel=0.002),
	tube("rd_antenna", [RD + Vector((0.0, 0.094, -0.03)), RD + Vector((0.004, 0.18, -0.027)), RD + Vector((0.008, 0.24, -0.022))], 0.0028, "steel", sides=6, r_end=0.0018),
	cyl("rd_ant_tip", 0.006, 0.01, RD + Vector((0.008, 0.243, -0.022)), "lamp_accent", verts=10, bevel=0.002),
]
for k in range(4):
	rd.append(rbox("rd_slat", (0.004, 0.007, 0.06), RD + Vector((0.045, -0.014 - k * 0.013, -0.006)), 0.001, "steel", sub=0, segs=1))
ACC["acc_radio"] = (join("acc_radio", rd), HEAD_P)

ACC_OBJS = [o for (o, _p) in ACC.values()]
for name, (o, piv) in ACC.items():
	PARTS[name] = piv
	o.name = name
	o.data.name = name
