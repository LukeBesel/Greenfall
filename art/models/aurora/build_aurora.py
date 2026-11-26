# Builds the Aurora hero bot mesh set and exports art/models/aurora/aurora.glb (Nov 2026, to the
# owner's concept turnaround + portrait; see the layout notes at "HERO v2" below).
#   blender -b --python art/models/aurora/build_aurora.py      (Blender 4.0; about 20 s)
#   python3 tools/hero/bake_masks.py                           (ALWAYS after a build: the atlas UVs change)
#   python3 tools/hero/quick_views.py OUT && python3 tools/hero/overlay.py SHEET.png OUT   (shape check in seconds)
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

OUT = os.environ.get("AURORA_OUT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "aurora.glb"))

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


# ================================================================ HERO v2 (Aurora, owner's concept portrait + turnaround)
# Layout (float space, metres; the figure is 1.10 m from the crown to the bottom of the hover unit),
# matched to art/concept/aurora_turnaround.png by measurement (tools/hero/overlay.py):
#   head 0.56 .. 1.21: a fat rounded-box pill (superellipsoid, flatter underneath) with one curved
#   black visor in a dark frame, amber cheek lamps beside it, big dark ear modules seated in the
#   sides with a thin cyan ring, a raised back plate over a dark vent band with amber lights, a
#   dark neck recess with mechanics low at the back, a short stalk with a flat amber paddle;
#   torso 0.255 .. 0.575: small, straight-sided, hips angling in to a dark underside; a cyan strip
#   along the top front and down each side of the framed recycling plate, orange latches on the
#   shoulder plates, a cyan-lit square frame round the bale hatch on the back;
#   hover unit 0.113 .. 0.23: a stem, a dark tiered ring disc with a cyan ring, and a smaller
#   emitter disc that glows; short segmented arms that hang at rest (PatchModel.ARM_REST).
HEAD_P = Vector((0, 0.56, 0))
# [art2] Measured on the turnaround (tools/hero/overlay.py): the head is a fat pill, over half the
# figure's height, 0.73 as tall as wide WITH the ear modules (0.82 to 0.86 from the other sides), nearly
# as deep as it is wide; the body height (crown to the bottom of the hover unit) stays 1.10 m.
HC = 0.885                         # head centre height
HA, HB, HCZ = 0.35, 0.325, 0.335  # head half sizes (x, y, z)
E_H, E_V = 3.0, 2.35              # superellipsoid exponents: horizontal (x-z), vertical
E_V_LOW = 3.1                     # the underside is flatter, with fuller lower corners
HEAD_TAPER = 0.035                # the crown is a little narrower than the cheeks
HW, HH, HD = HA * 2, HB * 2, HCZ * 2


def spow(v, e):
	return math.copysign(abs(v) ** e, v)


def capsule(name, material, nu=72, nv=128):
	"""Superellipsoid head shell with a slightly domed top and a gently convex face."""
	bm = bmesh.new()
	rows = []
	top = bm.verts.new((0, HC + HB + 0.012, 0))
	bot = bm.verts.new((0, HC - HB, 0))
	for i in range(1, nu):
		u = -math.pi / 2 + math.pi * i / nu
		row = []
		for j in range(nv):
			v = -math.pi + 2 * math.pi * j / nv
			ev = E_V if u > 0 else E_V_LOW
			cu = spow(math.cos(u), 2.0 / ev)
			y = HB * spow(math.sin(u), 2.0 / ev)
			tp = 1.0 - HEAD_TAPER * max(y / HB, 0.0) ** 2
			x = HA * tp * cu * spow(math.cos(v), 2.0 / E_H)
			z = HCZ * tp * cu * spow(math.sin(v), 2.0 / E_H)
			# Domed top: the crown rises a little toward the middle.
			if y > 0:
				r2 = (x / HA) ** 2 + (z / HCZ) ** 2
				y += 0.012 * max(0.0, 1.0 - r2) * (y / HB) ** 2
			# Convex face: the front bulges forward a touch in the middle.
			if z < 0:
				w = (-z / HCZ) ** 2
				z -= w * 0.022 * max(0.0, 1.0 - (x / HA) ** 2) * max(0.0, 1.0 - ((y) / HB) ** 2)
			row.append(bm.verts.new((x, HC + y, z)))
		rows.append(row)
	for j in range(nv):
		bm.faces.new((bot, rows[0][(j + 1) % nv], rows[0][j]))
		bm.faces.new((top, rows[-1][j], rows[-1][(j + 1) % nv]))
	for i in range(len(rows) - 1):
		for j in range(nv):
			bm.faces.new((rows[i][j], rows[i][(j + 1) % nv], rows[i + 1][(j + 1) % nv], rows[i + 1][j]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return smooth(from_bm(bm, name, material))


head = capsule("head_shell", "paint")
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


def shell_z_back(y):
	"""z of the shell's back surface at height y (x = 0), from the original (uncut) shell."""
	p, _n = shell_hit((0, y, 2.0), (0, 0, -1))
	return p.z if p is not None else HCZ


def on_shell(x, y, z_sign=-1):
	"""Point and normal on the shell straight in from x/y on the front (z_sign -1) or back (+1)."""
	return shell_hit((x, y, 2.0 * z_sign), (0, 0, -z_sign))


# Visor: one curved glossy black screen across nearly the whole front; the shell is a thick band
# below it and a thinner one above and at the sides (portrait).
VA, VB, VN = 0.3, 0.185, 3.3      # [art2] visor: 0.59 of the head's height, wrapping round the front (turnaround)
VCY = HC + 0.015


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
	# [hero v2] Triangulate the (non-planar on the curved capsule) back cap, or the EXACT boolean
	# leaves a patch of shell in the middle of the visor.
	tri = bmesh.ops.triangulate(bm, faces=[walls[-1]])
	walls = walls[:-1] + list(tri["faces"])
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


def loop_tube(name, pts, r, material, sides=8):
	"""A closed tube through `pts` (already smooth), for light bands and bezels."""
	bm = bmesh.new()
	n = len(pts)
	P = [Vector(p) for p in pts]
	rings = []
	for i in range(n):
		d = (P[(i + 1) % n] - P[i - 1]).normalized()
		up = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))
		nrm = (up - d * up.dot(d)).normalized()
		bi = d.cross(nrm)
		rings.append([bm.verts.new(P[i] + (nrm * math.cos(2 * math.pi * k / sides) + bi * math.sin(2 * math.pi * k / sides)) * r) for k in range(sides)])
	for i in range(n):
		a, b = rings[i], rings[(i + 1) % n]
		for k in range(sides):
			bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return smooth(from_bm(bm, name, material))


def rrect_loop(hx, hz, rad, y, n=24):
	"""Points round a rounded rectangle (x-z plane) at height y."""
	pts = []
	for (cx, cz, a0) in ((hx - rad, -hz + rad, -90), (hx - rad, hz - rad, 0), (-hx + rad, hz - rad, 90), (-hx + rad, -hz + rad, 180)):
		for k in range(n):
			a = math.radians(a0 + 90 * k / n)
			pts.append((cx + math.cos(a) * rad, y, cz + math.sin(a) * rad))
	return pts


# ---------------------------------------------------------------- HEAD details
# [art2] Panel seams (real grooves) as on the turnaround: a ring behind the ear modules, a framed
# back panel with a seam across its middle, a crown panel.
groove(head, (1.0, 0.8, 0.008), (0, HC, 0.175), depth=0.011)
for s in (-1, 1):
	groove(head, (0.008, 0.14, 0.3), (s * 0.13, HC + HB, 0.02), depth=0.009)
	groove(head, (0.008, 0.1, 0.3), (s * 0.2, HC - 0.055, 0.33), depth=0.009)     # belt panel joints
groove(head, (0.3, 0.14, 0.008), (0, HC + HB, -0.13), depth=0.009)
groove(head, (1.0, 0.008, 0.3), (0, HC - 0.005, 0.36), depth=0.009)              # belt panel top (under the vent)
groove(head, (1.0, 0.008, 0.36), (0, HC - 0.1, 0.36), depth=0.009)
# Visor recess: the thick shell wraps the glass (dark trim walls).
cut = conform("visor_cut", "trim", lambda s_: 0.034, grow=0.018, back=-0.15)
boolean(head, cut)
# Crown: a dark recessed slot on the top front with a hinged lid, a dark vent band high on the back
# with amber indicator lights, and the big dark neck recess low at the back with mechanics showing.
cut = rbox("crown_cut", (0.22, 0.09, 0.07), (0, HC + HB + 0.005, -0.1), 0.022, "trim", sub=1)
boolean(head, cut)
VENT_Y = HC + 0.05
cut = rbox("vent_cut", (0.4, 0.078, 0.16), (0, VENT_Y, HCZ - 0.05), 0.026, "trim", sub=1)
boolean(head, cut)
NECK_W = 0.36
cut = rbox("neck_cut", (NECK_W, 0.26, 0.34), (0, HC - HB + 0.04, 0.2), 0.08, "trim", sub=1)
boolean(head, cut)
# Ear sockets: a shallow round seat in each side for the ear module.
EAR_Y, EAR_R, EAR_X, EAR_Z = HC + 0.0, 0.17, 0.3, 0.035
for s in (-1, 1):
	cut = cyl("ear_cut", EAR_R + 0.006, 0.2, (s * (EAR_X + 0.1), EAR_Y, EAR_Z), "trim", axis='X', verts=64)
	boolean(head, cut)
head_parts = [head]
# [art2] Raised back plate (turnaround): a cream panel standing proud of the shell from the crown
# down to the vent band, following the head's curve.
def shell_patch(name, hx, y0, y1, lift, material, corner=6.0, rings=7, seg=56):
	"""A raised panel on the BACK of the head: outline hx wide from y0 to y1, lifted `lift` along the normal."""
	cy, hy = 0.5 * (y0 + y1), 0.5 * (y1 - y0)
	bm = bmesh.new()
	def at(s_, j, off):
		t = 2 * math.pi * j / seg
		x = hx * s_ * spow(math.cos(t), 2.0 / corner)
		y = cy + hy * s_ * spow(math.sin(t), 2.0 / corner)
		p_, n_ = shell_hit((x, y, 2.0), (0, 0, -1))
		return bm.verts.new(p_ + n_ * off)
	p_, n_ = shell_hit((0, cy, 2.0), (0, 0, -1))
	c = bm.verts.new(p_ + n_ * lift)
	rows = [[at((i + 1) / rings * 0.94, j, lift) for j in range(seg)] for i in range(rings)]
	rows.append([at(0.985, j, lift * 0.55) for j in range(seg)])
	rows.append([at(1.0, j, -0.004) for j in range(seg)])
	for j in range(seg):
		bm.faces.new((c, rows[0][j], rows[0][(j + 1) % seg]))
	for i in range(len(rows) - 1):
		for j in range(seg):
			bm.faces.new((rows[i][j], rows[i + 1][j], rows[i + 1][(j + 1) % seg], rows[i][(j + 1) % seg]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return smooth(from_bm(bm, name, material))


head_parts.append(shell_patch("back_plate", 0.168, VENT_Y + 0.052, HC + 0.262, 0.013, "paint"))
for sx in (-1, 1):
	for y in (VENT_Y + 0.075, HC + 0.22):
		p, n = shell_hit((sx * 0.135, y, 2.0), (0, 0, -1))
		head_parts.append(screw(p + n * 0.013, n, r=0.0065))
p, n = shell_hit((0, 3.0, -0.1), (0, -1, 0))
crown_y = p.y if p is not None else HC + HB
head_parts.append(rbox("crown_lid", (0.2, 0.014, 0.05), (0, crown_y - 0.006, -0.09), 0.006, "paint", sub=1, segs=2, rot=(-12, 0, 0)))
head_parts.append(rbox("crown_floor", (0.2, 0.01, 0.06), (0, crown_y - 0.03, -0.1), 0.003, "dark", sub=0))
for k in range(3):
	y = VENT_Y - 0.02 + k * 0.02
	head_parts.append(rbox("vent_slat", (0.37, 0.008, 0.014), (0, y, shell_z_back(y) - 0.032), 0.003, "dark", sub=0, segs=2))
for k, x in enumerate((-0.11, -0.03, 0.03, 0.11)):
	head_parts.append(rbox("vent_led", (0.02, 0.014, 0.012), (x, VENT_Y, shell_z_back(VENT_Y) - 0.026), 0.004, "lamp_accent", sub=0, segs=1))
# Neck recess: a dark ceiling and back wall with ribs, drums and cable runs (seen from behind).
NK_Y = HC - HB
head_parts.append(rbox("neck_ceiling", (NECK_W - 0.03, 0.012, 0.3), (0, NK_Y + 0.165, 0.19), 0.005, "dark", sub=0))
head_parts.append(rbox("neck_wall", (NECK_W - 0.03, 0.17, 0.012), (0, NK_Y + 0.085, 0.045), 0.005, "dark", sub=0))
for k in range(5):
	x = (k - 2) * 0.062
	head_parts.append(rbox("neck_rib", (0.014, 0.14, 0.018), (x, NK_Y + 0.09, 0.058), 0.004, "trim", sub=0, segs=1))
for k in range(2):
	x = (k - 0.5) * 0.17
	head_parts.append(cyl("neck_drum", 0.03, 0.09, (x, NK_Y + 0.115, 0.14), "dark", axis='X', verts=16, bevel=0.006))
	head_parts.append(cyl("neck_drum_cap", 0.016, 0.1, (x, NK_Y + 0.115, 0.14), "steel", axis='X', verts=12, bevel=0.003))
for k in range(4):
	x = (k - 1.5) * 0.07
	head_parts.append(tube("neck_cable", [(x, NK_Y + 0.15, 0.08), (x * 0.8, NK_Y + 0.08, 0.2), (x * 0.6, NK_Y + 0.02, 0.22)], 0.011, "cable" if k % 2 else "dark", sides=8))
# Dark frame where the glass meets the shell (the concept's visor has a distinct dark surround).
bm = bmesh.new()
rows = []
for j in range(128):
	gx, gy = outline(2 * math.pi * j / 128, 0.012)
	z0 = shell_z(gx, VCY + gy)
	rows.append((bm.verts.new((gx, VCY + gy, z0 + 0.022)), bm.verts.new((gx * 1.02, VCY + gy * 1.035, z0 + 0.036))))
for j in range(128):
	a, b = rows[j], rows[(j + 1) % 128]
	bm.faces.new((a[0], b[0], b[1], a[1]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
head_parts.append(smooth(from_bm(bm, "visor_gasket", "dark")))
# Amber cheek lamps: tall rounded bars on the shell just outside the visor, lying on the surface.
for s in (-1, 1):
	x = s * (VA + 0.034)
	y = VCY - 0.005
	p, n = on_shell(x, y)
	if p is None:
		continue
	ang = math.degrees(math.atan2(abs(n.x), -n.z))
	head_parts.append(rbox("cheek_house", (0.038, 0.118, 0.02), p + n * -0.004, 0.009, "dark", sub=1, rot=(0, s * -ang, 0)))
	head_parts.append(rbox("cheek", (0.027, 0.104, 0.02), p + n * 0.002, 0.008, "lamp_accent", sub=1, rot=(0, s * -ang, 0)))
# Fasteners.
for sx in (-1, 1):
	for sy in (-1, 1):
		p, n = on_shell(sx * (VA - 0.02), VCY + sy * (VB + 0.045))
		if p is not None:
			head_parts.append(screw(p, n))
	for z in (-0.02, 0.1):
		p, n = shell_hit((sx * 0.1, 3.0, z), (0, -1, 0))
		if p is not None:
			head_parts.append(screw(p, n, r=0.0075))
	for y in (-0.09, 0.0, 0.19):
		p, n = shell_hit((sx * 0.16, HC + y, 2.0), (0, 0, -1))
		if p is not None:
			head_parts.append(screw(p, n, r=0.0075))

# [art2] Ear modules (the turnaround's are about half the head's height across): a dark round slab
# seated in the socket, a THIN cyan ring near its rim, then a dark glossy recessed face with
# concentric steps and a small lens hub. (r, height) profiles; height runs outward.
mod = []
mod.append(lathe("sm_house", [(EAR_R - 0.004, 0.0), (EAR_R, 0.004), (EAR_R, 0.048), (EAR_R - 0.006, 0.06), (EAR_R - 0.016, 0.066), (EAR_R - 0.023, 0.064)], "trim", segs=72))
mod.append(torus("sm_ring", EAR_R - 0.028, 0.0058, (0, 0.0635, 0), "glow_soft", axis='Y', major=72, minor=8))
mod.append(lathe("sm_face", [(EAR_R - 0.033, 0.064), (EAR_R - 0.037, 0.056), (0.098, 0.052), (0.096, 0.058), (0.09, 0.059), (0.086, 0.052), (0.064, 0.049),
	(0.062, 0.055), (0.056, 0.056), (0.052, 0.049), (0.034, 0.047)], "screen", segs=56))
mod.append(lathe("sm_step", [(0.092, 0.0595), (0.094, 0.057), (0.088, 0.057), (0.089, 0.0595)], "dark", segs=56))
mod.append(lathe("sm_lens", [(0.0, 0.06), (0.012, 0.0595), (0.024, 0.057), (0.032, 0.052), (0.034, 0.046)], "screen", segs=32))
mod.append(torus("sm_lens_ring", 0.036, 0.003, (0, 0.049, 0), "steel", axis='Y', major=32, minor=6))
for k in range(4):
	a = 2 * math.pi * (k + 0.5) / 4
	mod.append(screw((math.cos(a) * 0.075, 0.05, math.sin(a) * 0.075), (0, 1, 0), r=0.005))
side_r = join("side_module_r", mod)
side_r.data.transform(Matrix.Translation(Vector((EAR_X, EAR_Y, EAR_Z))) @ Matrix.Rotation(math.radians(-90), 4, 'Z'))
side_l = mirror_x(side_r, "side_module_l")
# [hero v2] Character builder: the side modules ("ears") are their own part so they can be swapped.
ears = join("ears", [side_r, side_l])
head = join("head", head_parts)

# Fin (part "antenna", head pivot): a short dark stalk leaning back from the crown, carrying a small
# flat amber paddle with a lighter lit edge (the turnaround's is short: about a fifth of the head).
p, n = shell_hit((0, 3.0, 0.1), (0, -1, 0))
FIN_BASE = Vector((0, (p.y if p is not None else HC + HB) - 0.004, 0.1))
STALK_END = FIN_BASE + Vector((0, 0.115, 0.06))
STALK_L = (STALK_END - FIN_BASE).length
fin_parts = [
	rbox("fin_mount", (0.075, 0.03, 0.1), FIN_BASE + Vector((0, 0.008, 0.0)), 0.012, "trim", segs=2, sub=1),
	cyl("fin_hinge", 0.014, 0.085, FIN_BASE + Vector((0, 0.026, -0.005)), "steel", axis='X', verts=16, bevel=0.003),
]
stalk = rbox("fin_stalk", (0.04, 0.022, STALK_L + 0.03), (0, 0, 0), 0.007, "fin", segs=2, sub=1)
ang = math.degrees(math.atan2(STALK_END.y - FIN_BASE.y, STALK_END.z - FIN_BASE.z))
xform(stalk, (FIN_BASE + STALK_END) * 0.5 + Vector((0, 0.012, 0)), (-ang, 0, 0))
fin_parts.append(stalk)
fin_parts.append(rbox("fin_stalk_inset", (0.014, 0.024, STALK_L * 0.7), (0, 0, 0), 0.003, "dark", sub=0, segs=1))
xform(fin_parts[-1], (FIN_BASE + STALK_END) * 0.5 + Vector((0, 0.012, 0)), (-ang, 0, 0))
# Paddle: a rounded pad on top of the stalk, reaching forward, tilted up a little at the front.
PAD_W, PAD_L = 0.055, 0.095
PAD_C = STALK_END + Vector((0, 0.02, -0.035))
pad_pts = []
for k in range(40):
	t = 2 * math.pi * k / 40
	w = PAD_W * (1.0 - 0.25 * max(math.sin(t), 0.0))
	pad_pts.append((math.cos(t) * w, math.sin(t) * PAD_L))
paddle = prism("fin_paddle", pad_pts, 0.02, (0, 0, 0), "paddle", bevel=0.005, segs=2, sub=1, rot=(90, 0, 0))
xform(paddle, PAD_C, (8, 0, 0))
fin_parts.append(paddle)
rim = loop_tube("fin_edge", [(x, 0.0105, z) for (x, z) in pad_pts], 0.003, "paddle_edge", sides=6)
xform(rim, PAD_C, (8, 0, 0))
fin_parts.append(rim)
fin_parts.append(screw(FIN_BASE + Vector((0.039, 0.008, 0.02)), (1, 0, 0), r=0.006))
fin_parts.append(screw(FIN_BASE + Vector((-0.039, 0.008, 0.02)), (-1, 0, 0), r=0.006))
antenna = join("antenna", fin_parts)
BEACON = FIN_BASE + Vector((0, 0.026, 0.055))

# Visor glass: convex, sitting just behind the shell lip at its edge and swelling forward in the
# middle. Only the front surface carries the "face" material (the eyes); walls/back are plain glass.
VISOR_C = Vector((0, VCY, shell_z(0, VCY)))
visor = conform("visor", "face", lambda s_: 0.03 - 0.022 * (1 - s_ * s_) - 0.004 * (1 - s_ ** 8), back=0.06, rings=18, seg=128, wall_material="screen")

# ---------------------------------------------------------------- BODY (pivot = float origin)
# [art2] Turnaround: a small torso, about 0.6 of the head's width (0.63 from the front with the
# latches, 0.58 from behind), wider at the shoulders and tapering to a dark underside; the hover
# unit is a small tiered disc floating a little below it (ring about 0.4 of the head's width).
body_parts = []
TY, TH, TW, TD = 0.415, 0.32, 0.52, 0.385
T_TOP, T_BOT = TY + TH * 0.5, TY - TH * 0.5
TAPER = 0.2


def tf(y):
	"""Torso outline: nearly straight sides, the hips angling in over the bottom third (turnaround)."""
	t = min(max((y - T_BOT) / TH, 0.0), 1.0)
	if t > 0.34:
		return 1.0 - 0.03 * (1.0 - t)
	return 0.98 - TAPER * (1.0 - t / 0.34) ** 1.4


def taper(obj):
	for v in obj.data.vertices:
		f = tf(v.co.y)
		v.co.x *= f
		v.co.z *= f
	return obj


upper = taper(rbox("torso", (TW, TH, TD), (0, TY, 0), 0.085, "paint", segs=4, sub=2))
# Plate gaps: dark seams between the shoulder plates, the hip plates and the back panel.
groove(upper, (0.8, 0.016, 0.8), (0, 0.352, 0), depth=0.011)           # waist gap
for s in (-1, 1):
	groove(upper, (0.012, 0.4, 0.6), (s * 0.128, TY, -0.12), depth=0.01)   # either side of the chest plate
	groove(upper, (0.008, 0.4, 0.3), (s * 0.135, TY, 0.2), depth=0.008)    # back panel sides
groove(upper, (0.8, 0.4, 0.008), (0, TY, 0.05), depth=0.008)
groove(upper, (0.27, 0.008, 0.3), (0, 0.535, 0.2), depth=0.008)        # back panel top
# Top-front bay: a dark recess of machinery just under the head, lit along its lip.
cut = taper(rbox("bay_cut", (0.25, 0.07, 0.1), (0, T_TOP - 0.01, -TD * 0.5 + 0.02), 0.02, "trim", sub=1))
boolean(upper, cut)
# Dark keel: the middle of the lower hull is dark between the cream hip plates (front and back).
for zs in (-1, 1):
	cut = rbox("keel_cut", (0.2, 0.1, 0.09), (0, T_BOT + 0.03, zs * TD * 0.5 * tf(T_BOT + 0.03)), 0.02, "trim", sub=1)
	boolean(upper, cut)
# Recessed dark frame for the chest plate.
PL_Y = 0.425
PL_C = Vector((0, PL_Y, -TD * 0.5 * tf(PL_Y)))
cut = rbox("plate_cut", (0.236, 0.196, 0.07), PL_C, 0.02, "trim", sub=1)
boolean(upper, cut)
body_parts.append(upper)
_bm = bmesh.new()
_bm.from_mesh(upper.data)
TORSO = BVHTree.FromBMesh(_bm)
_bm.free()


def torso_hit(origin, direction):
	hit = TORSO.ray_cast(Vector(origin), Vector(direction).normalized())
	return (hit[0], hit[1]) if hit[0] is not None else (None, None)


def front_z(x, y):
	p, _n = torso_hit((x, y, -2.0), (0, 0, 1))
	return p.z if p is not None else -TD * 0.5 * tf(y)


def back_z(x, y):
	p, _n = torso_hit((x, y, 2.0), (0, 0, -1))
	return p.z if p is not None else TD * 0.5 * tf(y)


def side_x(y, z=0.0):
	p, _n = torso_hit((2.0, y, z), (-1, 0, 0))
	return p.x if p is not None else TW * 0.5 * tf(y)


# Cyan light: one strip along the top front edge (the turnaround's bright bar under the head) and a
# thin line down each side of the chest plate.
STRIP_Y = T_TOP - 0.03
strip = [(x, STRIP_Y, front_z(x, STRIP_Y) - 0.001) for x in [-0.155 + 0.31 * k / 12 for k in range(13)]]
body_parts.append(tube("light_band", strip, 0.0075, "glow", sides=8))
for s in (-1, 1):
	x = s * 0.128
	line = [(x, y, front_z(x, y) + 0.004) for y in (0.52, 0.47, 0.42, 0.372)]
	body_parts.append(tube("light_line", line, 0.0045, "glow", sides=6))
for k in range(4):
	x = -0.084 + k * 0.056
	body_parts.append(cyl("bay_drum", 0.015, 0.04, (x, T_TOP - 0.022, -TD * 0.5 + 0.05), "dark", axis='X', verts=12, bevel=0.003))
	body_parts.append(rbox("bay_block", (0.024, 0.026, 0.026), (x + 0.028, T_TOP - 0.024, -TD * 0.5 + 0.052), 0.005, "steel", sub=0, segs=1))
# Plate: raised, bevelled light metal, four screws, sitting in its dark frame.
plate = rbox("chest_plate", (0.204, 0.164, 0.04), PL_C + Vector((0, 0, -0.004)), 0.014, "plate", segs=4, sub=1)
groove(plate, (0.4, 0.006, 0.1), PL_C + Vector((0, -0.06, -0.02)), depth=0.004)
body_parts.append(plate)
PL_FRONT = PL_C.z - 0.024
for sx in (-1, 1):
	for sy in (-1, 1):
		body_parts.append(screw((sx * 0.086, PL_C.y + sy * 0.064, PL_FRONT), (0, 0, -1), r=0.007))
# Orange latches: glowing bars in dark housings on the shoulder plates, either side of the plate.
for s in (-1, 1):
	x = s * 0.168
	p, n = torso_hit((x, PL_Y + 0.005, -2.0), (0, 0, 1))
	ang = math.degrees(math.atan2(abs(n.x), -n.z))
	body_parts.append(rbox("latch_house", (0.044, 0.135, 0.03), p + n * -0.006, 0.012, "dark", segs=2, sub=1, rot=(0, s * -ang, 0)))
	body_parts.append(rbox("latch", (0.029, 0.112, 0.02), p + n * 0.006, 0.01, "latch", segs=3, sub=1, rot=(0, s * -ang, 0)))
	body_parts.append(rbox("latch_pin", (0.042, 0.01, 0.012), p + n * 0.008 + Vector((0, 0.063, 0)), 0.004, "steel", sub=0, segs=1, rot=(0, s * -ang, 0)))
	# Flank: a small orange vent on the hip plate, dark slats over it.
	fx = side_x(0.31, 0.03)
	body_parts.append(rbox("flank_vent", (0.016, 0.05, 0.1), (s * (fx - 0.003), 0.31, 0.03), 0.006, "accent", segs=2, sub=1))
	for k in range(2):
		body_parts.append(rbox("flank_slat", (0.012, 0.008, 0.09), (s * (fx + 0.005), 0.3 + k * 0.02, 0.03), 0.003, "dark", sub=0, segs=1))
	sx_ = side_x(0.5)
	body_parts.append(cyl("shoulder_socket", 0.066, 0.05, (s * (sx_ - 0.012), 0.5, 0.0), "dark", axis='X', bevel=0.012))
	body_parts.append(torus("socket_ring", 0.069, 0.0055, (s * (sx_ + 0.01), 0.5, 0.0), "steel", axis='X', major=40, minor=6))
	for z in (-0.1, 0.1):
		xx = side_x(0.325, z)
		body_parts.append(screw((s * xx, 0.325, z), (s, 0, 0), r=0.0065))
# Dark underside: the torso's bottom rounds into a dark shell that carries the hover unit's stem.
UZ = TD / TW
under = lathe("underside", [(TW * 0.5 * tf(T_BOT) - 0.012, T_BOT + 0.03), (TW * 0.5 * tf(T_BOT) - 0.006, T_BOT + 0.004), (TW * 0.5 * tf(T_BOT) - 0.03, T_BOT - 0.022),
	(0.12, T_BOT - 0.03), (0.06, T_BOT - 0.034), (0.0, T_BOT - 0.035)], "trim", segs=56)
under.data.transform(Matrix.Scale(UZ, 4, Vector((0, 0, 1))))
body_parts.append(under)
# Neck: a dark column with pistons in the gap between head and torso.
body_parts.append(cyl("neck", 0.08, 0.075, (0, T_TOP + 0.02, 0.02), "dark", bevel=0.01))
for k in range(6):
	a = 2 * math.pi * k / 6
	body_parts.append(cyl("neck_piston", 0.006, 0.055, (math.cos(a) * 0.066, T_TOP + 0.022, 0.02 + math.sin(a) * 0.066), "steel", verts=8))
# Back: the framed panel's cyan-lit square round the bale hatch, screws.
HATCH_C = Vector((0, 0.435, back_z(0, 0.435)))
HATCH_HW, HATCH_HH = 0.092, 0.086
frame = []
for (cx, cy, a0) in ((HATCH_HW - 0.02, HATCH_HH - 0.02, 0), (-HATCH_HW + 0.02, HATCH_HH - 0.02, 90), (-HATCH_HW + 0.02, -HATCH_HH + 0.02, 180), (HATCH_HW - 0.02, -HATCH_HH + 0.02, 270)):
	for k in range(8):
		a = math.radians(a0 + 90 * k / 8)
		frame.append((cx + math.cos(a) * 0.02, HATCH_C.y + cy + math.sin(a) * 0.02))
body_parts.append(loop_tube("hatch_frame", [(x, y, back_z(x, y) + 0.002) for (x, y) in frame], 0.0105, "glow", sides=8))
for sx in (-1, 1):
	for y in (0.38, 0.5):
		body_parts.append(screw((sx * 0.118, y, back_z(sx * 0.118, y)), (0, 0, 1), r=0.0065))
# Hover unit: a stem, a dark tiered ring disc with a cyan rim light, and under it a smaller emitter
# disc whose whole underside glows (the turnaround's lit lower disc).
POD_N = len(body_parts)
POD_R = 0.178
body_parts.append(cyl("pod_stem", 0.05, 0.08, (0, 0.205, 0), "dark", verts=24, bevel=0.006))
body_parts.append(lathe("pod", [(0.0, 0.228), (0.085, 0.228), (0.095, 0.221), (0.14, 0.219), (POD_R - 0.008, 0.214), (POD_R, 0.204), (POD_R, 0.192), (POD_R - 0.01, 0.182),
	(0.135, 0.178), (0.125, 0.182), (0.07, 0.182), (0.0, 0.182)], "trim", segs=72))
body_parts.append(torus("pod_lip", 0.09, 0.005, (0, 0.228, 0), "steel", major=56, minor=6))
for k in range(8):
	a = 2 * math.pi * (k + 0.5) / 8
	body_parts.append(screw((math.cos(a) * 0.118, 0.2205, math.sin(a) * 0.118), (0, 1, 0), r=0.0055))
body_parts.append(lathe("pod_emitter", [(0.0, 0.172), (0.07, 0.172), (0.104, 0.168), (0.114, 0.158), (0.112, 0.147), (0.104, 0.143)], "dark", segs=56))
POD_DY = 0.0
body = join("body", body_parts)
thruster = torus("thruster", POD_R - 0.014, 0.0075, (0, 0.2125, 0), "thruster", major=96, minor=10)
thr_in = torus("thruster_in", 0.13, 0.0055, (0, 0.179, 0), "thruster", major=72, minor=8)
thr_em = lathe("thruster_em", [(0.052, 0.1735), (0.07, 0.1735), (0.102, 0.17), (0.108, 0.166), (0.106, 0.162), (0.052, 0.162), (0.052, 0.1735)], "thruster_core", segs=56)
core = lathe("thruster_core", [(0.104, 0.143), (0.094, 0.13), (0.06, 0.118), (0.0, 0.113)], "thruster_core", segs=48)
thruster = join("thruster", [thruster, thr_in, thr_em, core])

ICON_P = Vector((0, PL_C.y + 0.01, PL_FRONT - 0.002))

def recycle_icon(name, size, center, material):
	"""Three bent arrows chasing around a triangle (the recycling symbol), flat, facing -Z."""
	R = size * 0.5
	tri = [Vector((math.cos(math.radians(90 + 120 * k)), math.sin(math.radians(90 + 120 * k)), 0)) * R for k in range(3)]
	w = size * 0.12  # [hero v2] slimmer arrows, hollow middle (concept)
	parts = []
	for k in range(3):
		c0 = tri[k]
		prev = tri[k - 1]
		nxt = tri[(k + 1) % 3]
		a = c0 + (prev - c0) * 0.24   # start on the previous edge
		b = c0 + (nxt - c0) * 0.36    # shaft end on the next edge
		h = c0 + (nxt - c0) * 0.56    # arrow tip (a clear gap before the next arrow)
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



icon_recycle = recycle_icon("icon_recycle", 0.1, ICON_P, "glow")

# Hatch (hinged at its top edge) on the torso back: the dark square inside the lit frame.
HZ = HATCH_C.z
HATCH_P = Vector((0, HATCH_C.y + HATCH_HH - 0.006, HZ))
hatch = join("hatch", [
	rbox("hatch_plate", (HATCH_HW * 2 - 0.02, HATCH_HH * 2 - 0.02, 0.022), (0, HATCH_C.y, HZ + 0.002), 0.012, "trim", sub=1, segs=3),
	rbox("hatch_screen", (0.11, 0.1, 0.008), (0, HATCH_C.y + 0.004, HZ + 0.012), 0.005, "screen", sub=0, segs=2),
	rbox("hatch_handle", (0.036, 0.009, 0.01), (0, HATCH_C.y - 0.06, HZ + 0.014), 0.004, "accent", sub=0, segs=2),
	rbox("hatch_lamp", (0.012, 0.012, 0.006), (0, HATCH_C.y + 0.004, HZ + 0.017), 0.003, "glow_soft", sub=0, segs=1),
])

# ---------------------------------------------------------------- ARMS (right side; left is mirrored)
# Short, segmented: dark shoulder drum with a steel ring, cream shoulder cap, dark upper-arm core with
# a cream guard, chunky dark elbow drum with steel caps, a cream forearm with a dark band, a dark
# wrist and palm; pistons and cable bundles across the joints; chunky segmented claws.
S = Vector((side_x(0.5) + 0.03, 0.5, 0.0))
E = S + Vector((0.07, -0.105, -0.045))
W = E + Vector((0.0, -0.025, -0.145))
shoulder = join("arm_shoulder", [
	cyl("sh_drum", 0.06, 0.07, S + Vector((0.0, 0, 0)), "dark", axis='X', bevel=0.016, segs=3),
	torus("sh_ring", 0.06, 0.005, S + Vector((0.035, 0, 0)), "steel", axis='X', major=40, minor=6),
	rbox("sh_cap", (0.1, 0.105, 0.12), S + Vector((0.055, 0.02, 0.0)), 0.04, "paint", segs=4, sub=1),
	screw(S + Vector((0.106, 0.02, 0.0)), (1, 0, 0), r=0.008),
	tube("upper_core", [S + Vector((0.05, -0.03, -0.01)), E], 0.03, "dark", sides=16),
	rbox("upper_guard", (0.075, 0.06, 0.075), (S + E) * 0.5 + Vector((0.028, -0.008, -0.012)), 0.022, "paint", segs=3, sub=1, rot=(-24, 0, 24)),
	tube("sh_piston", [S + Vector((0.02, -0.055, 0.04)), E + Vector((-0.022, 0.0, 0.032))], 0.0065, "steel", sides=8),
	tube("sh_cable_a", [S + Vector((-0.03, -0.04, 0.03)), S + Vector((0.02, -0.08, 0.05)), E + Vector((-0.01, 0.02, 0.045))], 0.0055, "dark", sides=8),
	tube("sh_cable_b", [S + Vector((-0.03, -0.05, 0.015)), S + Vector((0.025, -0.09, 0.035)), E + Vector((0.0, 0.015, 0.04))], 0.0045, "cable", sides=8),
])
elbow = join("arm_elbow", [
	cyl("el_drum", 0.044, 0.095, E, "dark", axis='X', bevel=0.013, segs=3),
	cyl("el_cap", 0.026, 0.1, E, "steel", axis='X', bevel=0.004),
	rbox("fore_armor", (0.098, 0.088, 0.13), E + Vector((0.004, -0.01, -0.082)), 0.032, "paint", segs=4, sub=1, rot=(8, 0, 0)),
	rbox("fore_band", (0.101, 0.092, 0.02), E + Vector((0.004, -0.012, -0.124)), 0.008, "trim", sub=0, segs=2, rot=(8, 0, 0)),
	screw(E + Vector((0.054, -0.008, -0.07)), (1, 0, 0), r=0.007),
	screw(E + Vector((0.054, -0.008, -0.1)), (1, 0, 0), r=0.006),
	tube("el_piston", [E + Vector((-0.034, -0.042, -0.02)), E + Vector((-0.034, -0.038, -0.135))], 0.0065, "steel", sides=8),
	tube("el_cable", [E + Vector((-0.02, 0.035, 0.0)), E + Vector((-0.04, 0.02, -0.06)), E + Vector((-0.03, -0.01, -0.14))], 0.005, "cable", sides=8),
])
wrist = join("arm_wrist", [
	cyl("wr_ring", 0.042, 0.02, W + Vector((0, 0, 0.02)), "dark", axis='Z', bevel=0.006),
	torus("wr_steel", 0.044, 0.004, W + Vector((0, 0, 0.008)), "steel", axis='Z', major=32, minor=6),
	cyl("wr_cuff", 0.054, 0.034, W + Vector((0, 0, -0.006)), "paint", axis='Z', bevel=0.01),  # [hero v2] cream cuff (concept)
	rbox("palm", (0.088, 0.084, 0.052), W + Vector((0, 0, -0.038)), 0.018, "dark", segs=3, sub=1),
	torus("palm_ring", 0.047, 0.004, W + Vector((0, 0, -0.024)), "steel", axis='Z', major=32, minor=6),
])
# [hero v2] Hands (concept): chunky three-finger grippers. Each finger has a dark core with a light
# worn-grey armour plate on its outer face, a steel knuckle, then a second armoured segment ending in
# a hooked tip; the fingers curl into an open C. One finger (base segment) and one claw (middle
# segment + hooked tip), in their own frames: they point down -Z, outward = +Y.
finger = join("finger", [
	rbox("fg_core", (0.03, 0.028, 0.056), (0, -0.003, -0.024), 0.009, "dark", segs=2, sub=1),
	rbox("fg_armor", (0.042, 0.02, 0.05), (0, 0.011, -0.024), 0.009, "claw", segs=3, sub=1),
	rbox("fg_rib", (0.044, 0.006, 0.008), (0, 0.016, -0.04), 0.002, "dark", sub=0, segs=1),
	cyl("fg_knuckle", 0.017, 0.046, (0, 0.0, -0.051), "steel", axis='X', verts=16, bevel=0.004),
	cyl("fg_knuckle_cap", 0.009, 0.05, (0, 0.0, -0.051), "dark", axis='X', verts=12, bevel=0.002),
	screw((0.0, 0.021, -0.014), (0, 1, 0), r=0.0045),
])
# Tip: two more short armoured blocks with dark gaps and pads, each angled further inward, ending
# in a short blunt hook (the concept's fingers are three-block chains curling into a C).
def seg(name, size, center, rot, move):
	o = rbox(name, size, center, min(size) * 0.28, "claw", segs=3, sub=1)
	xform(o, move, rot)
	return o


def pad_(name, size, center, rot, move):
	o = rbox(name, size, center, 0.003, "dark", sub=0, segs=2)
	xform(o, move, rot)
	return o


S2 = Vector((0, -0.006, -0.04))      # second knuckle (tip frame), already turned 32 deg inward
S3 = S2 + Vector((0, -0.019, -0.031))  # third knuckle, another 30 deg in
tip_parts = [
	rbox("ft_mid", (0.04, 0.032, 0.038), (0, 0.004, -0.019), 0.01, "claw", segs=3, sub=1),
	rbox("ft_pad", (0.028, 0.012, 0.03), (0, -0.012, -0.02), 0.004, "dark", sub=0, segs=2),
	cyl("ft_knuckle", 0.014, 0.042, (0, 0.0, -0.034), "steel", axis='X', verts=14, bevel=0.003),
	cyl("ft_gap2", 0.012, 0.044, S2, "dark", axis='X', verts=12, bevel=0.002),
	seg("ft_seg2", (0.038, 0.03, 0.034), (0, 0.002, -0.017), (-32, 0, 0), S2),
	pad_("ft_pad2", (0.026, 0.01, 0.026), (0, -0.012, -0.016), (-32, 0, 0), S2),
	cyl("ft_gap3", 0.011, 0.04, S3, "dark", axis='X', verts=12, bevel=0.002),
	seg("ft_hook", (0.034, 0.026, 0.03), (0, 0.0, -0.013), (-62, 0, 0), S3),
	pad_("ft_hook_tip", (0.024, 0.012, 0.012), (0, -0.006, -0.028), (-62, 0, 0), S3),
]
tip = join("finger_tip", tip_parts)
tip.name = tip.data.name = "finger_tip"

shoulder_l = mirror_x(shoulder, "arm_shoulder_l")
elbow_l = mirror_x(elbow, "arm_elbow_l")
wrist_l = mirror_x(wrist, "arm_wrist_l")
for o, n in ((shoulder, "arm_shoulder_r"), (elbow, "arm_elbow_r"), (wrist, "arm_wrist_r")):
	o.name = n
	o.data.name = n

PARTS = {
	"body": Vector((0, 0, 0)), "thruster": Vector((0, 0, 0)), "hatch": HATCH_P, "head": HEAD_P, "ears": HEAD_P, "antenna": HEAD_P, "visor": VISOR_C,
	"icon_recycle": ICON_P,
	"arm_shoulder_r": S, "arm_elbow_r": E, "arm_wrist_r": W,
	"arm_shoulder_l": Vector((-S.x, S.y, S.z)), "arm_elbow_l": Vector((-E.x, E.y, E.z)), "arm_wrist_l": Vector((-W.x, W.y, W.z)),
	"finger": Vector((0, 0, 0)), "finger_tip": Vector((0, 0, 0)),
}
# Joint wear: armour near these pivots gets extra chips (vertex colour alpha).
JOINTS = [S, E, W, Vector((-S.x, S.y, S.z)), Vector((-E.x, E.y, E.z)), Vector((-W.x, W.y, W.z)), Vector((0, T_TOP + 0.02, 0.02))]


def decimate(obj, ratio):
	"""Collapse-decimate a dense shell (keeps the silhouette)."""
	md = obj.modifiers.new("dec", 'DECIMATE')
	md.ratio = ratio
	apply_mods(obj)
	smooth(obj)


decimate(head, float(os.environ.get("HEAD_DEC", "0.6")))
decimate(body, float(os.environ.get("BODY_DEC", "0.6")))
decimate(ears, 0.6)
HERO_OBJS = [o for o in bpy.data.objects if o.type == 'MESH']
print("anchors: head_top", tuple(FIN_BASE), "beacon(head space)", tuple(BEACON - HEAD_P), "chest_plate", tuple(ICON_P), "visor", tuple(VISOR_C), "S", tuple(S), "E", tuple(E), "W", tuple(W))

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
SHELLS = ("head", "body", "hatch")


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
		if o.name in SHELLS:
			edge = min(1.0, edge + 0.5 * sstep(4.0, 14.0, c))  # wear on the big rounded corners too
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


# ---------------------------------------------------------------- UVs
# [hero v2] Image-texture baking of the wear masks was tried and dropped: this container's Blender
# 4.0.2 Cycles bakes any shaded pass to images as black (EMIT, DIFFUSE colour and AO all came out
# 0; only NORMAL works). The wear is therefore per-pixel procedural in hero_paint.gdshader (object
# space, locked to the mesh), driven by the per-vertex AO / edge / cavity / joint masks baked above.


def unwrap(o):
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.select_all(action='DESELECT')
	o.select_set(True)
	bpy.ops.object.mode_set(mode='EDIT')
	bpy.ops.mesh.select_all(action='SELECT')
	bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, area_weight=0.6)
	bpy.ops.object.mode_set(mode='OBJECT')


def unwrap_atlas(group, margin=0.003):
	"""[hero v2] One shared UV atlas for a group of parts (multi-object edit mode packs every
	island into the same 0..1 square at one texel density): tools/hero/bake_masks.py bakes the
	per-pixel AO / edge / cavity mask atlas into it, and every hero paint material samples it."""
	bpy.ops.object.select_all(action='DESELECT')
	for o in group:
		o.select_set(True)
	bpy.context.view_layer.objects.active = group[0]
	bpy.ops.object.mode_set(mode='EDIT')
	bpy.ops.mesh.select_all(action='SELECT')
	bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=margin, area_weight=0.6)
	bpy.ops.object.mode_set(mode='OBJECT')


unwrap_atlas(HERO_OBJS)
for o in ACC_OBJS:
	unwrap(o)


# ---------------------------------------------------------------- pivots, UVs, axis conversion, export
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Godot (x,y,z) -> Blender (x,-z,y)
for o in objs:
	piv = PARTS.get(o.name, Vector((0, 0, 0)))
	o.data.transform(Matrix.Translation(-piv))
	o.data.transform(TO_BLENDER)
	o.location = TO_BLENDER @ piv
	o.data.use_auto_smooth = True
	o.data.auto_smooth_angle = math.radians(50)
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
					uvk = (round(uv[li].uv[0], 5), round(uv[li].uv[1], 5)) if uv else (0.0, 0.0)
					# [hero v2] UV seams split vertices too (the mask atlas needs exact UVs).
					key = (lp.vertex_index, round(lp.normal.x, 3), round(lp.normal.y, 3), round(lp.normal.z, 3), uvk)
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
		"face": (0.01, 0.01, 0.012), "paddle": (0.95, 0.66, 0.2), "paddle_edge": (1.0, 0.8, 0.45), "latch": (0.95, 0.42, 0.02), "cable": (0.12, 0.12, 0.13), "plate": (0.85, 0.83, 0.78), "fin": (0.55, 0.57, 0.6), "claw": (0.3, 0.31, 0.33), "glow_soft": (0.3, 0.9, 1.0), "thruster": (0.3, 0.9, 1.0), "thruster_core": (0.6, 1.0, 1.0)}
	for name, m in MATS.items():
		b = m.node_tree.nodes["Principled BSDF"]
		b.inputs["Base Color"].default_value = (*cols.get(name, (0.5, 0.5, 0.5)), 1)
		b.inputs["Roughness"].default_value = 0.1 if name in ("face", "screen") else 0.45
		if name in ("glow", "glow_soft", "lamp_accent", "thruster", "thruster_core", "paddle_edge", "latch"):
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
