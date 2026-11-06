# Builds the Aurora hero bot mesh set and exports art/models/aurora/aurora.glb.
#   blender -b --python art/models/aurora/build_aurora.py
# Everything is modelled in Godot coordinates (Y up, the bot faces -Z) and rotated into Blender's
# Z-up frame just before export, so the glTF comes out in the same space PatchModel uses.
# Each exported object is one animated part of PatchModel; its origin is the part's pivot
# (in the float space of the bot) and its vertices are relative to that pivot.
# Material slot names tell PatchModel which runtime material goes on each surface.
# Vertex colours: R = baked ambient occlusion, G = convex edge wear, B = cavity dirt.
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


# ---------------------------------------------------------------- HEAD (pivot 0, 0.56, 0)
HEAD_P = Vector((0, 0.56, 0))
HC = 0.80  # head centre height (float space)
head = rbox("head_shell", (0.78, 0.5, 0.6), (0, HC, 0), 0.2, "paint", segs=4, sub=2)


def bulge(obj):
	"""Make the head front gently convex (like the concept), fading out toward the back and ears."""
	for v in obj.data.vertices:
		w = min(max(-v.co.z / 0.3, 0.0), 1.0)
		u = min(abs(v.co.x) / 0.4, 1.0)
		t = min(abs(v.co.y - HC) / 0.3, 1.0)
		v.co.z -= w * (0.045 * (1 - u * u) + 0.012 * (1 - t * t))


bulge(head)
from mathutils.bvhtree import BVHTree
_bm = bmesh.new()
_bm.from_mesh(head.data)
SHELL = BVHTree.FromBMesh(_bm)
_bm.free()


def shell_z(x, y):
	hit = SHELL.ray_cast(Vector((x, y, -2.0)), Vector((0, 0, 1)))
	return hit[0].z if hit[0] is not None else 0.0


VA, VB, VN = 0.3, 0.185, 3.6  # visor outline: superellipse half-width, half-height, exponent


def outline(t, grow=0.0):
	c, s_ = math.cos(t), math.sin(t)
	x = (VA + grow) * math.copysign(abs(c) ** (2.0 / VN), c)
	y = (VB + grow) * math.copysign(abs(s_) ** (2.0 / VN), s_)
	return x, y


def conform(name, material, depth_fn, grow=0.0, back=0.05, rings=14, seg=96):
	"""A slab following the head's front surface inside the visor outline.
	depth_fn(s) = how far behind the shell surface the front face sits (s = 0 centre .. 1 rim)."""
	bm = bmesh.new()
	cy = HC - 0.005
	center = bm.verts.new((0, cy, shell_z(0, cy) + depth_fn(0.0)))
	ring_vs = []
	for i in range(1, rings + 1):
		s_ = i / rings
		row = []
		for j in range(seg):
			x, y = outline(2 * math.pi * j / seg, grow)
			x *= s_
			y *= s_
			row.append(bm.verts.new((x, cy + y, shell_z(x, cy + y) + depth_fn(s_))))
		ring_vs.append(row)
	for j in range(seg):
		bm.faces.new((center, ring_vs[0][(j + 1) % seg], ring_vs[0][j]))
	for i in range(rings - 1):
		for j in range(seg):
			bm.faces.new((ring_vs[i][j], ring_vs[i][(j + 1) % seg], ring_vs[i + 1][(j + 1) % seg], ring_vs[i + 1][j]))
	# Side wall and a flat back.
	backs = [bm.verts.new((v.co.x, v.co.y, v.co.z + back)) for v in ring_vs[-1]]
	for j in range(seg):
		bm.faces.new((ring_vs[-1][j], ring_vs[-1][(j + 1) % seg], backs[(j + 1) % seg], backs[j]))
	bm.faces.new(list(reversed(backs)) if False else backs)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return smooth(from_bm(bm, name, material))


