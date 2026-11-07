# Builds the ark *Cradle* (the seed-vault ship) and exports art/models/cradle/cradle.glb.
#   blender -b --python art/models/cradle/build_cradle.py
# Modelled in Godot coordinates (Y up, the ship flies toward -Z, ~40 m long) and converted to
# glTF axes by the writer. Material slot names tell CradleShip which runtime material to use:
# hull (glossy white), glass (dark glass), glow (cyan seams), accent (orange), trim (dark grey),
# dome (vault glass), garden (vault greenery), vault (the glowing seed vault), engine (thrust).
# Objects: hull (static), ring (habitat ring, spins around Z; origin = its centre), dome.
import bpy
import bmesh
import math
import os
import json
import struct
from mathutils import Vector, Matrix

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cradle.glb")
for o in list(bpy.data.objects):
	bpy.data.objects.remove(o, do_unlink=True)

MAT_NAMES = ["hull", "glass", "glow", "accent", "trim", "dome", "garden", "vault", "engine"]
MI = {n: i for i, n in enumerate(MAT_NAMES)}


class Part:
	def __init__(self, name, pivot=(0, 0, 0)):
		self.name = name
		self.bm = bmesh.new()
		self.pivot = Vector(pivot)

	def quad_grid(self, rings, mat_fn, closed=True):
		"""rings: list of lists of Vector (same length). mat_fn(i, j, centre) -> material name."""
		vs = [[self.bm.verts.new(p) for p in ring] for ring in rings]
		n = len(rings[0])
		for i in range(len(vs) - 1):
			for j in range(n if closed else n - 1):
				j2 = (j + 1) % n
				f = self.bm.faces.new((vs[i][j], vs[i][j2], vs[i + 1][j2], vs[i + 1][j]))
				c = (rings[i][j] + rings[i][j2] + rings[i + 1][j] + rings[i + 1][j2]) * 0.25
				f.material_index = MI[mat_fn(i, j, c)]
		return vs

	def cap(self, ring_verts, mat, flip=False):
		f = self.bm.faces.new(list(reversed(ring_verts)) if flip else ring_verts)
		f.material_index = MI[mat]


def rot_frame(axis):
	"""Two unit vectors perpendicular to axis."""
	a = Vector(axis).normalized()
	up = Vector((0, 1, 0)) if abs(a.y) < 0.9 else Vector((1, 0, 0))
	u = a.cross(up).normalized()
	v = a.cross(u).normalized()
	return a, u, v


def lathe(part, profile, mat, center=(0, 0, 0), axis=(0, 0, 1), segs=48, sx=1.0, sy=1.0, mat_fn=None, cap_ends=True):
	"""profile: list of (t, r) along axis. Ring points: centre + axis*t + (u*cos*sx + v*sin*sy)*r."""
	a, u, v = rot_frame(axis)
	c = Vector(center)
	rings = []
	for (t, r) in profile:
		ring = []
		for k in range(segs):
			ang = 2 * math.pi * k / segs
			ring.append(c + a * t + (u * math.cos(ang) * sx + v * math.sin(ang) * sy) * max(r, 1e-4))
		rings.append(ring)
	fn = mat_fn or (lambda i, j, cc: mat)
	vs = part.quad_grid(rings, fn)
	if cap_ends:
		if profile[0][1] > 1e-3:
			part.cap(vs[0], mat, flip=True)
		if profile[-1][1] > 1e-3:
			part.cap(vs[-1], mat)
	return vs


def torus(part, R, r, center, axis, mat, major=64, minor=12, sy=1.0, mat_fn=None):
	a, u, v = rot_frame(axis)
	c = Vector(center)
	rings = []
	for i in range(major + 1):
		ang = 2 * math.pi * i / major
		d = u * math.cos(ang) + v * math.sin(ang)
		ring = []
		for j in range(minor):
			b = 2 * math.pi * j / minor
			ring.append(c + d * (R + r * math.cos(b)) + a * (r * math.sin(b) * sy))
		rings.append(ring)
	part.quad_grid(rings, mat_fn or (lambda i, j, cc: mat))


def box(part, size, center, mat, rot=(0, 0, 0), bevel=0.0):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
	if bevel > 0:
		bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=3, affect='EDGES', profile=0.5)
	m = Matrix.Translation(Vector(center)) @ (Matrix.Rotation(math.radians(rot[1]), 4, 'Y') @ Matrix.Rotation(math.radians(rot[0]), 4, 'X') @ Matrix.Rotation(math.radians(rot[2]), 4, 'Z'))
	bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
	merge(part, bm, mat)


