# [art2] Hardware detail for Lumi, laid onto the shells of aurora.glb and exported as lumi_detail.glb:
#   blender -b --python art/models/aurora/build_lumi_detail.py
# The play camera sees Lumi from behind and above, where the model was a smooth white shell. This adds
# what real hardware has there: a service hatch (gasket seam, bolts, a vent grille, status lights, the
# stencilled unit number), panel seams round the head and over the crown, two grab rails, a seam and
# bolts round the body's bale hatch, and heat-sink fins low on the back.
# Method (ToggleOps toggle-studio 04, "fine pattern as thin geometry only where the silhouette or the
# shadow needs it"): every piece is found by casting rays onto the existing shell, so it follows the
# surface whatever its shape. Two objects come out, `detail_head` and `detail_body`, with their
# origins on the head and body pivots; PatchModel hangs them on those parts. Material slot names are
# PatchModel's (dark = rubber and recesses, steel, trim, accent, glow, lamp_accent, and side = the
# Locker's side-module colour), so every piece follows the Locker's colours; nothing has a colour of its own.
# Vertex colours as in build_aurora.py: R = ambient occlusion, G = edge wear, B = cavity dirt.
import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "aurora.glb")
OUT = os.path.join(HERE, "lumi_detail.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
SHELL = {o.name: o for o in bpy.data.objects if o.type == 'MESH'}
HEAD, BODY = SHELL["head"], SHELL["body"]
DG = bpy.context.evaluated_depsgraph_get()

MATS = {}


def mat(name):
	if name not in MATS:
		MATS[name] = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	return MATS[name]


class Part:
	"""One output object: faces gathered per material, in world space."""

	def __init__(self, name, pivot):
		self.name, self.pivot = name, Vector(pivot)
		self.bm = bmesh.new()
		self.slots = []
		self.col = self.bm.loops.layers.color.new("Col")

	def slot(self, material):
		if material not in self.slots:
			self.slots.append(material)
		return self.slots.index(material)

	def face(self, pts, material, ao=1.0, wear=0.0, dirt=0.2, smooth=True):
		vs = [self.bm.verts.new(p) for p in pts]
		try:
			f = self.bm.faces.new(vs)
		except ValueError:
			return
		f.material_index = self.slot(material)
		f.smooth = smooth
		for lp in f.loops:
			lp[self.col] = (ao, wear, dirt, 1.0)

	def finish(self):
		bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=0.00005)
		bmesh.ops.translate(self.bm, verts=self.bm.verts, vec=-self.pivot)
		me = bpy.data.meshes.new(self.name)
		self.bm.to_mesh(me)
		self.bm.free()
		for s in self.slots:
			me.materials.append(mat(s))
		ob = bpy.data.objects.new(self.name, me)
		ob.location = self.pivot
		bpy.context.scene.collection.objects.link(ob)
		return ob


def cast(shell, origin, direction):
	"""First hit of a ray on a shell (world space): (point, normal) or None."""
	inv = shell.matrix_world.inverted()
	o = inv @ Vector(origin)
	d = (inv.to_3x3() @ Vector(direction)).normalized()
	ok, loc, nrm, _ = shell.ray_cast(o, d)
	if not ok:
		return None
	return shell.matrix_world @ loc, (shell.matrix_world.to_3x3() @ nrm).normalized()


def back(shell, x, z):
	"""A point on the shell's back (the side the play camera sees), by a ray from behind."""
	return cast(shell, (x, -1.0, z), (0, 1, 0))


def top(shell, x, y):
	return cast(shell, (x, y, 2.0), (0, 0, -1))


def tube(part, hits, r, material, lift=0.0, sides=6, closed=False, ao=0.7, wear=0.0, dirt=0.6):
	"""A thin tube along surface hits [(point, normal)], sitting `lift` proud of the shell."""
	pts = [p + n * lift for p, n in hits]
	nrm = [n for _, n in hits]
	rings = []
	cnt = len(pts)
	for i in range(cnt):
		a = pts[(i - 1) % cnt] if (closed or i > 0) else pts[i]
		b = pts[(i + 1) % cnt] if (closed or i < cnt - 1) else pts[i]
		t = (b - a).normalized()
		side = t.cross(nrm[i]).normalized()
		up = side.cross(t).normalized()
		rings.append([pts[i] + (side * math.cos(k * math.tau / sides) + up * math.sin(k * math.tau / sides)) * r for k in range(sides)])
	last = cnt if closed else cnt - 1
	for i in range(last):
		ra, rb = rings[i], rings[(i + 1) % cnt]
		for k in range(sides):
			part.face([ra[k], ra[(k + 1) % sides], rb[(k + 1) % sides], rb[k]], material, ao, wear, dirt)