# Panel seams: a ring around the head behind the ears and a crown seam line.
groove(head, (0.9, 0.7, 0.008), (0, HC, 0.13), depth=0.012)
groove(head, (0.008, 0.2, 0.42), (0, HC + 0.24, 0.12), depth=0.01)
# Visor recess following the convex front (its walls take the dark trim material).
cut = conform("visor_cut", "trim", lambda s_: 0.02, grow=0.012, back=-0.12)
boolean(head, cut)
# Top vent slot and rear slot (recessed, dark).
cut = rbox("vent_cut", (0.26, 0.08, 0.1), (0, HC + 0.26, -0.11), 0.03, "trim", sub=1)
boolean(head, cut)
cut = rbox("back_cut", (0.3, 0.06, 0.1), (0, HC + 0.12, 0.33), 0.025, "trim", sub=1)
boolean(head, cut)
head_parts = [head]
for k in range(4):
	head_parts.append(rbox("vent_slat", (0.2, 0.012, 0.012), (0, HC + 0.235, -0.145 + k * 0.022), 0.005, "dark", sub=1))
for k in range(2):
	head_parts.append(rbox("back_slat", (0.24, 0.01, 0.012), (0, HC + 0.112 + k * 0.02 - 0.01, 0.288), 0.004, "dark", sub=1))
# Chin: dark neck socket under the head.
head_parts.append(cyl("chin", 0.11, 0.04, (0, HC - 0.245, 0.0), "dark", bevel=0.01))
# Orange cheek lights at the lower outer corners of the visor.
for s in (-1, 1):
	head_parts.append(rbox("cheek", (0.03, 0.075, 0.05), (s * 0.325, HC - 0.075, shell_z(s * 0.325, HC - 0.075) + 0.018), 0.012, "lamp_accent", sub=1, rot=(0, s * -35, 0)))
# Ears: white housing, dark trim ring, glowing ring, dark vented cap with a hub.
for s in (-1, 1):
	x = s * 0.375
	head_parts.append(cyl("ear_house", 0.14, 0.08, (x, HC - 0.02, 0.05), "paint", axis='X', verts=48, bevel=0.025, segs=3))
	head_parts.append(cyl("ear_trim", 0.118, 0.03, (x + s * 0.042, HC - 0.02, 0.05), "dark", axis='X', verts=48, bevel=0.008))
	head_parts.append(torus("ear_ring", 0.1, 0.009, (x + s * 0.058, HC - 0.02, 0.05), "glow", axis='X'))
	head_parts.append(cyl("ear_cap", 0.085, 0.03, (x + s * 0.05, HC - 0.02, 0.05), "trim", axis='X', verts=48, bevel=0.01))
	head_parts.append(torus("ear_groove", 0.055, 0.005, (x + s * 0.066, HC - 0.02, 0.05), "dark", axis='X', major=40, minor=6))
	head_parts.append(cyl("ear_hub", 0.028, 0.02, (x + s * 0.068, HC - 0.02, 0.05), "steel", axis='X', verts=24, bevel=0.005))
# Antenna: dark base on the crown, a curved stalk leaning back, an orange swept fin.
head_parts.append(cyl("ant_base", 0.05, 0.05, (0.0, HC + 0.245, 0.12), "trim", verts=32, bevel=0.012, r2=0.04))
head_parts.append(cyl("ant_collar", 0.03, 0.03, (0.0, HC + 0.27, 0.125), "dark", verts=20, bevel=0.006))
head_parts.append(tube("ant_stalk", [(0, HC + 0.26, 0.125), (0, HC + 0.33, 0.15), (0, HC + 0.4, 0.13), (0, HC + 0.44, 0.08)], 0.014, "dark", r_end=0.011))
head_parts.append(cyl("ant_joint", 0.02, 0.04, (0, HC + 0.44, 0.08), "trim", axis='X', verts=16, bevel=0.006))
fin = rbox("ant_fin", (0.095, 0.018, 0.21), (0, HC + 0.455, 0.0), 0.0105, "accent", segs=2, sub=2)
# Sweep the fin: taper toward the front tip and bend up a little.
for v in fin.data.vertices:
	z = v.co.z
	t = min(max((0.08 - z) / 0.2, 0.0), 1.0)  # 0 at the back, 1 at the tip
	v.co.x *= 1.0 - 0.45 * t
	v.co.y += 0.05 * t * t
