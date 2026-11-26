# [art6] Builds the worker robots (Scoopie, Haul Bug) and exports art/models/robots/workers.glb.
#   blender -b --python art/models/robots/build_workers.py          (PREVIEW=/path/prefix renders stills)
# Same maker as Lumi (art/models/aurora): pale chipped shells over dark mechanics, panel grooves,
# bolts, glow rings and strips, a dark visor with two round eyes. Simpler, lower work machines:
#   Scoopie   an overshot loader: twin booms pivot at the shoulders and throw the bucket over the
#             head into the open hopper behind it; four wheels (hover pods at Mk IV).
#   Haul Bug  a six-wheeled flatbed: a low head with two feelers up front, short fork tines, a bed
#             for six bales with a headboard and two side clamps that close on the load.
# Modelled in Godot coordinates (Y up, the robot faces -Z). Every exported object is one part of
# robots/robot_visual.gd: its origin is the part's pivot and its vertices are relative to it.
# Object names: sc_* / hb_*; material slot names tell RobotVisual which runtime material goes on
# a surface (paint, accent, trim, dark, steel, tyre, glass, glow, eye, lamp, bucket, far).
# Vertex colours: R = ambient occlusion (ray cast here), G = convex edge wear, B = cavity dirt
# (plus dirt from the ground up), A = 1 - joint wear. "lamp" surfaces carry their light colour
# instead; the *_far meshes carry R = AO, G = colour class, B = glow.
# The helpers are the ones Lumi's build uses (read out of build_aurora.py, not copied).
import ast
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "workers.glb")
AURORA = os.path.join(HERE, "..", "aurora", "build_aurora.py")

for o in list(bpy.data.objects):
	bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.meshes):
	bpy.data.meshes.remove(m)

MATS = {}
_src = open(AURORA).read()
_want = {"mat", "link", "from_bm", "apply_mods", "smooth", "xform", "rbox", "cyl", "torus", "lathe", "tube", "boolean",
	"groove", "join", "mirror_x", "prism", "with_material", "loop_tube", "rrect_loop", "curvature", "sstep", "write_glb"}
_mod = ast.parse(_src)
_mod.body = [n for n in _mod.body if isinstance(n, ast.FunctionDef) and n.name in _want]
import json
import struct
exec(compile(_mod, AURORA, "exec"), globals())


def decimate(obj, ratio):
	md = obj.modifiers.new("dec", 'DECIMATE')
	md.ratio = ratio
	apply_mods(obj)
	return smooth(obj)


def V(*a):
	return Vector(a)


def bolt(center, normal, r=0.009, material="steel"):
	"""A low hex bolt head, axis along `normal`."""
	n = Vector(normal).normalized()
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=5, radius1=r, radius2=r * 0.8, depth=r * 0.7)
	o = from_bm(bm, "bolt", material)
	o.data.transform(Matrix.Translation(Vector(center) + n * (r * 0.2)) @ n.to_track_quat('Z', 'Y').to_matrix().to_4x4())
	return o


def box(name, size, center, material, bevel=0.006, rot=(0, 0, 0), segs=1):
	return rbox(name, size, center, bevel, material, segs=segs, sub=0, rot=rot)


def strip_solid(name, profile, width, thick, material, bevel=0.003):
	"""A sheet following `profile` [(y, z)] extruded along X (centred), given a thickness."""
	bm = bmesh.new()
	a = [bm.verts.new((-width * 0.5, y, z)) for (y, z) in profile]
	b = [bm.verts.new((width * 0.5, y, z)) for (y, z) in profile]
	for i in range(len(profile) - 1):
		bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	o = from_bm(bm, name, material)
	md = o.modifiers.new("sol", 'SOLIDIFY')
	md.thickness = thick
	md.offset = 0.0
	if bevel > 0:
		md = o.modifiers.new("bev", 'BEVEL')
		md.width = bevel
		md.segments = 1
		md.limit_method = 'ANGLE'
		md.angle_limit = math.radians(50)
	apply_mods(o)
	return smooth(o)


def side_prism(name, pts_yz, thick, x, material, bevel=0.003):
	"""A flat plate in the Y-Z plane (outline [(y, z)]) at x, `thick` wide."""
	o = prism(name, [(-z, y) for (y, z) in pts_yz], thick, (0, 0, 0), material, bevel=bevel, segs=1, sub=0)
	# prism lies in X-Y extruded along Z: turn its X to -Z and its Z to X.
	o.data.transform(Matrix(((0, 0, 1, 0), (0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 0, 1))))
	o.data.transform(Matrix.Translation(V(x, 0, 0)))
	bm = bmesh.new()
	bm.from_mesh(o.data)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(o.data)
	bm.free()
	return o


def rod(name, a, b, r, material, verts=10):
	a, b = Vector(a), Vector(b)
	d = b - a
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts, radius1=r, radius2=r, depth=d.length)
	o = from_bm(bm, name, material)
	o.data.transform(Matrix.Translation((a + b) * 0.5) @ d.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4())
	return smooth(o)


def disc_x(name, r, depth, center, material, verts=20, bevel=0.004, r2=None):
	return cyl(name, r, depth, center, material, axis='X', verts=verts, bevel=bevel, r2=r2, segs=1)


def lamp_piece(o, color):
	"""A light surface: the vertex colour is the light's colour (unshaded material in the game)."""
	o.data.materials.clear()
	o.data.materials.append(mat("lamp"))
	attr = o.data.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
	for d in attr.data:
		d.color = (*color, 1.0)
	o["lamp"] = 1
	return o


def retag(o, material):
	o.data.materials.clear()
	o.data.materials.append(mat(material))
	return o


PARTS = {}      # object name -> pivot (Godot space)
JOINTS = {}     # prefix -> pivots that wear the paint near them
FAR = {}        # prefix -> objects whose copies make the far mesh
ANCHORS = {}


def part(name, objs, pivot=(0, 0, 0), far=True):
	o = join(name, objs) if len(objs) > 1 else objs[0]
	o.name = name
	o.data.name = name
	PARTS[name] = Vector(pivot)
	if far:
		FAR.setdefault(name[:2], []).append(o)
	return o


WARM = (1.0, 0.86, 0.62)
RED = (1.0, 0.12, 0.06)
AMBER = (1.0, 0.55, 0.1)