def disc(part, hit, r, h, material, sides=8, ao=1.0, wear=0.5, dirt=0.2, dome=0.0):
	"""A bolt head or lamp: a short cylinder standing on the shell along its normal."""
	p, n = hit
	ref = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
	u = n.cross(ref).normalized()
	v = n.cross(u)
	base = [p + (u * math.cos(k * math.tau / sides) + v * math.sin(k * math.tau / sides)) * r - n * 0.001 for k in range(sides)]
	cap = [p + (u * math.cos(k * math.tau / sides) + v * math.sin(k * math.tau / sides)) * r * (0.86 if dome == 0.0 else 0.6) + n * h for k in range(sides)]
	for k in range(sides):
		part.face([base[k], base[(k + 1) % sides], cap[(k + 1) % sides], cap[k]], material, ao * 0.8, wear, dirt, smooth=False)
	centre = p + n * (h + dome)
	for k in range(sides):
		part.face([cap[k], cap[(k + 1) % sides], centre], material, ao, wear, dirt, smooth=dome > 0.0)


def patch(part, fn, x0, x1, z0, z1, material, lift, nx=10, nz=5, ao=0.45, wear=0.0, dirt=0.8):
	"""A conformal quad patch over a rectangle of the fn(a, b) surface."""
	grid = []
	for j in range(nz + 1):
		row = []
		for i in range(nx + 1):
			h = fn(x0 + (x1 - x0) * i / nx, z0 + (z1 - z0) * j / nz)
			if h is None:
				return
			row.append(h[0] + h[1] * lift)
		grid.append(row)
	for j in range(nz):
		for i in range(nx):
			part.face([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]], material, ao, wear, dirt)


def box_on(part, hit, along, size, material, ao=0.9, wear=0.4, dirt=0.3):
	"""A small box standing on the shell: size = (along, across, out)."""
	p, n = hit
	a = (Vector(along) - n * Vector(along).dot(n)).normalized()
	c = n.cross(a)
	hx, hy, hz = size[0] / 2, size[1] / 2, size[2]
	cs = [p + a * sx * hx + c * sy * hy + n * sz for sz in (-0.001, hz) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
	for q in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
		part.face([cs[i] for i in q], material, ao, wear, dirt, smooth=False)


def rounded_rect(cx, cz, w, h, r, n=6):
	pts = []
	for qx, qz, a0 in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
		for k in range(n + 1):
			a = math.radians(a0 + 90 * k / n)
			pts.append((cx + qx * (w / 2 - r) + math.cos(a) * r, cz + qz * (h / 2 - r) + math.sin(a) * r))
	out = []
	for i in range(len(pts)):  # resample the straights so the tube follows the curved shell
		a, b = pts[i], pts[(i + 1) % len(pts)]
		steps = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / 0.012))
		for s in range(steps):
			out.append((a[0] + (b[0] - a[0]) * s / steps, a[1] + (b[1] - a[1]) * s / steps))
	return out


def stencil(part, text, cx, cz, height, material, shell):
	"""Real font glyphs (Blender's built-in face) pressed onto the back of a shell, read from behind."""
	cu = bpy.data.curves.new("txt", 'FONT')
	cu.body = text
	cu.size = height
	cu.align_x = 'CENTER'
	cu.resolution_u = 2
	ob = bpy.data.objects.new("txt", cu)
	bpy.context.scene.collection.objects.link(ob)
	me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
	bpy.data.objects.remove(ob)
	for poly in me.polygons:
		pts = []
		for vi in poly.vertices:
			v = me.vertices[vi].co
			# glyph x runs right for a reader standing behind Lumi (who looks along +Y): mirror x
			h = back(shell, cx - v.x, cz + v.y - height * 0.35)
			if h is None:
				pts = None
				break
			pts.append(h[0] + h[1] * 0.0009)
		if pts:
			part.face(list(reversed(pts)), material, 1.0, 0.0, 0.0, smooth=False)


# ------------------------------------------------------------------------------------------- head
head = Part("detail_head", HEAD.location)