head_parts.append(fin)
head_parts.append(rbox("ant_tip", (0.038, 0.016, 0.03), (0, HC + 0.505, -0.098), 0.007, "lamp_accent", sub=1, rot=(-25, 0, 0)))
head = join("head", head_parts)


# Visor glass: a rounded slab with a gently convex front (the flat middle carries the eyes).
VISOR_C = Vector((0, HC - 0.005, shell_z(0, HC - 0.005)))
# Glass: sits just behind the rim at its edge and swells forward toward the middle (convex).
visor = conform("visor", "face", lambda s_: 0.019 - 0.014 * (1 - s_ * s_) - 0.004 * (1 - s_ ** 8), back=0.06, rings=18, seg=128)

# ---------------------------------------------------------------- BODY (pivot = float origin)
body_parts = []
upper = rbox("torso_up", (0.46, 0.24, 0.38), (0, 0.43, 0), 0.085, "paint", segs=3, sub=2)
# Side panel seams and chest screen recess.
groove(upper, (0.6, 0.008, 0.5), (0, 0.37, 0), depth=0.01)
cut = rbox("chest_cut", (0.24, 0.15, 0.1), (0, 0.43, -0.2), 0.03, "trim", sub=1)
boolean(upper, cut)
body_parts.append(upper)
body_parts.append(rbox("torso_low", (0.43, 0.15, 0.35), (0, 0.3, 0.0), 0.06, "trim", segs=3, sub=2))
body_parts.append(rbox("waist_band", (0.445, 0.035, 0.365), (0, 0.33, 0.0), 0.017, "dark", sub=1))
# Chest screen glass and orange side lights.
body_parts.append(rbox("chest_glass", (0.21, 0.125, 0.03), (0, 0.43, -0.165), 0.015, "screen", sub=1))
for s in (-1, 1):
	body_parts.append(rbox("chest_tab", (0.03, 0.11, 0.035), (s * 0.155, 0.43, -0.185), 0.012, "lamp_accent", sub=1))
	# Orange side panels on the flanks.
	body_parts.append(rbox("side_panel", (0.03, 0.13, 0.17), (s * 0.228, 0.43, -0.03), 0.012, "accent", sub=1))
	body_parts.append(rbox("side_vent", (0.012, 0.05, 0.08), (s * 0.244, 0.43, -0.03), 0.004, "dark", sub=1))
	# Shoulder sockets.
	body_parts.append(cyl("shoulder_socket", 0.06, 0.04, (s * 0.235, 0.46, -0.01), "dark", axis='X', bevel=0.01))
# Cyan light strip along the top front edge of the torso.
body_parts.append(tube("collar_strip", [(-0.17, 0.535, -0.165), (-0.08, 0.545, -0.185), (0.08, 0.545, -0.185), (0.17, 0.535, -0.165)], 0.008, "glow", sides=8))
# Neck.
body_parts.append(cyl("neck", 0.075, 0.07, (0, 0.565, 0.0), "dark", bevel=0.01))
body_parts.append(cyl("neck_ring", 0.09, 0.018, (0, 0.545, 0.0), "trim", bevel=0.006))
# Back: cyan frame around the bale hatch, two bolts.
for (sz, c) in (((0.23, 0.012, 0.012), (0, 0.5, 0.19)), ((0.23, 0.012, 0.012), (0, 0.32, 0.183)), ((0.012, 0.18, 0.012), (-0.115, 0.41, 0.19)), ((0.012, 0.18, 0.012), (0.115, 0.41, 0.19))):
	body_parts.append(rbox("hatch_frame", sz, c, 0.005, "glow", sub=1))
# Hover base: dark bowl, steel rim, thruster ring and core.
body_parts.append(lathe("bowl", [(0.0, 0.245), (0.13, 0.245), (0.158, 0.232), (0.165, 0.21), (0.155, 0.175), (0.13, 0.14), (0.105, 0.118), (0.088, 0.108), (0.0, 0.108)], "trim"))
body_parts.append(torus("bowl_rim", 0.16, 0.01, (0, 0.215, 0), "dark", major=56, minor=8))
for k in range(8):
	a = 2 * math.pi * (k + 0.5) / 8
	body_parts.append(rbox("bowl_fin", (0.014, 0.05, 0.03), (math.cos(a) * 0.148, 0.175, math.sin(a) * 0.148), 0.005, "dark", sub=1, rot=(0, -math.degrees(a), 0)))