def wheel(name, r, w):
	"""Tyre with tread lugs and a dished, bolted hub on both faces. Axis X, centred."""
	hw = w * 0.5
	tyre = lathe("tyre", [(r * 0.62, hw), (r * 0.9, hw), (r, hw * 0.72), (r, -hw * 0.72), (r * 0.9, -hw), (r * 0.62, -hw)], "tyre", segs=16)
	ps = [tyre]
	for k in range(14):
		a = 2 * math.pi * k / 14
		lug = box("lug", (0.03, w * 0.8, 0.02), (math.cos(a) * (r - 0.006), 0, math.sin(a) * (r - 0.006)), "tyre", bevel=0.0, rot=(0, -math.degrees(a), 12 if k % 2 else -12))
		# lathe is about Y: lugs built round Y too.
		ps.append(lug)
	for s in (-1, 1):
		ps.append(lathe("hub", [(0.0, s * hw * 0.62), (r * 0.3, s * hw * 0.62), (r * 0.56, s * hw * 0.8), (r * 0.64, s * hw * 0.86), (r * 0.64, s * hw * 0.5)] if s > 0 else
			[(r * 0.64, s * hw * 0.5), (r * 0.64, s * hw * 0.86), (r * 0.56, s * hw * 0.8), (r * 0.3, s * hw * 0.62), (0.0, s * hw * 0.62)], "accent", segs=12))
		ps.append(cyl("cap", r * 0.16, 0.012, (0, s * hw * 0.66, 0), "accent", axis='Y', verts=8))
		for k in range(5):
			a = 2 * math.pi * k / 5
			ps.append(bolt((math.cos(a) * r * 0.42, s * hw * 0.7, math.sin(a) * r * 0.42), (0, s, 0), r=0.008, material="accent"))
	o = join(name, ps)
	o.data.transform(Matrix.Rotation(math.radians(90), 4, 'Z'))  # Y axis -> X axis
	return o


def wheel_glow(name, r, w):
	ps = [torus("wg", r * 0.6, 0.005, (s * w * 0.44, 0, 0), "glow", axis='X', major=10, minor=3) for s in (-1, 1)]
	return join(name, ps)


def visor_head(pre, w, h, d, eye_r, eye_dx):
	"""A pill head (centred on the origin, facing -Z): pale shell, a dark visor let into the
	front, bolts, dark ear discs. Returns (head objects, eyes object, ear ring objects)."""
	shell = rbox(pre + "head_shell", (w, h, d), (0, 0, 0), min(h, d) * 0.42, "paint", segs=4, sub=1)
	cut = rbox("visor_cut", (w * 0.84, h * 0.66, 0.06), (0, 0.004, -d * 0.5), h * 0.2, "dark", segs=3, sub=0)
	boolean(shell, cut)
	groove(shell, (w * 1.2, 0.005, d * 1.2), (0, -h * 0.5 + h * 0.2, 0), depth=0.006, material="dark")
	ps = [decimate(shell, 0.4)]
	ps.append(rbox("visor", (w * 0.8, h * 0.6, 0.03), (0, 0.004, -d * 0.5 + 0.03), h * 0.17, "glass", segs=3, sub=0))
	brow = box("brow", (w * 0.6, 0.014, 0.03), (0, h * 0.5 - 0.012, -d * 0.5 + 0.035), "dark", bevel=0.004, rot=(-12, 0, 0))
	ps.append(brow)
	ears = []
	for s in (-1, 1):
		ps.append(disc_x("ear", h * 0.3, 0.03, (s * (w * 0.5 + 0.004), 0, 0.005), "dark", verts=16))
		ps.append(disc_x("ear_cap", h * 0.14, 0.012, (s * (w * 0.5 + 0.022), 0, 0.005), "dark", verts=10, bevel=0.0))
		ears.append(torus("ear_ring", h * 0.22, 0.005, (s * (w * 0.5 + 0.02), 0, 0.005), "glow", axis='X', major=20, minor=4))
		for (y, z) in ((h * 0.3, d * 0.22), (-h * 0.3, d * 0.22)):
			ps.append(bolt((s * w * 0.5, y * 0.6, z), (s, 0, 0), r=0.007, material="dark"))
	for x in (-w * 0.3, w * 0.3):
		ps.append(bolt((x, h * 0.5, d * 0.12), (0, 1, 0), r=0.007, material="dark"))
	eyes = []
	for s in (-1, 1):
		eyes.append(cyl("eye", eye_r, 0.006, (s * eye_dx, 0.004, -d * 0.5 + 0.013), "eye", axis='Z', verts=18))
		eyes.append(torus("eye_ring", eye_r * 1.25, 0.004, (s * eye_dx, 0.004, -d * 0.5 + 0.013), "eye", axis='Z', major=16, minor=4))
	return ps, join(pre + "eyes", eyes), join(pre + "head_glow", ears)


def hover_pod(name, r):
	"""A hover pod like Lumi's underside: a dark dish, a pale collar and a recessed glow ring."""
	ps = [lathe("pod_dish", [(r * 0.5, 0.05), (r, 0.03), (r * 1.06, 0.0), (r * 0.98, -0.03), (r * 0.6, -0.045), (0.0, -0.045)], "dark", segs=20),
		lathe("pod_collar", [(r * 0.3, 0.085), (r * 0.56, 0.075), (r * 0.62, 0.045), (r * 0.3, 0.045)], "paint", segs=16)]
	for k in range(4):
		a = 2 * math.pi * (k + 0.5) / 4
		ps.append(bolt((math.cos(a) * r * 0.82, 0.022, math.sin(a) * r * 0.82), (0, 1, 0.0), r=0.008, material="dark"))
	glow = join(name + "_glow", [torus("pg", r * 0.78, 0.008, (0, -0.04, 0), "glow", axis='Y', major=24, minor=4),
		lathe("pg_core", [(0.0, -0.047), (r * 0.42, -0.047)], "glow", segs=14)])
	bm = bmesh.new()
	bm.from_mesh(glow.data)
	for f in bm.faces:  # the core disc faces down
		if f.normal.y > 0.5:
			f.normal_flip()
	bm.to_mesh(glow.data)
	bm.free()
	return join(name, ps), glow


def under_ring(name, r, y):
	"""The glow ring under the body that lights the ground (all looks)."""
	return join(name, [torus("ur", r, 0.009, (0, y, 0), "glow", axis='Y', major=24, minor=4),
		torus("ur2", r * 0.62, 0.005, (0, y + 0.004, 0), "glow", axis='Y', major=16, minor=3)])


def ring_seat(r, y, material="dark"):
	return lathe("ring_seat", [(r * 0.5, y + 0.03), (r + 0.03, y + 0.03), (r + 0.036, y + 0.008), (r - 0.03, y + 0.004), (r * 0.5, y + 0.012)], material, segs=28)