def sphere(part, r, center, mat, scale=(1, 1, 1), segs=24, rings=12):
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
	bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
	bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
	merge(part, bm, mat)


def cone(part, r1, r2, h, center, mat, segs=16):
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=h)
	# create_cone is along Blender-local Z; we want Godot Y up.
	bmesh.ops.rotate(bm, matrix=Matrix.Rotation(math.radians(-90), 3, 'X'), verts=bm.verts)
	bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
	merge(part, bm, mat)


def merge(part, bm, mat):
	me = bpy.data.meshes.new("tmp")
	bm.to_mesh(me)
	bm.free()
	for p in me.polygons:
		p.material_index = 0
	n0 = len(part.bm.faces)
	part.bm.from_mesh(me)
	part.bm.faces.ensure_lookup_table()
	for f in part.bm.faces[n0:]:
		f.material_index = MI[mat]
	bpy.data.meshes.remove(me)


def catmull(pts, steps):
	out = []
	n = len(pts)
	for i in range(n - 1):
		p0 = pts[max(i - 1, 0)]; p1 = pts[i]; p2 = pts[i + 1]; p3 = pts[min(i + 2, n - 1)]
		for s in range(steps):
			t = s / steps
			out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t * t + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t * t * t) for k in range(2)))
	out.append(pts[-1])
	return out


# ---------------------------------------------------------------- HULL
hull = Part("hull")
SX, SY = 1.22, 0.84
ctrl = [(-21.0, 0.0), (-20.7, 0.75), (-19.8, 1.55), (-18.0, 2.35), (-15.0, 3.05), (-10.0, 3.45), (-4.0, 3.55),
	(2.0, 3.4), (8.0, 3.05), (13.0, 2.6), (16.0, 2.3), (17.2, 2.15), (17.6, 1.7), (17.7, 0.0)]
prof = catmull(ctrl, 22)
SEAMS = [-17.0, -12.2, -7.0, 9.6, 14.4]


def hull_mat(i, j, c):
	z = c.z
	r = max(math.hypot(c.x / SX, c.y / SY), 1e-3)
	ny = (c.y / SY) / r  # -1 bottom .. 1 top
	nx = (c.x / SX) / r
	if z > 17.15:
		return "trim"
	for s in SEAMS:
		if abs(z - s) < 0.13:
			return "glow"
	if -20.2 < z < -16.4 and ny > 0.28 and abs(nx) < 0.85:
		return "glass"  # bridge visor
	if -18.4 < z < -17.6 and ny < 0.2:
		return "accent"
	if -0.24 < ny < -0.17 and -15.5 < z < 15.5:
		return "glow"  # side seam line under the windows
	if -0.08 < ny < 0.22 and -14.5 < z < 13.5 and abs(z + 2.0) > 3.0:
		ph = ((z + 14.5) / 1.35) % 1.0
		return "glass" if ph < 0.8 else "hull"
	if ny < -0.93:
		return "trim"  # keel
	if 0.98 < ny and (z < -6.0 or z > 4.0):
		return "glow"  # dorsal light line
	return "hull"


lathe(hull, prof, "hull", axis=(0, 0, 1), segs=80, sx=SX, sy=SY, mat_fn=hull_mat)

# Engines: three nozzles at the stern with glowing throats.
for (ex, ey, er) in ((0.0, 0.0, 1.2), (-2.3, -0.4, 0.8), (2.3, -0.4, 0.8)):
	lathe(hull, [(0.0, er * 0.9), (0.6, er * 1.05), (1.6, er * 1.25), (1.65, er * 1.1)], "trim", center=(ex, ey, 17.3), axis=(0, 0, 1), segs=32, cap_ends=False)
	lathe(hull, [(0.0, er * 0.0), (1.1, er * 0.95)], "engine", center=(ex, ey, 17.6), axis=(0, 0, 1), segs=32, cap_ends=False)
	torus(hull, er * 1.16, 0.07, (ex, ey, 18.3), (0, 0, 1), "glow", major=40, minor=6)

