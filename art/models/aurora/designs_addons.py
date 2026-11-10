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


def leaf(name, length, width, center, material, rot=(0, 0, 0), cup=0.25, curl=0.12, thick=0.005):
	"""A leaf blade along +Y: pointed tip, rounded base, cupped across, curling back at the tip."""
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
# A two-leaf seedling growing from a soil-filled socket on the crown (instead of the fin), and moss
# grown over the crown's front edge (a separate, static part: the seedling sways, the moss does not).
p, n = crown(0.075, 0.11)
SPROUT_P = Vector(p) - Vector(n) * 0.004
sp = [
	lathe("sp_socket", [(0.034, 0.012), (0.04, 0.008), (0.042, -0.002), (0.04, -0.02), (0.0, -0.02)], "dark", segs=28),
	torus("sp_socket_rim", 0.037, 0.0045, (0, 0.01, 0), "steel", major=28, minor=6),
	lathe("sp_soil", [(0.0, 0.016), (0.02, 0.015), (0.033, 0.011), (0.035, 0.006)], "moss", segs=24),
	tube("sp_stem", [(0, 0.008, 0), (0.004, 0.04, 0.004), (-0.004, 0.08, 0.0), (0.0, 0.112, -0.006)], 0.0075, "leaf", sides=10, r_end=0.005),
	leaf("sp_leaf_a", 0.14, 0.09, (0.0, 0.108, -0.006), "leaf", rot=(-12, 25, -58), cup=0.22, curl=0.1),
	leaf("sp_leaf_b", 0.125, 0.082, (-0.002, 0.104, -0.004), "leaf", rot=(8, -30, 60), cup=0.22, curl=0.1),
	tube("sp_vein_a", [(0.0, 0.11, -0.006), (0.05, 0.14, -0.004), (0.1, 0.165, 0.004)], 0.0016, "moss", sides=5),
	tube("sp_vein_b", [(0.0, 0.106, -0.004), (-0.045, 0.135, -0.002), (-0.09, 0.158, 0.006)], 0.0016, "moss", sides=5),
]
for k in range(7):
	a = 2 * math.pi * k / 7 + 0.3
	sp.append(blob("sp_clump", 0.012, (math.cos(a) * 0.03, 0.014, math.sin(a) * 0.03), (0, 1, 0), "moss", squash=0.6, rng=RNG, sub=0))
for o in sp:
	o.data.transform(Matrix.Translation(SPROUT_P))
ACC["acc_sprout"] = (join("acc_sprout", sp), SPROUT_P)

moss = []
for k in range(240):
	# A soft mat, densest on the crown's front edge and top, thinning toward the back and the sides.
	x = (RNG.random() * 2 - 1) * (0.34 - 0.1 * RNG.random())
	z = -0.29 + RNG.random() ** 1.8 * 0.4
	p, n = crown(x, z)
	if p is None or p.y < HC + HB * 0.6:
		continue
	r = 0.007 + RNG.random() ** 2 * 0.013
	moss.append(blob("moss_clump", r, p - n * 0.0015, n, "moss", squash=0.32, rng=RNG, sub=0))
ACC["acc_moss"] = (join("acc_moss", moss), HEAD_P)

# Chest icon: two leaves sprouting from a short stem (the sheet's eco plate).
ic = [
	leaf("ic_leaf_l", 0.07, 0.05, (0.0, -0.03, 0.0), "glow", rot=(0, 0, 32), cup=0.0, curl=0.0, thick=0.006),
	leaf("ic_leaf_r", 0.07, 0.05, (0.0, -0.03, 0.0), "glow", rot=(0, 0, -32), cup=0.0, curl=0.0, thick=0.006),
	rbox("ic_stem", (0.008, 0.03, 0.006), (0, -0.04, 0), 0.002, "glow", sub=0, segs=1),
]
for o in ic:
	o.data.transform(Matrix.Scale(0.5, 4, Vector((0, 0, 1))))
	o.data.transform(Matrix.Translation(ICON_P + Vector((0, 0.004, -0.001))))