# ================================================================ SCOOPIE
def build_scoopie():
	P = "sc_"
	WR, WW = 0.15, 0.11
	WX, WZ0, WZ1 = 0.355, -0.25, 0.27
	# --- unsprung base: axles, hub carriers
	base = []
	for z in (WZ0, WZ1):
		base.append(rod("axle", (-WX + WW * 0.5, WR, z), (WX - WW * 0.5, WR, z), 0.022, "steel", 8))
		for s in (-1, 1):
			base.append(disc_x("carrier", 0.06, 0.03, (s * (WX - WW * 0.5 - 0.02), WR, z), "dark", verts=12))
			base.append(box("swing", (0.03, 0.035, 0.2), (s * 0.24, WR + 0.03, z + (0.07 if z < 0 else -0.07)), "dark", rot=(12 if z < 0 else -12, 0, 0)))
	part(P + "base", base, far=False)
	part(P + "tyre", [wheel(P + "tyre", WR, WW)], far=False)
	part(P + "hub_glow", [wheel_glow(P + "hub_glow", WR, WW)], far=False)
	# --- sprung body
	body = []
	tub = rbox("tub", (0.5, 0.17, 0.8), (0, 0.215, 0.01), 0.05, "dark", segs=3, sub=0)
	body.append(tub)
	body.append(box("skid", (0.4, 0.016, 0.26), (0, 0.13, -0.3), "steel", rot=(-14, 0, 0)))
	body.append(box("bumper", (0.54, 0.05, 0.035), (0, 0.2, -0.415), "steel", bevel=0.012))
	for x in (-0.2, 0.2):
		body.append(box("bump_arm", (0.035, 0.035, 0.06), (x, 0.2, -0.39), "dark"))
	# Shell: a pale hopper tub with an open top, a belt groove and panel seams.
	SH_C, SH_S = V(0, 0.475, 0.045), (0.58, 0.39, 0.68)
	shell = rbox("shell", SH_S, SH_C, 0.085, "paint", segs=4, sub=1)
	cut = rbox("hop_cut", (0.42, 0.3, 0.4), (0, 0.67, 0.12), 0.05, "trim", segs=3, sub=0)
	boolean(shell, cut)
	groove(shell, (0.7, 0.006, 0.8), (0, 0.395, 0.045), depth=0.008)
	for z in (-0.13, 0.25):
		groove(shell, (0.7, 0.2, 0.005), (0, 0.5, z), depth=0.007)
	body.append(decimate(shell, 0.4))
	# Hopper rim: a dark bolted collar round the opening, a rubber lip.
	body.append(loop_tube("hop_rim", rrect_loop(0.218, 0.208, 0.055, 0.672, n=5), 0.014, "trim", sides=6).data and bpy.context.scene.objects["hop_rim"])
	bpy.context.scene.objects["hop_rim"].data.transform(Matrix.Translation(V(0, 0, 0.12)))
	for (x, z) in ((-0.2, -0.05), (0.2, -0.05), (-0.2, 0.29), (0.2, 0.29), (0, 0.325), (-0.235, 0.12), (0.235, 0.12)):
		body.append(bolt((x, 0.684, z), (0, 1, 0), r=0.008))
	# Accent band plates below the belt line, proud of the shell, bolted.
	for s in (-1, 1):
		body.append(rbox("band", (0.016, 0.085, 0.36), (s * 0.292, 0.335, 0.06), 0.006, "accent", segs=2, sub=0))
		for z in (-0.1, 0.22):
			body.append(bolt((s * 0.301, 0.335, z), (s, 0, 0), r=0.007))
		# Side port: a dark round socket (the glow ring sits in it on the lit looks).
		body.append(disc_x("port", 0.05, 0.02, (s * 0.287, 0.52, 0.19), "dark", verts=16))
		body.append(disc_x("port_cap", 0.022, 0.012, (s * 0.297, 0.52, 0.19), "steel", verts=10, bevel=0.0))
		# Fenders over the rear wheels.
		body.append(strip_solid("fender", [(0.2, WZ1 + 0.21), (0.3, WZ1 + 0.17), (0.335, WZ1 + 0.06), (0.335, WZ1 - 0.08), (0.3, WZ1 - 0.17)], 0.13, 0.012, "paint"))
		body[-1].data.transform(Matrix.Translation(V(s * WX, 0, 0)))
		for (y, z) in ((0.61, -0.2), (0.61, 0.33), (0.44, 0.33)):
			body.append(bolt((s * 0.289, y, z), (s, 0, 0), r=0.007))
	body.append(rbox("band_back", (0.4, 0.085, 0.016), (0, 0.335, 0.383), 0.006, "accent", segs=2, sub=0))
	# Rear power pack: vented dark box, cables into the shell, a grab bar.
	body.append(rbox("pack", (0.34, 0.2, 0.09), (0, 0.5, 0.415), 0.02, "trim", segs=2, sub=0))
	for k in range(4):
		body.append(box("vent", (0.24, 0.012, 0.012), (0, 0.44 + k * 0.035, 0.462), "dark", bevel=0.003))
	for s in (-1, 1):
		body.append(tube("cable", [(s * 0.12, 0.6, 0.43), (s * 0.15, 0.66, 0.42), (s * 0.17, 0.655, 0.36), (s * 0.17, 0.62, 0.33)], 0.011, "dark", sides=6))
		body.append(bolt((s * 0.14, 0.5, 0.461), (0, 0, 1), r=0.007))
	body.append(tube("grab", [(-0.13, 0.6, 0.45), (-0.13, 0.63, 0.485), (0.13, 0.63, 0.485), (0.13, 0.6, 0.45)], 0.009, "steel", sides=6))
	# Shoulder hubs for the booms; ram feet low on the tub.
	SHO = V(0.335, 0.53, 0.0)
	for s in (-1, 1):
		body.append(disc_x("sho_hub", 0.072, 0.05, (s * 0.305, SHO.y, SHO.z), "dark", verts=18))
		body.append(box("sho_plate", (0.02, 0.17, 0.17), (s * 0.288, SHO.y - 0.01, SHO.z), "trim", bevel=0.02))
		body.append(box("ram_foot", (0.04, 0.06, 0.07), (s * 0.3, 0.25, 0.12), "dark", bevel=0.01))
	# Neck socket in front of the hopper.
	body.append(cyl("neck_seat", 0.06, 0.03, (0, 0.672, -0.2), "dark", axis='Y', verts=16, bevel=0.006))
	body.append(ring_seat(0.2, 0.118))
	body.append(box("plate_no", (0.15, 0.06, 0.008), (0, 0.5, -0.297), "accent", bevel=0.003))
	part(P + "body", body)
	# Lit pieces.
	lamps = []
	for s in (-1, 1):
		lamps.append(lamp_piece(cyl("headlight", 0.028, 0.012, (s * 0.2, 0.34, -0.3), "lamp", axis='Z', verts=12), WARM))
		lamps.append(lamp_piece(box("tail", (0.07, 0.022, 0.008), (s * 0.2, 0.34, 0.392), "lamp", bevel=0.0), RED))
	part(P + "lamps", lamps, far=False)
	glow = []
	for s in (-1, 1):
		glow.append(torus("port_ring", 0.036, 0.005, (s * 0.299, 0.52, 0.19), "glow", axis='X', major=20, minor=4))
		glow.append(box("strip", (0.006, 0.014, 0.3), (s * 0.292, 0.425, 0.06), "glow", bevel=0.0))
	glow.append(box("strip_b", (0.26, 0.014, 0.006), (0, 0.425, 0.386), "glow", bevel=0.0))
	part(P + "body_glow", glow, far=False)
	part(P + "ring", [under_ring(P + "ring", 0.2, 0.118)], far=False)
	part(P + "status", [box("status", (0.1, 0.016, 0.01), (0, 0.585, 0.462), "glow", bevel=0.003)], far=False)
	# Salvage look: the left side cover is gone (frame, cells and cables show), a bolted patch.
	guts = [box("gut_frame", (0.012, 0.03, 0.34), (-0.296, y, 0.06), "dark", bevel=0.003) for y in (0.3, 0.37)]
	for k in range(3):
		guts.append(cyl("cell", 0.03, 0.02, (-0.296, 0.335, -0.04 + k * 0.1), "dark", axis='X', verts=10))
	guts.append(tube("gut_cable", [(-0.3, 0.37, -0.1), (-0.31, 0.33, -0.02), (-0.305, 0.36, 0.1), (-0.3, 0.31, 0.2)], 0.008, "accent", sides=5))
	part(P + "guts", guts, far=False)
	patch = [rbox("patch", (0.012, 0.15, 0.2), (0.294, 0.54, -0.02), 0.004, "accent", segs=1, sub=0, rot=(0, 0, 0))]
	for (y, z) in ((0.6, -0.1), (0.6, 0.06), (0.48, -0.1), (0.48, 0.06)):
		patch.append(bolt((0.301, y, z), (1, 0, 0), r=0.008, material="accent"))
	part(P + "patch", patch, far=False)
	# --- head: on a short neck in front of the hopper, between the booms
	HEAD = V(0, 0.7, -0.2)
	HC = V(0, 0.835, -0.215)
	hp, eyes, ears = visor_head(P, 0.31, 0.19, 0.22, 0.03, 0.07)
	for o in hp + [eyes, ears]:
		o.data.transform(Matrix.Translation(HC))
	hp.append(cyl("neck", 0.032, 0.09, (0, 0.72, -0.2), "dark", axis='Y', verts=10))
	for k in range(3):
		hp.append(torus("neck_rib", 0.036, 0.008, (0, 0.69 + k * 0.022, -0.2), "dark", axis='Y', major=12, minor=4))
	part(P + "head", hp, HEAD)
	part(P + "eyes", [eyes], HC + V(0, 0.004, -0.097), far=False)
	part(P + "head_glow", [ears], HEAD, far=False)
	ANT = HC + V(0.1, 0.09, 0.05)
	part(P + "antenna", [rod("ant", ANT, ANT + V(0.01, 0.13, 0.03), 0.005, "dark", 5), cyl("ant_base", 0.014, 0.02, ANT + V(0, 0.005, 0), "dark", axis='Y', verts=8)], ANT, far=False)
	part(P + "beacon", [cyl("beacon", 0.014, 0.022, ANT + V(0.01, 0.14, 0.03), "glow", axis='Y', verts=8)], ANT, far=False)
	# --- booms (one part, both sides): shoulder (0.335, 0.53, 0) down to the bucket pin
	PIN = V(0.3, 0.2, -0.535)
	boom = []
	for s in (-1, 1):
		a = V(s * 0.352, SHO.y, SHO.z)
		k1 = V(s * 0.352, 0.42, -0.3)   # knee: the boom is cranked, like a loader's
		b = V(s * PIN.x, PIN.y, PIN.z)
		for (p, q, sz) in ((a, k1, (0.034, 0.062)), (k1, b, (0.03, 0.052))):
			d = q - p
			seg = rbox("boom_seg", (sz[0], sz[1], d.length + 0.03), (0, 0, 0), 0.01, "accent", segs=1, sub=0)
			seg.data.transform(Matrix.Translation((p + q) * 0.5) @ d.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4())
			boom.append(seg)
		boom.append(disc_x("boom_eye", 0.05, 0.04, tuple(a), "accent", verts=12))
		boom.append(disc_x("boom_pin", 0.02, 0.05, tuple(a), "dark", verts=8, bevel=0.0))
		boom.append(disc_x("knee", 0.036, 0.04, tuple(k1), "dark", verts=12))
		boom.append(disc_x("pin", 0.03, 0.045, tuple(b), "dark", verts=12))
		boom.append(box("ram_ear", (0.03, 0.045, 0.05), (s * 0.322, 0.4, -0.25), "dark", bevel=0.008))
		boom.append(bolt(k1 + V(s * 0.022, 0, 0), (s, 0, 0), r=0.009, material="dark"))
	boom.append(rod("cross", (-0.34, 0.43, -0.27), (0.34, 0.43, -0.27), 0.016, "dark", 8))
	part(P + "boom", boom, V(0, SHO.y, SHO.z))
	# Rams: each a barrel (from the tub foot) and a rod (from the boom ear), aimed by the script.
	# Built along -Z from their pivot.
	part(P + "ram_cyl", [rod("ram_cyl", (0, 0, 0), (0, 0, -0.3), 0.019, "dark", 8), rod("ram_collar", (0, 0, -0.285), (0, 0, -0.305), 0.023, "dark", 8)], (0, 0, 0), far=False)
	part(P + "ram_rod", [rod("ram_rod", (0, 0, 0), (0, 0, -0.33), 0.01, "steel", 6)], (0, 0, 0), far=False)
	# --- bucket: pivots on the pins
	prof = [(0.11, 0.0), (0.085, 0.05), (0.0, 0.07), (-0.085, 0.05), (-0.13, -0.02), (-0.145, -0.14), (-0.15, -0.27)]
	bk = [strip_solid("bucket_skin", prof, 0.56, 0.014, "bucket", bevel=0.0)]
	hull = [(0.11, 0.0), (0.085, 0.05), (0.0, 0.07), (-0.085, 0.05), (-0.13, -0.02), (-0.145, -0.14), (-0.15, -0.27), (-0.06, -0.2), (0.06, -0.06)]
	for s in (-1, 1):
		bk.append(side_prism("cheek", hull, 0.014, s * 0.283, "bucket"))
		bk.append(box("pin_ear", (0.03, 0.07, 0.07), (s * 0.3, 0.0, 0.03), "steel", bevel=0.012))
	bk.append(box("lip", (0.58, 0.012, 0.05), (0, -0.152, -0.262), "steel", bevel=0.003, rot=(-4, 0, 0)))
	for k in range(5):
		bk.append(box("tooth", (0.04, 0.02, 0.07), (-0.22 + k * 0.11, -0.153, -0.305), "steel", bevel=0.006, rot=(-6, 0, 0)))
	for x in (-0.2, 0.0, 0.2):
		bk.append(box("rib", (0.02, 0.02, 0.2), (x, -0.157, -0.12), "bucket", bevel=0.004, rot=(-4, 0, 0)))
	bk.append(box("back_bar", (0.5, 0.03, 0.024), (0, 0.09, 0.04), "steel", bevel=0.006))
	o = join("bucket_tmp", bk)
	o.data.transform(Matrix.Translation(V(0, PIN.y, PIN.z)))
	part(P + "bucket", [o], V(0, PIN.y, PIN.z))
	# --- hover pods (Mk IV, instead of the wheels)
	pod, pod_glow = hover_pod(P + "pod", 0.13)
	part(P + "pod", [pod], far=False)
	part(P + "pod_glow", [pod_glow], far=False)
	JOINTS[P] = [V(s * 0.335, 0.53, 0) for s in (-1, 1)] + [V(s * 0.3, 0.2, -0.535) for s in (-1, 1)] + [HEAD]
	ANCHORS[P] = {"head": HEAD, "head_c": HC, "antenna": ANT, "boom": V(0, SHO.y, SHO.z), "pin": PIN, "ram_foot": V(0.312, 0.25, 0.12),
		"ram_ear": V(0.312, 0.4, -0.25), "wheels": [V(s * WX, WR, z) for z in (WZ0, WZ1) for s in (-1, 1)], "wheel_r": WR,
		"pods": [V(s * 0.3, 0.1, z) for z in (-0.22, 0.26) for s in (-1, 1)], "hopper": V(0, 0.66, 0.12), "ring_y": 0.118,
		"emitter": V(0, 0.07, -0.72), "top": 1.07}


