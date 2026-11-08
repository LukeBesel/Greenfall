# Builds Lumi's travel ship (the "Seedglider") as modular parts and exports art/models/ship/ship.glb
# plus ship_points.json (nozzles, lift fans, lamps, hinges) for automation/ship_model.gd.
#   blender -b --python art/models/ship/build_ship.py            (PREVIEW=/path/prefix for Cycles stills)
# Same approach as art/models/aurora/build_aurora.py: modelled in Godot coordinates (Y up, the nose
# points +Z, ground at y=0 with the gear down), baked vertex colours (R = AO, G = convex edge,
# B = cavity) and material slot names that ShipModel maps to runtime materials.
#
# One base ship that grows with the tiers (ShipModel.PARTS_BY_TIER):
#   Mk I    hull_rear + hull_front, wing, canopy_a, eng_a, skids          (compact one-seat glider)
#   Mk II   + wing_ext (drooping tip fins)
#   Mk III  eng_b replaces eng_a, canopy_b replaces canopy_a
#   Mk IV   gear replaces skids, + pods (cargo pods)
#   Mk V    + hull_mid (the front moves forward by MID), eng_c (second pair), fins
#   Mk VI   wing_big replaces wing_ext, + ring (fold ring), eng_tip
#   Mk VII  + vault (seed vault), eng_core; light banners are added at runtime
import bpy
import bmesh
import json
import math
import os
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "ship.glb")
OUT_PTS = os.path.join(HERE, "ship_points.json")

for o in list(bpy.data.objects):
	bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.meshes):
	bpy.data.meshes.remove(m)

LIFT = 0.62   # hull space -> ground space (gear height)
MID = 2.2     # hull_mid length (Mk V+ moves the front parts forward by this)
MATS = {}
POINTS = {"nozzles": [], "fans": [], "lamps": [], "mid": MID, "lift": LIFT}


def mat(name):
	if name not in MATS:
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		MATS[name] = m
	return MATS[name]


def link(obj):
	bpy.context.scene.collection.objects.link(obj)
	return obj


def select_only(obj):
	bpy.context.view_layer.objects.active = obj
	for o in bpy.context.view_layer.objects:
		o.select_set(o == obj)


def from_bm(bm, name, material):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = link(bpy.data.objects.new(name, me))
	obj.data.materials.append(mat(material))
	return obj


def apply_mods(obj):
	select_only(obj)
	for md in list(obj.modifiers):
		try:
			bpy.ops.object.modifier_apply(modifier=md.name)
		except Exception as ex:  # pragma: no cover
			print("modifier failed", obj.name, md.name, ex)
			obj.modifiers.remove(md)


def finish(obj, bevel=0.0, segs=2, angle=30, smooth_angle=34):
	if bevel > 0:
		md = obj.modifiers.new("bev", 'BEVEL')
		md.width = bevel
		md.segments = segs
		md.limit_method = 'ANGLE'
		md.angle_limit = math.radians(angle)
		md.harden_normals = False
		apply_mods(obj)
	for p in obj.data.polygons:
		p.use_smooth = True
	obj.data.use_auto_smooth = True
	obj.data.auto_smooth_angle = math.radians(smooth_angle)
	return obj


def xform(obj, center=(0, 0, 0), rot=(0, 0, 0)):
	r = Matrix.Rotation(math.radians(rot[1]), 4, 'Y') @ Matrix.Rotation(math.radians(rot[0]), 4, 'X') @ Matrix.Rotation(math.radians(rot[2]), 4, 'Z')
	obj.data.transform(Matrix.Translation(Vector(center)) @ r)
	return obj


def box(name, size, center, material, bevel=0.01, rot=(0, 0, 0), segs=2):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
	obj = from_bm(bm, name, material)
	if bevel > 0:
		md = obj.modifiers.new("bev", 'BEVEL')
		md.width = min(bevel, min(size) * 0.45)
		md.segments = segs
		md.limit_method = 'NONE'
		apply_mods(obj)
	xform(obj, center, rot)
	return finish(obj)


def cyl(name, r, depth, center, material, axis='Z', verts=24, r2=None, bevel=0.0, rot=None):
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth)
	obj = from_bm(bm, name, material)
	if rot is None:
		rot = {'X': (0, 90, 0), 'Y': (90, 0, 0), 'Z': (0, 0, 0)}[axis]
	xform(obj, center, rot)
	return finish(obj, bevel, angle=40)