ACC["acc_icon_leaf"] = (join("acc_icon_leaf", ic), ICON_P)

# Ear emblem: a small glowing leaf on each side lens.
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
	a = leaf("el_leaf", 0.075, 0.05, (0, -0.036, 0), "glow", rot=(0, 0, -20), cup=0.0, curl=0.0, thick=0.006)
	a.data.transform(Matrix.Scale(0.4, 4, Vector((0, 0, 1))))
	return [a, tube("el_vein", [(0.008, -0.03, -0.004), (-0.002, 0.0, -0.004), (-0.012, 0.03, -0.004)], 0.0018, "dark", sides=5)]


ACC["acc_ear_leaf"] = (ear_emblem("acc_ear_leaf", _leaf_emblem), HEAD_P)


# --------------------------------------------------------------------------------------------- NOVA
# Cat-ear fins on the head's top corners, tilted out and back a little, each with a glowing violet
# inner panel framed by a dark rim, sitting in a dark collar on the shell.
ears = []
for s_ in (-1, 1):
	x0 = s_ * 0.255
	p, n = crown(x0, 0.0)
	c = Vector((x0, p.y - 0.05, 0.0))
	rot = (6, s_ * -12, s_ * -18)
	ax = s_ * -0.1
	# Modelled upright at the origin (front face at z = -0.031), then turned and moved as one.
	ear = [
		prism("cat_ear", rounded_tri(0.25, 0.29, 0.045, apex_x=ax), 0.066, (0, 0, 0), "paint", bevel=0.017, segs=3, sub=1),
		prism("cat_ear_rim", rounded_tri(0.185, 0.22, 0.032, apex_x=ax), 0.01, (0, 0.014, -0.032), "dark", bevel=0.003, segs=2, sub=1),
		prism("cat_ear_in", rounded_tri(0.145, 0.18, 0.026, apex_x=ax), 0.01, (0, 0.03, -0.037), "glow", bevel=0.003, segs=2, sub=1),
	]
	for o in ear:
		xform(o, c, rot)
	ears += ear
	ears.append(lathe("cat_ear_collar", [(0.0, 0.03), (0.1, 0.03), (0.115, 0.018), (0.12, -0.01), (0.0, -0.01)], "dark", segs=40, center=(x0, p.y - 0.035, 0.0)))
	for dz in (-0.07, 0.07):
		q, qn = crown(x0 + s_ * 0.06, dz)
		if q is not None:
			ears.append(screw(q, qn, r=0.006))
ACC["acc_catears"] = (join("acc_catears", ears), HEAD_P)


# -------------------------------------------------------------------------------------------- PIXEL
# Swept wing fins rising from the head's upper sides (red, with a cream stripe), and a cream lower
# head: a painted panel over the shell below the red cap, open round the visor, neck and vent.
def wing_pts(n=28):
	"""Swept fin outline along +Y (root at y=0): a broad root, a raked leading edge, rounded tip."""
	pts = []
	for i in range(n + 1):
		t = i / n
		y = t * 0.2
		x = 0.055 * (1 - t) ** 0.6 + 0.012 + 0.07 * t * t
		pts.append((x, y))
	for i in range(1, 12):
		a = math.pi * i / 12
		pts.append((0.056 + 0.026 * math.cos(a), 0.2 + math.sin(a) * 0.03))
	for i in range(1, n):
		t = 1 - i / n
		y = t * 0.2
		x = -0.05 * (1 - t) ** 0.8 + 0.03 * t * t
		pts.append((x, y))
	return pts