# Swept wings with dark solar glass and orange tips.
for side in (-1, 1):
	for k in range(5):
		t = k / 4.0
		x = side * (3.6 + t * 5.4)
		z = 6.0 + t * 6.5
		box(hull, (1.25, 0.16, 3.4 - t * 1.1), (x, -0.6 - t * 0.5, z), "hull", rot=(0, side * -28, side * -6), bevel=0.05)
		box(hull, (1.05, 0.2, 2.8 - t * 1.0), (x, -0.6 - t * 0.5, z), "glass", rot=(0, side * -28, side * -6))
	box(hull, (0.7, 0.3, 1.6), (side * 9.4, -1.15, 12.7), "accent", rot=(0, side * -28, side * -6), bevel=0.1)
	sphere(hull, 0.18, (side * 9.6, -1.0, 12.0), "glow")
# Dorsal tail fin.
for k in range(4):
	t = k / 3.0
	box(hull, (0.22, 1.0, 3.0 - t * 0.9), (0, 3.1 + t * 0.95, 12.6 + t * 1.6), "hull", rot=(-12, 0, 0), bevel=0.06)
box(hull, (0.3, 0.5, 1.1), (0, 6.0, 15.3), "accent", rot=(-12, 0, 0), bevel=0.08)

# Cargo pods slung under the belly (one of them takes a fall).
for k in range(6):
	z = -9.0 + k * 2.6
	lathe(hull, [(-1.0, 0.0), (-0.95, 0.35), (-0.7, 0.55), (0.7, 0.55), (0.95, 0.35), (1.0, 0.0)], "hull", center=(0, -3.35, z), axis=(0, 0, 1), segs=20)
	torus(hull, 0.57, 0.06, (0, -3.35, z), (0, 0, 1), "accent", major=20, minor=6)
	box(hull, (0.25, 0.5, 0.25), (0, -2.85, z), "trim")
box(hull, (0.5, 0.3, 17.0), (0, -2.75, -2.5), "trim", bevel=0.08)  # pod rail

# Seed-vault dome base (collar) and the bow beacon.
torus(hull, 3.15, 0.2, (0, 2.62, -2.0), (0, 1, 0), "glow", major=64, minor=8)
lathe(hull, [(-0.4, 3.45), (0.0, 3.3), (0.2, 3.05)], "hull", center=(0, 2.4, -2.0), axis=(0, 1, 0), segs=64, cap_ends=False)
sphere(hull, 0.22, (0, 0.2, -21.0), "glow")

# ---------------------------------------------------------------- DOME (seed vault + garden)
dome = Part("dome", (0, 2.6, -2.0))
dome_prof = []
for k in range(17):
	a = math.pi * 0.5 * k / 16
	dome_prof.append((math.sin(a) * 2.35, math.cos(a) * 3.0))
dome_prof.append((2.36, 0.0))
lathe(dome, dome_prof, "dome", center=(0, 2.6, -2.0), axis=(0, 1, 0), segs=56, cap_ends=False)
# Glass ribs.
for k in range(8):
	ang = 2 * math.pi * k / 8
	rib = []
	for s in range(17):
		a = math.pi * 0.5 * s / 16
		r = math.cos(a) * 3.04
		rib.append(Vector((math.cos(ang) * r, 2.6 + math.sin(a) * 2.38, -2.0 + math.sin(ang) * r)))
	for s in range(16):
		p, q = rib[s], rib[s + 1]
		d = q - p
		bm = bmesh.new()
		bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.05, radius2=0.05, depth=d.length)
		rotm = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
		bmesh.ops.transform(bm, matrix=Matrix.Translation((p + q) * 0.5) @ rotm, verts=bm.verts)
		merge(dome, bm, "hull")
# Garden floor, trees and the seed vault column.
lathe(dome, [(0.0, 0.0), (0.0, 2.95), (0.15, 2.95)], "garden", center=(0, 2.65, -2.0), axis=(0, 1, 0), segs=48, cap_ends=False)
import random
random.seed(4)
for k in range(22):
	a = random.uniform(0, 2 * math.pi)
	r = random.uniform(1.0, 2.5)
	x, z = math.cos(a) * r, -2.0 + math.sin(a) * r
	h = random.uniform(0.5, 1.2) * (1.0 - r / 4.0) + 0.3
	cone(dome, 0.05, 0.05, h * 0.5, (x, 2.75 + h * 0.25, z), "trim", segs=6)
	sphere(dome, 0.28 + h * 0.25, (x, 2.75 + h * 0.6, z), "garden", scale=(1, 0.85, 1), segs=10, rings=6)
