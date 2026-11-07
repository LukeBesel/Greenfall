# Builds the Aurora hero bot mesh set and exports art/models/aurora/aurora.glb (rebuilt Nov 2026 to the
# owner's concept portrait + turnaround: wide rounded head with a thick shell, one curved black visor,
# round cyan-ringed side modules, a short swept fin with an amber edge, a compact torso with a raised
# recycling plate and orange latches, short chunky arms with curved claws, a rounded underside with one
# recessed hover ring; real panel grooves, screws and joint gaps).
#   blender -b --python art/models/aurora/build_aurora.py
# DESIGNS=1 also rebuilds designs.glb from designs_addons.py (the unlockable designs' add-ons, still
# placed for the previous head).
# Everything is modelled in Godot coordinates (Y up, the bot faces -Z) and rotated into Blender's
# Z-up frame just before export, so the glTF comes out in the same space PatchModel uses.
# Each exported object is one animated part of PatchModel; its origin is the part's pivot
# (in the float space of the bot) and its vertices are relative to that pivot.
# Material slot names tell PatchModel which runtime material goes on each surface.
# Vertex colours: R = baked ambient occlusion, G = convex edge wear, B = cavity dirt, A = 1 - joint wear.
import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "aurora.glb")

for o in list(bpy.data.objects):
	bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.meshes):
	bpy.data.meshes.remove(m)

MATS = {}


def mat(name):
	if name not in MATS:
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		MATS[name] = m
	return MATS[name]


def link(obj):
	bpy.context.scene.collection.objects.link(obj)
	return obj


def from_bm(bm, name, material):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = link(bpy.data.objects.new(name, me))
	obj.data.materials.append(mat(material))
	return obj


def apply_mods(obj):
	bpy.context.view_layer.objects.active = obj
	for o in bpy.context.view_layer.objects:
		o.select_set(o == obj)
	for md in list(obj.modifiers):
		bpy.ops.object.modifier_apply(modifier=md.name)


def smooth(obj, angle=None):
	for p in obj.data.polygons:
		p.use_smooth = True
	if angle is not None:
		# Keep crisp creases on hard edges (split normals by angle).
		bpy.context.view_layer.objects.active = obj
		for o in bpy.context.view_layer.objects:
			o.select_set(o == obj)
		bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle)) if hasattr(bpy.ops.object, "shade_smooth_by_angle") else None
	return obj


def xform(obj, center=(0, 0, 0), rot=(0, 0, 0)):
	"""Rotate (degrees, XYZ euler, Godot axes) then move the mesh data."""
	r = Matrix.Rotation(math.radians(rot[2]), 4, 'Z') @ Matrix.Rotation(math.radians(rot[1]), 4, 'Y') @ Matrix.Rotation(math.radians(rot[0]), 4, 'X')
	r = Matrix.Rotation(math.radians(rot[1]), 4, 'Y') @ Matrix.Rotation(math.radians(rot[0]), 4, 'X') @ Matrix.Rotation(math.radians(rot[2]), 4, 'Z')
	obj.data.transform(Matrix.Translation(Vector(center)) @ r)
	return obj


def rbox(name, size, center, bevel, material, segs=3, sub=2, rot=(0, 0, 0)):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
	obj = from_bm(bm, name, material)
	if bevel > 0:
		md = obj.modifiers.new("bev", 'BEVEL')
		md.width = min(bevel, min(size) * 0.499)
		md.segments = segs
		md.limit_method = 'NONE'
		md.profile = 0.5
	if sub > 0:
		md = obj.modifiers.new("sub", 'SUBSURF')
		md.levels = sub
		md.render_levels = sub
	apply_mods(obj)
	xform(obj, center, rot)
	return smooth(obj)


def cyl(name, r, depth, center, material, axis='Y', verts=32, bevel=0.0, r2=None, segs=2, rot=None):
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth)
	obj = from_bm(bm, name, material)
	if bevel > 0:
		md = obj.modifiers.new("bev", 'BEVEL')
		md.width = bevel
		md.segments = segs
		md.limit_method = 'ANGLE'
		md.angle_limit = math.radians(40)
		apply_mods(obj)
	# bmesh cone is along Z; orient it.
	if rot is None:
		rot = {'X': (0, 90, 0), 'Y': (90, 0, 0), 'Z': (0, 0, 0)}[axis]
	xform(obj, center, rot)
	smooth(obj)
	# Flat caps: crisp normals with auto smooth.
	obj.data.use_auto_smooth = True
	obj.data.auto_smooth_angle = math.radians(35)
	return obj