wings = []
for s_ in (-1, 1):
	x0 = s_ * 0.3
	p, n = crown(x0, 0.06)
	root = Vector((x0, p.y - 0.06, 0.06))
	rot = (30, s_ * 14, s_ * -52)
	f = prism("wing_fin", wing_pts(), 0.034, (0, 0, 0), "paint", bevel=0.012, segs=3, sub=1)
	f.data.transform(Matrix.Scale(1.3, 4))
	for v in f.data.vertices:
		t = min(max(v.co.y / 0.23, 0.0), 1.0)
		v.co.z *= 1.0 - 0.45 * t        # thinner toward the tip
		v.co.z += 0.05 * t * t           # sweeping back
	stripe = prism("wing_stripe", [(0.012, 0.03), (0.034, 0.03), (0.06, 0.19), (0.04, 0.2)], 0.036, (0, 0, 0), "accent", bevel=0.004, segs=2, sub=0)
	stripe.data.transform(Matrix.Scale(1.3, 4))
	for v in stripe.data.vertices:
		t = min(max(v.co.y / 0.23, 0.0), 1.0)
		v.co.z *= 1.0 - 0.45 * t
		v.co.z += 0.05 * t * t
	for o in (f, stripe):
		if s_ < 0:
			o.data.transform(Matrix.Scale(-1, 4, Vector((1, 0, 0))))
			o.data.flip_normals()
		xform(o, root, rot)
	wings += [f, stripe, lathe("wing_root", [(0.0, 0.025), (0.05, 0.025), (0.06, 0.012), (0.062, -0.02), (0.0, -0.02)], "trim", segs=32, center=root + Vector((0, 0.01, 0)))]
	q, qn = crown(x0 * 0.82, 0.12)
	if q is not None:
		wings.append(screw(q, qn, r=0.006))

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
wings.append(band)
ACC["acc_pixel"] = (join("acc_pixel", wings), HEAD_P)


def _heart_emblem():
	return [prism("el_heart", heart_pts(0.1), 0.012, (0, -0.005, 0), "glow", bevel=0.004, segs=2, sub=1)]


ACC["acc_ear_heart"] = (ear_emblem("acc_ear_heart", _heart_emblem), HEAD_P)

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
# Chunky hazard shoulder pads (pivot = shoulder): a yellow armour block over the shoulder cap with a
# dark bevelled frame on its outer face, an amber hex-nut emblem, steel bolts and a dark under-lip.
def pad(name):
	c = S + Vector((0.095, 0.045, 0.0))
	rot = (0, 0, -14)
	parts = [
		rbox("pad_shell", (0.15, 0.2, 0.25), c, 0.045, "paint", segs=4, sub=2, rot=rot),
		rbox("pad_lip", (0.155, 0.032, 0.255), c + Vector((0.004, -0.1, 0)), 0.013, "trim", segs=2, sub=1, rot=rot),
	]
	fx = c + Vector((0.076, 0.016, 0.0))
	for (sz, off) in (((0.012, 0.012, 0.2), (0, 0.075, 0)), ((0.012, 0.012, 0.2), (0, -0.06, 0)), ((0.012, 0.135, 0.012), (0, 0.007, 0.1)), ((0.012, 0.135, 0.012), (0, 0.007, -0.1))):
		parts.append(rbox("pad_frame", sz, fx + Vector(off), 0.004, "trim", sub=0, segs=2, rot=rot))
	parts.append(rbox("pad_badge", (0.01, 0.07, 0.07), fx + Vector((0.002, 0.005, 0.0)), 0.012, "dark", segs=2, sub=1, rot=rot))
	nut = prism("pad_nut", ngon(0.026, 6, math.pi / 6), 0.008, (0, 0, 0), "lamp_accent", bevel=0.002, segs=1, sub=0)
	boolean(nut, cyl("nut_hole", 0.011, 0.04, (0, 0, 0), "lamp_accent", axis='Z', verts=20))
	face_out(nut, 1)
	xform(nut, fx + Vector((0.008, 0.005, 0.0)), rot)
	parts.append(nut)
	for y in (0.06, -0.045):
		for z in (-0.08, 0.08):
			parts.append(cyl("pad_bolt", 0.009, 0.012, fx + Vector((0.005, y, z)), "steel", axis='X', verts=12, bevel=0.003, rot=(0, 90, rot[2])))
	return join(name, parts)