# Service hatch on the back of the head: gasket seam, corner bolts, vent grille, lights, unit number.
HX, HZ, HW, HH = 0.0, 0.795, 0.34, 0.24
seam = [back(HEAD, x, z) for x, z in rounded_rect(HX, HZ, HW, HH, 0.045)]
if all(seam):
	tube(head, seam, 0.0048, "dark", lift=-0.0012, closed=True)
for sx in (-1, 1):
	for sz in (-1, 1):
		h = back(HEAD, HX + sx * (HW / 2 - 0.03), HZ + sz * (HH / 2 - 0.03))
		if h:
			disc(head, h, 0.0065, 0.003, "steel", sides=6)
# Vent grille: a dark recess with steel slats that stand proud and catch the light.
VZ = HZ + 0.045
patch(head, lambda a, b: back(HEAD, a, b), -0.095, 0.095, VZ - 0.036, VZ + 0.036, "dark", 0.0006)
for k in range(5):
	z = VZ - 0.027 + k * 0.0135
	hits = [back(HEAD, -0.088 + 0.176 * i / 12, z) for i in range(13)]
	if all(hits):
		tube(head, hits, 0.0034, "steel", lift=0.0032, sides=5, ao=0.9, wear=0.5, dirt=0.3)
for k in range(3):  # status lights under the grille
	h = back(HEAD, 0.075 - k * 0.022, HZ - 0.03)
	if h:
		disc(head, h, 0.0055, 0.002, "glow" if k < 2 else "lamp_accent", sides=8, dome=0.002)
stencil(head, "LM-1", -0.045, HZ - 0.072, 0.036, "dark", HEAD)
# A hazard tab by the hatch's lower corner (painted accent, not a light).
patch(head, lambda a, b: back(HEAD, a, b), 0.045, 0.125, HZ - 0.088, HZ - 0.07, "accent", 0.0007, nx=4, nz=1, ao=1.0, dirt=0.1)

# Panel seam round the back of the head, below the hatch, and two seams over the crown.
C = Vector((0.0, 0.02, 0.0))
ring = []
for i in range(61):
	a = math.radians(-78 + 156 * i / 60)  # 0 = straight back
	d = Vector((math.sin(a), -math.cos(a), 0.0))
	h = cast(HEAD, C + Vector((0, 0, 0.645)) + d * 1.2, -d)
	if h:
		ring.append(h)
tube(head, ring, 0.0042, "dark", lift=-0.0012)
for sx in (-1, 1):
	crown = [top(HEAD, sx * 0.17, -0.2 + 0.36 * i / 24) for i in range(25)]
	crown = [h for h in crown if h]
	tube(head, crown, 0.004, "dark", lift=-0.0012)
	for y in (-0.16, 0.12):  # a fastener at each end of the crown panel
		h = top(HEAD, sx * 0.2, y)
		if h:
			disc(head, h, 0.0055, 0.0025, "steel", sides=6)

# Grab rails either side of the hatch: steel bar on two standoffs (hardware you could lift him by).
for sx in (-1, 1):
	x = sx * 0.235
	feet = [back(HEAD, x, HZ - 0.075), back(HEAD, x, HZ + 0.075)]
	if all(feet):
		out = (feet[0][1] + feet[1][1]).normalized()
		arc = [(feet[0][0], out)] + [(feet[0][0].lerp(feet[1][0], t) + out * 0.022, out) for t in (0.08, 0.3, 0.5, 0.7, 0.92)] + [(feet[1][0], out)]
		tube(head, arc, 0.0055, "steel", sides=7, ao=0.95, wear=0.6, dirt=0.2)
		for f in feet:
			disc(head, f, 0.011, 0.004, "trim", sides=10, wear=0.3)

# Ear rings (owner's concept sheet, 26 Nov: a big glowing ring on each side of the head): a dark
# housing over the side pod, a wide light ring, a stepped hub with a steel collar and a lit centre.
xs = [(HEAD.matrix_world @ v.co) for v in HEAD.data.vertices]
pod = [v for v in xs if v.x > 0.40]
EY = sum(v.y for v in pod) / len(pod)
EZ = sum(v.z for v in pod) / len(pod)
print("EAR pod centre y=%.3f z=%.3f y[%.3f %.3f] z[%.3f %.3f]" % (EY, EZ, min(v.y for v in pod), max(v.y for v in pod), min(v.z for v in pod), max(v.z for v in pod)))


