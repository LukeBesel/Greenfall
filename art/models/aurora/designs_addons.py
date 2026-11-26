# Design add-ons for designs.glb (Bolt, Sprout, Pixel, Nova, Patch), split out of build_aurora.py.
# exec()'d by build_aurora.py only with DESIGNS=1, with the OLD hero constants (HC, S, HEAD_P) so a rebuild
# reproduces the current designs.glb exactly. [hero] These were placed on the previous head; on the new
# Aurora head (taller, side modules) some sit a little off until the designs are reworked.
# ---------------------------------------------------------------- DESIGN ACCESSORIES (designs.glb)
# Signature add-ons for the unlockable designs (PatchModel.VARIANTS "acc"). Same kit, same paint
# materials and baked vertex colours as the hero; exported to designs.glb so the hero mesh is untouched.
# Pivots: head add-ons use their own attachment point (PatchModel parents them to the head),
# pads the shoulder pivot, held props the point the claw grips.


def prism(name, pts, depth, center, material, bevel=0.0, segs=3, sub=1, rot=(0, 0, 0)):
	"""Extrude a 2D outline (XY, counter-clockwise) along Z, centred, then bevel and subdivide."""
	bm = bmesh.new()
	vs = [bm.verts.new((x, y, -depth * 0.5)) for (x, y) in pts]
	f = bm.faces.new(vs)
	ext = bmesh.ops.extrude_face_region(bm, geom=[f])
	bmesh.ops.translate(bm, vec=(0, 0, depth), verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	obj = from_bm(bm, name, material)
	if bevel > 0:
		md = obj.modifiers.new("bev", 'BEVEL')
		md.width = bevel
		md.segments = segs
		md.limit_method = 'ANGLE'
		md.angle_limit = math.radians(30)
	if sub > 0:
		md = obj.modifiers.new("tri", 'TRIANGULATE')
		md.min_vertices = 5
		md = obj.modifiers.new("sub", 'SUBSURF')
		md.levels = sub
	apply_mods(obj)
	xform(obj, center, rot)
	return smooth(obj)


def leaf(name, length, width, center, material, rot=(0, 0, 0), cup=0.25, curl=0.12, thick=0.005):
	"""A leaf blade along +Y: pointed tip, rounded base, cupped across, curling back at the tip."""
	bm = bmesh.new()
	nu, nv = 18, 8
	grid = []
	for i in range(nu + 1):
		u = i / nu
		w = width * (math.sin(math.pi * min(u * 1.08, 1.0)) ** 0.75) * (1.0 - 0.15 * u) + 0.002
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


def rounded_tri(base, height, r, n=8):
	"""Rounded triangle (cat ear outline), base on y=0, apex up."""
	cs = [(-base * 0.5, 0.0), (base * 0.5, 0.0), (base * 0.08, height)]
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


ACC = {}
SH_L = Vector((-S.x, S.y, S.z))

# --- Sprout: a little seedling growing from a moss tuft on the crown.
SPROUT_P = Vector((0.06, HC + 0.245, 0.02))
sp = [
	lathe("sp_tuft", [(0.0, 0.03), (0.04, 0.026), (0.062, 0.012), (0.07, -0.004), (0.0, -0.01)], "moss", segs=24, center=SPROUT_P),
	tube("sp_stem", [SPROUT_P + Vector((0, 0.01, 0)), SPROUT_P + Vector((0.004, 0.06, 0.006)), SPROUT_P + Vector((-0.006, 0.12, 0.0)), SPROUT_P + Vector((0.0, 0.16, -0.004))], 0.0085, "leaf", sides=10, r_end=0.006),
	leaf("sp_leaf_a", 0.15, 0.085, SPROUT_P + Vector((0.0, 0.155, -0.004)), "leaf", rot=(-8, 20, -62)),
	leaf("sp_leaf_b", 0.12, 0.07, SPROUT_P + Vector((-0.004, 0.15, 0.0)), "leaf", rot=(6, -25, 58)),
]
for k in range(5):
	a = 2 * math.pi * k / 5 + 0.4
	sp.append(cyl("sp_moss", 0.018, 0.012, SPROUT_P + Vector((math.cos(a) * 0.05, 0.022, math.sin(a) * 0.05)), "moss", verts=10, bevel=0.005))
ACC["acc_sprout"] = (join("acc_sprout", sp), SPROUT_P)

# --- Nova: cat-ear fins on the head corners, each with a glowing inner panel.
ears = []
for s_ in (-1, 1):
	c = Vector((s_ * 0.255, HC + 0.17, 0.03))
	ears.append(prism("cat_ear", rounded_tri(0.21, 0.24, 0.035), 0.06, c, "paint", bevel=0.018, segs=3, sub=1, rot=(-6, s_ * -18, s_ * -16)))
	ears.append(prism("cat_ear_in", rounded_tri(0.12, 0.15, 0.022), 0.012, c + Vector((s_ * -0.004, 0.035, -0.032)), "glow", bevel=0.004, segs=2, sub=1, rot=(-6, s_ * -18, s_ * -16)))
	ears.append(prism("cat_ear_rim", rounded_tri(0.145, 0.18, 0.026), 0.012, c + Vector((s_ * -0.003, 0.025, -0.027)), "dark", bevel=0.004, segs=2, sub=1, rot=(-6, s_ * -18, s_ * -16)))
ACC["acc_catears"] = (join("acc_catears", ears), HEAD_P)

# --- Pixel: swept wing fins on the crown and heart lenses over the ear hubs.
wings = []
for s_ in (-1, 1):
	f = rbox("wing_fin", (0.03, 0.15, 0.2), (0, 0, 0), 0.014, "accent", segs=2, sub=2)
	for v in f.data.vertices:
		t = min(max((v.co.y + 0.075) / 0.15, 0.0), 1.0)  # 0 root .. 1 tip
		v.co.z *= 1.0 - 0.55 * t
		v.co.z += 0.07 * t * t
		v.co.x *= 1.0 - 0.4 * t
	xform(f, (s_ * 0.27, HC + 0.25, 0.06), (-10, 0, s_ * -38))
	wings.append(f)
	tipc = rbox("wing_tip", (0.028, 0.05, 0.07), (0, 0, 0), 0.012, "paint", sub=1)
	xform(tipc, (s_ * 0.335, HC + 0.31, 0.105), (-10, 0, s_ * -38))
	wings.append(tipc)
	h = prism("heart", heart_pts(0.075), 0.012, (s_ * 0.452, HC - 0.02, 0.05), "glow", bevel=0.004, segs=2, sub=1, rot=(0, s_ * 90, 0))
	wings.append(h)
ACC["acc_pixel"] = (join("acc_pixel", wings), HEAD_P)

# --- Bolt: chunky hazard shoulder pads (pivot = shoulder) and a gear for the claw.
def pad(name):
	parts = [
		rbox("pad_shell", (0.15, 0.075, 0.19), S + Vector((0.055, 0.075, 0.0)), 0.034, "paint", segs=3, sub=2, rot=(0, 0, -22)),
		rbox("pad_band", (0.155, 0.03, 0.195), S + Vector((0.07, 0.05, 0.0)), 0.012, "accent", sub=1, rot=(0, 0, -22)),
	]
	for z in (-0.06, 0.06):
		parts.append(cyl("pad_bolt", 0.012, 0.012, S + Vector((0.035, 0.118, z)), "steel", verts=12, bevel=0.003, rot=(0, 0, -22)))
	return join(name, parts)


ACC["acc_pad_r"] = (pad("acc_pad_r"), S)
ACC["acc_pad_l"] = (mirror_x(ACC["acc_pad_r"][0], "acc_pad_l"), SH_L)

g_pts = []
TEETH = 10
for k in range(TEETH * 4):
	a = 2 * math.pi * k / (TEETH * 4)
	r = 0.085 if (k % 4) in (1, 2) else 0.066
	g_pts.append((math.cos(a) * r, math.sin(a) * r))
gear = prism("gear", g_pts, 0.024, (0, 0, 0), "rust", bevel=0.005, segs=2, sub=0)
gear.data.use_auto_smooth = True
for k in range(5):
	a = 2 * math.pi * k / 5
	boolean(gear, cyl("gear_hole", 0.017, 0.06, (math.cos(a) * 0.042, math.sin(a) * 0.042, 0), "rust", axis='Z', verts=20))
boolean(gear, cyl("gear_axle", 0.014, 0.06, (0, 0, 0), "rust", axis='Z', verts=20))
ACC["acc_gear"] = (join("acc_gear", [gear, torus("gear_hub", 0.022, 0.006, (0, 0, 0.012), "rust", axis='Z', major=24, minor=6)]), Vector((0, 0, 0)))

# --- Patch: hip toolbox on the left flank, a carry case and the medic cross for the chest screen.
TB = Vector((-0.262, 0.29, 0.085))
tb = [
	rbox("tb_box", (0.075, 0.13, 0.17), TB, 0.025, "accent", segs=3, sub=2),
	rbox("tb_lid", (0.08, 0.03, 0.175), TB + Vector((0, 0.06, 0)), 0.012, "dark", sub=1),
	rbox("tb_strap", (0.082, 0.16, 0.022), TB + Vector((0.002, 0.0, 0.045)), 0.008, "dark", sub=1),
	rbox("tb_cross_h", (0.006, 0.022, 0.07), TB + Vector((-0.039, -0.012, -0.03)), 0.003, "paint", sub=1),
	rbox("tb_cross_v", (0.006, 0.07, 0.022), TB + Vector((-0.039, -0.012, -0.03)), 0.003, "paint", sub=1),
	cyl("tb_latch", 0.01, 0.012, TB + Vector((-0.04, 0.035, -0.03)), "steel", axis='X', verts=12, bevel=0.003),
]
ACC["acc_toolbox"] = (join("acc_toolbox", tb), Vector((0, 0, 0)))

case = [
	rbox("cs_body", (0.2, 0.14, 0.075), (0, -0.1, 0), 0.026, "accent", segs=3, sub=2),
	rbox("cs_seam", (0.205, 0.012, 0.08), (0, -0.075, 0), 0.005, "dark", sub=1),
	rbox("cs_cross_h", (0.06, 0.02, 0.006), (0, -0.115, -0.039), 0.003, "paint", sub=1),
	rbox("cs_cross_v", (0.02, 0.06, 0.006), (0, -0.115, -0.039), 0.003, "paint", sub=1),
	tube("cs_handle", [(-0.05, -0.03, 0), (-0.042, 0.0, 0), (0.042, 0.0, 0), (0.05, -0.03, 0)], 0.009, "dark", sides=10),
]
for x in (-0.07, 0.07):
	case.append(rbox("cs_latch", (0.024, 0.03, 0.01), (x, -0.07, -0.038), 0.004, "steel", sub=1))
ACC["acc_case"] = (join("acc_case", case), Vector((0, 0, 0)))

CHEST = Vector((0, 0.43, -0.183))
ACC["acc_icon_cross"] = (join("acc_icon_cross", [
	rbox("ic_h", (0.075, 0.024, 0.008), CHEST, 0.004, "glow", sub=1),
	rbox("ic_v", (0.024, 0.075, 0.008), CHEST, 0.004, "glow", sub=1),
]), CHEST)
lf = leaf("ic_leaf", 0.07, 0.05, CHEST + Vector((0.0, -0.032, 0)), "glow", rot=(0, 0, -28), cup=0.0, curl=0.0, thick=0.006)
for v in lf.data.vertices:
	v.co.z = CHEST.z + (v.co.z - CHEST.z) * 0.6
ACC["acc_icon_leaf"] = (join("acc_icon_leaf", [lf, tube("ic_vein", [CHEST + Vector((0.012, -0.036, -0.004)), CHEST + Vector((-0.006, 0.0, -0.005)), CHEST + Vector((-0.02, 0.026, -0.004))], 0.002, "dark", sides=6)]), CHEST)

# --- Butterfly companion (Pixel): one wing (PatchModel mirrors and flaps it) and a body.
# Outline swept around the hinge (a fan, so it triangulates cleanly): big forewing, rounder hindwing.
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

ACC_OBJS = [o for (o, _p) in ACC.values()]
for name, (o, piv) in ACC.items():
	PARTS[name] = piv
	o.name = name
	o.data.name = name