def torus(name, R, r, center, material, axis='Y', major=48, minor=10):
	bm = bmesh.new()
	verts = []
	for i in range(major):
		a = 2 * math.pi * i / major
		row = []
		for j in range(minor):
			b = 2 * math.pi * j / minor
			rr = R + r * math.cos(b)
			row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b))))
		verts.append(row)
	for i in range(major):
		for j in range(minor):
			bm.faces.new((verts[i][j], verts[(i + 1) % major][j], verts[(i + 1) % major][(j + 1) % minor], verts[i][(j + 1) % minor]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	obj = from_bm(bm, name, material)
	rot = {'X': (0, 90, 0), 'Y': (90, 0, 0), 'Z': (0, 0, 0)}[axis]
	xform(obj, center, rot)
	return smooth(obj)


def lathe(name, profile, material, segs=48, center=(0, 0, 0)):
	"""profile: list of (radius, y) from top to bottom; revolved around Y."""
	bm = bmesh.new()
	rings = []
	for (r, y) in profile:
		ring = []
		for i in range(segs):
			a = 2 * math.pi * i / segs
			ring.append(bm.verts.new((r * math.cos(a), y, r * math.sin(a))))
		rings.append(ring)
	for k in range(len(rings) - 1):
		for i in range(segs):
			bm.faces.new((rings[k][i], rings[k][(i + 1) % segs], rings[k + 1][(i + 1) % segs], rings[k + 1][i]))
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	obj = from_bm(bm, name, material)
	xform(obj, center)
	return smooth(obj)


def tube(name, pts, r, material, sides=12, r_end=None):
	"""A tube along a polyline (Catmull-Rom smoothed)."""
	# Smooth the path.
	path = []
	n = len(pts)
	P = [Vector(p) for p in pts]
	for i in range(n - 1):
		p0 = P[max(i - 1, 0)]
		p1 = P[i]
		p2 = P[i + 1]
		p3 = P[min(i + 2, n - 1)]
		for s in range(8):
			t = s / 8
			t2 = t * t
			t3 = t2 * t
			path.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
	path.append(P[-1])
	bm = bmesh.new()
	rings = []
	prev_n = None
	for i, c in enumerate(path):
		d = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
		up = Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 0, 1))
		nrm = (up - d * up.dot(d)).normalized() if prev_n is None else (prev_n - d * prev_n.dot(d)).normalized()
		prev_n = nrm
		bi = d.cross(nrm)
		rr = r if r_end is None else r + (r_end - r) * i / (len(path) - 1)
		ring = [bm.verts.new(c + (nrm * math.cos(2 * math.pi * k / sides) + bi * math.sin(2 * math.pi * k / sides)) * rr) for k in range(sides)]
		rings.append(ring)
	for k in range(len(rings) - 1):
		for i in range(sides):
			bm.faces.new((rings[k][i], rings[k][(i + 1) % sides], rings[k + 1][(i + 1) % sides], rings[k + 1][i]))
	bm.faces.new(list(reversed(rings[0])))
	bm.faces.new(rings[-1])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return smooth(from_bm(bm, name, material))


def boolean(target, cutter, op='DIFFERENCE', keep=False):
	md = target.modifiers.new("bool", 'BOOLEAN')
	md.operation = op
	md.object = cutter
	md.solver = 'EXACT'
	md.material_mode = 'TRANSFER'
	apply_mods(target)
	if not keep:
		bpy.data.objects.remove(cutter, do_unlink=True)
	return target


def groove(target, slab_size, center, rot=(0, 0, 0), depth=0.012, material="trim"):
	"""Cut a shallow panel seam: a thin slab, hollowed by a shrunk copy of the target."""
	slab = rbox("slab", slab_size, center, 0.0, material, sub=0, rot=rot)
	core = target.copy()
	core.data = target.data.copy()
	link(core)
	# Shrink along normals.
	bm = bmesh.new()
	bm.from_mesh(core.data)
	for v in bm.verts:
		v.co -= v.normal * depth
	bm.to_mesh(core.data)
	bm.free()
	boolean(slab, core)
	boolean(target, slab)
	return target


def join(name, objs):
	bpy.ops.object.select_all(action='DESELECT')
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.join()
	o = bpy.context.view_layer.objects.active
	o.name = name
	o.data.name = name
	return o


def mirror_x(obj, name):
	c = obj.copy()
	c.data = obj.data.copy()
	link(c)
	c.data.transform(Matrix.Scale(-1, 4, Vector((1, 0, 0))))
	c.data.flip_normals()
	c.name = name
	c.data.name = name
	return c



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


def screw(center, normal, r=0.0085, name="screw"):
	"""A small domed screw head with a slot, its axis along `normal` (sunk a hair into the surface)."""
	n = Vector(normal).normalized()
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=10, radius1=r, radius2=r * 0.75, depth=r * 0.6)
	o = from_bm(bm, name, "steel")
	slot = rbox("slot", (r * 1.7, r * 0.32, r * 0.5), (0, 0, r * 0.3), 0.0, "dark", sub=0)
	o = join(name, [o, slot])
	q = n.to_track_quat('Z', 'Y').to_matrix().to_4x4()
	o.data.transform(Matrix.Translation(Vector(center) + n * (r * 0.1)) @ q)
	smooth(o)
	return o


def with_material(obj, material):
	if material not in [m.name for m in obj.data.materials]:
		obj.data.materials.append(mat(material))
	return [m.name for m in obj.data.materials].index(material)


# ================================================================ HERO (Aurora rebuild, owner's concept)
# Layout (float space, metres; base of the hover pod near y = 0.1):
#   head 0.55 .. 1.13 (about 56% of the height; wide rounded rectangle, thick off-white shell),
#   torso 0.28 .. 0.55 tucked right under it, compact rounded underside 0.105 .. 0.28 with one
#   recessed hover ring, short chunky arms on shoulders at y 0.46.
HEAD_P = Vector((0, 0.56, 0))
HC = 0.84                      # head centre height
HW, HH, HD = 0.80, 0.58, 0.66  # head size
head = rbox("head_shell", (HW, HH, HD), (0, HC, 0), 0.2, "paint", segs=4, sub=2)


def bulge(obj):
	"""A gently convex front (the visor face), fading out toward the back and sides."""
	for v in obj.data.vertices:
		w = min(max(-v.co.z / (HD * 0.5), 0.0), 1.0)
		u = min(abs(v.co.x) / (HW * 0.5), 1.0)
		t = min(abs(v.co.y - HC) / (HH * 0.5), 1.0)
		v.co.z -= w * w * (0.03 * (1 - u * u) + 0.01 * (1 - t * t))


bulge(head)
from mathutils.bvhtree import BVHTree
_bm = bmesh.new()
_bm.from_mesh(head.data)
SHELL = BVHTree.FromBMesh(_bm)
_bm.free()


def shell_z(x, y):
	hit = SHELL.ray_cast(Vector((x, y, -2.0)), Vector((0, 0, 1)))
	return hit[0].z if hit[0] is not None else 0.0