ACC["acc_pad_r"] = (pad("acc_pad_r"), S)
ACC["acc_pad_l"] = (mirror_x(ACC["acc_pad_r"][0], "acc_pad_l"), SH_L)


def _nut_emblem():
	o = prism("el_nut", ngon(0.04, 6, math.pi / 6), 0.01, (0, 0, 0), "lamp_accent", bevel=0.003, segs=2, sub=0)
	boolean(o, cyl("el_nut_hole", 0.018, 0.04, (0, 0, 0), "lamp_accent", axis='Z', verts=24))
	return [o, torus("el_nut_ring", 0.018, 0.003, (0, 0, -0.004), "dark", axis='Z', major=24, minor=6)]


ACC["acc_ear_nut"] = (ear_emblem("acc_ear_nut", _nut_emblem), HEAD_P)

# A big rusty spur gear (held in the left claw by its rim).
g_pts = []
TEETH = 12
for k in range(TEETH):
	a0 = 2 * math.pi * k / TEETH
	for (da, r) in ((-0.42, 0.098), (-0.22, 0.123), (0.22, 0.123), (0.42, 0.098)):
		a = a0 + da * 2 * math.pi / TEETH / 2
		g_pts.append((math.cos(a) * r, math.sin(a) * r))
gear = prism("gear", g_pts, 0.03, (0, 0, 0), "rust", bevel=0.005, segs=2, sub=0)
gear.data.use_auto_smooth = True
for k in range(6):
	a = 2 * math.pi * k / 6
	boolean(gear, cyl("gear_hole", 0.022, 0.06, (math.cos(a) * 0.062, math.sin(a) * 0.062, 0), "rust", axis='Z', verts=20))
boolean(gear, cyl("gear_axle", 0.018, 0.06, (0, 0, 0), "rust", axis='Z', verts=24))
ACC["acc_gear"] = (join("acc_gear", [gear, torus("gear_hub", 0.026, 0.008, (0, 0, 0.015), "rust", axis='Z', major=28, minor=6),
	torus("gear_hub_b", 0.026, 0.008, (0, 0, -0.015), "rust", axis='Z', major=28, minor=6),
	torus("gear_rim", 0.088, 0.005, (0, 0, 0.015), "rust", axis='Z', major=60, minor=6)]), Vector((0, 0, 0)))


# -------------------------------------------------------------------------------------------- PATCH
# Medic satchel on the right hip: a rounded orange bag with a flap, a white cross, a side pocket,
# steel buckles and a strap up over the shoulder.
TB = Vector((TW * 0.5 + 0.07, 0.34, 0.07))
tb = [
	rbox("tb_bag", (0.11, 0.19, 0.24), TB, 0.04, "accent", segs=3, sub=2),
	rbox("tb_flap", (0.116, 0.06, 0.245), TB + Vector((0.002, 0.07, 0)), 0.02, "accent", segs=3, sub=1),
	rbox("tb_flap_edge", (0.118, 0.008, 0.247), TB + Vector((0.002, 0.04, 0)), 0.003, "trim", sub=0, segs=1),
	rbox("tb_pocket", (0.04, 0.1, 0.1), TB + Vector((0.0, -0.025, 0.13)), 0.014, "accent", segs=2, sub=1),
	rbox("tb_cross_h", (0.006, 0.03, 0.095), TB + Vector((0.056, -0.02, 0)), 0.003, "decal", sub=0, segs=1),
	rbox("tb_cross_v", (0.006, 0.095, 0.03), TB + Vector((0.056, -0.02, 0)), 0.003, "decal", sub=0, segs=1),
	tube("tb_strap", [TB + Vector((-0.01, 0.07, -0.08)), Vector((TW * 0.5 + 0.02, 0.52, -0.1)), Vector((TW * 0.5 - 0.06, 0.6, -0.08))], 0.009, "trim", sides=8),
	tube("tb_strap_b", [TB + Vector((-0.01, 0.07, 0.08)), Vector((TW * 0.5 + 0.02, 0.52, 0.12)), Vector((TW * 0.5 - 0.06, 0.6, 0.1))], 0.009, "trim", sides=8),
]
for z in (-0.06, 0.06):
	tb.append(rbox("tb_buckle", (0.01, 0.034, 0.024), TB + Vector((0.058, 0.045, z * 1.2)), 0.003, "steel", sub=0, segs=1))