# ================================================================ HAUL BUG
def build_haulbug():
	P = "hb_"
	WR, WW = 0.13, 0.1
	WX = 0.4
	WZ = (-0.36, 0.08, 0.5)
	base = []
	for z in WZ:
		base.append(rod("axle", (-WX + WW * 0.5, WR, z), (WX - WW * 0.5, WR, z), 0.02, "steel", 8))
		for s in (-1, 1):
			base.append(disc_x("carrier", 0.055, 0.03, (s * (WX - WW * 0.5 - 0.02), WR, z), "dark", verts=8, bevel=0.0))
	for s in (-1, 1):  # bogie beam between the two rear axles
		base.append(box("bogie", (0.03, 0.04, 0.46), (s * 0.3, WR + 0.012, 0.29), "dark"))
		base.append(disc_x("bogie_pin", 0.035, 0.04, (s * 0.3, WR + 0.03, 0.29), "steel", verts=10))
	part(P + "base", base, far=False)
	part(P + "tyre", [wheel(P + "tyre", WR, WW)], far=False)
	part(P + "hub_glow", [wheel_glow(P + "hub_glow", WR, WW)], far=False)
	body = []
	body.append(rbox("frame", (0.56, 0.13, 1.22), (0, 0.225, 0.07), 0.04, "dark", segs=3, sub=0))
	body.append(box("bumper_r", (0.66, 0.05, 0.035), (0, 0.2, 0.7), "steel", bevel=0.012))
	body.append(tube("tow", [(0, 0.2, 0.71), (0, 0.19, 0.76), (0, 0.23, 0.775), (0, 0.25, 0.75)], 0.012, "steel", sides=6))
	# Bed: a deck for two stacks of bales side by side, slats, tie rings, a low back rail.
	BED_Y = 0.335
	BED_Z = 0.3
	body.append(rbox("deck", (0.9, 0.05, 0.62), (0, BED_Y - 0.025, BED_Z), 0.014, "trim", segs=2, sub=0))
	for k in range(5):
		body.append(box("slat", (0.82, 0.01, 0.07), (0, BED_Y + 0.003, BED_Z - 0.22 + k * 0.11), "dark", bevel=0.003))
	body.append(rbox("deck_edge_b", (0.9, 0.07, 0.03), (0, BED_Y + 0.012, BED_Z + 0.31), 0.008, "accent", segs=2, sub=0))
	for s in (-1, 1):
		body.append(rbox("deck_edge", (0.03, 0.05, 0.62), (s * 0.45, BED_Y - 0.005, BED_Z), 0.008, "accent", segs=2, sub=0))
		for z in (-0.2, 0.2):
			body.append(torus("tie", 0.016, 0.004, (s * 0.41, BED_Y + 0.012, BED_Z + z), "steel", axis='X', major=8, minor=4))
		body.append(box("post", (0.03, 0.12, 0.03), (s * 0.43, BED_Y + 0.06, BED_Z + 0.3), "trim"))
		# clamp hinge blocks on the bed side
		for z in (-0.12, 0.12):
			body.append(box("hinge", (0.04, 0.05, 0.05), (s * 0.465, BED_Y + 0.005, BED_Z + z), "dark", bevel=0.01))
		body.append(strip_solid("mudflap", [(0.26, 0.0), (0.12, 0.012)], 0.1, 0.008, "dark", bevel=0.0))
		body[-1].data.transform(Matrix.Translation(V(s * WX, 0, 0.66)))
	body.append(rod("back_rail", (-0.43, BED_Y + 0.115, BED_Z + 0.3), (0.43, BED_Y + 0.115, BED_Z + 0.3), 0.012, "steel", 8))
	# Headboard: a pale panel between the bed and the hood, with the load meter's dark window.
	HB_Z = BED_Z - 0.335
	hb = rbox("headboard", (0.84, 0.36, 0.05), (0, BED_Y + 0.16, HB_Z), 0.02, "paint", segs=3, sub=1)
	groove(hb, (0.9, 0.005, 0.2), (0, BED_Y + 0.08, HB_Z), depth=0.006)
	body.append(decimate(hb, 0.35))
	body.append(box("meter_win", (0.5, 0.045, 0.012), (0, BED_Y + 0.27, HB_Z + 0.026), "dark", bevel=0.004))
	for k in range(7):
		body.append(box("meter_div", (0.008, 0.05, 0.016), (-0.24 + k * 0.08, BED_Y + 0.27, HB_Z + 0.028), "trim", bevel=0.0))
	for s in (-1, 1):
		body.append(box("hb_stay", (0.03, 0.3, 0.035), (s * 0.4, BED_Y + 0.14, HB_Z - 0.04), "trim"))
		for y in (0.05, 0.27):
			body.append(bolt((s * 0.34, BED_Y + y, HB_Z + 0.026), (0, 0, 1), r=0.008))
	# Hood: a pale rounded nose over the front axle, belt groove, accent cheeks, side ports.
	HOOD_C = V(0, 0.4, -0.33)
	hood = rbox("hood", (0.62, 0.26, 0.5), HOOD_C, 0.09, "paint", segs=4, sub=1)
	groove(hood, (0.7, 0.005, 0.6), (0, 0.345, -0.33), depth=0.007)
	groove(hood, (0.2, 0.3, 0.005), (0, 0.5, -0.3), depth=0.006)
	body.append(decimate(hood, 0.4))
	for s in (-1, 1):
		body.append(rbox("cheek", (0.016, 0.07, 0.3), (s * 0.312, 0.305, -0.33), 0.006, "accent", segs=2, sub=0))
		for z in (-0.44, -0.22):
			body.append(bolt((s * 0.321, 0.305, z), (s, 0, 0), r=0.007))
		body.append(disc_x("port", 0.045, 0.02, (s * 0.307, 0.43, -0.3), "dark", verts=16))
		body.append(disc_x("port_cap", 0.02, 0.012, (s * 0.317, 0.43, -0.3), "steel", verts=10, bevel=0.0))
		body.append(strip_solid("fender", [(0.2, WZ[0] - 0.19), (0.275, WZ[0] - 0.15), (0.3, WZ[0] - 0.04), (0.3, WZ[0] + 0.1), (0.27, WZ[0] + 0.18)], 0.12, 0.012, "paint"))
		body[-1].data.transform(Matrix.Translation(V(s * WX, 0, 0)))
		for (x, z) in ((0.2, -0.5), (0.2, -0.16)):
			body.append(bolt((s * x, 0.531, z), (0, 1, 0), r=0.007))
	body.append(box("grille", (0.3, 0.07, 0.012), (0, 0.38, -0.582), "dark", bevel=0.004))
	for k in range(3):
		body.append(box("grille_bar", (0.28, 0.008, 0.012), (0, 0.36 + k * 0.02, -0.586), "steel", bevel=0.0))
	body.append(box("bumper_f", (0.6, 0.05, 0.035), (0, 0.2, -0.56), "steel", bevel=0.012))
	body.append(cyl("neck_seat", 0.06, 0.03, (0, 0.535, -0.4), "dark", axis='Y', verts=16, bevel=0.006))
	# fork carriage rails on the nose
	for s in (-1, 1):
		body.append(box("fork_rail", (0.03, 0.2, 0.03), (s * 0.17, 0.27, -0.6), "trim"))
	body.append(ring_seat(0.2, 0.118))
	part(P + "body", body)
	lamps = []
	for s in (-1, 1):
		lamps.append(lamp_piece(cyl("headlight", 0.028, 0.012, (s * 0.24, 0.4, -0.583), "lamp", axis='Z', verts=12), WARM))
		lamps.append(lamp_piece(box("tail", (0.08, 0.022, 0.008), (s * 0.3, 0.335, 0.628), "lamp", bevel=0.0), RED))
	part(P + "lamps", lamps, far=False)
	glow = []
	for s in (-1, 1):
		glow.append(torus("port_ring", 0.032, 0.005, (s * 0.319, 0.43, -0.3), "glow", axis='X', major=20, minor=4))
		glow.append(box("strip", (0.006, 0.012, 0.5), (s * 0.467, BED_Y - 0.005, BED_Z), "glow", bevel=0.0))
	glow.append(box("strip_b", (0.6, 0.012, 0.006), (0, BED_Y + 0.012, BED_Z + 0.327), "glow", bevel=0.0))
	part(P + "body_glow", glow, far=False)
	part(P + "ring", [under_ring(P + "ring", 0.2, 0.118)], far=False)
	part(P + "status", [box("status", (0.12, 0.016, 0.01), (0, BED_Y + 0.33, HB_Z + 0.03), "glow", bevel=0.003)], far=False)
	# The load meter: one lit bar behind the dividers, scaled along X from its left end.
	METER = V(-0.24, BED_Y + 0.27, HB_Z + 0.03)
	part(P + "meter", [box("meter", (0.48, 0.034, 0.006), (0, METER.y, METER.z), "glow", bevel=0.0)], METER, far=False)
	guts = [box("gut_frame", (0.012, 0.03, 0.26), (-0.314, 0.305, -0.33), "dark", bevel=0.003)]
	for k in range(2):
		guts.append(cyl("cell", 0.028, 0.02, (-0.314, 0.3, -0.4 + k * 0.12), "dark", axis='X', verts=10))
	guts.append(tube("gut_cable", [(-0.318, 0.33, -0.46), (-0.325, 0.29, -0.36), (-0.32, 0.33, -0.26), (-0.316, 0.28, -0.2)], 0.008, "accent", sides=5))
	part(P + "guts", guts, far=False)
	patch = [rbox("patch", (0.2, 0.012, 0.16), (0.14, 0.533, -0.36), 0.004, "accent", segs=1, sub=0)]
	for (x, z) in ((0.06, -0.42), (0.22, -0.42), (0.06, -0.3), (0.22, -0.3)):
		patch.append(bolt((x, 0.54, z), (0, 1, 0), r=0.008, material="accent"))
	part(P + "patch", patch, far=False)
	# Head: low and wide on the nose, two feelers.
	HEAD = V(0, 0.56, -0.4)
	HC = V(0, 0.665, -0.43)
	hp, eyes, ears = visor_head(P, 0.36, 0.17, 0.21, 0.028, 0.085)
	for o in hp + [eyes, ears]:
		o.data.transform(Matrix.Translation(HC))
	hp.append(cyl("neck", 0.034, 0.06, (0, 0.57, -0.4), "dark", axis='Y', verts=10))
	for k in range(2):
		hp.append(torus("neck_rib", 0.038, 0.008, (0, 0.555 + k * 0.022, -0.4), "dark", axis='Y', major=12, minor=4))
	part(P + "head", hp, HEAD)
	part(P + "eyes", [eyes], HC + V(0, 0.004, -0.092), far=False)
	part(P + "head_glow", [ears], HEAD, far=False)
	FEEL = HC + V(0.11, 0.08, 0.03)
	part(P + "feeler", [tube("feeler", [FEEL, FEEL + V(0.02, 0.09, -0.01), FEEL + V(0.05, 0.15, -0.05), FEEL + V(0.07, 0.17, -0.1)], 0.006, "dark", sides=5, r_end=0.004),
		cyl("feel_base", 0.014, 0.02, FEEL + V(0, 0.004, 0), "dark", axis='Y', verts=8)], FEEL, far=False)
	part(P + "beacon", [cyl("beacon", 0.012, 0.02, FEEL + V(0.07, 0.17, -0.105), "glow", axis='Z', verts=8)], FEEL, far=False)
	# Clamp (right; the left is mirrored): hinged on the bed's side edge, an arm up to a pad.
	HINGE = V(0.465, BED_Y + 0.01, BED_Z)
	cl = [rod("clamp_shaft", HINGE + V(0, 0, -0.15), HINGE + V(0, 0, 0.15), 0.016, "dark", 8)]
	for z in (-0.12, 0.12):
		cl.append(rbox("clamp_arm", (0.03, 0.3, 0.04), HINGE + V(0.012, 0.15, z), 0.008, "accent", segs=2, sub=0))
		cl.append(bolt(HINGE + V(0.028, 0.02, z), (1, 0, 0), r=0.008, material="dark"))
	cl.append(rbox("clamp_bar", (0.034, 0.045, 0.3), HINGE + V(0.012, 0.3, 0), 0.008, "accent", segs=2, sub=0))
	cl.append(rbox("clamp_pad", (0.022, 0.2, 0.34), HINGE + V(-0.016, 0.23, 0), 0.006, "dark", segs=1, sub=0))
	for z in (-0.1, 0.1):
		cl.append(bolt(HINGE + V(0.03, 0.3, z), (1, 0, 0), r=0.008, material="dark"))
	clamp_r = part(P + "clamp_r", cl, HINGE)
	clamp_l = mirror_x(clamp_r, P + "clamp_l")
	PARTS[P + "clamp_l"] = V(-HINGE.x, HINGE.y, HINGE.z)
	FAR[P[:2]].append(clamp_l)
	# Fork: two short tines on a carriage that rides the nose rails.
	FORK = V(0, 0.2, -0.6)
	fk = [box("carriage", (0.42, 0.09, 0.03), (0, 0.2, -0.625), "accent", bevel=0.008)]
	for s in (-1, 1):
		fk.append(box("tine_up", (0.06, 0.13, 0.022), (s * 0.13, 0.17, -0.648), "steel", bevel=0.005))
		fk.append(box("tine", (0.06, 0.02, 0.26), (s * 0.13, 0.112, -0.78), "steel", bevel=0.005))
		fk.append(bolt((s * 0.18, 0.2, -0.642), (0, 0, -1), r=0.008))
	part(P + "fork", fk, FORK)
	pod, pod_glow = hover_pod(P + "pod", 0.125)
	part(P + "pod", [pod], far=False)
	part(P + "pod_glow", [pod_glow], far=False)
	JOINTS[P] = [HINGE, V(-HINGE.x, HINGE.y, HINGE.z), HEAD, FORK]
	ANCHORS[P] = {"head": HEAD, "head_c": HC, "feeler": FEEL, "hinge": HINGE, "fork": FORK, "meter": METER,
		"wheels": [V(s * WX, WR, z) for z in WZ for s in (-1, 1)], "wheel_r": WR,
		"pods": [V(s * 0.33, 0.1, z) for z in (-0.3, 0.14, 0.52) for s in (-1, 1)], "bed": V(0, BED_Y, BED_Z), "ring_y": 0.118,
		"fork_point": V(0, 0.125, -0.8), "top": 0.94}