def shell_hit(origin, direction):
	hit = SHELL.ray_cast(Vector(origin), Vector(direction).normalized())
	return (hit[0], hit[1]) if hit[0] is not None else (None, None)


# Visor: one curved glossy black screen across nearly the entire front (rounded-rectangle outline).
VA, VB, VN = 0.325, 0.212, 3.4
VCY = HC - 0.01


def outline(t, grow=0.0):
	c, s_ = math.cos(t), math.sin(t)
	x = (VA + grow) * math.copysign(abs(c) ** (2.0 / VN), c)
	y = (VB + grow) * math.copysign(abs(s_) ** (2.0 / VN), s_)
	return x, y


def conform(name, material, depth_fn, grow=0.0, back=0.05, rings=14, seg=96, wall_material=None):
	"""A slab following the head's front surface inside the visor outline.
	depth_fn(s) = how far behind the shell surface the front face sits (s = 0 centre .. 1 rim).
	The front gets `material`; the side wall and back get `wall_material` (only ONE face surface)."""
	bm = bmesh.new()
	center = bm.verts.new((0, VCY, shell_z(0, VCY) + depth_fn(0.0)))
	ring_vs = []
	for i in range(1, rings + 1):
		s_ = (i / rings) ** 0.8
		row = []
		for j in range(seg):
			x, y = outline(2 * math.pi * j / seg, grow)
			x *= s_
			y *= s_
			row.append(bm.verts.new((x, VCY + y, shell_z(x, VCY + y) + depth_fn(s_))))
		ring_vs.append(row)
	front = []
	for j in range(seg):
		front.append(bm.faces.new((center, ring_vs[0][(j + 1) % seg], ring_vs[0][j])))
	for i in range(rings - 1):
		for j in range(seg):
			front.append(bm.faces.new((ring_vs[i][j], ring_vs[i][(j + 1) % seg], ring_vs[i + 1][(j + 1) % seg], ring_vs[i + 1][j])))
	backs = [bm.verts.new((v.co.x, v.co.y, v.co.z + back)) for v in ring_vs[-1]]
	walls = []
	for j in range(seg):
		walls.append(bm.faces.new((ring_vs[-1][j], ring_vs[-1][(j + 1) % seg], backs[(j + 1) % seg], backs[j])))
	walls.append(bm.faces.new(backs))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	wall_set = set(walls)
	obj = from_bm(bm, name, material)
	if wall_material:
		wi = with_material(obj, wall_material)
		for p, f in zip(obj.data.polygons, front + walls):
			pass
		# bmesh face order is preserved in the mesh: fronts first, then walls.
		nf = len(front)
		for k, p in enumerate(obj.data.polygons):
			p.material_index = wi if k >= nf else 0
	return smooth(obj)


# Panel seams: a ring around the head behind the side modules, two crown seams front to back, and a
# low side seam. Real recessed grooves (they collect grime through the cavity bake).
groove(head, (0.95, 0.75, 0.008), (0, HC, 0.17), depth=0.012)
for s in (-1, 1):
	groove(head, (0.008, 0.16, 0.8), (s * 0.13, HC + HH * 0.5 - 0.02, 0.0), depth=0.01)
groove(head, (0.95, 0.008, 0.36), (0, HC - 0.14, 0.17), depth=0.01)
# Visor recess: the thick shell wraps the glass (dark trim walls).
cut = conform("visor_cut", "trim", lambda s_: 0.03, grow=0.014, back=-0.14)
boolean(head, cut)
# Back of the head: a dark horizontal vent slot up high and the rounded neck opening at the bottom.
cut = rbox("vent_cut", (0.34, 0.055, 0.12), (0, HC + 0.1, HD * 0.5 - 0.01), 0.025, "trim", sub=1)
boolean(head, cut)
cut = rbox("neck_cut", (0.36, 0.14, 0.42), (0, HC - HH * 0.5 + 0.02, 0.17), 0.06, "trim", sub=1)
boolean(head, cut)
head_parts = [head]
for k in range(3):
	head_parts.append(rbox("vent_slat", (0.31, 0.009, 0.014), (0, HC + 0.083 + k * 0.017, HD * 0.5 - 0.035), 0.004, "dark", sub=0, segs=2))
head_parts.append(rbox("neck_cavity", (0.33, 0.012, 0.36), (0, HC - HH * 0.5 + 0.075, 0.14), 0.005, "dark", sub=0))
# Thin dark gasket where the glass meets the shell (reads as a separate fitted part).
gpts = [outline(2 * math.pi * j / 96, 0.008) for j in range(96)]
gasket = []
bm = bmesh.new()
rows = []
for (gx, gy) in gpts:
	z0 = shell_z(gx, VCY + gy)
	rows.append((bm.verts.new((gx, VCY + gy, z0 + 0.02)), bm.verts.new((gx * 1.02, VCY + gy * 1.03, z0 + 0.034))))