ACC["acc_toolbox"] = (join("acc_toolbox", tb), TB)

# Carry case (left claw grips the handle; origin = the handle's grip point): weathered rusty-orange
# box with a seam, corner guards, latches and a white recycling emblem.
case = [
	rbox("cs_body", (0.27, 0.19, 0.11), (0, -0.135, 0), 0.022, "case", segs=3, sub=2),
	rbox("cs_lid", (0.275, 0.05, 0.115), (0, -0.06, 0), 0.02, "case", segs=3, sub=1),
	rbox("cs_seam", (0.277, 0.008, 0.117), (0, -0.087, 0), 0.003, "trim", sub=0, segs=1),
	tube("cs_handle", [(-0.06, -0.035, 0), (-0.05, 0.0, 0), (0.05, 0.0, 0), (0.06, -0.035, 0)], 0.01, "trim", sides=10),
]
for x in (-0.135, 0.135):
	for y in (-0.05, -0.225):
		case.append(rbox("cs_corner", (0.03, 0.03, 0.12), (x * 0.97, y, 0), 0.008, "trim", sub=1, segs=2))
	case.append(rbox("cs_latch", (0.026, 0.034, 0.012), (x * 0.62, -0.085, -0.058), 0.004, "steel", sub=0, segs=1))
for zs in (-1, 1):
	ic = recycle_icon("cs_icon", 0.085, (0, -0.15, zs * 0.0565), "decal")
	if zs > 0:
		ic.data.transform(Matrix.Translation(Vector((0, -0.15, 0.0565))) @ Matrix.Rotation(math.pi, 4, 'Y') @ Matrix.Translation(-Vector((0, -0.15, 0.0565))))
	case.append(ic)
ACC["acc_case"] = (join("acc_case", case), Vector((0, 0, 0)))

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

# ------------------------------------------------------------------------------------------- SPROUT
# Plastic bottle held in the left claw (origin = the grip, round its middle), with three glowing
# pickup-beam bands round it (the sheet's green beam).
bt = [
	lathe("bt_body", [(0.0, 0.13), (0.012, 0.13), (0.016, 0.115), (0.02, 0.1), (0.036, 0.075), (0.05, 0.05), (0.052, 0.03), (0.047, 0.02),
		(0.052, 0.008), (0.047, -0.004), (0.052, -0.016), (0.052, -0.09), (0.048, -0.1), (0.04, -0.106), (0.0, -0.103)], "bottle", segs=40),
	lathe("bt_cap", [(0.0, 0.158), (0.016, 0.158), (0.018, 0.152), (0.018, 0.132), (0.014, 0.13), (0.0, 0.13)], "bottle_cap", segs=24),
	torus("bt_ring", 0.0185, 0.003, (0, 0.127, 0), "bottle_cap", major=24, minor=6),
]
for k, (y, tilt) in enumerate(((-0.06, 8), (0.0, -6), (0.06, 10))):
	r = torus("bt_beam", 0.064 - k * 0.002, 0.0045, (0, 0, 0), "glow", major=56, minor=8)
	xform(r, (0, y, 0), (tilt, 0, tilt * 0.6))
	bt.append(r)
ACC["acc_bottle"] = (join("acc_bottle", bt), Vector((0, 0, 0)))

ACC_OBJS = [o for (o, _p) in ACC.values()]
for name, (o, piv) in ACC.items():
	PARTS[name] = piv
	o.name = name
	o.data.name = name