build_scoopie()
build_haulbug()
objs = [o for o in bpy.data.objects if o.type == 'MESH' and o.name in PARTS]
for o in [o for o in bpy.data.objects if o.type == 'MESH' and o.name not in PARTS]:
	print("stray object removed:", o.name)
	bpy.data.objects.remove(o, do_unlink=True)

# ---------------------------------------------------------------- far meshes (one surface, a few hundred triangles)
CLASS = {"paint": 0.0, "accent": 0.33, "bucket": 0.33, "tyre": 1.0}


def far_box(c, s, cls):
	return (Vector(c), Vector(s), cls)


FAR_BOXES = {
	# (centre, size, colour class) in Godot space: the silhouette, nothing else.
	"sc": [far_box((0, 0.215, 0.01), (0.5, 0.17, 0.8), 0.66), far_box((0, 0.475, 0.045), (0.58, 0.39, 0.68), 0.0),
		far_box((0, 0.335, 0.06), (0.6, 0.085, 0.36), 0.33), far_box((0, 0.835, -0.215), (0.31, 0.19, 0.22), 0.0),
		far_box((0, 0.84, -0.33), (0.25, 0.12, 0.01), 1.0), far_box((0, 0.5, 0.415), (0.34, 0.2, 0.09), 0.66),
		far_box((0, 0.13, -0.62), (0.58, 0.2, 0.26), 0.33)] +
		[far_box((s * 0.352, 0.4, -0.25), (0.035, 0.07, 0.62), 0.33) for s in (-1, 1)] +
		[far_box((s * 0.355, 0.15, z), (0.11, 0.3, 0.3), 0.9) for s in (-1, 1) for z in (-0.25, 0.27)],
	"hb": [far_box((0, 0.225, 0.07), (0.56, 0.13, 1.22), 0.66), far_box((0, 0.31, 0.3), (0.9, 0.05, 0.62), 0.33),
		far_box((0, 0.495, -0.035), (0.84, 0.36, 0.05), 0.0), far_box((0, 0.4, -0.33), (0.62, 0.26, 0.5), 0.0),
		far_box((0, 0.665, -0.43), (0.36, 0.17, 0.21), 0.0), far_box((0, 0.67, -0.54), (0.29, 0.1, 0.01), 1.0),
		far_box((0, 0.12, -0.75), (0.34, 0.03, 0.3), 0.66)] +
		[far_box((s * 0.47, 0.5, 0.3), (0.03, 0.32, 0.3), 0.33) for s in (-1, 1)] +
		[far_box((s * 0.4, 0.13, z), (0.1, 0.26, 0.26), 0.9) for s in (-1, 1) for z in (-0.36, 0.08, 0.5)],
}
for pre, boxes in FAR_BOXES.items():
	ps = []
	cls = []
	for (c, s, k) in boxes:
		b = rbox("fb", tuple(s), tuple(c), min(s) * 0.3, "far", segs=1, sub=0)
		cls += [k] * len(b.data.vertices)
		ps.append(b)
	far = join(pre + "_far", ps)
	far["cls"] = cls
	PARTS[far.name] = Vector((0, 0, 0))
	objs.append(far)