for j in range(96):
	a, b = rows[j], rows[(j + 1) % 96]
	bm.faces.new((a[0], b[0], b[1], a[1]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
head_parts.append(smooth(from_bm(bm, "visor_gasket", "dark")))

# Orange cheek lights on the shell at the outer edges of the visor (like the portrait).
for s in (-1, 1):
	x = s * (VA + 0.045)
	y = VCY - 0.035
	z = shell_z(x, y)
	head_parts.append(rbox("cheek", (0.024, 0.085, 0.03), (x, y, z + 0.01), 0.01, "lamp_accent", sub=1, rot=(0, s * -38, 0)))
# Fasteners: four screws at the corners of the shell around the visor, two on the crown, four on the back.
for sx in (-1, 1):
	for sy in (-1, 1):
		x, y = sx * (VA + 0.035), VCY + sy * (VB + 0.03)
		p, n = shell_hit((x, y, -2.0), (0, 0, 1))
		if p is not None:
			head_parts.append(screw(p, n))
for sx in (-1, 1):
	p, n = shell_hit((sx * 0.13, 3.0, -0.2), (0, -1, 0))
	if p is not None:
		head_parts.append(screw(p, n, r=0.008))
	for sy in (0.17, -0.06):
		p, n = shell_hit((sx * 0.22, HC + sy, 2.0), (0, 0, -1))
		if p is not None:
			head_parts.append(screw(p, n))

# Side modules: a thick round white housing, a THIN dimmer cyan ring lens, a dark dish and a
# mechanical steel hub with radial fins and screws (no dark pupil dot: they must not read as eyes).
SM_Y, SM_Z = HC - 0.03, 0.01
SM_R = 0.132
mod = []
# Lathe profiles: (radius, height along the module axis; 0 = on the head side).
mod.append(lathe("sm_house", [(SM_R * 0.6, 0.0), (SM_R, 0.0), (SM_R + 0.006, 0.02), (SM_R + 0.002, 0.045), (SM_R - 0.008, 0.058), (SM_R - 0.022, 0.062),
	(0.102, 0.062), (0.097, 0.058), (0.096, 0.03)], "paint", segs=56))
mod.append(lathe("sm_dish", [(0.096, 0.031), (0.088, 0.034), (0.05, 0.03), (0.0, 0.028)], "trim", segs=48))
mod.append(torus("sm_ring", 0.0905, 0.0042, (0, 0.04, 0), "glow_soft", axis='Y', major=64, minor=8))
mod.append(lathe("sm_hub", [(0.0, 0.058), (0.02, 0.058), (0.034, 0.054), (0.04, 0.046), (0.042, 0.032)], "steel", segs=32))
mod.append(cyl("sm_hub_cap", 0.013, 0.008, (0, 0.06, 0), "dark", axis='Y', verts=16, bevel=0.002))
for k in range(6):
	a = 2 * math.pi * k / 6
	mod.append(rbox("sm_fin", (0.036, 0.012, 0.007), (math.cos(a) * 0.064, 0.038, math.sin(a) * 0.064), 0.002, "dark", sub=0, rot=(0, -math.degrees(a), 0)))
for k in range(4):
	a = 2 * math.pi * (k + 0.5) / 4
	mod.append(screw((math.cos(a) * 0.116, 0.061, math.sin(a) * 0.116), (0, 1, 0), r=0.006))
side_r = join("side_module_r", mod)
side_r.data.transform(Matrix.Translation(Vector((HW * 0.5 - 0.022, SM_Y, SM_Z))) @ Matrix.Rotation(math.radians(-90), 4, 'Z'))
side_l = mirror_x(side_r, "side_module_l")
head_parts += [side_r, side_l]
head = join("head", head_parts)

# Fin (part "antenna", same pivot as the head, so a design can leave it off): a short swept-back
# metal fin on a low crown mount, with an amber-lit leading/top edge.
TOP = HC + HH * 0.5
FIN_Z = 0.03
fin_pts = [(0.05, 0.0), (0.0, 0.05), (-0.055, 0.105), (-0.12, 0.14), (-0.17, 0.145), (-0.19, 0.13), (-0.15, 0.1), (-0.1, 0.035), (-0.09, 0.0)]
fin_pts = list(reversed(fin_pts))  # counter-clockwise
fin_parts = [
	rbox("fin_mount", (0.075, 0.035, 0.17), (0, TOP - 0.005, FIN_Z + 0.02), 0.014, "trim", segs=2, sub=1),
	prism("fin_blade", fin_pts, 0.026, (0, TOP + 0.005, FIN_Z), "fin", bevel=0.007, segs=2, sub=1, rot=(0, 90, 0)),
]
edge = [(0.05, 0.004), (0.0, 0.054), (-0.055, 0.109), (-0.12, 0.144), (-0.168, 0.149)]
fin_parts.append(tube("fin_edge", [(0, TOP + 0.005 + y + 0.002, FIN_Z - x) for (x, y) in edge], 0.0062, "lamp_accent", sides=8))
for z in (FIN_Z - 0.045, FIN_Z + 0.085):
	fin_parts.append(screw((0.038, TOP + 0.0, z), (1, 0.2, 0), r=0.006))
	fin_parts.append(screw((-0.038, TOP + 0.0, z), (-1, 0.2, 0), r=0.006))
antenna = join("antenna", fin_parts)

# Visor glass: convex, sitting just behind the shell lip at its edge and swelling forward in the
# middle. Only the front surface carries the "face" material (the eyes); walls/back are plain glass.
VISOR_C = Vector((0, VCY, shell_z(0, VCY)))
visor = conform("visor", "face", lambda s_: 0.026 - 0.02 * (1 - s_ * s_) - 0.004 * (1 - s_ ** 8), back=0.06, rings=14, seg=96, wall_material="screen")

# ---------------------------------------------------------------- BODY (pivot = float origin)
body_parts = []
TY, TH, TW, TD = 0.415, 0.27, 0.48, 0.38
upper = rbox("torso", (TW, TH, TD), (0, TY, 0), 0.085, "paint", segs=3, sub=1)
groove(upper, (0.6, 0.008, 0.5), (0, 0.335, 0), depth=0.01)            # waist seam
for s in (-1, 1):
	groove(upper, (0.008, 0.4, 0.5), (s * 0.165, TY, 0.06), depth=0.008)  # side panel seams (back half)
groove(upper, (0.6, 0.4, 0.008), (0, TY, 0.1), depth=0.008)
body_parts.append(upper)
# Dark mechanical band between torso and the underside (a visible gap).
body_parts.append(rbox("waist_gap", (0.4, 0.04, 0.3), (0, 0.285, 0.0), 0.016, "dark", sub=1))
# Raised metal chest plate with an inset border, four screws and the recycling icon.
PL_C = Vector((0, 0.42, -TD * 0.5 - 0.012))
plate = rbox("chest_plate", (0.255, 0.18, 0.04), PL_C, 0.016, "plate", segs=3, sub=1)
body_parts.append(plate)
body_parts.append(rbox("plate_base", (0.27, 0.195, 0.02), PL_C + Vector((0, 0, 0.012)), 0.008, "dark", sub=0, segs=2))
PL_FRONT = PL_C.z - 0.02
for sx in (-1, 1):
	for sy in (-1, 1):
		body_parts.append(screw((sx * 0.106, PL_C.y + sy * 0.068, PL_FRONT), (0, 0, -1), r=0.0075))
# Orange side latches either side of the plate (with a small amber lamp strip).
for s in (-1, 1):
	body_parts.append(rbox("latch", (0.034, 0.12, 0.05), (s * 0.158, PL_C.y, PL_C.z - 0.002), 0.012, "accent", segs=2, sub=1))
	body_parts.append(rbox("latch_lamp", (0.012, 0.07, 0.01), (s * 0.158, PL_C.y, PL_C.z - 0.027), 0.004, "lamp_accent", sub=0, segs=2))
	body_parts.append(rbox("latch_pin", (0.04, 0.012, 0.012), (s * 0.158, PL_C.y + 0.045, PL_C.z - 0.02), 0.004, "steel", sub=0, segs=1))
	# Shoulder sockets: dark recessed rings in the flanks.
	body_parts.append(cyl("shoulder_socket", 0.064, 0.04, (s * 0.232, 0.46, -0.01), "dark", axis='X', bevel=0.01))
	# Flank screws.
	for z in (-0.1, 0.12):
		body_parts.append(screw((s * TW * 0.5, 0.36, z), (s, 0, 0), r=0.007))
# Neck: short dark joint (gap) under the head.
body_parts.append(cyl("neck", 0.085, 0.06, (0, 0.56, 0.02), "dark", bevel=0.01))
body_parts.append(cyl("neck_ring", 0.1, 0.016, (0, 0.545, 0.02), "trim", bevel=0.006))
# Back: thin cyan frame around the bale hatch, screws.
for (sz, c) in (((0.22, 0.01, 0.01), (0, 0.5, 0.192)), ((0.22, 0.01, 0.01), (0, 0.34, 0.192)), ((0.01, 0.17, 0.01), (-0.11, 0.42, 0.192)), ((0.01, 0.17, 0.01), (0.11, 0.42, 0.192))):
	body_parts.append(rbox("hatch_frame", sz, c, 0.004, "glow_soft", sub=0, segs=2))
for sx in (-1, 1):
	for y in (0.36, 0.48):
		body_parts.append(screw((sx * 0.15, y, TD * 0.5), (0, 0, 1), r=0.007))
# Compact rounded underside: a white pod rounding in to a dark base with ONE recessed hover ring.
body_parts.append(lathe("pod", [(0.0, 0.29), (0.2, 0.29), (0.212, 0.272), (0.212, 0.245), (0.2, 0.215), (0.178, 0.188), (0.15, 0.17), (0.0, 0.17)], "paint", segs=56))
body_parts.append(lathe("pod_base", [(0.0, 0.18), (0.152, 0.18), (0.14, 0.158), (0.125, 0.135), (0.112, 0.122), (0.104, 0.121), (0.102, 0.128),
	(0.098, 0.13), (0.072, 0.13), (0.068, 0.128), (0.066, 0.121), (0.06, 0.12), (0.0, 0.122)], "trim", segs=56))
body_parts.append(torus("pod_seam", 0.152, 0.006, (0, 0.175, 0), "dark", major=56, minor=6))
for k in range(6):
	a = 2 * math.pi * (k + 0.5) / 6
	body_parts.append(screw((math.cos(a) * 0.132, 0.145, math.sin(a) * 0.132), (math.cos(a), -0.8, math.sin(a)), r=0.006))
body = join("body", body_parts)
thruster = torus("thruster", 0.085, 0.0095, (0, 0.124, 0), "thruster", major=56, minor=10)
core = cyl("thruster_core", 0.03, 0.006, (0, 0.122, 0), "thruster_core", verts=24)
thruster = join("thruster", [thruster, core])

# Recycling icon for the chest plate (its own part so other icons can replace it).
ICON_P = Vector((0, PL_C.y + 0.01, PL_FRONT - 0.002))


def recycle_icon(name, size, center, material):
	"""Three bent arrows chasing around a triangle (the recycling symbol), flat, facing -Z."""
	R = size * 0.5
	tri = [Vector((math.cos(math.radians(90 + 120 * k)), math.sin(math.radians(90 + 120 * k)), 0)) * R for k in range(3)]
	w = size * 0.15
	parts = []
	for k in range(3):
		c0 = tri[k]
		prev = tri[k - 1]
		nxt = tri[(k + 1) % 3]
		a = c0 + (prev - c0) * 0.3    # start on the previous edge
		b = c0 + (nxt - c0) * 0.4     # shaft end on the next edge
		h = c0 + (nxt - c0) * 0.6     # arrow tip (a clear gap before the next arrow)
		for (p, q) in ((a, c0), (c0, b)):
			d = (q - p).normalized()
			nrm = Vector((-d.y, d.x, 0)) * w * 0.5
			p2, q2 = p - d * w * 0.45, q + d * w * 0.45
			parts.append(prism("ic_shaft", [(p2 - nrm).to_2d()[:], (q2 - nrm).to_2d()[:], (q2 + nrm).to_2d()[:], (p2 + nrm).to_2d()[:]], 0.006, (0, 0, 0), material, sub=0))
		d = (nxt - c0).normalized()
		nrm = Vector((-d.y, d.x, 0))
		pts = [b - nrm * w * 1.5, h, b + nrm * w * 1.5]
		# Counter-clockwise.
		if (pts[1] - pts[0]).cross(pts[2] - pts[0]).z < 0:
			pts.reverse()
		parts.append(prism("ic_head", [p.to_2d()[:] for p in pts], 0.006, (0, 0, 0), material, sub=0))
	o = join(name, parts)
	# Arrows run clockwise as seen from the front (-Z): mirror X since the plate faces -Z.
	o.data.transform(Matrix.Translation(Vector(center)) @ Matrix.Scale(-1, 4, Vector((1, 0, 0))))
	o.data.flip_normals()
	return smooth(o)


icon_recycle = recycle_icon("icon_recycle", 0.105, ICON_P, "glow")

# Hatch (pivot 0, 0.5, 0.19, hinged at the top edge).
HATCH_P = Vector((0, 0.5, 0.19))
hatch = join("hatch", [
	rbox("hatch_plate", (0.2, 0.15, 0.026), (0, 0.42, 0.199), 0.01, "trim", sub=1, segs=3),
	rbox("hatch_screen", (0.11, 0.07, 0.01), (0, 0.43, 0.212), 0.005, "screen", sub=0, segs=2),
	rbox("hatch_handle", (0.08, 0.014, 0.014), (0, 0.365, 0.215), 0.006, "accent", sub=0, segs=2),
])

# ---------------------------------------------------------------- ARMS (right side; left is mirrored)
# Short and chunky: dark shoulder ball, white shoulder cap, short upper arm, dark elbow drum, a
# heavier white forearm, dark wrist; dark mechanical gaps and pistons between the armour.
S = Vector((0.27, 0.46, -0.01))
E = S + Vector((0.065, -0.115, -0.05))
W = E + Vector((0.0, -0.03, -0.15))
shoulder = join("arm_shoulder", [
	cyl("sh_ball", 0.052, 0.07, S + Vector((0.005, 0, 0)), "dark", axis='X', bevel=0.016, segs=3),
	rbox("sh_cap", (0.1, 0.11, 0.12), S + Vector((0.05, 0.012, 0.0)), 0.04, "paint", segs=3, sub=1),
	screw(S + Vector((0.1, 0.012, 0.0)), (1, 0, 0), r=0.008),
	tube("upper_arm", [S + Vector((0.045, -0.03, -0.01)), E], 0.03, "dark", sides=14),
	rbox("upper_armor", (0.07, 0.06, 0.07), (S + E) * 0.5 + Vector((0.025, -0.01, -0.012)), 0.022, "paint", segs=3, sub=1, rot=(-24, 0, 22)),
	tube("sh_piston", [S + Vector((0.02, -0.05, 0.035)), E + Vector((-0.02, 0.0, 0.03))], 0.006, "steel", sides=8),
])
elbow = join("arm_elbow", [
	cyl("el_drum", 0.04, 0.085, E, "dark", axis='X', bevel=0.012, segs=3),
	cyl("el_cap", 0.024, 0.09, E, "steel", axis='X', bevel=0.004),
	rbox("fore_armor", (0.09, 0.08, 0.12), E + Vector((0.004, -0.008, -0.08)), 0.03, "paint", segs=3, sub=1, rot=(8, 0, 0)),
	rbox("fore_band", (0.093, 0.084, 0.018), E + Vector((0.004, -0.01, -0.118)), 0.008, "trim", sub=0, segs=2, rot=(8, 0, 0)),
	screw(E + Vector((0.05, -0.006, -0.07)), (1, 0, 0), r=0.007),
	tube("el_piston", [E + Vector((-0.03, -0.04, -0.02)), E + Vector((-0.03, -0.035, -0.13))], 0.007, "steel", sides=8),
])
wrist = join("arm_wrist", [
	cyl("wr_ring", 0.04, 0.02, W + Vector((0, 0, 0.018)), "dark", axis='Z', bevel=0.006),
	cyl("wr_cuff", 0.046, 0.026, W + Vector((0, 0, -0.002)), "trim", axis='Z', bevel=0.008),
	cyl("palm", 0.042, 0.05, W + Vector((0, 0, -0.032)), "dark", axis='Z', bevel=0.012, segs=2, r2=0.036),
])
# One finger (base) and one claw tip, in their own frames: they point down -Z, outward = +Y.
finger = join("finger", [
	rbox("fg", (0.028, 0.024, 0.06), (0, 0.0, -0.026), 0.009, "dark", sub=0, segs=2),
	cyl("fg_knuckle", 0.014, 0.034, (0, 0.0, -0.055), "steel", axis='X', verts=12, bevel=0.004),
])
tip = tube("finger_tip", [(0, 0.0, 0.0), (0, 0.0, -0.025), (0, -0.01, -0.05), (0, -0.028, -0.066)], 0.012, "claw", sides=10, r_end=0.004)
for v in tip.data.vertices:
	v.co.x *= 1.25  # a little wider than deep (a blade, not a rod)
tip.name = tip.data.name = "finger_tip"

shoulder_l = mirror_x(shoulder, "arm_shoulder_l")
elbow_l = mirror_x(elbow, "arm_elbow_l")
wrist_l = mirror_x(wrist, "arm_wrist_l")
for o, n in ((shoulder, "arm_shoulder_r"), (elbow, "arm_elbow_r"), (wrist, "arm_wrist_r")):
	o.name = n
	o.data.name = n

PARTS = {
	"body": Vector((0, 0, 0)), "thruster": Vector((0, 0, 0)), "hatch": HATCH_P, "head": HEAD_P, "antenna": HEAD_P, "visor": VISOR_C,
	"icon_recycle": ICON_P,
	"arm_shoulder_r": S, "arm_elbow_r": E, "arm_wrist_r": W,
	"arm_shoulder_l": Vector((-S.x, S.y, S.z)), "arm_elbow_l": Vector((-E.x, E.y, E.z)), "arm_wrist_l": Vector((-W.x, W.y, W.z)),
	"finger": Vector((0, 0, 0)), "finger_tip": Vector((0, 0, 0)),
}
# Joint wear: armour near these pivots gets extra chips (vertex colour alpha).
JOINTS = [S, E, W, Vector((-S.x, S.y, S.z)), Vector((-E.x, E.y, E.z)), Vector((-W.x, W.y, W.z)), Vector((0, 0.56, 0.02))]


def decimate(obj, ratio):
	"""Collapse-decimate the dense subdivided shells (keeps the silhouette, halves the triangles)."""
	md = obj.modifiers.new("dec", 'DECIMATE')
	md.ratio = ratio
	apply_mods(obj)
	smooth(obj)


decimate(head, 0.5)
decimate(body, 0.6)
HERO_OBJS = [o for o in bpy.data.objects if o.type == 'MESH']
print("anchors: head_top", (0, TOP, FIN_Z), "chest_plate", tuple(ICON_P), "visor", tuple(VISOR_C), "claw W", tuple(W))

# ---------------------------------------------------------------- DESIGN ADD-ONS (designs.glb), opt-in
ACC = {}
if os.environ.get("DESIGNS"):
	# Frozen previous-hero constants: designs.glb stays exactly as it was.
	HC = 0.80
	S = Vector((0.27, 0.46, -0.01))
	exec(open(os.path.join(os.path.dirname(OUT), "designs_addons.py")).read())
ACC_OBJS = [o for (o, _p) in ACC.values()]
for name, (o, piv) in ACC.items():
	PARTS[name] = piv
	o.name = name
	o.data.name = name


# ---------------------------------------------------------------- vertex colours (AO + edge wear)
def curvature(obj, iters=2):
	"""Mean curvature per vertex (1/m, > 0 convex, < 0 concave), lightly smoothed over neighbours."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.verts.ensure_lookup_table()
	cur = [0.0] * len(bm.verts)
	for v in bm.verts:
		if not v.link_edges:
			continue
		acc, n = 0.0, 0
		for e in v.link_edges:
			o = e.other_vert(v)
			d = o.co - v.co
			l2 = d.length_squared
			if l2 > 1e-10:
				acc += (o.normal - v.normal).dot(d) / l2
				n += 1
		cur[v.index] = acc / max(n, 1)
	for _ in range(iters):
		nxt = cur[:]
		for v in bm.verts:
			if v.link_edges:
				nxt[v.index] = 0.5 * cur[v.index] + 0.5 * sum(cur[e.other_vert(v).index] for e in v.link_edges) / len(v.link_edges)
		cur = nxt
	bm.free()
	return cur


def sstep(a, b, x):
	t = min(max((x - a) / (b - a), 0.0), 1.0)
	return t * t * (3 - 2 * t)


objs = [o for o in bpy.data.objects if o.type == 'MESH']
for o in objs:
	attr = o.data.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
	o.data.color_attributes.active_color = attr
	for d in attr.data:
		d.color = (1, 1, 1, 1)

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 64
scene.cycles.device = 'CPU'
scene.render.bake.target = 'VERTEX_COLORS'
scene.world = bpy.data.worlds.new("w") if scene.world is None else scene.world
scene.world.light_settings.distance = 0.2
ao = {}
HERO_OBJS_NAMES = set(o.name for o in HERO_OBJS)


def bake_ao(targets, hidden):
	"""Bake AO into vertex colours for `targets`, with `hidden` left out of the occluders."""
	for o in objs:
		o.hide_render = o in hidden
	bpy.ops.object.select_all(action='DESELECT')
	for o in targets:
		o.select_set(True)
	bpy.context.view_layer.objects.active = targets[0]
	try:
		bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
		for o in targets:
			ao[o.name] = [d.color[0] for d in o.data.color_attributes["Col"].data]
		print("AO bake ok", [o.name for o in targets][:3])
	except Exception as ex:  # pragma: no cover
		print("AO bake failed:", ex)
	for o in objs:
		o.hide_render = False


# The hero bakes without any design add-on in the way; each add-on bakes against the hero alone.
bake_ao([o for o in HERO_OBJS if o.name not in ("finger", "finger_tip")], ACC_OBJS)
for o in ACC_OBJS:
	if o.name in ("acc_wing", "acc_bfly_body", "acc_gear", "acc_case"):
		continue
	bake_ao([o], [x for x in ACC_OBJS if x is not o])

for o in objs:
	cur = curvature(o)
	a = ao.get(o.name)
	data = o.data.color_attributes["Col"].data
	verts = o.data.vertices
	piv = PARTS.get(o.name, None)
	for i, d in enumerate(data):
		c = cur[i]
		edge = sstep(22.0, 75.0, c)
		cav = sstep(6.0, 30.0, -c)
		occ = a[i] if a else 1.0
		# Joint wear (alpha, 1 = none): armour and shell close to a joint pivot chip more.
		p = verts[i].co
		j = 0.0
		if o.name in HERO_OBJS_NAMES:
			for J in JOINTS:
				j = max(j, sstep(0.11, 0.035, (p - J).length))
		d.color = (occ, edge, cav, 1.0 - 0.8 * j)
	if o.name in ("head", "body", "arm_elbow_r"):
		cs = [d.color for d in data]
		n = max(len(cs), 1)
		print("mask", o.name, "edge>0.5 %.2f" % (sum(1 for c in cs if c[1] > 0.5) / n), "cav>0.5 %.2f" % (sum(1 for c in cs if c[2] > 0.5) / n), "ao<0.7 %.2f" % (sum(1 for c in cs if c[0] < 0.7) / n), "curv pct", sorted(cur)[int(n * 0.1)], sorted(cur)[int(n * 0.5)], sorted(cur)[int(n * 0.9)])

# ---------------------------------------------------------------- pivots, UVs, axis conversion, export
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Godot (x,y,z) -> Blender (x,-z,y)
for o in objs:
	piv = PARTS.get(o.name, Vector((0, 0, 0)))
	o.data.transform(Matrix.Translation(-piv))
	o.data.transform(TO_BLENDER)
	o.location = TO_BLENDER @ piv
	o.data.use_auto_smooth = True
	o.data.auto_smooth_angle = math.radians(50)
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.select_all(action='DESELECT')
	o.select_set(True)
	bpy.ops.object.mode_set(mode='EDIT')
	bpy.ops.mesh.select_all(action='SELECT')
	bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
	bpy.ops.object.mode_set(mode='OBJECT')
	print("part", o.name, len(o.data.vertices), "verts", [m.name for m in o.data.materials])


# Minimal GLB writer (Blender's bundled glTF exporter needs numpy, which this Blender lacks).
import json
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
		uv = me.uv_layers.active.data if me.uv_layers.active else None
		prims = {}
		for tri in me.loop_triangles:
			prims.setdefault(tri.material_index, []).append(tri)
		gprims = []
		for mi, tris in sorted(prims.items()):
			pos, nrm, cl, tc, idx = [], [], [], [], []
			remap = {}
			for tri in tris:
				# Blender is CCW front-facing like glTF; convert Z-up to Y-up: (x, y, z) -> (x, z, -y).
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
						cl += [c[0], c[1], c[2], c[3]]
						u = uv[li].uv if uv else (0.0, 0.0)
						tc += [u[0], 1.0 - u[1]]
					idx.append(remap[key])
			mname = me.materials[mi].name
			if mname not in mat_index:
				mat_index[mname] = len(materials)
				materials.append({"name": mname, "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.8, 1.0]}})
			n = len(pos) // 3
			gprims.append({"attributes": {
				"POSITION": add_acc(pos, n, 5126, "VEC3", 34962, True),
				"NORMAL": add_acc(nrm, n, 5126, "VEC3", 34962),
				"COLOR_0": add_acc(cl, n, 5126, "VEC4", 34962),
				"TEXCOORD_0": add_acc(tc, n, 5126, "VEC2", 34962)},
				"indices": add_acc(idx, len(idx), 5125, "SCALAR", 34963), "material": mat_index[mname]})
		meshes.append({"name": o.name, "primitives": gprims})
		L = o.location
		nodes.append({"name": o.name, "mesh": len(meshes) - 1, "translation": [L.x, L.z, -L.y]})
	gltf = {"asset": {"version": "2.0", "generator": "build_aurora.py"}, "scene": 0,
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


write_glb(OUT, sorted(HERO_OBJS, key=lambda o: o.name))
print("exported", OUT)
if ACC_OBJS:
	OUT_DESIGNS = os.path.join(os.path.dirname(OUT), "designs.glb")
	write_glb(OUT_DESIGNS, sorted(ACC_OBJS, key=lambda o: o.name))
	print("exported", OUT_DESIGNS)
tris = sum(len(o.data.loop_triangles) for o in HERO_OBJS)
print("hero tris (fingers/tips once):", tris, sorted(((len(o.data.loop_triangles), o.name) for o in HERO_OBJS), reverse=True)[:6])

# Optional quick Cycles preview of the shapes (PREVIEW=/path/prefix): front, 3/4, side, back.
if os.environ.get("PREVIEW"):
	cols = {"paint": (0.8, 0.78, 0.74), "trim": (0.08, 0.085, 0.095), "accent": (0.9, 0.4, 0.08), "dark": (0.05, 0.05, 0.055),
		"steel": (0.5, 0.5, 0.5), "glow": (0.3, 0.9, 1.0), "lamp_accent": (1.0, 0.6, 0.2), "screen": (0.01, 0.01, 0.01),
		"face": (0.01, 0.01, 0.012), "plate": (0.85, 0.83, 0.78), "fin": (0.55, 0.57, 0.6), "claw": (0.3, 0.31, 0.33), "glow_soft": (0.3, 0.9, 1.0), "thruster": (0.3, 0.9, 1.0), "thruster_core": (0.6, 1.0, 1.0)}
	for name, m in MATS.items():
		b = m.node_tree.nodes["Principled BSDF"]
		b.inputs["Base Color"].default_value = (*cols.get(name, (0.5, 0.5, 0.5)), 1)
		b.inputs["Roughness"].default_value = 0.1 if name in ("face", "screen") else 0.45
		if name in ("glow", "glow_soft", "lamp_accent", "thruster", "thruster_core"):
			b.inputs["Emission Color"].default_value = (*cols[name], 1)
			b.inputs["Emission Strength"].default_value = 4.0
	# Instance fingers onto the right wrist only (rough) for the preview.
	scene.cycles.samples = 24
	scene.cycles.use_denoising = False
	scene.render.resolution_x = 640
	scene.render.resolution_y = 640
	w = scene.world
	w.use_nodes = True
	w.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.22, 0.2, 1)
	sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
	link(sun)
	sun.data.energy = 3.0
	sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	link(cam)
	cam.data.lens = 70
	scene.camera = cam
	target = Vector((0, 0, 0.65))
	for i, (az, el) in enumerate(((0, 8), (40, 15), (90, 5), (180, 10))):
		a = math.radians(az)
		# Model faces Blender +Y (Godot -Z).
		pos = target + Vector((math.sin(a) * 3.2, math.cos(a) * 3.2, math.tan(math.radians(el)) * 3.2))
		cam.location = pos
		cam.rotation_euler = (target - pos).to_track_quat('-Z', 'Y').to_euler()
		scene.render.filepath = "%s_%d.png" % (os.environ["PREVIEW"], i)
		bpy.ops.render.render(write_still=True)