def ear_ring(part, sx):
	x0 = sx * (max(v.x for v in pod) - 0.004)
	ax = Vector((sx, 0, 0))

	def circ(r, out, n=28):
		return [Vector((x0 + sx * out, EY + math.cos(k * math.tau / n) * r, EZ + math.sin(k * math.tau / n) * r)) for k in range(n)]

	def band(a, b, material, ao=1.0, wear=0.3, dirt=0.2, smooth=True):
		n = len(a)
		for k in range(n):
			q = [a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]]
			part.face(q if sx > 0 else list(reversed(q)), material, ao, wear, dirt, smooth)

	R = 0.118
	prof = [  # (radius, outward, material of the band that ends here)
		(R, -0.03, None), (R, 0.0, "side"), (R + 0.002, 0.001, "side"), (R + 0.002, 0.009, "glow"), (R, 0.012, "side"), (R - 0.008, 0.02, "side"), (R - 0.016, 0.02, "side"),
		(R - 0.022, 0.014, "dark"), (R - 0.026, 0.017, "dark"), (R - 0.039, 0.017, "glow"), (R - 0.044, 0.012, "dark"),
		(R - 0.056, 0.022, "dark"), (R - 0.07, 0.026, "steel"), (R - 0.078, 0.02, "dark"), (R - 0.092, 0.022, "dark"), (R - 0.1, 0.024, "glow"),
	]
	prev = None
	for r, out, m in prof:
		c = circ(r, out)
		if prev is not None:
			band(prev, c, m, ao=0.8 if m == "dark" else 1.0, wear=0.6 if m in ("side", "steel") else 0.0, dirt=0.5 if m == "dark" else 0.15, smooth=m != "side")
		prev = c
	centre = Vector((x0 + sx * 0.024, EY, EZ))
	for k in range(len(prev)):
		q = [prev[k], prev[(k + 1) % len(prev)], centre]
		part.face(q if sx > 0 else list(reversed(q)), "dark", 0.8, 0.0, 0.4)
	for k in range(6):  # collar bolts
		a = k * math.tau / 6 + 0.3
		disc(part, (Vector((x0 + sx * 0.02, EY + math.cos(a) * (R - 0.012), EZ + math.sin(a) * (R - 0.012))), ax), 0.0045, 0.0025, "steel", sides=6)


# Their own object, so the Locker can swap the side modules without touching the shell hardware.
ears = Part("detail_ears", HEAD.location)
for sx in (-1, 1):
	ear_ring(ears, sx)

# ------------------------------------------------------------------------------------------- body
body = Part("detail_body", BODY.location)
# Seam round the back of the torso and bolts round the bale hatch (the hatch is its own part).
ring = []
for i in range(41):
	a = math.radians(-70 + 140 * i / 40)
	d = Vector((math.sin(a), -math.cos(a), 0.0))
	h = cast(BODY, Vector((0, 0, 0.295)) + d * 1.0, -d)
	if h:
		ring.append(h)
tube(body, ring, 0.004, "dark", lift=-0.0012)
for x, z in ((-0.135, 0.34), (0.135, 0.34), (-0.135, 0.48), (0.135, 0.48), (-0.135, 0.41), (0.135, 0.41)):
	h = back(BODY, x, z)
	if h:
		disc(body, h, 0.0055, 0.0028, "steel", sides=6)
# Heat-sink fins low on the back, either side of the spine: where the hover drive dumps its heat.
for sx in (-1, 1):
	for k in range(5):
		h = back(BODY, sx * (0.075 + k * 0.014), 0.235)
		if h:
			box_on(body, h, (0, 0, 1), (0.05, 0.005, 0.012), "steel", ao=0.75, wear=0.5, dirt=0.5)

objs = [head.finish(), ears.finish(), body.finish()]
for o in list(bpy.data.objects):
	if o not in objs:
		bpy.data.objects.remove(o, do_unlink=True)
for o in objs:
	o.select_set(True)
	print("DETAIL %s tris=%d slots=%s" % (o.name, sum(len(p.vertices) - 2 for p in o.data.polygons), [m.name for m in o.data.materials]))
kw = dict(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True, export_apply=False, export_normals=True, export_materials='EXPORT')
try:
	bpy.ops.export_scene.gltf(export_colors=True, **kw)
except TypeError:
	bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
print("WROTE", OUT)