cone(dome, 0.45, 0.25, 1.6, (0, 3.45, -2.0), "vault", segs=24)
sphere(dome, 0.42, (0, 4.4, -2.0), "vault", segs=20, rings=10)
torus(dome, 0.75, 0.05, (0, 3.0, -2.0), (0, 1, 0), "glow", major=32, minor=6)

# ---------------------------------------------------------------- HABITAT RING (spins)
ring = Part("ring", (0, 0, 4.0))
torus(ring, 6.6, 0.55, (0, 0, 4.0), (0, 0, 1), "hull", major=96, minor=14, sy=1.5,
	mat_fn=lambda i, j, c: "glass" if (j in (0, 1, 13) and (i % 8) < 6) else "hull")
torus(ring, 6.0, 0.08, (0, 0, 4.0 - 0.0), (0, 0, 1), "glow", major=96, minor=6)
for k in range(4):
	ang = math.pi * 0.25 + k * math.pi * 0.5
	d = Vector((math.cos(ang), math.sin(ang), 0))
	p = Vector((0, 0, 4.0)) + d * 3.2
	q = Vector((0, 0, 4.0)) + d * 6.2
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.22, radius2=0.22, depth=(q - p).length)
	bmesh.ops.transform(bm, matrix=Matrix.Translation((p + q) * 0.5) @ (q - p).to_track_quat('Z', 'Y').to_matrix().to_4x4(), verts=bm.verts)
	merge(ring, bm, "hull")
	sphere(ring, 0.16, tuple(q + d * 0.6 + Vector((0, 0, -0.9))), "accent", segs=10, rings=6)
torus(ring, 3.3, 0.35, (0, 0, 4.0), (0, 0, 1), "trim", major=48, minor=8)

parts = [hull, dome, ring]
objs = []
for p in parts:
	bmesh.ops.remove_doubles(p.bm, verts=p.bm.verts, dist=1e-5)
	bmesh.ops.recalc_face_normals(p.bm, faces=p.bm.faces)
	me = bpy.data.meshes.new(p.name)
	p.bm.to_mesh(me)
	p.bm.free()
	for n in MAT_NAMES:
		m = bpy.data.materials.get(n) or bpy.data.materials.new(n)
		me.materials.append(m)
	me.transform(Matrix.Translation(-p.pivot))
	for poly in me.polygons:
		poly.use_smooth = True
	me.use_auto_smooth = True
	me.auto_smooth_angle = math.radians(42)
	o = bpy.data.objects.new(p.name, me)
	bpy.context.scene.collection.objects.link(o)
	o["pivot"] = list(p.pivot)
	objs.append(o)
	print("part", p.name, len(me.vertices), "verts")


# Minimal GLB writer (Godot coordinates already; Blender's glTF exporter needs numpy).
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
		prims = {}
		for tri in me.loop_triangles:
			prims.setdefault(tri.material_index, []).append(tri)
		gprims = []
		for mi, tris in sorted(prims.items()):
			pos, nrm, idx = [], [], []
			remap = {}
			for tri in tris:
				for li in tri.loops:
					lp = me.loops[li]
					key = (lp.vertex_index, round(lp.normal.x, 3), round(lp.normal.y, 3), round(lp.normal.z, 3))
					if key not in remap:
						co = me.vertices[lp.vertex_index].co
						remap[key] = len(pos) // 3
						pos += [co.x, co.y, co.z]
						nrm += [lp.normal.x, lp.normal.y, lp.normal.z]
					idx.append(remap[key])
			mname = me.materials[mi].name
			if mname not in mat_index:
				mat_index[mname] = len(materials)
				materials.append({"name": mname, "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.8, 1.0]}})
			n = len(pos) // 3
			gprims.append({"attributes": {
				"POSITION": add_acc(pos, n, 5126, "VEC3", 34962, True),
				"NORMAL": add_acc(nrm, n, 5126, "VEC3", 34962)},
				"indices": add_acc(idx, len(idx), 5125, "SCALAR", 34963), "material": mat_index[mname]})
		meshes.append({"name": o.name, "primitives": gprims})
		nodes.append({"name": o.name, "mesh": len(meshes) - 1, "translation": list(o["pivot"])})
	gltf = {"asset": {"version": "2.0", "generator": "build_cradle.py"}, "scene": 0,
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


write_glb(OUT, objs)
print("exported", OUT)