# ---------------------------------------------------------------- vertex colours: ray-cast AO, edge, cavity, joint wear
def hemi_dirs(n):
	out = []
	for i in range(n):
		z = (i + 0.5) / n
		r = math.sqrt(1 - z * z)
		a = i * 2.399963
		out.append(Vector((r * math.cos(a), r * math.sin(a), z)))
	return out


DIRS = hemi_dirs(20)


def bvh_of(group):
	bm = bmesh.new()
	for o in group:
		tmp = bmesh.new()
		tmp.from_mesh(o.data)
		me = bpy.data.meshes.new("tmp")
		tmp.to_mesh(me)
		tmp.free()
		bm.from_mesh(me)
		bpy.data.meshes.remove(me)
	# The ground under the robot.
	g = [bm.verts.new(p) for p in ((-3, 0, -3), (3, 0, -3), (3, 0, 3), (-3, 0, 3))]
	bm.faces.new(g)
	t = BVHTree.FromBMesh(bm)
	bm.free()
	return t


def ray_ao(o, tree, reach=0.22):
	out = []
	for v in o.data.vertices:
		n = v.normal
		q = n.to_track_quat('Z', 'Y')
		p = v.co + n * 0.003
		hit = 0.0
		for d in DIRS:
			h = tree.ray_cast(p, q @ d, reach)
			if h[0] is not None:
				hit += (1.0 - h[3] / reach) * d.z
		out.append(max(0.0, 1.0 - 2.2 * hit / len(DIRS)))
	return out