body = join("body", body_parts)
thruster = torus("thruster", 0.09, 0.014, (0, 0.104, 0), "thruster", major=56, minor=10)
core = cyl("thruster_core", 0.078, 0.012, (0, 0.099, 0), "thruster_core", verts=48)
thruster = join("thruster", [thruster, core])

# Hatch (pivot 0, 0.5, 0.19 — hinged at the top edge).
HATCH_P = Vector((0, 0.5, 0.19))
hatch = join("hatch", [
	rbox("hatch_plate", (0.21, 0.17, 0.028), (0, 0.41, 0.197), 0.012, "trim", sub=2),
	rbox("hatch_screen", (0.12, 0.08, 0.01), (0, 0.42, 0.211), 0.006, "screen", sub=1),
	rbox("hatch_handle", (0.08, 0.015, 0.015), (0, 0.35, 0.215), 0.006, "accent", sub=1),
])

# ---------------------------------------------------------------- ARMS (right side; left is mirrored)
S = Vector((0.27, 0.46, -0.01))       # shoulder pivot
E = S + Vector((0.07, -0.13, -0.06))  # elbow pivot
W = E + Vector((0.0, -0.02, -0.16))   # wrist pivot
shoulder = join("arm_shoulder", [
	cyl("sh_ball", 0.05, 0.06, S + Vector((0.01, 0, 0)), "dark", axis='X', bevel=0.015, segs=3),
	rbox("sh_pad", (0.1, 0.12, 0.13), S + Vector((0.045, 0.0, 0.0)), 0.045, "paint", segs=3, sub=2),
	rbox("sh_band", (0.092, 0.022, 0.118), S + Vector((0.047, -0.04, 0.0)), 0.01, "accent", sub=1),
	tube("upper_arm", [S + Vector((0.05, -0.04, -0.01)), E], 0.026, "dark", sides=14),
	rbox("upper_armor", (0.065, 0.075, 0.07), (S + E) * 0.5 + Vector((0.03, -0.025, -0.02)), 0.025, "paint", sub=2, rot=(-25, 0, 22)),
])
elbow = join("arm_elbow", [
	cyl("el_ball", 0.036, 0.07, E, "dark", axis='X', bevel=0.012, segs=3),
	rbox("fore_armor", (0.08, 0.075, 0.12), E + Vector((0.004, -0.004, -0.075)), 0.03, "paint", segs=3, sub=2, rot=(7, 0, 0)),
	rbox("fore_stripe", (0.083, 0.02, 0.04), E + Vector((0.004, 0.028, -0.1)), 0.008, "accent", sub=1, rot=(7, 0, 0)),
	tube("piston", [E + Vector((-0.03, -0.035, -0.02)), E + Vector((-0.03, -0.035, -0.13))], 0.008, "steel", sides=8),
])
wrist = join("arm_wrist", [
	torus("wr_ring", 0.035, 0.008, W, "glow", axis='Z', major=32, minor=8),
	cyl("wr_cuff", 0.042, 0.03, W + Vector((0, 0, 0.012)), "trim", axis='Z', bevel=0.008),
	cyl("palm", 0.04, 0.05, W + Vector((0, 0, -0.03)), "dark", axis='Z', bevel=0.012, segs=2, r2=0.034),
])
# One finger (base) and one claw tip in their own frames: point down -Z, outward = +Y.
finger = join("finger", [
	rbox("fg", (0.026, 0.022, 0.065), (0, 0.0, -0.028), 0.009, "dark", sub=1),
	cyl("fg_knuckle", 0.013, 0.03, (0, 0.0, -0.055), "steel", axis='X', verts=16, bevel=0.004),
])
tip = rbox("finger_tip", (0.022, 0.02, 0.055), (0, 0, -0.025), 0.008, "trim", sub=1)
for v in tip.data.vertices:
	t = min(max(-v.co.z / 0.055, 0.0), 1.0)
	v.co.x *= 1.0 - 0.5 * t
	v.co.y *= 1.0 - 0.4 * t
	v.co.y -= 0.018 * t * t  # hook inward