def torus(name, R, r, center, material, axis='Z', major=40, minor=6, rot=None):
	bm = bmesh.new()
	vs = []
	for i in range(major):
		a = 2 * math.pi * i / major
		row = []
		for j in range(minor):
			b = 2 * math.pi * j / minor
			rr = R + r * math.cos(b)
			row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b))))
		vs.append(row)
	for i in range(major):
		for j in range(minor):
			bm.faces.new((vs[i][j], vs[(i + 1) % major][j], vs[(i + 1) % major][(j + 1) % minor], vs[i][(j + 1) % minor]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	obj = from_bm(bm, name, material)
	if rot is None:
		rot = {'X': (0, 90, 0), 'Y': (90, 0, 0), 'Z': (0, 0, 0)}[axis]
	xform(obj, center, rot)
	return finish(obj)


def loft(name, rings, material, cap=True):
	"""Closed rings of equal length -> a solid (ngon caps)."""
	bm = bmesh.new()
	R = [[bm.verts.new(p) for p in ring] for ring in rings]
	n = len(rings[0])
	for k in range(len(R) - 1):
		for i in range(n):
			bm.faces.new((R[k][i], R[k][(i + 1) % n], R[k + 1][(i + 1) % n], R[k + 1][i]))
	if cap:
		bm.faces.new(R[0])
		bm.faces.new(list(reversed(R[-1])))
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return from_bm(bm, name, material)


def prism_y(name, poly, y0, y1, material, thick_fn=None):
	"""Extrude an XZ outline (list of (x, z)) between y0 and y1; thick_fn(x, z) -> (bottom, top) overrides."""
	bm = bmesh.new()
	bot, top = [], []
	for (x, z) in poly:
		b, t = (y0, y1) if thick_fn is None else thick_fn(x, z)
		bot.append(bm.verts.new((x, b, z)))
		top.append(bm.verts.new((x, t, z)))
	n = len(poly)
	bm.faces.new(top)
	bm.faces.new(list(reversed(bot)))
	for i in range(n):
		bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	obj = from_bm(bm, name, material)
	return obj


def tri_fill(obj):
	"""Triangulate ngons cleanly before bevel (long ngons shade badly)."""
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method='BEAUTY', ngon_method='BEAUTY')
	bm.to_mesh(obj.data)
	bm.free()
	return obj


def rod(name, a, b, r, material, verts=8):
	a, b = Vector(a), Vector(b)
	d = b - a
	obj = cyl(name, r, d.length, (0, 0, 0), material, verts=verts, rot=(0, 0, 0))
	q = Vector((0, 0, 1)).rotation_difference(d.normalized())
	obj.data.transform(Matrix.Translation((a + b) * 0.5) @ q.to_matrix().to_4x4())
	return obj


def boolean(target, cutter, op='DIFFERENCE'):
	md = target.modifiers.new("bool", 'BOOLEAN')
	md.operation = op
	md.object = cutter
	md.solver = 'EXACT'
	md.material_mode = 'TRANSFER'
	apply_mods(target)
	bpy.data.objects.remove(cutter, do_unlink=True)
	return target


def join(name, objs):
	objs = [o for o in objs if o is not None]
	bpy.ops.object.select_all(action='DESELECT')
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.join()
	o = bpy.context.view_layer.objects.active
	o.name = name
	o.data.name = name
	return o


def mirror(obj, name=None):
	c = obj.copy()
	c.data = obj.data.copy()
	link(c)
	c.data.transform(Matrix.Scale(-1, 4, Vector((1, 0, 0))))
	c.data.flip_normals()
	if name:
		c.name = name
	return c


def both(obj):
	"""obj + its X mirror, joined."""
	return join(obj.name, [obj, mirror(obj)])


def lamp(name, p, r=0.035, material="lamp"):
	POINTS["lamps"].append({"pos": [p[0], p[1] + LIFT, p[2]], "kind": material})
	return cyl(name, r, 0.03, p, material, verts=10, axis='Z')


# ---------------------------------------------------------------- HULL
# Cross-section stations (z, half-width, top, chine, bottom) in hull space (LIFT below the ground).
ST = [(-2.75, 0.52, 0.64, 0.44, 0.28), (-2.45, 0.68, 0.76, 0.46, 0.17), (-1.6, 0.84, 0.84, 0.47, 0.12),
	(-0.6, 0.86, 0.86, 0.47, 0.11), (0.0, 0.84, 0.86, 0.47, 0.12), (0.8, 0.74, 0.84, 0.46, 0.15),
	(1.6, 0.56, 0.77, 0.44, 0.2), (2.3, 0.38, 0.67, 0.43, 0.26), (2.8, 0.2, 0.58, 0.42, 0.31), (3.1, 0.05, 0.5, 0.42, 0.37)]


def catmull(vals, t):
	n = len(vals)
	i = min(int(t), n - 2)
	u = t - i
	p0 = vals[max(i - 1, 0)]
	p1, p2 = vals[i], vals[i + 1]
	p3 = vals[min(i + 2, n - 1)]
	return 0.5 * (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)


def station(z):
	"""Interpolated (w, top, chine, bottom) at z (clamped to the hull)."""
	zs = [s[0] for s in ST]
	z = min(max(z, zs[0]), zs[-1])
	k = 0
	while k < len(zs) - 2 and z > zs[k + 1]:
		k += 1
	t = k + (z - zs[k]) / (zs[k + 1] - zs[k])
	return tuple(catmull([s[j] for s in ST], t) for j in range(1, 5))


def section(z, grow=0.0, w_k=1.0):
	w, yt, yc, yb = station(z)
	w = w * w_k + grow
	yt += grow
	yb -= grow
	right = [(0.0, yt), (0.42 * w, yt - 0.025), (0.84 * w, yc + 0.15), (w, yc), (0.8 * w, yb + 0.1), (0.0, yb)]
	left = [(-x, y) for (x, y) in reversed(right[1:-1])]
	return [(x, y, z) for (x, y) in right + left]


def hull_piece(name, z0, z1, n):
	rings = [section(z0 + (z1 - z0) * i / n) for i in range(n + 1)]
	return loft(name, rings, "paint")


def mid_section(z):
	w, yt, yc, yb = station(0.0)
	right = [(0.0, yt), (0.42 * w, yt - 0.025), (0.84 * w, yc + 0.15), (w, yc), (0.8 * w, yb + 0.1), (0.0, yb)]
	left = [(-x, y) for (x, y) in reversed(right[1:-1])]
	return [(x, y, z) for (x, y) in right + left]


def strip_plate(name, z0, z1, idx, off, material, n=10, zfn=None, taper=0.0):
	"""A raised plate following the hull over [z0, z1], across section points idx (indices into the
	10-point ring, in order), lifted `off` outward. Solid (outer, inner, walls)."""
	def outward(z, i, d):
		w, yt, yc, yb = station(z)
		ring = section(z)
		p = Vector(ring[i])
		c = Vector((0, (yt + yb) * 0.5, z))
		v = (p - c)
		v.z = 0
		return p + v.normalized() * d
	outer, inner = [], []
	for k in range(n + 1):
		z = z0 + (z1 - z0) * k / n
		outer.append([outward(z, i, off) for i in idx])
		inner.append([outward(z, i, -0.01) for i in idx])
	bm = bmesh.new()
	O = [[bm.verts.new(p) for p in row] for row in outer]
	I = [[bm.verts.new(p) for p in row] for row in inner]
	m = len(idx)
	for k in range(n):
		for i in range(m - 1):
			bm.faces.new((O[k][i], O[k][i + 1], O[k + 1][i + 1], O[k + 1][i]))
			bm.faces.new((I[k][i], I[k + 1][i], I[k + 1][i + 1], I[k][i + 1]))
		bm.faces.new((O[k][0], O[k + 1][0], I[k + 1][0], I[k][0]))
		bm.faces.new((O[k][m - 1], I[k][m - 1], I[k + 1][m - 1], O[k + 1][m - 1]))
	bm.faces.new([O[0][i] for i in range(m)] + [I[0][i] for i in reversed(range(m))])
	bm.faces.new([O[n][i] for i in reversed(range(m))] + [I[n][i] for i in range(m)])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	obj = from_bm(bm, name, material)
	tri_fill(obj)
	return finish(obj, 0.012, angle=25)


def groove_ring(target, z, depth=0.012, width=0.012, z_fn=section):
	"""Panel seam around the hull at z: a thin ring slab cut into the surface."""
	outer = loft("gr_o", [section(z - width, 0.05), section(z + width, 0.05)], "trim")
	inner = loft("gr_i", [section(z - width * 2, -depth), section(z + width * 2, -depth)], "trim")
	boolean(outer, inner)
	return boolean(target, outer)


def groove_line(target, pts, depth=0.014, width=0.012):
	"""Seam along a polyline on the surface (pts already on the surface, outward normal ~ +y)."""
	cut = join("gl", [rod("gl%d" % i, pts[i], pts[i + 1], width, "trim", verts=6) for i in range(len(pts) - 1)])
	return boolean(target, cut)


def surf_y(x, z):
	"""Top surface height of the hull at (x, z) (top facets only)."""
	w, yt, yc, yb = station(z)
	ax = abs(x)
	if ax <= 0.42 * w:
		return yt - 0.025 * ax / (0.42 * w + 1e-6)
	if ax <= 0.84 * w:
		u = (ax - 0.42 * w) / (0.42 * w)
		return (yt - 0.025) * (1 - u) + (yc + 0.15) * u
	u = (ax - 0.84 * w) / (0.16 * w)
	return (yc + 0.15) * (1 - u) + yc * u


# Rear hull (tail .. 0) and front hull (0 .. nose).
hull_rear = hull_piece("hull_rear", -2.75, 0.0, 14)
hull_front = hull_piece("hull_front", 0.0, 3.1, 16)
hull_mid = loft("hull_mid", [mid_section(MID * i / 6) for i in range(7)], "paint")
for h in (hull_rear, hull_front, hull_mid):
	tri_fill(h)
	finish(h, 0.014, angle=24)

# Panel seams.
groove_ring(hull_rear, -1.75)
groove_ring(hull_rear, -0.55)
groove_ring(hull_front, 1.15)
groove_ring(hull_mid, 1.1)
# Side intake slots on the rear hull (dark recess), RCS slots at the nose.
for sx in (1, -1):
	c = box("in_cut", (0.5, 0.12, 0.7), (sx * 0.86, 0.6, -1.05), "trim", 0.02)
	boolean(hull_rear, c)
	c = box("rcs_cut", (0.3, 0.05, 0.16), (sx * 0.33, 0.47, 2.62), "trim", 0.01)
	boolean(hull_front, c)
	c = box("mid_cut", (0.4, 0.09, 0.9), (sx * 0.84, 0.62, 1.1), "trim", 0.02)
	boolean(hull_mid, c)

parts = {}
rear_bits = [hull_rear]
# Layered plates: a dorsal plate over the rear, shoulder plates along the chines, a belly plate.
rear_bits.append(strip_plate("p_dorsal", -2.5, -0.15, [8, 9, 0, 1, 2], 0.03, "panel"))
rear_bits.append(strip_plate("p_sh_r", -2.35, -1.35, [2, 3], 0.025, "paint", n=6))
rear_bits.append(strip_plate("p_sh_l", -2.35, -1.35, [7, 8], 0.025, "paint", n=6))
rear_bits.append(strip_plate("p_belly", -2.2, -0.2, [4, 5, 6], 0.02, "panel", n=8))
# Intake grilles inside the side slots.
for sx in (1, -1):
	for k in range(4):
		rear_bits.append(box("vane", (0.36, 0.012, 0.03), (sx * 0.84, 0.6, -1.3 + k * 0.16), "steel", 0.0))
	rear_bits.append(box("in_glow", (0.012, 0.012, 0.6), (sx * 0.62, 0.66, -1.05), "glow", 0.0))
# Tail: a flat recessed exhaust plate with a small central thruster ring (always there), tail light.
rear_bits.append(cyl("tail_plate", 0.3, 0.06, (0, 0.47, -2.76), "trim", verts=8))
rear_bits.append(torus("tail_ring", 0.18, 0.012, (0, 0.47, -2.79), "glow", major=24, minor=4))
rear_bits.append(lamp("tail_lamp", (0, 0.68, -2.72), 0.03))
# Spine fin stub with an antenna and two thin cyan lines along the top.
rear_bits.append(box("spine", (0.08, 0.1, 1.0), (0, surf_y(0, -1.6) + 0.08, -1.6), "paint", 0.03))
rear_bits.append(rod("antenna", (0, surf_y(0, -2.0) + 0.1, -2.0), (0, surf_y(0, -2.0) + 0.42, -2.25), 0.008, "steel"))
for sx in (1, -1):
	pts = [(sx * 0.33, surf_y(0.33, z) + 0.036, z) for z in (-2.3, -1.6, -0.9, -0.25)]
	for i in range(3):
		rear_bits.append(rod("cl", pts[i], pts[i + 1], 0.007, "glow", verts=5))
parts["hull_rear"] = join("hull_rear", rear_bits)

front_bits = [hull_front]
# Nose: tangerine chevron band, sensor bezel (C-eye face is drawn at runtime), little lamps.
nose = strip_plate("p_nose", 2.35, 2.62, [8, 9, 0, 1, 2], 0.012, "accent", n=3)
front_bits.append(nose)
front_bits.append(strip_plate("p_chin", 1.2, 2.5, [4, 5, 6], 0.015, "panel", n=8))
for sx in (1, -1):
	front_bits.append(box("rcs_noz", (0.22, 0.03, 0.1), (sx * 0.33, 0.47, 2.62), "dark", 0.004))
	front_bits.append(lamp("nose_lamp", (sx * 0.2, 0.42, 2.93), 0.022))
	# Chine light line forward of the wing.
	pts = [(sx * (station(z)[0] + 0.004), station(z)[2], z) for z in (0.2, 0.9, 1.6, 2.2)]
	for i in range(3):
		front_bits.append(rod("chl", pts[i], pts[i + 1], 0.007, "glow", verts=5))
# Sensor bezel: a dark recessed plate on the nose where the C eyes sit.
front_bits.append(box("sensor", (0.3, 0.07, 0.03), (0, 0.5, 3.02), "dark", 0.015, rot=(-12, 0, 0)))
parts["hull_front"] = join("hull_front", front_bits)

mid_bits = [hull_mid]
mid_bits.append(strip_plate("p_mid_dorsal", 0.15, MID - 0.15, [8, 9, 0, 1, 2], 0.0, "panel"))
for sx in (1, -1):
	for k in range(5):
		mid_bits.append(box("mvane", (0.3, 0.012, 0.03), (sx * 0.84, 0.62, 0.78 + k * 0.16), "steel", 0.0))
	pts = [(sx * 0.83, 0.47, z) for z in (0.1, MID - 0.1)]
	mid_bits.append(rod("mchl", pts[0], pts[1], 0.007, "glow", verts=5))
	mid_bits.append(lamp("mid_lamp", (sx * 0.5, 0.82, MID - 0.3), 0.022))
parts["hull_mid"] = join("hull_mid", mid_bits)
# hull_mid is built from z=0 with the plate helper using the tapering front stations; good enough
# because it sits flush with the z=0 station (the widest point).

# ---------------------------------------------------------------- WINGS
WY = 0.47   # wing root height (the chine)


def wing_thick(x, z):
	t = max(0.05, 0.17 - 0.035 * (x - 0.6))
	return (WY - t * 0.45 - (x - 0.6) * 0.05, WY + t * 0.55 - (x - 0.6) * 0.05)


WING = [(0.4, 2.2), (0.62, 1.2), (1.0, 0.45), (1.6, -0.25), (3.0, -1.5), (3.22, -1.75), (3.25, -2.45), (3.05, -2.6), (2.25, -2.38),
	(1.55, -2.62), (0.55, -2.45)]


def wing_surface(x):
	"""Approximate top y of the wing at span x."""
	return wing_thick(x, 0)[1]


def build_wing():
	bits = []
	w = prism_y("wing_r", WING, 0, 0, "paint", thick_fn=wing_thick)
	tri_fill(w)
	finish(w, 0.02, angle=25)
	# Lift fan: a round hole through the wing with a fan and grille inside.
	fan_c = (1.62, -1.15)
	POINTS["fans"].append({"pos": [fan_c[0], wing_thick(*fan_c)[0] + LIFT, fan_c[1]], "r": 0.36})
	cut = cyl("fan_cut", 0.38, 1.0, (fan_c[0], WY, fan_c[1]), "trim", axis='Y', verts=32)
	boolean(w, cut)
	bits.append(w)
	yb, yt = wing_thick(*fan_c)
	bits.append(torus("fan_rim", 0.38, 0.03, (fan_c[0], yt - 0.01, fan_c[1]), "trim", axis='Y', major=32, minor=6))
	bits.append(torus("fan_glow", 0.345, 0.006, (fan_c[0], yt - 0.0, fan_c[1]), "glow", axis='Y', major=32, minor=4))
	bits.append(cyl("fan_hub", 0.09, 0.12, (fan_c[0], (yb + yt) * 0.5, fan_c[1]), "steel", axis='Y', verts=16))
	for k in range(9):
		a = 2 * math.pi * k / 9
		bl = box("blade", (0.27, 0.012, 0.07), (fan_c[0] + math.cos(a) * 0.2, (yb + yt) * 0.5, fan_c[1] + math.sin(a) * 0.2), "steel", 0.0, rot=(0, -math.degrees(a), 22))
		bits.append(bl)
	for k in range(5):
		bits.append(box("grille", (0.7, 0.014, 0.018), (fan_c[0], yt - 0.015, fan_c[1] - 0.3 + k * 0.15), "trim", 0.0))
	# Upper inset plate, a tangerine tip stripe, a thin cyan line inside the leading edge.
	plate = [(0.9, 0.2), (1.45, -0.42), (2.6, -1.55), (2.6, -2.2), (2.2, -2.15), (2.0, -1.95), (1.05, -2.05)]
	p = prism_y("wing_plate", plate, 0, 0, "panel", thick_fn=lambda x, z: (wing_thick(x, z)[1] - 0.02, wing_thick(x, z)[1] + 0.018))
	cut = cyl("pc", 0.43, 1.0, (fan_c[0], WY, fan_c[1]), "trim", axis='Y', verts=32)
	tri_fill(p)
	boolean(p, cut)
	bits.append(finish(p, 0.01, angle=25))
	tip = [(2.72, -1.25), (3.02, -1.52), (3.22, -1.77), (3.25, -2.45), (3.07, -2.58), (2.75, -2.5)]
	t = prism_y("wing_tip", tip, 0, 0, "accent", thick_fn=lambda x, z: (wing_thick(x, z)[0] - 0.006, wing_thick(x, z)[1] + 0.006))
	tri_fill(t)
	bits.append(finish(t, 0.008))
	le = [(0.75 + (2.9 - 0.75) * u, 0.62 - (0.62 + 1.38) * u) for u in (0.0, 0.33, 0.66, 1.0)]
	for i in range(3):
		a = (le[i][0], wing_thick(*le[i])[1] + 0.004, le[i][1] - 0.12)
		b = (le[i + 1][0], wing_thick(*le[i + 1])[1] + 0.004, le[i + 1][1] - 0.12)
		bits.append(rod("le_glow", a, b, 0.006, "glow", verts=5))
	# Red tip light and a small flap actuator fairing (greeble) on the trailing edge.
	bits.append(lamp("tip_lamp", (3.2, wing_thick(3.2, -2.3)[1] + 0.01, -2.35), 0.035))
	for x in (1.2, 2.0):
		bits.append(box("fair", (0.1, 0.07, 0.45), (x, wing_thick(x, -2.2)[0] - 0.02, -2.25), "paint", 0.03))
	return both(join("wing", bits))


parts["wing"] = build_wing()


def wing_panel(name, poly, base_x, droop, y0, mat_main="paint", lamp_at=None, tip_poly=None):
	"""An outer wing panel hinged at x=base_x (the root chord sits on the previous tip), drooping."""
	bits = []
	thick = lambda x, z: (-0.03 + 0.0 * x, 0.03)
	w = prism_y(name, poly, 0, 0, mat_main, thick_fn=lambda x, z: (-max(0.025, 0.05 - 0.01 * x), max(0.025, 0.05 - 0.01 * x)))
	tri_fill(w)
	finish(w, 0.012, angle=25)
	bits.append(w)
	if tip_poly:
		t = prism_y(name + "_tip", tip_poly, 0, 0, "accent", thick_fn=lambda x, z: (-0.034, 0.034))
		tri_fill(t)
		bits.append(finish(t, 0.008))
	o = join(name, bits)
	if lamp_at:
		o = join(name, [o, lamp(name + "_lamp", lamp_at, 0.03)])
	# Local x=0 is the hinge: droop about Z, then move to the tip.
	o.data.transform(Matrix.Translation((base_x, y0, 0)) @ Matrix.Rotation(math.radians(-droop), 4, 'Z'))
	return o


# Mk II wing extension: a drooping crescent fin under the tip (the glider's signature silhouette).
EXT = [(0.0, -1.62), (0.35, -1.75), (0.95, -2.2), (1.15, -2.7), (1.0, -3.05), (0.7, -2.95), (0.0, -2.55)]
EXT_TIP = [(0.82, -2.35), (1.15, -2.7), (1.0, -3.05), (0.75, -2.98)]
EXT = [(x * 0.82, z) for (x, z) in EXT]
EXT_TIP = [(x * 0.82, z) for (x, z) in EXT_TIP]
ext = wing_panel("wing_ext", EXT, 3.18, 48, wing_thick(3.18, -2.0)[1] - 0.06, lamp_at=None, tip_poly=EXT_TIP)
ext = join("wing_ext", [ext, lamp("ext_lamp", (3.18 + 0.86 * math.cos(math.radians(-48)) + 0.03, wing_thick(3.18, -2)[1] - 0.06 + 0.86 * math.sin(math.radians(-48)), -2.95), 0.03)])
parts["wing_ext"] = both(ext)

# Mk VI big wing: a long outer panel (span to ~5.6) with its own drooping fin at the end.
BIG = [(0.0, -1.5), (1.2, -2.0), (2.3, -2.45), (2.45, -2.75), (2.3, -3.2), (1.0, -3.0), (0.0, -2.6)]
big_y = wing_thick(3.18, -2.0)[1] - 0.04
big = wing_panel("wing_big", BIG, 3.12, 8, big_y, mat_main="paint")
bx = 3.12 + 2.42 * math.cos(math.radians(-8))
by = big_y + 2.42 * math.sin(math.radians(-8))
big_plate = prism_y("big_plate", [(3.5, -1.85), (4.6, -2.3), (4.8, -2.85), (3.5, -2.75)], 0, 0, "panel",
	thick_fn=lambda x, z: (big_y - (x - 3.12) * 0.14 + 0.02, big_y - (x - 3.12) * 0.14 + 0.07))
tri_fill(big_plate)
finish(big_plate, 0.008)
fin2 = wing_panel("big_fin", [(x * 0.8, z) for (x, z) in EXT], bx - 0.05, 40, by, tip_poly=[(x * 0.8, z) for (x, z) in EXT_TIP])
glow_big = rod("big_glow", (3.3, big_y + 0.07 - 0.03, -1.62), (5.3, by + 0.07 - 0.02, -2.33), 0.007, "glow", verts=5)
parts["wing_big"] = both(join("wing_big", [big, big_plate, fin2, glow_big]))


# ---------------------------------------------------------------- ENGINES
def nacelle(name, cx, cy, z0, z1, r, big=False, intake=True):
	"""Octagonal engine nacelle along Z: intake at z1 (front), nozzle at z0 (rear)."""
	n = 8
	prof = [(z1, r * 0.82), (z1 - 0.1, r * 0.98), (z1 - 0.4, r), (z0 + 0.45, r * 0.97), (z0 + 0.12, r * 0.86), (z0, r * 0.8)]
	rings = []
	for (z, rr) in prof:
		rings.append([(cx + math.cos(2 * math.pi * (i + 0.5) / n) * rr, cy + math.sin(2 * math.pi * (i + 0.5) / n) * rr * 0.92, z) for i in range(n)])
	shell = loft(name + "_shell", rings, "paint")
	tri_fill(shell)
	finish(shell, 0.012, angle=20, smooth_angle=30)
	groove = [box(name + "_g", (r * 2.4, r * 2.4, 0.02), (cx, cy, (z0 + z1) * 0.5 + 0.1), "trim", 0.0)]
	cut_in = cyl(name + "_gi", r * 0.97 - 0.012, 0.06, (cx, cy, (z0 + z1) * 0.5 + 0.1), "trim", verts=16)
	boolean(groove[0], cut_in)
	boolean(shell, groove[0])
	bits = [shell]
	# Intake: dark mouth, steel spinner, thin cyan ring.
	if intake:
		bits.append(cyl(name + "_mouth", r * 0.7, 0.05, (cx, cy, z1 - 0.03), "dark", verts=16))
		bits.append(cyl(name + "_spin", r * 0.25, 0.14, (cx, cy, z1 - 0.02), "steel", verts=12, r2=r * 0.05))
		bits.append(torus(name + "_ring", r * 0.8, 0.008, (cx, cy, z1 + 0.003), "glow", major=24, minor=4))
	# Nozzle: graphite petals bell and the thruster disc (lit at runtime).
	bits.append(cyl(name + "_bell", r * 0.8, 0.26, (cx, cy, z0 - 0.1), "trim", verts=16, r2=r * 0.72))
	bits.append(cyl(name + "_noz", r * 0.62, 0.02, (cx, cy, z0 - 0.22), "thruster", verts=16))
	bits.append(torus(name + "_nring", r * 0.74, 0.012, (cx, cy, z0 - 0.23), "steel", major=24, minor=4))
	# Tangerine band and a small fin on top.
	band = loft(name + "_band", [[(cx + math.cos(2 * math.pi * (i + 0.5) / n) * (r + 0.008), cy + math.sin(2 * math.pi * (i + 0.5) / n) * (r + 0.008) * 0.92, z) for i in range(n)] for z in (z1 - 0.62, z1 - 0.5)], "accent")
	bits.append(finish(band))
	if big:
		for k in range(3):
			zz = z0 + 0.35 + k * 0.12
			bits.append(torus(name + "_cool%d" % k, r * 0.99, 0.014, (cx, cy, zz), "steel", major=8, minor=4))
		bits.append(box(name + "_fin", (0.03, r * 0.9, 0.7), (cx, cy + r * 1.25, z0 + 0.6), "paint", 0.012))
		bits.append(lamp(name + "_flamp", (cx, cy + r * 1.7, z0 + 0.35), 0.02))
	POINTS["nozzles"].append({"part": name, "pos": [cx, cy + LIFT, z0 - 0.23], "r": r * 0.62})
	return join(name, bits)


def eng(name, cx, cy, z0, z1, r, big=False, pylon=None):
	e = nacelle(name, cx, cy, z0, z1, r, big)
	bits = [e]
	if pylon:
		bits.append(box(name + "_py", pylon[0], pylon[1], "panel", 0.02))
	o = join(name, bits)
	m = mirror(o)
	POINTS["nozzles"].append({"part": name, "pos": [-cx, cy + LIFT, z0 - 0.23], "r": r * 0.62})
	return join(name, [o, m])


parts["eng_a"] = eng("eng_a", 1.0, 0.64, -2.95, -0.7, 0.25, pylon=((0.3, 0.14, 1.2), (0.78, 0.66, -1.7)))
parts["eng_b"] = eng("eng_b", 1.04, 0.68, -3.25, -0.3, 0.33, big=True, pylon=((0.36, 0.16, 1.6), (0.8, 0.66, -1.7)))
parts["eng_c"] = eng("eng_c", 2.3, wing_surface(2.3) + 0.2, -3.0, -1.35, 0.21, pylon=((0.1, 0.16, 0.9), (2.3, wing_surface(2.3) + 0.06, -2.0)))
TIP_X = 5.45
ty = big_y + (TIP_X - 3.12) * math.sin(math.radians(-8)) + 0.05
parts["eng_tip"] = eng("eng_tip", TIP_X, ty + 0.12, -3.25, -1.8, 0.18, pylon=((0.08, 0.14, 0.8), (TIP_X, ty + 0.02, -2.6)))
# Mk VII core: a big central engine cluster at the tail (three nozzles in a graphite cowl).
core_bits = [cyl("core_cowl", 0.56, 0.6, (0, 0.5, -2.95), "panel", verts=8, r2=0.5, bevel=0.02)]
for k, (dx, dy) in enumerate(((0, 0.1), (-0.25, -0.1), (0.25, -0.1))):
	core_bits.append(cyl("core_bell%d" % k, 0.19, 0.3, (dx, 0.5 + dy, -3.35), "trim", verts=16, r2=0.16))
	core_bits.append(cyl("core_noz%d" % k, 0.14, 0.02, (dx, 0.5 + dy, -3.5), "thruster", verts=16))
	POINTS["nozzles"].append({"part": "eng_core", "pos": [dx, 0.5 + dy + LIFT, -3.5], "r": 0.14})
core_bits.append(torus("core_glow", 0.545, 0.008, (0, 0.5, -3.24), "glow", major=8, minor=4))
parts["eng_core"] = join("eng_core", core_bits)


# ---------------------------------------------------------------- CANOPIES
def canopy(name, z0, z1, wmax, h, frame_mat="paint", seg=6):
	"""Faceted canopy: a low glass dome sitting on the hull top, with frame bars on its facet edges."""
	zs = [z0 + (z1 - z0) * i / seg for i in range(seg + 1)]
	rings = []
	for i, z in enumerate(zs):
		u = i / seg
		w = wmax * math.sin(math.pi * min(1.0, 0.12 + u * 0.95)) ** 0.6
		hh = h * math.sin(math.pi * min(1.0, 0.1 + u * 0.92)) ** 0.8
		w = max(w, 0.02)
		hh = max(hh, 0.01)
		base = surf_y(w, z) - 0.02
		top = surf_y(0, z)
		pts = [(w, base, z), (w * 0.72, top + hh * 0.62, z), (w * 0.3, top + hh, z), (-w * 0.3, top + hh, z), (-w * 0.72, top + hh * 0.62, z), (-w, base, z)]
		rings.append(pts)
	g = loft(name + "_glass", rings, "glass")
	finish(g, 0.0, smooth_angle=8)
	bits = [g]
	# Frame: bars along the facet edges (longitudinal) and a few cross hoops.
	for j in (1, 4):
		for i in range(seg):
			bits.append(rod(name + "_fb", rings[i][j], rings[i + 1][j], 0.016, frame_mat, verts=6))
	for i in (2, 4):
		for j in range(5):
			bits.append(rod(name + "_fx", rings[i][j], rings[i][j + 1], 0.016, frame_mat, verts=6))
	# Sill: a pearl lip around the base, thin cyan line beneath it.
	for i in range(seg):
		for j in (0, 5):
			a, b = Vector(rings[i][j]), Vector(rings[i + 1][j])
			bits.append(rod(name + "_sill", a, b, 0.026, "paint", verts=6))
			off = Vector((0.03 if j == 0 else -0.03, -0.035, 0))
			if 0 < i < seg - 1:
				bits.append(rod(name + "_sg", a + off, b + off, 0.005, "glow", verts=4))
	return join(name, bits)


parts["canopy_a"] = canopy("canopy_a", 0.15, 2.05, 0.4, 0.3)
POINTS["canopy_hinge_a"] = [0.0, surf_y(0, 0.15) + 0.05 + LIFT, 0.15]
cb = canopy("canopy_b", -0.25, 2.25, 0.47, 0.36, seg=7)
# Mk III canopy extras: a tangerine headrest fairing behind it and a small sensor dome.
cb_bits = [cb, box("cb_fair", (0.5, 0.12, 0.5), (0, surf_y(0, -0.45) + 0.04, -0.45), "accent", 0.04)]
cb_bits.append(cyl("cb_dome", 0.09, 0.07, (0, surf_y(0, -0.45) + 0.13, -0.6), "glass", axis='Y', verts=12, r2=0.05))
parts["canopy_b"] = join("canopy_b", cb_bits)
POINTS["canopy_hinge_b"] = [0.0, surf_y(0, -0.25) + 0.05 + LIFT, -0.25]


# ---------------------------------------------------------------- GEAR, PODS, FINS, RING, VAULT
PIVOTS = {}


def skid(name, sx):
	px = sx * 0.42
	piv = Vector((px, 0.1, -0.3))
	fx = px * 1.6
	bits = [box(name + "_rail", (0.12, 0.07, 2.4), (fx, -LIFT + 0.05, -0.35), "trim", 0.03)]
	for zz in (-1.15, 0.45):
		bits.append(rod(name + "_st", (px, 0.12, zz), (fx, -LIFT + 0.08, zz), 0.05, "paint", verts=10))
		bits.append(cyl(name + "_kn", 0.065, 0.1, (fx, -LIFT + 0.1, zz), "accent", axis='X', verts=12))
	bits.append(box(name + "_tip", (0.12, 0.06, 0.16), (fx, -LIFT + 0.09, 0.9), "accent", 0.025))
	bits.append(rod(name + "_gl", (fx + sx * 0.062, -LIFT + 0.06, -1.4), (fx + sx * 0.062, -LIFT + 0.06, 0.7), 0.006, "glow", verts=4))
	o = join(name, bits)
	PIVOTS[name] = piv
	return o


parts["skid_l"] = skid("skid_l", -1)
parts["skid_r"] = skid("skid_r", 1)


def leg(name, top, foot, pad_r=0.17):
	top, foot = Vector(top), Vector(foot)
	bits = [rod(name + "_up", top, top.lerp(foot, 0.55), 0.055, "paint", verts=10)]
	bits.append(rod(name + "_lo", top.lerp(foot, 0.5), foot + Vector((0, 0.08, 0)), 0.035, "steel", verts=10))
	bits.append(cyl(name + "_knee", 0.07, 0.12, top.lerp(foot, 0.5), "accent", axis='X', verts=12))
	bits.append(cyl(name + "_pad", pad_r, 0.06, foot + Vector((0, 0.03, 0)), "trim", axis='Y', verts=16, r2=pad_r * 0.85))
	bits.append(torus(name + "_pg", pad_r * 0.8, 0.006, foot + Vector((0, 0.065, 0)), "glow", axis='Y', major=16, minor=4))
	bits.append(rod(name + "_brace", top + Vector((0, -0.05, 0.25)), top.lerp(foot, 0.5), 0.02, "steel", verts=6))
	o = join(name, bits)
	PIVOTS[name] = top
	return o


parts["gear_n"] = leg("gear_n", (0, 0.12, 1.9), (0, -LIFT, 2.0), 0.15)
parts["gear_l"] = leg("gear_l", (-1.15, 0.38, -1.5), (-1.35, -LIFT, -1.55))
parts["gear_r"] = leg("gear_r", (1.15, 0.38, -1.5), (1.35, -LIFT, -1.55))


def pod(name, cx):
	cy = 0.12
	n = 10
	prof = [(-2.55, 0.06), (-2.45, 0.15), (-2.2, 0.21), (-1.0, 0.21), (-0.6, 0.17), (-0.45, 0.08)]
	rings = [[(cx + math.cos(2 * math.pi * i / n) * r, cy + math.sin(2 * math.pi * i / n) * r, z) for i in range(n)] for (z, r) in prof]
	s = loft(name + "_s", rings, "paint")
	tri_fill(s)
	finish(s, 0.01, angle=20)
	bits = [s]
	bits.append(finish(loft(name + "_b", [[(cx + math.cos(2 * math.pi * i / n) * 0.218, cy + math.sin(2 * math.pi * i / n) * 0.218, z) for i in range(n)] for z in (-1.75, -1.6)], "accent")))
	bits.append(rod(name + "_gl", (cx + 0.22, cy, -2.15), (cx + 0.22, cy, -1.1), 0.006, "glow", verts=4))
	bits.append(box(name + "_py", (0.06, 0.3, 0.9), (cx, cy + 0.3, -1.6), "panel", 0.02))
	return join(name, bits)


pr = pod("pods", 2.55)
parts["pods"] = join("pods", [pr, mirror(pr)])


def fins():
	bits = []
	poly = [(0.0, -2.55), (0.0, -1.6), (0.42, -2.15), (0.5, -2.6)]
	for sx in (1, -1):
		f = prism_y("fin", [(z, x) for (x, z) in poly], 0, 0, "paint")
		# prism_y builds in XZ: map (a, b) -> x=a(z coord), z=b... rebuild directly instead:
		bpy.data.objects.remove(f, do_unlink=True)
		bm = bmesh.new()
		t = 0.025
		vs_o = [bm.verts.new((t, y, z)) for (y, z) in poly]
		vs_i = [bm.verts.new((-t, y, z)) for (y, z) in poly]
		bm.faces.new(vs_o)
		bm.faces.new(list(reversed(vs_i)))
		for i in range(len(poly)):
			bm.faces.new((vs_o[i], vs_o[(i + 1) % len(poly)], vs_i[(i + 1) % len(poly)], vs_i[i]))
		bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
		f = from_bm(bm, "fin", "paint")
		finish(f, 0.01)
		base = surf_y(0.36, -2.1) - 0.02
		f.data.transform(Matrix.Translation((sx * 0.36, base, 0)) @ Matrix.Rotation(math.radians(-sx * 18), 4, 'Z'))
		bits.append(f)
		tipx = sx * (0.36 + 0.46 * math.sin(math.radians(18)))
		bits.append(lamp("fin_lamp", (tipx, base + 0.46 * math.cos(math.radians(18)), -2.58), 0.02))
	return join("fins", bits)


parts["fins"] = fins()


def ring():
	"""The fold ring (Mk VI): an elliptical faceted hoop around the rear hull on four struts."""
	n = 12
	cy = 0.52
	rx, ry = 1.55, 0.95
	z0, z1 = -2.2, -1.75
	def pt(i, grow, z):
		a = 2 * math.pi * (i + 0.5) / n
		return (math.cos(a) * (rx + grow), cy + math.sin(a) * (ry + grow), z)
	outer = [[pt(i, 0.0, z) for i in range(n)] for z in (z0, z1)]
	inner = [[pt(i, -0.12, z) for i in range(n)] for z in (z0, z1)]
	bm = bmesh.new()
	O = [[bm.verts.new(p) for p in r_] for r_ in outer]
	I = [[bm.verts.new(p) for p in r_] for r_ in inner]
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new((O[0][i], O[0][j], O[1][j], O[1][i]))
		bm.faces.new((I[0][i], I[1][i], I[1][j], I[0][j]))
		bm.faces.new((O[0][i], I[0][i], I[0][j], O[0][j]))
		bm.faces.new((O[1][i], O[1][j], I[1][j], I[1][i]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	r_ = from_bm(bm, "ring_hoop", "paint")
	finish(r_, 0.015, angle=25)
	bits = [r_]
	gl = [[pt(i, -0.125, (z0 + z1) * 0.5) for i in range(n)]]
	for i in range(n):
		bits.append(rod("ring_gl", gl[0][i], gl[0][(i + 1) % n], 0.008, "glow", verts=4))
	for i in range(n):
		if i % 3 == 0:
			a = 2 * math.pi * (i + 0.5) / n
			bits.append(box("ring_node", (0.16, 0.16, 0.5), pt(i, 0.03, (z0 + z1) * 0.5), "accent", 0.03, rot=(0, 0, math.degrees(a))))
	for (x, y) in ((0.6, 0.85), (-0.6, 0.85), (0.6, 0.2), (-0.6, 0.2)):
		a = math.atan2((y - cy) / ry, x / rx)
		end = (math.cos(a) * (rx - 0.1), cy + math.sin(a) * (ry - 0.1), (z0 + z1) * 0.5)
		bits.append(rod("ring_strut", (x * 0.9, y, (z0 + z1) * 0.5), end, 0.035, "steel", verts=8))
	return join("ring", bits)


parts["ring"] = ring()


def vault():
	"""The seed vault (Mk VII): a long faceted greenhouse on the mid hull with seedling trays inside."""
	z0, z1 = 0.05, MID - 0.05
	n = 6
	rings = []
	base = surf_y(0, 0.0)
	for z in (z0, z0 + 0.12, z1 - 0.12, z1):
		k = 0.7 if z in (z0, z1) else 1.0
		pts = []
		for i in range(n + 1):
			a = math.pi * i / n
			pts.append((math.cos(a) * 0.5 * k, base - 0.03 + math.sin(a) * 0.42 * k, z))
		rings.append(pts)
	bm = bmesh.new()
	R = [[bm.verts.new(p) for p in r_] for r_ in rings]
	for k in range(3):
		for i in range(n):
			bm.faces.new((R[k][i], R[k][i + 1], R[k + 1][i + 1], R[k + 1][i]))
	bm.faces.new(R[0])
	bm.faces.new(list(reversed(R[-1])))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	g = from_bm(bm, "vault_glass", "vault_glass")
	finish(g, 0.0, smooth_angle=5)
	bits = [g]
	for z in (z0 + 0.12, (z0 + z1) * 0.5, z1 - 0.12):
		for i in range(n):
			a0, a1 = math.pi * i / n, math.pi * (i + 1) / n
			bits.append(rod("vrib", (math.cos(a0) * 0.51, base - 0.03 + math.sin(a0) * 0.43, z), (math.cos(a1) * 0.51, base - 0.03 + math.sin(a1) * 0.43, z), 0.022, "paint", verts=6))
	for i in range(1, n):
		a = math.pi * i / n
		bits.append(rod("vspine", (math.cos(a) * 0.51, base - 0.03 + math.sin(a) * 0.43, z0 + 0.1), (math.cos(a) * 0.51, base - 0.03 + math.sin(a) * 0.43, z1 - 0.1), 0.012, "paint", verts=6))
	# Trays of seedlings inside (green glow under them), and a sill.
	bits.append(box("vtray", (0.7, 0.05, z1 - z0 - 0.3), (0, base + 0.02, (z0 + z1) * 0.5), "trim", 0.01))
	bits.append(box("vtray_glow", (0.66, 0.01, z1 - z0 - 0.34), (0, base + 0.05, (z0 + z1) * 0.5), "vault", 0.0))
	import random
	rnd = random.Random(7)
	for k in range(26):
		x = rnd.uniform(-0.28, 0.28)
		z = rnd.uniform(z0 + 0.25, z1 - 0.25)
		bm = bmesh.new()
		bmesh.ops.create_icosphere(bm, subdivisions=1, radius=rnd.uniform(0.04, 0.07))
		leafy = from_bm(bm, "sprout", "leaf")
		leafy.data.transform(Matrix.Translation((x, base + 0.1, z)) @ Matrix.Scale(1.0, 4))
		finish(leafy, smooth_angle=60)
		bits.append(leafy)
	for sx in (1, -1):
		bits.append(box("vsill", (0.06, 0.06, z1 - z0), (sx * 0.5, base - 0.02, (z0 + z1) * 0.5), "accent", 0.02))
	return join("vault", bits)


parts["vault"] = vault()


# ---------------------------------------------------------------- vertex colours (AO + edge wear)
def curvature(obj):
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bm.verts.ensure_lookup_table()
	cur = [0.0] * len(bm.verts)
	for v in bm.verts:
		if not v.link_edges:
			continue
		acc = 0.0
		for e in v.link_edges:
			d = e.other_vert(v).co - v.co
			l = d.length
			if l > 1e-7:
				acc += v.normal.dot(d / l)
		cur[v.index] = acc / len(v.link_edges)
	bm.free()
	return cur


objs = [o for o in bpy.data.objects if o.type == 'MESH']
names = sorted(o.name for o in objs)
print("parts:", names)
for o in objs:
	attr = o.data.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
	o.data.color_attributes.active_color = attr
	for d in attr.data:
		d.color = (1, 1, 1, 1)

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = int(os.environ.get("AO_SAMPLES", "48"))
scene.cycles.device = 'CPU'
scene.render.bake.target = 'VERTEX_COLORS'
scene.world = bpy.data.worlds.new("w") if scene.world is None else scene.world
scene.world.light_settings.distance = 0.35
ao = {}
BY = {o.name: o for o in objs}
LOW = ["hull_rear", "hull_front", "wing", "canopy_a", "eng_a", "skid_l", "skid_r", "wing_ext"]
HIGH = ["hull_mid", "canopy_b", "eng_b", "gear_n", "gear_l", "gear_r", "pods", "eng_c", "fins", "wing_big", "ring", "eng_tip", "vault", "eng_core"]
FRONT = ["hull_front", "canopy_a", "canopy_b", "gear_n"]


def bake_ao(targets, visible):
	for o in objs:
		o.hide_render = o.name not in visible
	bpy.ops.object.select_all(action='DESELECT')
	tl = [BY[n] for n in targets]
	for o in tl:
		o.select_set(True)
	bpy.context.view_layer.objects.active = tl[0]
	try:
		bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
		for o in tl:
			ao[o.name] = [d.color[0] for d in o.data.color_attributes["Col"].data]
		print("AO bake ok", targets[:3])
	except Exception as ex:  # pragma: no cover
		print("AO bake failed:", ex)
	for o in objs:
		o.hide_render = False


if not os.environ.get("NO_BAKE"):
	# Pass 1: the Mk II look (all the low-tier parts together).
	bake_ao(LOW, LOW)
	# Pass 2: the Mk VII layout (front moved forward by MID), high-tier parts.
	for n in FRONT:
		BY[n].location.z += MID
	vis = ["hull_rear", "hull_front", "hull_mid", "wing", "canopy_b", "eng_b", "gear_n", "gear_l", "gear_r", "pods", "eng_c", "fins", "wing_big", "ring", "eng_tip", "vault", "eng_core"]
	bake_ao(HIGH, vis)
	for n in FRONT:
		BY[n].location.z -= MID

for o in objs:
	cur = curvature(o)
	a = ao.get(o.name)
	data = o.data.color_attributes["Col"].data
	for i, d in enumerate(data):
		c = cur[i]
		edge = min(max((-c - 0.03) * 5.0, 0.0), 1.0)
		cav = min(max((c - 0.02) * 6.0, 0.0), 1.0)
		occ = a[i] if a else 1.0
		d.color = (occ, edge, cav, 1.0)

# ---------------------------------------------------------------- pivots, axis conversion, export
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
UP = Matrix.Translation((0, LIFT, 0))
for o in objs:
	piv = PIVOTS.get(o.name, Vector((0, -LIFT, 0))) + Vector((0, LIFT, 0))
	o.data.transform(UP)
	o.data.transform(Matrix.Translation(-piv))
	o.data.transform(TO_BLENDER)
	o.location = TO_BLENDER @ piv
	o.data.use_auto_smooth = True
	print("part", o.name, len(o.data.vertices), "verts", [m.name for m in o.data.materials])
for k in ("canopy_hinge_a", "canopy_hinge_b"):
	pass

import struct


def write_glb(path, objects):
	bin_data = bytearray()
	views, accessors, meshes, nodes, materials = [], [], [], [], []
	mat_index = {}

	def add_view(data, target):
		while len(bin_data) % 4:
			bin_data.append(0)
		views.append({"buffer": 0, "byteOffset": len(bin_data), "byteLength": len(data), "target": target})
		bin_data.extend(data)
		return len(views) - 1

	def add_acc(flat, count, comp, typ, target, minmax=False):
		fmt = "<%d%s" % (len(flat), "f" if comp == 5126 else "I")
		v = add_view(struct.pack(fmt, *flat), target)
		a = {"bufferView": v, "componentType": comp, "count": count, "type": typ}
		if minmax:
			xs, ys, zs = flat[0::3], flat[1::3], flat[2::3]
			a["min"] = [min(xs), min(ys), min(zs)]
			a["max"] = [max(xs), max(ys), max(zs)]
		accessors.append(a)
		return len(accessors) - 1

	for o in objects:
		me = o.data
		me.calc_loop_triangles()
		me.calc_normals_split()
		col = me.color_attributes["Col"].data
		prims = {}
		for tri in me.loop_triangles:
			prims.setdefault(tri.material_index, []).append(tri)
		gprims = []
		for mi, tris in sorted(prims.items()):
			pos, nrm, cl, idx = [], [], [], []
			remap = {}
			for tri in tris:
				for li in tri.loops:
					lp = me.loops[li]
					key = (lp.vertex_index, round(lp.normal.x, 3), round(lp.normal.y, 3), round(lp.normal.z, 3))
					if key not in remap:
						co = me.vertices[lp.vertex_index].co
						n = lp.normal
						remap[key] = len(pos) // 3
						pos += [co.x, co.z, -co.y]
						nrm += [n.x, n.z, -n.y]
						c = col[lp.vertex_index].color
						cl += [c[0], c[1], c[2], 1.0]
					idx.append(remap[key])
			mname = me.materials[mi].name
			if mname not in mat_index:
				mat_index[mname] = len(materials)
				materials.append({"name": mname, "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.8, 1.0]}})
			n = len(pos) // 3
			gprims.append({"attributes": {
				"POSITION": add_acc(pos, n, 5126, "VEC3", 34962, True),
				"NORMAL": add_acc(nrm, n, 5126, "VEC3", 34962),
				"COLOR_0": add_acc(cl, n, 5126, "VEC4", 34962)},
				"indices": add_acc(idx, len(idx), 5125, "SCALAR", 34963), "material": mat_index[mname]})
		meshes.append({"name": o.name, "primitives": gprims})
		L = o.location
		nodes.append({"name": o.name, "mesh": len(meshes) - 1, "translation": [L.x, L.z, -L.y]})
	gltf = {"asset": {"version": "2.0", "generator": "build_ship.py"}, "scene": 0,
		"scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": meshes, "materials": materials,
		"accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(bin_data)}]}
	js = json.dumps(gltf, separators=(",", ":")).encode()
	while len(js) % 4:
		js += b" "
	while len(bin_data) % 4:
		bin_data.append(0)
	total = 12 + 8 + len(js) + 8 + len(bin_data)
	with open(path, "wb") as f:
		f.write(struct.pack("<III", 0x46546C67, 2, total))
		f.write(struct.pack("<II", len(js), 0x4E4F534A))
		f.write(js)
		f.write(struct.pack("<II", len(bin_data), 0x004E4942))
		f.write(bin_data)


write_glb(OUT, sorted(objs, key=lambda o: o.name))
POINTS["pivots"] = {k: [v.x, v.y + LIFT, v.z] for k, v in PIVOTS.items()}
with open(OUT_PTS, "w") as f:
	json.dump(POINTS, f, indent=1)
print("exported", OUT, OUT_PTS)

# ---------------------------------------------------------------- optional Cycles preview
if os.environ.get("PREVIEW"):
	cols = {"paint": (0.86, 0.86, 0.84), "panel": (0.72, 0.73, 0.74), "trim": (0.07, 0.075, 0.085), "accent": (1.0, 0.42, 0.1),
		"dark": (0.02, 0.02, 0.025), "steel": (0.5, 0.5, 0.52), "glow": (0.3, 0.88, 1.0), "lamp": (1.0, 0.3, 0.1),
		"glass": (0.05, 0.45, 0.6), "thruster": (0.3, 0.9, 1.0), "vault": (0.4, 1.0, 0.5), "vault_glass": (0.6, 0.85, 0.75), "leaf": (0.2, 0.6, 0.2)}
	for name, m in MATS.items():
		b = m.node_tree.nodes["Principled BSDF"]
		b.inputs["Base Color"].default_value = (*cols.get(name, (0.5, 0.5, 0.5)), 1)
		b.inputs["Roughness"].default_value = 0.08 if name in ("glass", "vault_glass") else 0.35
		b.inputs["Metallic"].default_value = 0.8 if name == "steel" else 0.0
		if name in ("glow", "lamp", "thruster", "vault"):
			b.inputs["Emission Color"].default_value = (*cols[name], 1)
			b.inputs["Emission Strength"].default_value = 5.0
	TIERS = {
		1: ["hull_rear", "hull_front", "wing", "canopy_a", "eng_a", "skid_l", "skid_r"],
		4: ["hull_rear", "hull_front", "wing", "wing_ext", "canopy_b", "eng_b", "gear_n", "gear_l", "gear_r", "pods"],
		5: ["hull_rear", "hull_front", "hull_mid", "wing", "wing_ext", "canopy_b", "eng_b", "eng_c", "fins", "gear_n", "gear_l", "gear_r", "pods"],
		6: ["hull_rear", "hull_front", "hull_mid", "wing", "wing_big", "canopy_b", "eng_b", "eng_c", "fins", "gear_n", "gear_l", "gear_r", "pods", "ring", "eng_tip"],
		7: ["hull_rear", "hull_front", "hull_mid", "wing", "wing_big", "canopy_b", "eng_b", "eng_c", "fins", "gear_n", "gear_l", "gear_r", "pods", "ring", "eng_tip", "vault", "eng_core"],
	}
	scene.cycles.samples = 24
	scene.cycles.use_denoising = False
	scene.render.resolution_x = 720
	scene.render.resolution_y = 540
	w = scene.world
	w.use_nodes = True
	w.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.45, 0.5, 1)
	sun = link(bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')))
	sun.data.energy = 3.5
	sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(-35))
	cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
	cam.data.lens = 50
	scene.camera = cam
	which = [int(x) for x in os.environ.get("PREVIEW_TIERS", "1,4,5,6,7").split(",")]
	for t in which:
		show = TIERS[t]
		for o in objs:
			o.hide_render = o.name not in show
			o.location = o.location.copy()
		for n in FRONT:
			if n in BY:
				base = BY[n].get("z0")
				if base is None:
					BY[n]["z0"] = BY[n].location.y
				# Blender frame: Godot +Z (nose) is Blender -Y.
				BY[n].location.y = BY[n]["z0"] - (MID if t >= 5 else 0.0)
		for k, (az, el, dist) in enumerate(((35, 22, 11.0 + t), (90, 4, 10.0 + t), (0, 75, 12.0 + t))):
			a = math.radians(az)
			target = Vector((0, 0 if t < 5 else -0.6, 0.6))
			pos = target + Vector((math.sin(a) * dist, -math.cos(a) * dist, math.tan(math.radians(el)) * dist))
			cam.location = pos
			cam.rotation_euler = (target - pos).to_track_quat('-Z', 'Y').to_euler()
			scene.render.filepath = "%s_mk%d_%d.png" % (os.environ["PREVIEW"], t, k)
			bpy.ops.render.render(write_still=True)