for pre in ("sc", "hb"):
	group = [o for o in objs if o.name.startswith(pre + "_") and not o.name.endswith("_far") and not o.get("lamp")
		and o.name[3:] not in ("pod", "pod_glow", "tyre", "hub_glow", "ram_cyl", "ram_rod", "guts", "patch")]
	tree = bvh_of(group)
	solo = {}
	for o in objs:
		if not o.name.startswith(pre + "_") or o.get("lamp"):
			continue
		if o.name.endswith("_far"):
			a = ray_ao(o, bvh_of([o]), 0.4)
			attr = o.data.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
			for i, d in enumerate(attr.data):
				d.color = (a[i], o["cls"][i], 0.0, 1.0)
			continue
		a = ray_ao(o, tree if o in group else bvh_of([o]))
		cur = curvature(o)
		attr = o.data.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
		for i, d in enumerate(attr.data):
			c = cur[i]
			edge = min(1.0, sstep(22.0, 75.0, c) + 0.4 * sstep(4.0, 14.0, c))
			p = o.data.vertices[i].co
			low = sstep(0.42, 0.1, p.y) if o in group else 0.3   # dirt from the ground up
			cav = min(1.0, sstep(6.0, 30.0, -c) + 0.55 * low)
			j = 0.0
			for J in JOINTS[pre + "_"]:
				j = max(j, sstep(0.13, 0.04, (p - J).length))
			d.color = (a[i], edge, cav, 1.0 - 0.8 * j)
	print(pre, "masks done")