tip.name = tip.data.name = "finger_tip"

# Left arm by mirroring.
shoulder_l = mirror_x(shoulder, "arm_shoulder_l")
elbow_l = mirror_x(elbow, "arm_elbow_l")
wrist_l = mirror_x(wrist, "arm_wrist_l")
for o, n in ((shoulder, "arm_shoulder_r"), (elbow, "arm_elbow_r"), (wrist, "arm_wrist_r")):
	o.name = n
	o.data.name = n

PARTS = {
	"body": Vector((0, 0, 0)), "thruster": Vector((0, 0, 0)), "hatch": HATCH_P, "head": HEAD_P, "visor": VISOR_C,
	"arm_shoulder_r": S, "arm_elbow_r": E, "arm_wrist_r": W,
	"arm_shoulder_l": Vector((-S.x, S.y, S.z)), "arm_elbow_l": Vector((-E.x, E.y, E.z)), "arm_wrist_l": Vector((-W.x, W.y, W.z)),
	"finger": Vector((0, 0, 0)), "finger_tip": Vector((0, 0, 0)),
}


# ---------------------------------------------------------------- vertex colours (AO + edge wear)
def curvature(obj):
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.verts.ensure_lookup_table()
	cur = [0.0] * len(bm.verts)
	for v in bm.verts:
		if not v.link_edges:
			continue
		acc = 0.0
		for e in v.link_edges:
			o = e.other_vert(v)
			d = o.co - v.co
			l = d.length
			if l > 1e-7:
				acc += v.normal.dot(d / l)
		cur[v.index] = acc / len(v.link_edges)  # <0 convex, >0 concave
	bm.free()
	return cur


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
bake_objs = [o for o in objs if o.name not in ("finger", "finger_tip")]
ao = {}
bpy.ops.object.select_all(action='DESELECT')
for o in bake_objs:
	o.select_set(True)
bpy.context.view_layer.objects.active = bake_objs[0]
try:
	bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
	for o in bake_objs:
		ao[o.name] = [d.color[0] for d in o.data.color_attributes["Col"].data]
	print("AO bake ok")
except Exception as ex:  # pragma: no cover
	print("AO bake failed:", ex)

for o in objs:
	cur = curvature(o)
	a = ao.get(o.name)
	data = o.data.color_attributes["Col"].data
	for i, d in enumerate(data):
		c = cur[i]
		edge = min(max((-c - 0.04) * 5.0, 0.0), 1.0)
		cav = min(max((c - 0.02) * 6.0, 0.0), 1.0)
		occ = a[i] if a else 1.0
		d.color = (occ, edge, cav, 1.0)

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
						cl += [c[0], c[1], c[2], 1.0]
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


write_glb(OUT, sorted(objs, key=lambda o: o.name))
print("exported", OUT)

# Optional quick Cycles preview of the shapes (PREVIEW=/path/prefix): front, 3/4, side, back.
if os.environ.get("PREVIEW"):
	cols = {"paint": (0.8, 0.78, 0.74), "trim": (0.08, 0.085, 0.095), "accent": (0.9, 0.4, 0.08), "dark": (0.05, 0.05, 0.055),
		"steel": (0.5, 0.5, 0.5), "glow": (0.3, 0.9, 1.0), "lamp_accent": (1.0, 0.6, 0.2), "screen": (0.01, 0.01, 0.01),
		"face": (0.01, 0.01, 0.012), "thruster": (0.3, 0.9, 1.0), "thruster_core": (0.6, 1.0, 1.0)}
	for name, m in MATS.items():
		b = m.node_tree.nodes["Principled BSDF"]
		b.inputs["Base Color"].default_value = (*cols.get(name, (0.5, 0.5, 0.5)), 1)
		b.inputs["Roughness"].default_value = 0.1 if name in ("face", "screen") else 0.45
		if name in ("glow", "lamp_accent", "thruster", "thruster_core"):
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