# ---------------------------------------------------------------- pivots, axis conversion, export
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
PREVIEW = os.environ.get("PREVIEW")
for o in objs:
	piv = PARTS[o.name]
	if not o.data.uv_layers:
		o.data.uv_layers.new(name="UVMap")
	o.data.transform(Matrix.Translation(-piv))
	o.data.transform(TO_BLENDER)
	o.location = TO_BLENDER @ piv
	if hasattr(o.data, "use_auto_smooth"):
		o.data.use_auto_smooth = True
		o.data.auto_smooth_angle = math.radians(40)

write_glb(OUT, sorted(objs, key=lambda o: o.name))
print("exported", OUT)
for pre in ("sc_", "hb_"):
	t = {o.name: len(o.data.loop_triangles) for o in objs if o.name.startswith(pre)}
	print(pre, "tris by part:", sorted(t.items(), key=lambda kv: -kv[1]))
	a = ANCHORS[pre]
	print(pre, "anchors:", {k: (tuple(round(c, 4) for c in v) if isinstance(v, Vector) else ([tuple(round(c, 4) for c in w) for w in v] if isinstance(v, list) else v)) for k, v in a.items()})
	print(pre, "pivots:", {n: tuple(round(c, 4) for c in p) for n, p in PARTS.items() if n.startswith(pre)})

if PREVIEW:
	cols = {"paint": (0.86, 0.83, 0.74), "accent": (0.95, 0.62, 0.08), "bucket": (0.95, 0.62, 0.08), "trim": (0.1, 0.105, 0.115), "dark": (0.05, 0.05, 0.055),
		"steel": (0.5, 0.5, 0.5), "tyre": (0.03, 0.03, 0.03), "glass": (0.01, 0.01, 0.012), "glow": (0.3, 0.9, 1.0), "eye": (0.3, 0.9, 1.0), "lamp": (1.0, 0.8, 0.5), "far": (0.7, 0.7, 0.7)}
	for name, m in MATS.items():
		b = m.node_tree.nodes["Principled BSDF"]
		b.inputs["Base Color"].default_value = (*cols.get(name, (0.5, 0.5, 0.5)), 1)
		b.inputs["Roughness"].default_value = 0.1 if name == "glass" else 0.5
		if name in ("glow", "eye", "lamp"):
			b.inputs["Emission Color"].default_value = (*cols[name], 1)
			b.inputs["Emission Strength"].default_value = 4.0
	scene = bpy.context.scene
	scene.render.engine = 'CYCLES'
	scene.cycles.samples = 24
	scene.cycles.use_denoising = False
	scene.render.resolution_x = 720
	scene.render.resolution_y = 560
	scene.world = bpy.data.worlds.new("w")
	scene.world.use_nodes = True
	scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.28, 0.26, 1)
	sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
	link(sun)
	sun.data.energy = 3.0
	sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	link(cam)
	cam.data.lens = 60
	scene.camera = cam
	skip = ("pod", "pod_glow", "guts", "patch", "ram_cyl", "ram_rod", "far")
	for pre in ("sc_", "hb_"):
		a = ANCHORS[pre]
		extra = []
		for o in objs:
			o.hide_render = not o.name.startswith(pre) or o.name[3:] in skip
			if o.name == pre + "tyre" or o.name == pre + "hub_glow":
				o.hide_render = True
				for w in a["wheels"]:
					c = o.copy()
					link(c)
					c.location = TO_BLENDER @ w
					c.hide_render = False
					extra.append(c)
		target = Vector((0, 0, 0.45))
		for i, (az, el) in enumerate(((35, 18), (90, 6), (150, 25), (0, 8))):
			an = math.radians(az)
			pos = target + Vector((math.sin(an) * 3.6, math.cos(an) * 3.6, math.tan(math.radians(el)) * 3.6))
			cam.location = pos
			cam.rotation_euler = (target - pos).to_track_quat('-Z', 'Y').to_euler()
			scene.render.filepath = "%s_%s%d.png" % (PREVIEW, pre, i)
			bpy.ops.render.render(write_still=True)
		for c in extra:
			bpy.data.objects.remove(c, do_unlink=True)
sys.stdout.flush()
