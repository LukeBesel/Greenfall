# Builds the junk kit: recognisable trash for the junk field (CRT monitor, open PC case, keyboard,
# cardboard boxes, a crate of parts, PET bottle, drink can, tarp heap, paper pile, e-waste pile).
#   python3 art/models/junk/build_junk.py            (the Blender 5.3 Python module; it bakes)
#   ONLY=crt_monitor,keyboard python3 ...            (a subset, for a quick look)
#   SIZE=1024 PREVIEW=out.png python3 ...            (atlas size; a Cycles still of the low meshes)
# Method (studio brief, toggle-studio 02/04): every piece is built twice in code. The HIGH version
# is real geometry (bevels, keys, vents, boards, cables) with layered procedural materials (two-tone
# base, speckle, scuffs, varied roughness, edge wear). The LOW version is the game mesh (a hull of
# 30-250 triangles). Colour, roughness, metal, normal and ambient occlusion are baked from high to
# low into ONE shared atlas, so the whole kit is one material and one texture set:
#   junk_kit.glb          <name>_lod0 and <name>_lod1 per piece (Y up, base at y = 0, metres)
#   junk_kit_albedo.png   colour with cavity shading multiplied in
#   junk_kit_orm.png      R ambient occlusion, G roughness, B metal
#   junk_kit_normal.png   tangent-space normal (OpenGL)
# The game reads them in planet/junk_looks.gd; which junk type shows which piece is data/junk_looks.json.
import bpy
import bmesh
import math
import os
import random
import sys
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = int(os.environ.get("SIZE", "2048"))
ONLY = [s for s in os.environ.get("ONLY", "").split(",") if s]
PREVIEW = os.environ.get("PREVIEW", "")
AO_SAMPLES = int(os.environ.get("AO_SAMPLES", "48"))

bpy.ops.wm.read_factory_settings(use_empty=True)
import addon_utils
addon_utils.enable("cycles")
addon_utils.enable("io_scene_gltf2")
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 4
random.seed(7)

# ----------------------------------------------------------------------------------------------
# Small helpers

def link(obj):
	scene.collection.objects.link(obj)
	return obj


def new_obj(name, bm, mat=None, smooth_angle=None):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	o = link(bpy.data.objects.new(name, me))
	if mat is not None:
		me.materials.append(mat)
	if smooth_angle is not None:
		for p in me.polygons:
			p.use_smooth = True
		select_only(o)
		bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth_angle))
	return o


def select_only(*objs):
	for o in bpy.context.view_layer.objects:
		o.select_set(False)
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]


def apply_mods(o):
	select_only(o)
	for md in list(o.modifiers):
		bpy.ops.object.modifier_apply(modifier=md.name)
	return o


def box(name, size, loc=(0, 0, 0), mat=None, bevel=0.0, segs=2, rot=(0, 0, 0), taper=None):
	"""A box centred on loc. taper = (sx, sy) scales the +Y end (a frustum along Y)."""
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
		if taper and v.co.y > 0:
			v.co.x *= taper[0]
			v.co.z *= taper[1]
	o = new_obj(name, bm, mat)
	o.location = loc
	o.rotation_euler = [math.radians(a) for a in rot]
	if bevel > 0:
		md = o.modifiers.new("bevel", 'BEVEL')
		md.width = bevel
		md.segments = segs
		md.limit_method = 'ANGLE'
		apply_mods(o)
		for p in o.data.polygons:
			p.use_smooth = True
		select_only(o)
		bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
	return o


def cyl(name, r, h, loc=(0, 0, 0), mat=None, n=16, rot=(0, 0, 0), bevel=0.0, r2=None):
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=n, radius1=r, radius2=r if r2 is None else r2, depth=h)
	o = new_obj(name, bm, mat)
	o.location = loc
	o.rotation_euler = [math.radians(a) for a in rot]
	if bevel > 0:
		md = o.modifiers.new("bevel", 'BEVEL')
		md.width = bevel
		md.segments = 2
		md.limit_method = 'ANGLE'
		apply_mods(o)
	for p in o.data.polygons:
		p.use_smooth = True
	select_only(o)
	bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
	return o


def tube(name, pts, r, mat=None, n=6, cyclic=False):
	"""A tube along a polyline, smoothed as a curve (cables)."""
	cu = bpy.data.curves.new(name, 'CURVE')
	cu.dimensions = '3D'
	sp = cu.splines.new('NURBS')
	sp.points.add(len(pts) - 1)
	for i, p in enumerate(pts):
		sp.points[i].co = (p[0], p[1], p[2], 1.0)
	sp.use_endpoint_u = True
	sp.use_cyclic_u = cyclic
	sp.order_u = 3
	cu.bevel_depth = r
	cu.bevel_resolution = max(0, n // 4)
	cu.resolution_u = 6
	o = link(bpy.data.objects.new(name, cu))
	select_only(o)
	bpy.ops.object.convert(target='MESH')
	o = bpy.context.view_layer.objects.active
	if mat is not None:
		o.data.materials.append(mat)
	for p in o.data.polygons:
		p.use_smooth = True
	return o


def lathe(name, profile, n=16, mat=None, loc=(0, 0, 0)):
	"""Revolve (r, z) points round Z."""
	bm = bmesh.new()
	rings = []
	for (r, z) in profile:
		ring = [bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)) for a in [i * math.tau / n for i in range(n)]]
		rings.append(ring)
	for k in range(len(rings) - 1):
		for i in range(n):
			a, b = rings[k][i], rings[k][(i + 1) % n]
			c, d = rings[k + 1][(i + 1) % n], rings[k + 1][i]
			bm.faces.new((a, b, c, d))
	bm.faces.new(list(reversed(rings[0])))
	bm.faces.new(rings[-1])
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	o = new_obj(name, bm, mat, smooth_angle=50)
	o.location = loc
	return o


def displace(o, strength, scale, seed=0, kind='CLOUDS', mid=0.5, direction='NORMAL'):
	tex = bpy.data.textures.new("d%d" % seed, kind)
	tex.noise_scale = scale
	md = o.modifiers.new("disp", 'DISPLACE')
	md.texture = tex
	md.strength = strength
	md.mid_level = mid
	md.texture_coords = 'GLOBAL'
	md.direction = direction  # 'Z' for thin sheets: along the normal their two faces would cross
	return o


def subdivide(o, cuts):
	bm = bmesh.new()
	bm.from_mesh(o.data)
	bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=cuts, use_grid_fill=True)
	bm.to_mesh(o.data)
	bm.free()
	return o


def bake_xf(o):
	select_only(o)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	return o


def join(name, objs):
	objs = [o for o in objs if o is not None]
	for o in objs:
		bake_xf(o)
	select_only(*objs)
	bpy.ops.object.join()
	o = bpy.context.view_layer.objects.active
	o.name = name
	return o


def tri_count(o):
	return sum(len(p.vertices) - 2 for p in o.data.polygons)


# ----------------------------------------------------------------------------------------------
# Materials: layered and procedural (04 materials/light). Each returns a material whose
# Principled inputs carry colour variation, speckle, scuffs, varied roughness and bump.

MATS = {}


def _nodes(name):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
	nt.links.new(bsdf.outputs[0], out.inputs[0])
	return m, nt, bsdf


def _noise(nt, scale, detail=3.0, rough=0.55, coord=None, stretch=None):
	n = nt.nodes.new("ShaderNodeTexNoise")
	n.inputs["Scale"].default_value = scale
	n.inputs["Detail"].default_value = detail
	n.inputs["Roughness"].default_value = rough
	tc = nt.nodes.new("ShaderNodeTexCoord")
	if stretch:
		mp = nt.nodes.new("ShaderNodeMapping")
		mp.inputs["Scale"].default_value = stretch
		nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
		nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
	else:
		nt.links.new(tc.outputs["Object"], n.inputs["Vector"])
	return n.outputs["Fac"]


def _ramp(nt, fac, lo, hi):
	r = nt.nodes.new("ShaderNodeMapRange")
	r.inputs["From Min"].default_value = lo
	r.inputs["From Max"].default_value = hi
	r.clamp = True
	nt.links.new(fac, r.inputs["Value"])
	return r.outputs["Result"]


def _mix(nt, fac, a, b, mode='MIX'):
	n = nt.nodes.new("ShaderNodeMix")
	n.data_type = 'RGBA'
	n.blend_type = mode
	if isinstance(fac, float):
		n.inputs[0].default_value = fac
	else:
		nt.links.new(fac, n.inputs[0])
	for sock, v in ((n.inputs[6], a), (n.inputs[7], b)):
		if isinstance(v, tuple):
			sock.default_value = (v[0], v[1], v[2], 1.0)
		else:
			nt.links.new(v, sock)
	return n.outputs[2]


def _math(nt, op, a, b=None):
	n = nt.nodes.new("ShaderNodeMath")
	n.operation = op
	n.use_clamp = True
	for i, v in enumerate((a, b)):
		if v is None:
			continue
		if isinstance(v, float):
			n.inputs[i].default_value = v
		else:
			nt.links.new(v, n.inputs[i])
	return n.outputs[0]


def _edge(nt, lo=0.5, hi=0.62):
	"""Convex-edge mask from Cycles' pointiness (works in bakes), broken up by noise."""
	g = nt.nodes.new("ShaderNodeNewGeometry")
	e = _ramp(nt, g.outputs["Pointiness"], lo, hi)
	return _math(nt, 'MULTIPLY', e, _ramp(nt, _noise(nt, 60.0, 4.0), 0.3, 0.7))


def _bump(nt, bsdf, layers):
	"""layers = [(height socket, strength, distance)] chained large to fine."""
	prev = None
	for (h, strength, dist) in layers:
		b = nt.nodes.new("ShaderNodeBump")
		b.inputs["Strength"].default_value = strength
		b.inputs["Distance"].default_value = dist
		nt.links.new(h, b.inputs["Height"])
		if prev is not None:
			nt.links.new(prev, b.inputs["Normal"])
		prev = b.outputs["Normal"]
	if prev is not None:
		nt.links.new(prev, bsdf.inputs["Normal"])


def _finish(m, nt, bsdf, col, rough, metal=0.0):
	for name, v in (("Base Color", col), ("Roughness", rough), ("Metallic", metal)):
		s = bsdf.inputs[name]
		if isinstance(v, float):
			s.default_value = v
		elif isinstance(v, tuple):
			s.default_value = (v[0], v[1], v[2], 1.0)
		else:
			nt.links.new(v, s)
	m["_metal"] = metal if isinstance(metal, float) else -1.0
	return m


def aged_plastic(name, base=(0.62, 0.58, 0.46), yellow=(0.60, 0.47, 0.24), dirt=(0.16, 0.13, 0.10), rough=0.5, age=1.0):
	"""Old ABS: sun-yellowed in patches, speckled, scuffed lighter and rougher, dirt in noise."""
	if name in MATS:
		return MATS[name]
	m, nt, bsdf = _nodes(name)
	big = _ramp(nt, _noise(nt, 4.0, 2.0), 0.35 - 0.1 * age, 0.75)
	col = _mix(nt, big, base, yellow)
	speck = _ramp(nt, _noise(nt, 90.0, 2.0), 0.0, 1.0)
	col = _mix(nt, _math(nt, 'MULTIPLY', speck, 0.25), col, (0.0, 0.0, 0.0), 'MULTIPLY')
	grime = _ramp(nt, _noise(nt, 9.0, 5.0, 0.7), 0.52, 0.78)
	col = _mix(nt, _math(nt, 'MULTIPLY', grime, 0.7), col, dirt)
	scuff = _ramp(nt, _noise(nt, 30.0, 3.0, 0.6, stretch=(1.0, 14.0, 1.0)), 0.66, 0.74)
	col = _mix(nt, _math(nt, 'MULTIPLY', scuff, 0.35), col, (0.8, 0.78, 0.7))
	edge = _edge(nt)
	col = _mix(nt, _math(nt, 'MULTIPLY', edge, 0.3), col, (0.85, 0.82, 0.74))
	r = _math(nt, 'ADD', _math(nt, 'MULTIPLY', grime, 0.3), _math(nt, 'ADD', _math(nt, 'MULTIPLY', scuff, 0.25), rough - 0.1))
	r = _math(nt, 'ADD', r, _math(nt, 'MULTIPLY', speck, 0.12))
	_bump(nt, bsdf, [(_noise(nt, 14.0, 2.0), 0.15, 0.004), (_noise(nt, 220.0, 2.0), 0.25, 0.0006)])
	MATS[name] = _finish(m, nt, bsdf, col, r)
	return MATS[name]


def crt_glass(name="crt_glass"):
	"""Dark tube glass: nearly black-green, glossy, a dust film in patches (rougher and greyer)."""
	if name in MATS:
		return MATS[name]
	m, nt, bsdf = _nodes(name)
	dust = _ramp(nt, _noise(nt, 6.0, 5.0, 0.7), 0.42, 0.8)
	streak = _ramp(nt, _noise(nt, 12.0, 3.0, 0.6, stretch=(6.0, 1.0, 0.6)), 0.55, 0.8)
	film = _math(nt, 'MAXIMUM', dust, _math(nt, 'MULTIPLY', streak, 0.6))
	col = _mix(nt, _math(nt, 'MULTIPLY', film, 0.55), (0.012, 0.022, 0.02), (0.30, 0.29, 0.25))
	r = _math(nt, 'ADD', _math(nt, 'MULTIPLY', film, 0.5), 0.07)
	MATS[name] = _finish(m, nt, bsdf, col, r)
	return MATS[name]


def painted_metal(name, paint=(0.50, 0.50, 0.46), rough=0.45, chips=1.0, rust=(0.22, 0.10, 0.045)):
	"""Painted sheet steel: paint with tone drift, chips to dark steel on edges and in noise patches,
	rust blooming round the chips (rough, not metal)."""
	if name in MATS:
		return MATS[name]
	m, nt, bsdf = _nodes(name)
	drift = _ramp(nt, _noise(nt, 3.0, 2.0), 0.3, 0.7)
	col = _mix(nt, drift, paint, tuple(c * 0.78 for c in paint))
	speck = _noise(nt, 120.0, 2.0)
	col = _mix(nt, _math(nt, 'MULTIPLY', speck, 0.2), col, (0.0, 0.0, 0.0), 'MULTIPLY')
	patch = _ramp(nt, _noise(nt, 16.0, 6.0, 0.72), 0.62 - 0.03 * chips, 0.66 - 0.03 * chips)
	chip = _math(nt, 'MAXIMUM', _edge(nt, 0.52, 0.6), patch)
	bloom = _ramp(nt, _noise(nt, 16.0, 6.0, 0.72), 0.52 - 0.03 * chips, 0.64)
	col = _mix(nt, _math(nt, 'MULTIPLY', bloom, 0.75), col, rust)
	col = _mix(nt, chip, col, (0.19, 0.17, 0.15))
	r = _math(nt, 'ADD', _math(nt, 'MULTIPLY', bloom, 0.35), _math(nt, 'ADD', _math(nt, 'MULTIPLY', drift, 0.12), rough - 0.05))
	metal = _math(nt, 'MULTIPLY', chip, 0.8)
	_bump(nt, bsdf, [(_math(nt, 'SUBTRACT', 1.0, chip), 0.3, 0.0008), (_noise(nt, 200.0, 2.0), 0.2, 0.0005)])
	MATS[name] = _finish(m, nt, bsdf, col, r, metal)
	return MATS[name]


def bare_metal(name, col=(0.56, 0.57, 0.58), rough=0.38, dull=(0.30, 0.29, 0.27)):
	"""Galvanised / aluminium: metal with dull oxide patches and fine scratches."""
	if name in MATS:
		return MATS[name]
	m, nt, bsdf = _nodes(name)
	patch = _ramp(nt, _noise(nt, 7.0, 5.0, 0.7), 0.4, 0.75)
	c = _mix(nt, patch, col, dull)
	scratch = _ramp(nt, _noise(nt, 40.0, 2.0, 0.5, stretch=(1.0, 20.0, 1.0)), 0.6, 0.72)
	r = _math(nt, 'ADD', _math(nt, 'MULTIPLY', patch, 0.3), _math(nt, 'ADD', _math(nt, 'MULTIPLY', scratch, 0.15), rough - 0.08))
	metal = _math(nt, 'SUBTRACT', 1.0, _math(nt, 'MULTIPLY', patch, 0.35))
	_bump(nt, bsdf, [(scratch, 0.2, 0.0004)])
	MATS[name] = _finish(m, nt, bsdf, c, r, metal)
	return MATS[name]


def pcb(name="pcb", base=(0.035, 0.16, 0.085)):
	"""Circuit board: solder-mask green, lighter trace lines (bricks), dust."""
	if name in MATS:
		return MATS[name]
	m, nt, bsdf = _nodes(name)
	br = nt.nodes.new("ShaderNodeTexBrick")
	br.inputs["Scale"].default_value = 26.0
	br.inputs["Mortar Size"].default_value = 0.035
	br.inputs["Color1"].default_value = (0, 0, 0, 1)
	br.inputs["Color2"].default_value = (0, 0, 0, 1)
	br.inputs["Mortar"].default_value = (1, 1, 1, 1)
	tc = nt.nodes.new("ShaderNodeTexCoord")
	nt.links.new(tc.outputs["Object"], br.inputs["Vector"])
	trace = _math(nt, 'MULTIPLY', br.outputs["Color"], _ramp(nt, _noise(nt, 5.0, 1.0), 0.45, 0.55))
	col = _mix(nt, _math(nt, 'MULTIPLY', trace, 0.6), base, (0.12, 0.34, 0.16))
	dust = _ramp(nt, _noise(nt, 8.0, 5.0, 0.7), 0.45, 0.85)
	col = _mix(nt, _math(nt, 'MULTIPLY', dust, 0.6), col, (0.26, 0.23, 0.18))
	r = _math(nt, 'ADD', _math(nt, 'MULTIPLY', dust, 0.4), 0.32)
	_bump(nt, bsdf, [(trace, 0.3, 0.0005)])
	MATS[name] = _finish(m, nt, bsdf, col, r)
	return MATS[name]


def cardboard(name="cardboard", base=(0.42, 0.30, 0.17), wet=0.5):
	"""Corrugated board: fibre tone drift, a faint flute pattern, damp stains (darker, with a tide
	line), dirt speckle; pale torn core on the edges."""
	if name in MATS:
		return MATS[name]
	m, nt, bsdf = _nodes(name)
	drift = _ramp(nt, _noise(nt, 5.0, 3.0), 0.3, 0.7)
	col = _mix(nt, drift, base, tuple(c * 1.22 for c in base))
	fibre = _noise(nt, 60.0, 3.0, 0.6, stretch=(1.0, 1.0, 12.0))
	col = _mix(nt, _math(nt, 'MULTIPLY', fibre, 0.22), col, (0.0, 0.0, 0.0), 'MULTIPLY')
	stain_n = _noise(nt, 3.2, 5.0, 0.62)
	stain = _ramp(nt, stain_n, 0.62 - 0.22 * wet, 0.66 - 0.22 * wet)
	tide = _math(nt, 'MULTIPLY', _ramp(nt, stain_n, 0.585 - 0.22 * wet, 0.62 - 0.22 * wet), _math(nt, 'SUBTRACT', 1.0, stain))
	col = _mix(nt, _math(nt, 'MULTIPLY', stain, 0.62), col, (0.10, 0.068, 0.04))
	col = _mix(nt, _math(nt, 'MULTIPLY', tide, 0.5), col, (0.07, 0.05, 0.03))
	edge = _edge(nt, 0.52, 0.6)
	col = _mix(nt, _math(nt, 'MULTIPLY', edge, 0.55), col, (0.62, 0.52, 0.36))
	wv = nt.nodes.new("ShaderNodeTexWave")
	wv.inputs["Scale"].default_value = 55.0
	tc = nt.nodes.new("ShaderNodeTexCoord")
	nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
	r = _math(nt, 'SUBTRACT', 0.86, _math(nt, 'MULTIPLY', stain, 0.3))
	_bump(nt, bsdf, [(_noise(nt, 9.0, 3.0), 0.5, 0.004), (wv.outputs["Fac"], 0.12, 0.0008), (fibre, 0.2, 0.0004)])
	MATS[name] = _finish(m, nt, bsdf, col, r)
	return MATS[name]


def flat(name, col, rough=0.6, metal=0.0, var=0.12, bump=0.0):
	"""A plain surface that still varies: tone drift, speckle, dust; optional grain."""
	if name in MATS:
		return MATS[name]
	m, nt, bsdf = _nodes(name)
	drift = _ramp(nt, _noise(nt, 7.0, 3.0), 0.3, 0.7)
	c = _mix(nt, drift, col, tuple(min(1.0, x * (1.0 - var * 2.0)) for x in col))
	dust = _ramp(nt, _noise(nt, 11.0, 5.0, 0.7), 0.5, 0.85)
	c = _mix(nt, _math(nt, 'MULTIPLY', dust, 0.45), c, (0.27, 0.24, 0.19))
	r = _math(nt, 'ADD', _math(nt, 'MULTIPLY', dust, 0.3), _math(nt, 'ADD', _math(nt, 'MULTIPLY', drift, 0.1), rough - 0.05))
	if bump > 0:
		_bump(nt, bsdf, [(_noise(nt, 150.0, 2.0), bump, 0.0006)])
	MATS[name] = _finish(m, nt, bsdf, c, r, metal)
	return MATS[name]


def striped(name, a, b, scale, rough=0.7, axis=2, duty=0.5, dirt=0.4):
	"""Stripes along an object axis (printed text lines on paper, label bands)."""
	if name in MATS:
		return MATS[name]
	m, nt, bsdf = _nodes(name)
	tc = nt.nodes.new("ShaderNodeTexCoord")
	sep = nt.nodes.new("ShaderNodeSeparateXYZ")
	nt.links.new(tc.outputs["Object"], sep.inputs[0])
	s = _math(nt, 'MULTIPLY', sep.outputs[axis], scale)
	fr = nt.nodes.new("ShaderNodeMath")
	fr.operation = 'FRACT'
	nt.links.new(s, fr.inputs[0])
	band = _ramp(nt, fr.outputs[0], duty - 0.04, duty + 0.04)
	broken = _math(nt, 'MULTIPLY', band, _ramp(nt, _noise(nt, 40.0, 1.0, 0.5, stretch=(1.0, 1.0, 0.05) if axis != 2 else (1.0, 0.05, 1.0)), 0.35, 0.5))
	c = _mix(nt, broken, a, b)
	dust = _ramp(nt, _noise(nt, 7.0, 5.0, 0.7), 0.45, 0.85)
	c = _mix(nt, _math(nt, 'MULTIPLY', dust, dirt), c, (0.24, 0.2, 0.15))
	MATS[name] = _finish(m, nt, bsdf, c, _math(nt, 'ADD', _math(nt, 'MULTIPLY', dust, 0.2), rough - 0.1))
	return MATS[name]


def tarp(name="tarp", col=(0.085, 0.14, 0.21)):
	"""Woven poly tarp: sun-faded in patches, dirt in the folds, a fine weave, glossy where clean."""
	if name in MATS:
		return MATS[name]
	m, nt, bsdf = _nodes(name)
	fade = _ramp(nt, _noise(nt, 4.0, 3.0), 0.3, 0.75)
	c = _mix(nt, fade, col, (0.20, 0.24, 0.27))
	g = nt.nodes.new("ShaderNodeNewGeometry")
	fold = _ramp(nt, g.outputs["Pointiness"], 0.5, 0.42)
	dirt = _math(nt, 'MAXIMUM', _math(nt, 'MULTIPLY', fold, 0.8), _ramp(nt, _noise(nt, 9.0, 5.0, 0.7), 0.5, 0.8))
	c = _mix(nt, _math(nt, 'MULTIPLY', dirt, 0.7), c, (0.15, 0.125, 0.09))
	ridge = _ramp(nt, g.outputs["Pointiness"], 0.52, 0.6)
	c = _mix(nt, _math(nt, 'MULTIPLY', ridge, 0.25), c, (0.30, 0.34, 0.37))
	chk = nt.nodes.new("ShaderNodeTexChecker")
	chk.inputs["Scale"].default_value = 260.0
	tc = nt.nodes.new("ShaderNodeTexCoord")
	nt.links.new(tc.outputs["Object"], chk.inputs["Vector"])
	r = _math(nt, 'ADD', _math(nt, 'MULTIPLY', dirt, 0.4), 0.36)
	_bump(nt, bsdf, [(chk.outputs["Fac"], 0.12, 0.0004)])
	MATS[name] = _finish(m, nt, bsdf, c, r)
	return MATS[name]


# Shared, named once
def M_BEIGE():
	return aged_plastic("plastic_beige")
def M_BEIGE_DARK():
	return aged_plastic("plastic_beige_dark", base=(0.50, 0.47, 0.38), yellow=(0.48, 0.38, 0.20))
def M_KEY():
	return aged_plastic("plastic_key", base=(0.68, 0.65, 0.55), yellow=(0.62, 0.52, 0.30), rough=0.55)
def M_KEY_GREY():
	return aged_plastic("plastic_key_grey", base=(0.36, 0.36, 0.34), yellow=(0.36, 0.33, 0.25), rough=0.55)
def M_BLACK():
	return flat("plastic_black", (0.03, 0.03, 0.032), rough=0.5, var=0.1, bump=0.2)
def M_RUBBER():
	return flat("rubber", (0.025, 0.025, 0.027), rough=0.72, var=0.1)
def M_STEEL():
	return bare_metal("steel")
def M_ALU():
	return bare_metal("alu", col=(0.74, 0.75, 0.76), rough=0.3, dull=(0.45, 0.45, 0.44))
def M_CASE():
	return painted_metal("case_paint", paint=(0.50, 0.48, 0.41), rough=0.5, chips=-1.2)


# ----------------------------------------------------------------------------------------------
# Low meshes from the high ones

def heightcap(name, hi_objs, nx, ny, pad=0.004, floor=0.004, skirt=True):
	"""A low mesh for a heap: a grid of the highs' top heights (rays from above); cells over bare
	ground are dropped, so the outline follows the heap; the rim is skirted down to the ground."""
	dg = bpy.context.evaluated_depsgraph_get()
	trees = []
	lo = Vector((1e9, 1e9, 1e9))
	hi = Vector((-1e9, -1e9, -1e9))
	for o in hi_objs:
		bm = bmesh.new()
		bm.from_object(o, dg)
		bm.transform(o.matrix_world)
		for v in bm.verts:
			for k in range(3):
				lo[k] = min(lo[k], v.co[k])
				hi[k] = max(hi[k], v.co[k])
		trees.append(BVHTree.FromBMesh(bm))
		bm.free()
	lo -= Vector((pad, pad, 0))
	hi += Vector((pad, pad, 0))
	hs = np.zeros((ny + 1, nx + 1))
	for j in range(ny + 1):
		for i in range(nx + 1):
			x = lo.x + (hi.x - lo.x) * i / nx
			y = lo.y + (hi.y - lo.y) * j / ny
			best = 0.0
			# the highest hit in a small neighbourhood, so thin things (cables) are not missed
			for (ox, oy) in ((0, 0), (0.3, 0), (-0.3, 0), (0, 0.3), (0, -0.3)):
				px = x + ox * (hi.x - lo.x) / nx
				py = y + oy * (hi.y - lo.y) / ny
				for t in trees:
					hit = t.ray_cast(Vector((px, py, hi.z + 1.0)), Vector((0, 0, -1)))
					if hit[0] is not None:
						best = max(best, hit[0].z)
			hs[j, i] = best
	bm = bmesh.new()
	vs = {}
	def v(i, j):
		if (i, j) not in vs:
			vs[(i, j)] = bm.verts.new((lo.x + (hi.x - lo.x) * i / nx, lo.y + (hi.y - lo.y) * j / ny, max(hs[j, i], floor)))
		return vs[(i, j)]
	for j in range(ny):
		for i in range(nx):
			if sum(1 for h in (hs[j, i], hs[j, i + 1], hs[j + 1, i], hs[j + 1, i + 1]) if h > floor * 1.5) < 3:
				continue
			bm.faces.new((v(i, j), v(i + 1, j), v(i + 1, j + 1), v(i, j + 1)))
	if skirt:
		edges = [e for e in bm.edges if len(e.link_faces) == 1 and max(e.verts[0].co.z, e.verts[1].co.z) > floor * 2.0]
		ret = bmesh.ops.extrude_edge_only(bm, edges=edges)
		for g in ret["geom"]:
			if isinstance(g, bmesh.types.BMVert):
				g.co.z = 0.0
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return new_obj(name, bm, None, smooth_angle=55)


def decimated(name, src, ratio):
	o = src.copy()
	o.data = src.data.copy()
	o.name = name
	link(o)
	md = o.modifiers.new("dec", 'DECIMATE')
	md.ratio = ratio
	md.use_collapse_triangulate = True
	apply_mods(o)
	return o


# ----------------------------------------------------------------------------------------------
# The pieces. Each returns (high objects, low object). Blender axes: X width, Y depth (front is
# -Y), Z up; the base sits on z = 0.

def crt_monitor():
	W, H, D = 0.40, 0.33, 0.40
	z0 = 0.05  # the body sits on its swivel foot
	hi = []
	beige = M_BEIGE()
	# bezel frame round the tube
	fy = -D * 0.5 + 0.03
	sw, sh = 0.30, 0.225
	hi.append(box("bz_top", (W, 0.06, (H - sh) * 0.5 - 0.012), (0, fy, z0 + H - ((H - sh) * 0.5 - 0.012) * 0.5), beige, 0.008))
	hi.append(box("bz_bot", (W, 0.06, (H - sh) * 0.5 + 0.012), (0, fy, z0 + ((H - sh) * 0.5 + 0.012) * 0.5), beige, 0.008))
	hi.append(box("bz_l", ((W - sw) * 0.5, 0.06, H), (-(W + sw) * 0.25, fy, z0 + H * 0.5), beige, 0.008))
	hi.append(box("bz_r", ((W - sw) * 0.5, 0.06, H), ((W + sw) * 0.25, fy, z0 + H * 0.5), beige, 0.008))
	# the tube face: a slightly bulged dark glass
	bm = bmesh.new()
	n = 10
	grid = [[bm.verts.new(((i / n - 0.5) * (sw + 0.01), -D * 0.5 + 0.012 - 0.012 * (1 - (2 * i / n - 1) ** 2) * (1 - (2 * j / n - 1) ** 2),
		z0 + H * 0.5 + 0.012 + (j / n - 0.5) * (sh + 0.01))) for i in range(n + 1)] for j in range(n + 1)]
	for j in range(n):
		for i in range(n):
			bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
	hi.append(new_obj("glass", bm, crt_glass(), 60))
	# buttons, a dead lamp, a badge
	for k in range(4):
		hi.append(cyl("btn%d" % k, 0.007, 0.008, (0.06 + k * 0.026, -D * 0.5 - 0.001, z0 + 0.03), M_BEIGE_DARK(), 10, (90, 0, 0)))
	hi.append(cyl("lamp", 0.004, 0.006, (0.165, -D * 0.5 - 0.001, z0 + 0.03), flat("lamp_dead", (0.10, 0.16, 0.08), 0.3), 8, (90, 0, 0)))
	hi.append(box("badge", (0.05, 0.004, 0.012), (-0.13, -D * 0.5 - 0.001, z0 + 0.03), bare_metal("badge", (0.5, 0.5, 0.52), 0.3), 0.001))
	# back shell: a frustum with vent ribs on top and the sides
	by = (-D * 0.5 + 0.06 + D * 0.5) * 0.5
	bl = D - 0.06
	hi.append(box("shell", (W - 0.02, bl, H - 0.02), (0, -D * 0.5 + 0.06 + bl * 0.5, z0 + H * 0.5), M_BEIGE_DARK(), 0.012, 2, taper=(0.62, 0.66)))
	for k in range(9):
		t = 0.12 + k * 0.085
		hw = (W - 0.02) * 0.5 * (1.0 - 0.38 * t) - 0.03
		zz = z0 + H * 0.5 + (H - 0.02) * 0.5 * (1.0 - 0.34 * t) + 0.001
		hi.append(box("rib%d" % k, (hw * 2.0, 0.012, 0.006), (0, -D * 0.5 + 0.06 + bl * t, zz), M_BEIGE_DARK(), 0.002, rot=(-12, 0, 0)))
	hi.append(box("port", (0.10, 0.006, 0.05), (0, D * 0.5 + 0.001, z0 + H * 0.42), M_BLACK(), 0.002))
	# swivel foot
	hi.append(cyl("neck", 0.055, 0.03, (0, 0.02, 0.04), M_BEIGE_DARK(), 16))
	foot = cyl("foot", 0.13, 0.022, (0, 0.02, 0.011), beige, 20, bevel=0.006)
	foot.scale = (1.0, 0.85, 1.0)
	hi.append(foot)
	# low: bezel box with an inset screen, frustum shell, foot
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		v.co = Vector((v.co.x * W, v.co.y * 0.06 + fy, v.co.z * H + z0 + H * 0.5))
	front = [f for f in bm.faces if f.normal.y < -0.9][0]
	r = bmesh.ops.inset_region(bm, faces=[front], thickness=0.045, depth=0.0)
	for v in front.verts:
		v.co.y += 0.014
		v.co.z += 0.012 if v.co.z < z0 + H * 0.5 else 0.0
	lo_a = new_obj("lo_a", bm)
	lo_b = box("lo_b", (W - 0.02, bl, H - 0.02), (0, -D * 0.5 + 0.06 + bl * 0.5, z0 + H * 0.5 + 0.003), taper=(0.62, 0.66))
	lo_c = cyl("lo_c", 0.13, 0.05, (0, 0.02, 0.025), None, 8, r2=0.07)
	lo_c.scale = (1.0, 0.85, 1.0)
	lo = join("crt_monitor", [lo_a, lo_b, lo_c])
	return hi, lo, 0.012


def pc_case():
	W, H, D = 0.19, 0.42, 0.43
	t = 0.006
	hi = []
	steel = M_STEEL()
	case = M_CASE()
	# chassis: floor, roof, back, the closed (-X) side; the +X side panel is gone
	hi.append(box("floor", (W, D, t), (0, 0, t * 0.5), case, 0.002))
	hi.append(box("roof", (W, D, t), (0, 0, H - t * 0.5), case, 0.002))
	hi.append(box("back", (W, t, H), (0, D * 0.5 - t * 0.5, H * 0.5), steel, 0.002))
	hi.append(box("side", (t, D, H), (-W * 0.5 + t * 0.5, 0, H * 0.5), case, 0.002))
	hi.append(box("lip_t", (0.012, D, 0.012), (W * 0.5 - 0.006, 0, H - 0.012), steel, 0.001))
	hi.append(box("lip_b", (0.012, D, 0.012), (W * 0.5 - 0.006, 0, 0.012), steel, 0.001))
	# plastic front with drive bays
	fy = -D * 0.5 - 0.012
	hi.append(box("front", (W + 0.004, 0.03, H + 0.004), (0, fy, H * 0.5), M_BEIGE(), 0.008))
	for k in range(2):
		hi.append(box("bay%d" % k, (0.15, 0.006, 0.04), (0, fy - 0.014, H - 0.05 - k * 0.048), M_KEY(), 0.002))
	hi.append(box("floppy", (0.105, 0.006, 0.026), (-0.015, fy - 0.014, H - 0.155), M_BEIGE_DARK(), 0.002))
	hi.append(box("slot", (0.085, 0.008, 0.004), (-0.015, fy - 0.015, H - 0.152), M_BLACK()))
	hi.append(cyl("power", 0.012, 0.008, (0.05, fy - 0.014, H - 0.215), M_KEY_GREY(), 12, (90, 0, 0)))
	hi.append(cyl("reset", 0.005, 0.006, (0.05, fy - 0.014, H - 0.245), M_KEY_GREY(), 8, (90, 0, 0)))
	for k in range(7):
		hi.append(box("grille%d" % k, (0.13, 0.008, 0.005), (0, fy - 0.013, 0.03 + k * 0.012), M_BEIGE_DARK(), 0.001))
	# motherboard on the closed side
	bx = -W * 0.5 + t + 0.006
	hi.append(box("mobo", (0.003, 0.245, 0.30), (bx, 0.07, 0.17), pcb()))
	chip = flat("chip", (0.03, 0.03, 0.035), 0.4, var=0.05)
	for (cy, cz, sy, sz) in ((0.02, 0.10, 0.035, 0.035), (0.13, 0.08, 0.025, 0.04), (0.0, 0.20, 0.02, 0.03), (0.15, 0.22, 0.03, 0.02), (0.10, 0.28, 0.045, 0.016)):
		hi.append(box("chip", (0.004, sy, sz), (bx + 0.003, cy, cz), chip, 0.0008))
	# heatsink with fins, memory, cards
	for k in range(9):
		hi.append(box("fin%d" % k, (0.045, 0.0025, 0.07), (bx + 0.026, 0.045 + k * 0.0075, 0.235), M_ALU()))
	hi.append(box("sink", (0.012, 0.07, 0.07), (bx + 0.008, 0.075, 0.235), M_ALU(), 0.001))
	for k in range(3):
		hi.append(box("ram%d" % k, (0.028, 0.003, 0.125), (bx + 0.016, -0.03 - k * 0.011, 0.225), pcb("pcb_ram", (0.03, 0.10, 0.16) if k == 1 else (0.035, 0.16, 0.085))))
		hi.append(box("ramslot%d" % k, (0.008, 0.007, 0.132), (bx + 0.005, -0.03 - k * 0.011, 0.225), flat("slot_white", (0.62, 0.6, 0.52), 0.5)))
	for k in range(2):
		hi.append(box("card%d" % k, (0.095, 0.003, 0.085), (bx + 0.05, 0.10, 0.06 + k * 0.045), pcb("pcb_card", (0.045, 0.14, 0.07)), rot=(90, 0, 0)))
		hi.append(box("bracket%d" % k, (0.11, 0.003, 0.016), (bx + 0.055, D * 0.5 - t - 0.002, 0.06 + k * 0.045), steel))
		hi.append(box("cchip%d" % k, (0.03, 0.03, 0.005), (bx + 0.05, 0.10, 0.063 + k * 0.045), chip, 0.0008))
	# power supply top-back, drive cage at the front
	hi.append(box("psu", (0.15, 0.14, 0.086), (0.005, D * 0.5 - t - 0.071, H - t - 0.045), bare_metal("psu", (0.50, 0.51, 0.50), 0.42), 0.003))
	hi.append(cyl("psu_fan", 0.036, 0.004, (0.081, D * 0.5 - t - 0.071, H - t - 0.045), M_BLACK(), 20, (0, 90, 0)))
	hi.append(box("psu_label", (0.002, 0.05, 0.03), (0.081, D * 0.5 - t - 0.12, H - t - 0.06), flat("label_white", (0.66, 0.65, 0.6), 0.6)))
	hi.append(box("cage", (0.11, 0.16, 0.15), (0.02, -D * 0.5 + 0.085, H - t - 0.08), steel, 0.002))
	for k in range(2):
		hi.append(box("drive%d" % k, (0.104, 0.15, 0.042), (0.024, -D * 0.5 + 0.088, H - t - 0.045 - k * 0.055), flat("drive", (0.07, 0.07, 0.075), 0.45, 0.3), 0.002))
	hi.append(box("hdd", (0.10, 0.146, 0.026), (0.02, -D * 0.5 + 0.09, 0.06), M_ALU(), 0.002))
	hi.append(box("hdd_label", (0.07, 0.09, 0.002), (0.02, -D * 0.5 + 0.09, 0.0735), flat("label_white", (0.66, 0.65, 0.6), 0.6)))
	# cables: a grey ribbon and a coloured loom hanging out of the open side
	bm = bmesh.new()
	pts = [(0.03, -0.11, 0.30), (0.075, -0.07, 0.25), (0.085, 0.0, 0.19), (0.06, 0.05, 0.13), (-0.02, 0.07, 0.09)]
	prev = None
	for (x, y, z) in pts:
		a = bm.verts.new((x, y - 0.022, z))
		b = bm.verts.new((x, y + 0.022, z))
		if prev:
			bm.faces.new((prev[0], prev[1], b, a))
		prev = (a, b)
	rib = new_obj("ribbon", bm, flat("ribbon", (0.45, 0.45, 0.43), 0.6), 60)
	md = rib.modifiers.new("sol", 'SOLIDIFY')
	md.thickness = 0.002
	md2 = rib.modifiers.new("sub", 'SUBSURF')
	md2.levels = 2
	apply_mods(rib)
	hi.append(rib)
	cols = [(0.42, 0.06, 0.04), (0.50, 0.40, 0.06), (0.03, 0.03, 0.03), (0.42, 0.06, 0.04), (0.05, 0.10, 0.28)]
	for k, c in enumerate(cols):
		o = 0.006 * (k - 2)
		hi.append(tube("wire%d" % k, [(0.0, D * 0.5 - 0.15, H - 0.1), (0.07 + o, 0.10, H - 0.14 + o), (0.10 + o, 0.02 + o, 0.20), (0.115 + o * 0.5, -0.05, 0.10 + o), (0.04, -0.12 + o, 0.085)],
			0.0028, flat("wire%d" % (k % 5), c, 0.55, var=0.1), 6))
	# low: the open shell (outside + inside), front, PSU, cage, heatsink, cards
	lo = []
	bm = bmesh.new()
	def quad(a, b, c, d):
		bm.faces.new([bm.verts.new(p) for p in (a, b, c, d)])
	x0, x1, y0, y1 = -W * 0.5, W * 0.5, -D * 0.5, D * 0.5
	xi = x0 + t + 0.009  # inner face of the closed side = the motherboard plane
	# outside
	quad((x0, y1, 0), (x0, y0, 0), (x0, y0, H), (x0, y1, H))
	quad((x0, y0, H), (x1, y0, H), (x1, y1, H), (x0, y1, H))
	quad((x0, y1, 0), (x1, y1, 0), (x1, y0, 0), (x0, y0, 0))
	quad((x1, y1, 0), (x0, y1, 0), (x0, y1, H), (x1, y1, H))
	# inside (faces look into the cavity)
	quad((xi, y0, t), (xi, y1 - t, t), (xi, y1 - t, H - t), (xi, y0, H - t))
	quad((xi, y0, H - t), (xi, y1 - t, H - t), (x1, y1 - t, H - t), (x1, y0, H - t))
	quad((xi, y1 - t, t), (xi, y0, t), (x1, y0, t), (x1, y1 - t, t))
	quad((xi, y1 - t, H - t), (xi, y1 - t, t), (x1, y1 - t, t), (x1, y1 - t, H - t))
	quad((xi, y0, t), (xi, y0, H - t), (x1, y0, H - t), (x1, y0, t))
	# rim strips closing the wall thickness on the open side
	quad((x1, y0, H - t), (x1, y1 - t, H - t), (x1, y1, H), (x1, y0, H))
	quad((x1, y1 - t, t), (x1, y0, t), (x1, y0, 0), (x1, y1, 0))
	quad((x1, y1 - t, H - t), (x1, y1 - t, t), (x1, y1, 0), (x1, y1, H))
	bmesh.ops.recalc_face_normals(bm, faces=[])
	lo.append(new_obj("lo_shell", bm))
	lo.append(box("lo_front", (W + 0.004, 0.03, H + 0.004), (0, fy, H * 0.5)))
	lo.append(box("lo_psu", (0.15, 0.14, 0.086), (0.005, D * 0.5 - t - 0.071, H - t - 0.045)))
	lo.append(box("lo_cage", (0.11, 0.16, 0.15), (0.02, -D * 0.5 + 0.085, H - t - 0.08)))
	lo.append(box("lo_sink", (0.058, 0.07, 0.07), (bx + 0.024, 0.075, 0.235)))
	lo.append(box("lo_hdd", (0.10, 0.146, 0.026), (0.02, -D * 0.5 + 0.09, 0.06)))
	for k in range(2):
		lo.append(box("lo_card%d" % k, (0.095, 0.085, 0.004), (bx + 0.05, 0.10, 0.06 + k * 0.045)))
	lo.append(box("lo_ram", (0.028, 0.026, 0.125), (bx + 0.016, -0.041, 0.225)))
	return hi, join("pc_case", lo), 0.007


def keyboard():
	W, D = 0.44, 0.155
	hi = []
	# wedge body: higher at the back
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		top = v.co.z > 0
		back = v.co.y > 0
		v.co = Vector((v.co.x * W, v.co.y * D, (0.034 if back else 0.02) if top else 0.0))
	body = new_obj("body", bm, M_BEIGE())
	md = body.modifiers.new("bevel", 'BEVEL')
	md.width = 0.006
	md.segments = 2
	apply_mods(body)
	for p in body.data.polygons:
		p.use_smooth = True
	select_only(body)
	bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
	hi.append(body)
	# keys: five rows on the slope, a block of grey function keys, a numpad
	pitch = 0.019
	def key(x, y, w=1.0, grey=False, gone=False):
		if gone:
			return
		z = 0.02 + (y + D * 0.5) / D * 0.014 + 0.004
		hi.append(box("key", (pitch * w - 0.003, pitch - 0.003, 0.008), (x, y, z), M_KEY_GREY() if grey else M_KEY(), 0.0025, rot=(5.2, 0, 0)))
	rnd = random.Random(3)
	for r in range(5):
		y = -D * 0.5 + 0.022 + r * pitch
		if r == 0:
			key(-W * 0.5 + 0.03, y, 1.4, True)
			key(-W * 0.5 + 0.03 + pitch * 1.4, y, 1.3, True)
			key(-0.06, y, 6.0)
			key(0.02 + pitch * 1.2, y, 1.3, True)
			key(0.02 + pitch * 2.6, y, 1.4, True)
		else:
			for c in range(14):
				x = -W * 0.5 + 0.022 + c * pitch + (r % 2) * 0.004
				key(x, y, 1.0, c == 0 or c == 13 or r == 4 and c > 11, rnd.random() < 0.04)
		for c in range(4):
			key(W * 0.5 - 0.022 - (3 - c) * pitch, y, 1.0, r == 4 or c == 3)
	for c in range(15):
		key(-W * 0.5 + 0.022 + c * pitch * 1.05, -D * 0.5 + 0.022 + 5 * pitch + 0.004, 0.9, True, c in (1, 6, 11))
	# cable: out of the back, curled on the ground
	hi.append(tube("cable", [(-0.05, D * 0.5 - 0.005, 0.02), (-0.05, D * 0.5 + 0.03, 0.006), (-0.02, D * 0.5 + 0.07, 0.005), (0.06, D * 0.5 + 0.085, 0.005), (0.12, D * 0.5 + 0.06, 0.005),
		(0.13, D * 0.5 + 0.025, 0.006), (0.09, D * 0.5 + 0.012, 0.009), (0.05, D * 0.5 + 0.04, 0.005), (0.10, D * 0.5 + 0.10, 0.005), (0.20, D * 0.5 + 0.09, 0.005)], 0.0035, M_RUBBER(), 6))
	# low: wedge with a raised key field, cable as a three-sided tube
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		top = v.co.z > 0
		back = v.co.y > 0
		v.co = Vector((v.co.x * W, v.co.y * D, (0.034 if back else 0.02) if top else 0.0))
	topf = [f for f in bm.faces if f.normal.z > 0.5][0]
	bmesh.ops.inset_region(bm, faces=[topf], thickness=0.009, depth=0.0)
	for v in topf.verts:
		v.co.z += 0.0085
	lo_a = new_obj("lo_a", bm)
	lo_b = tube("lo_cable", [(-0.05, D * 0.5 - 0.005, 0.018), (-0.03, D * 0.5 + 0.07, 0.004), (0.11, D * 0.5 + 0.075, 0.004), (0.10, D * 0.5 + 0.02, 0.006), (0.06, D * 0.5 + 0.05, 0.004), (0.20, D * 0.5 + 0.09, 0.004)], 0.006, None, 3)
	lo_b = decimated("lo_cable_d", lo_b, 0.3)
	return hi, join("keyboard", [lo_a, lo_b]), 0.006


def _flap(name, w, l, t, hinge, yaw, pitch, mat, torn=0, seed=0):
	"""A box flap: w wide, l long, hinged at `hinge`, turned yaw round Z then folded by pitch.
	torn > 0 gives the free edge a ragged outline. Returns (high, low)."""
	rnd = random.Random(seed)
	n = 6 if torn else 1
	bm = bmesh.new()
	a = [bm.verts.new((-w * 0.5 + w * i / n, 0, 0)) for i in range(n + 1)]
	b = [bm.verts.new((-w * 0.5 + w * i / n, l * (1.0 - torn * rnd.random()), 0)) for i in range(n + 1)]
	for i in range(n):
		bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
	lo = bm.copy()
	hi_o = new_obj(name, bm, mat)
	md = hi_o.modifiers.new("sol", 'SOLIDIFY')
	md.thickness = t
	md.offset = 0.0
	apply_mods(hi_o)
	# low: both sides, a hair apart
	for f in list(lo.faces):
		vs = [lo.verts.new((v.co.x, v.co.y, -t * 0.5)) for v in reversed(f.verts)]
		lo.faces.new(vs)
	for v in lo.verts:
		v.co.z += t * 0.25
	lo_o = new_obj(name + "_lo", lo)
	mtx = Matrix.Translation(Vector(hinge)) @ Matrix.Rotation(math.radians(yaw), 4, 'Z') @ Matrix.Rotation(math.radians(pitch), 4, 'X')
	for o in (hi_o, lo_o):
		o.data.transform(mtx)
	return hi_o, lo_o


def box_open():
	W, D, H, t = 0.38, 0.50, 0.26, 0.006
	hi = []
	lo = []
	cb = cardboard("cardboard", wet=0.35)
	# walls and floor
	hi.append(box("w_f", (W, t, H), (0, -D * 0.5 + t * 0.5, H * 0.5), cb, 0.0015, 1))
	hi.append(box("w_b", (W, t, H), (0, D * 0.5 - t * 0.5, H * 0.5), cb, 0.0015, 1))
	hi.append(box("w_l", (t, D, H), (-W * 0.5 + t * 0.5, 0, H * 0.5), cb, 0.0015, 1))
	hi.append(box("w_r", (t, D, H), (W * 0.5 - t * 0.5, 0, H * 0.5), cb, 0.0015, 1))
	hi.append(box("floor", (W, D, t), (0, 0, t * 0.5), cb))
	# tape along the seams
	tape = flat("tape", (0.50, 0.42, 0.26), 0.3, var=0.1)
	hi.append(box("tape_f", (0.05, 0.002, H * 0.5), (0, -D * 0.5 - 0.001, H * 0.25), tape))
	hi.append(box("tape_b", (0.05, 0.002, H * 0.45), (0, D * 0.5 + 0.001, H * 0.225), tape))
	# a faded shipping mark
	hi.append(box("mark", (0.002, 0.16, 0.07), (W * 0.5 + 0.0005, -0.05, H * 0.6), striped("mark", (0.42, 0.30, 0.17), (0.16, 0.10, 0.07), 60.0, 0.85, 2, 0.5, 0.5)))
	# flaps: two long ones fallen outward, a short one standing, a short one torn
	for (nm, w, l, hinge, yaw, pitch, torn, sd) in (
			("fl_r", D - 0.01, W * 0.5, (W * 0.5, 0, H), -90, -128, 0, 1), ("fl_l", D - 0.01, W * 0.5, (-W * 0.5, 0, H), 90, -22, 0, 2),
			("fl_f", W - 0.01, W * 0.45, (0, -D * 0.5, H), 180, -152, 0.5, 3), ("fl_b", W - 0.01, W * 0.5, (0, D * 0.5, H), 0, 62, 0, 4)):
		h, l_ = _flap(nm, w, l, t, hinge, yaw, pitch, cb, torn, sd)
		hi.append(h)
		lo.append(l_)
	# inside: packing paper and a few things left behind
	wad = box("wad", (W - 0.05, D - 0.06, 0.08), (0.0, 0.0, 0.045), flat("packing", (0.50, 0.47, 0.40), 0.85, var=0.2))
	subdivide(wad, 12)
	displace(wad, 0.07, 0.05, 1)
	displace(wad, 0.025, 0.012, 2)
	apply_mods(wad)
	for p in wad.data.polygons:
		p.use_smooth = True
	hi.append(wad)
	hi.append(cyl("tin", 0.036, 0.11, (-0.08, 0.10, 0.10), M_ALU(), 14, (70, 20, 0)))
	hi.append(box("book", (0.12, 0.17, 0.025), (0.07, -0.10, 0.095), flat("book", (0.25, 0.12, 0.10), 0.7), 0.002, rot=(8, -12, 30)))
	# low: outside walls, inside walls, floor of the cavity (at the wad's height), rim
	bm = bmesh.new()
	def quad(*ps):
		bm.faces.new([bm.verts.new(p) for p in ps])
	x0, x1, y0, y1 = -W * 0.5, W * 0.5, -D * 0.5, D * 0.5
	quad((x0, y0, 0), (x1, y0, 0), (x1, y0, H), (x0, y0, H))
	quad((x1, y0, 0), (x1, y1, 0), (x1, y1, H), (x1, y0, H))
	quad((x1, y1, 0), (x0, y1, 0), (x0, y1, H), (x1, y1, H))
	quad((x0, y1, 0), (x0, y0, 0), (x0, y0, H), (x0, y1, H))
	xi0, xi1, yi0, yi1 = x0 + t, x1 - t, y0 + t, y1 - t
	zc = 0.07
	quad((xi1, yi0, zc), (xi0, yi0, zc), (xi0, yi0, H), (xi1, yi0, H))
	quad((xi1, yi1, zc), (xi1, yi0, zc), (xi1, yi0, H), (xi1, yi1, H))
	quad((xi0, yi1, zc), (xi1, yi1, zc), (xi1, yi1, H), (xi0, yi1, H))
	quad((xi0, yi0, zc), (xi0, yi1, zc), (xi0, yi1, H), (xi0, yi0, H))
	lo.append(new_obj("lo_walls", bm))
	lo.append(heightcap("lo_cap", [wad, hi[-1], hi[-2]], 5, 6, pad=-0.012, floor=0.0, skirt=False))
	return hi, join("box_open", lo), 0.012


def box_crushed():
	"""A box that sat in the rain: slumped flat, one corner still standing, flaps splayed."""
	cb = cardboard("cardboard_wet", base=(0.36, 0.25, 0.14), wet=0.95)
	body = box("body", (0.42, 0.52, 0.24), (0, 0, 0.12), cb)
	subdivide(body, 9)
	bm = bmesh.new()
	bm.from_mesh(body.data)
	for v in bm.verts:
		# squash toward one corner: full height at (-x, +y), flat at (+x, -y)
		k = 0.5 + 0.5 * math.tanh((-v.co.x * 2.2 + v.co.y * 1.6) * 4.0 - 0.2)
		v.co.z *= 0.2 + 0.8 * k
		v.co.x += (1.0 - k) * 0.05 * (v.co.z / 0.24 + 0.3)
		v.co.y -= (1.0 - k) * 0.04
	bm.to_mesh(body.data)
	bm.free()
	displace(body, 0.035, 0.09, 5)
	displace(body, 0.012, 0.02, 6)
	apply_mods(body)
	for p in body.data.polygons:
		p.use_smooth = True
	hi = [body]
	lo = []
	for (nm, w, l, hinge, yaw, pitch, torn, sd) in (("fa", 0.50, 0.2, (0.21, -0.02, 0.05), -90, -168, 0.35, 7), ("fb", 0.40, 0.19, (0.0, -0.27, 0.03), 180, -176, 0.5, 8)):
		h, l_ = _flap(nm, w, l, 0.006, hinge, yaw, pitch, cb, torn, sd)
		hi.append(h)
		lo.append(l_)
	bm = bmesh.new()
	bmesh.ops.create_grid(bm, x_segments=3, y_segments=14, size=0.5)
	for v in bm.verts:
		v.co = Vector((v.co.x * 0.05 - 0.03, v.co.y * 0.36, 0.4))
	tp = new_obj("tape", bm, flat("tape", (0.50, 0.42, 0.26), 0.3, var=0.1), 60)
	md = tp.modifiers.new("sw", 'SHRINKWRAP')
	md.target = body
	md.offset = 0.003
	md.wrap_method = 'PROJECT'
	md.use_project_z = True
	md.use_negative_direction = True
	md.use_positive_direction = False
	apply_mods(tp)
	hi.append(tp)
	lo.append(heightcap("lo_cap", [body], 7, 8))
	return hi, join("box_crushed", lo), -0.05


def crate_parts():
	W, D, H, t = 0.30, 0.40, 0.25, 0.012
	hi = []
	pl = aged_plastic("crate_green", base=(0.07, 0.20, 0.15), yellow=(0.12, 0.22, 0.13), dirt=(0.10, 0.08, 0.06), rough=0.5)
	# a lattice crate: corner posts, rails, and bars between
	for (sx, sy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
		hi.append(box("post", (0.022, 0.022, H), (sx * (W * 0.5 - 0.011), sy * (D * 0.5 - 0.011), H * 0.5), pl, 0.004))
	for z in (0.012, H * 0.5, H - 0.014):
		for sy in (-1, 1):
			hi.append(box("rail", (W, t, 0.026), (0, sy * (D * 0.5 - t * 0.5), z), pl, 0.003))
		for sx in (-1, 1):
			hi.append(box("rail", (t, D, 0.026), (sx * (W * 0.5 - t * 0.5), 0, z), pl, 0.003))
	for k in range(1, 6):
		for sy in (-1, 1):
			hi.append(box("bar", (0.012, t * 0.7, H), (-W * 0.5 + k * W / 6.0, sy * (D * 0.5 - t * 0.5), H * 0.5), pl, 0.002))
	for k in range(1, 8):
		for sx in (-1, 1):
			hi.append(box("bar", (t * 0.7, 0.012, H), (sx * (W * 0.5 - t * 0.5), -D * 0.5 + k * D / 8.0, H * 0.5), pl, 0.002))
	hi.append(box("floor", (W, D, 0.01), (0, 0, 0.005), pl))
	# the parts inside: boards on edge, a coil of cable, a steel flask, a drive, small boxes
	inside = []
	inside.append(box("fill", (W - 0.03, D - 0.03, 0.12), (0, 0, 0.07), flat("fill", (0.08, 0.075, 0.07), 0.8, var=0.3)))
	subdivide(inside[-1], 10)
	displace(inside[-1], 0.05, 0.035, 11)
	apply_mods(inside[-1])
	for k, (x, y, rz, c) in enumerate(((-0.07, -0.08, 12, (0.035, 0.16, 0.085)), (-0.03, -0.06, 20, (0.03, 0.10, 0.16)), (0.02, -0.09, 6, (0.045, 0.14, 0.07)))):
		inside.append(box("pc%d" % k, (0.003, 0.15, 0.11), (x, y, 0.175), pcb("pcb_c%d" % k, c), rot=(8 * k - 6, 14 - 9 * k, rz)))
		inside.append(box("pcchip%d" % k, (0.006, 0.03, 0.03), (x + 0.003, y + 0.01, 0.19), flat("chip", (0.03, 0.03, 0.035), 0.4, var=0.05), rot=(8 * k - 6, 14 - 9 * k, rz)))
	inside.append(cyl("flask", 0.037, 0.20, (0.085, -0.03, 0.19), M_ALU(), 16, (74, 0, 24), bevel=0.004))
	inside.append(box("drive", (0.10, 0.146, 0.026), (-0.03, 0.11, 0.2), M_ALU(), 0.002, rot=(12, -8, 40)))
	inside.append(box("dlabel", (0.07, 0.09, 0.002), (-0.03, 0.11, 0.2145), flat("label_white", (0.66, 0.65, 0.6), 0.6), rot=(12, -8, 40)))
	inside.append(box("brick", (0.06, 0.10, 0.04), (0.08, 0.12, 0.185), M_BLACK(), 0.006, rot=(-10, 6, -20)))
	cols = [(0.03, 0.03, 0.03), (0.42, 0.06, 0.04), (0.50, 0.40, 0.06)]
	for k in range(3):
		rr = 0.055 + 0.012 * k
		pts = [(0.03 + math.cos(a) * rr, 0.03 + math.sin(a) * rr * 0.9, 0.2 + 0.012 * k + 0.012 * math.sin(a * 2 + k)) for a in [i * math.tau / 10 for i in range(10)]]
		inside.append(tube("coil%d" % k, pts, 0.005, flat("wire%d" % ((k + 2) % 5), cols[k], 0.55, var=0.1), 6, True))
	hi += inside
	bm = bmesh.new()
	def quad(*ps):
		bm.faces.new([bm.verts.new(p) for p in ps])
	x0, x1, y0, y1 = -W * 0.5, W * 0.5, -D * 0.5, D * 0.5
	quad((x0, y0, 0), (x1, y0, 0), (x1, y0, H), (x0, y0, H))
	quad((x1, y0, 0), (x1, y1, 0), (x1, y1, H), (x1, y0, H))
	quad((x1, y1, 0), (x0, y1, 0), (x0, y1, H), (x1, y1, H))
	quad((x0, y1, 0), (x0, y0, 0), (x0, y0, H), (x0, y1, H))
	xi0, xi1, yi0, yi1 = x0 + t, x1 - t, y0 + t, y1 - t
	zc = 0.1
	quad((xi1, yi0, zc), (xi0, yi0, zc), (xi0, yi0, H), (xi1, yi0, H))
	quad((xi1, yi1, zc), (xi1, yi0, zc), (xi1, yi0, H), (xi1, yi1, H))
	quad((xi0, yi1, zc), (xi1, yi1, zc), (xi1, yi1, H), (xi0, yi1, H))
	quad((xi0, yi0, zc), (xi0, yi1, zc), (xi0, yi1, H), (xi0, yi0, H))
	quad((x0, y0, H), (x1, y0, H), (xi1, yi0, H), (xi0, yi0, H))
	quad((x1, y0, H), (x1, y1, H), (xi1, yi1, H), (xi1, yi0, H))
	quad((x1, y1, H), (x0, y1, H), (xi0, yi1, H), (xi1, yi1, H))
	quad((x0, y1, H), (x0, y0, H), (xi0, yi0, H), (xi0, yi1, H))
	lo = [new_obj("lo_walls", bm), heightcap("lo_cap", inside, 6, 8, pad=-0.004, floor=0.0, skirt=False)]
	return hi, join("crate_parts", lo), 0.014


def bottle_pet():
	"""A crushed PET water bottle: clear plastic reads as pale, glossy, ribbed; faded label, blue cap."""
	prof = [(0.0, 0.0), (0.026, 0.0), (0.033, 0.006), (0.0335, 0.04), (0.031, 0.05), (0.0335, 0.06), (0.0335, 0.13), (0.031, 0.14), (0.0335, 0.15),
		(0.033, 0.175), (0.027, 0.20), (0.016, 0.218), (0.0135, 0.225), (0.0135, 0.235), (0.0, 0.235)]
	clear = flat("pet", (0.50, 0.56, 0.58), rough=0.16, var=0.06)
	body = lathe("pet_body", prof, 20, clear)
	subdivide(body, 1)
	bm = bmesh.new()
	bm.from_mesh(body.data)
	for v in bm.verts:
		# crushed in the middle: flattened along Y, with a kink
		k = math.exp(-((v.co.z - 0.10) / 0.05) ** 2)
		v.co.y *= 1.0 - 0.55 * k
		v.co.x += 0.012 * k * math.sin(v.co.z * 60.0)
		v.co.y += 0.006 * math.sin(v.co.z * 45.0) * (1.0 - k)
	bm.to_mesh(body.data)
	bm.free()
	for p in body.data.polygons:
		p.use_smooth = True
	hi = [body]
	lab = lathe("pet_label", [(0.0342, 0.07), (0.0342, 0.125)], 20, striped("pet_label", (0.52, 0.56, 0.60), (0.12, 0.22, 0.40), 26.0, 0.5, 2, 0.45, 0.3))
	bm = bmesh.new()
	bm.from_mesh(lab.data)
	for f in [f for f in bm.faces if abs(f.normal.z) > 0.9]:
		bm.faces.remove(f)
	for v in bm.verts:
		k = math.exp(-((v.co.z - 0.10) / 0.05) ** 2)
		v.co.y *= 1.0 - 0.55 * k
		v.co.x += 0.012 * k * math.sin(v.co.z * 60.0)
	bm.to_mesh(lab.data)
	bm.free()
	hi.append(lab)
	hi.append(cyl("cap", 0.0155, 0.014, (0, 0, 0.236), flat("cap_blue", (0.06, 0.16, 0.36), 0.45, var=0.1), 14, bevel=0.002))
	lo = lathe("lo", [(0.0, 0.0), (0.03, 0.002), (0.0345, 0.05), (0.0345, 0.15), (0.03, 0.19), (0.016, 0.225), (0.016, 0.245), (0.0, 0.245)], 6)
	bm = bmesh.new()
	bm.from_mesh(lo.data)
	for v in bm.verts:
		k = math.exp(-((v.co.z - 0.10) / 0.05) ** 2)
		v.co.y *= 1.0 - 0.5 * k
		v.co.x += 0.012 * k * math.sin(v.co.z * 60.0)
	bm.to_mesh(lo.data)
	bm.free()
	lo.name = "bottle_pet"
	return hi, lo, 0.006


def can_crushed():
	"""A drink can, stepped on: aluminium ends, a faded printed wall, a deep dent."""
	wall = striped("can_print", (0.46, 0.09, 0.07), (0.62, 0.60, 0.55), 9.0, 0.35, 2, 0.62, 0.25)
	wall["_metal"] = 0.55
	wall.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.55
	prof = [(0.0, 0.004), (0.022, 0.0), (0.031, 0.008), (0.033, 0.016), (0.033, 0.104), (0.028, 0.116), (0.026, 0.118), (0.0, 0.116)]
	body = lathe("can", prof, 20, wall)
	body.data.materials.append(M_ALU())
	subdivide(body, 2)
	bm = bmesh.new()
	bm.from_mesh(body.data)
	for f in bm.faces:
		c = f.calc_center_median()
		if c.z < 0.012 or c.z > 0.106:
			f.material_index = 1
	for v in bm.verts:
		k = math.exp(-((v.co.z - 0.062) / 0.03) ** 2)
		ang = math.atan2(v.co.y, v.co.x)
		v.co.y *= 1.0 - 0.6 * k
		v.co.x *= 1.0 + 0.12 * k
		v.co.z += 0.012 * k * math.cos(ang * 2.0)
		v.co.x += 0.01 * (v.co.z / 0.118 - 0.5)
	bm.to_mesh(body.data)
	bm.free()
	for p in body.data.polygons:
		p.use_smooth = True
	lo = lathe("lo", [(0.0, 0.0), (0.031, 0.004), (0.035, 0.03), (0.035, 0.062), (0.035, 0.094), (0.029, 0.119), (0.0, 0.119)], 6)
	bm = bmesh.new()
	bm.from_mesh(lo.data)
	for v in bm.verts:
		k = math.exp(-((v.co.z - 0.062) / 0.03) ** 2)
		v.co.y *= 1.0 - 0.58 * k
		v.co.x *= 1.0 + 0.12 * k
		v.co.x += 0.01 * (v.co.z / 0.118 - 0.5)
	bm.to_mesh(lo.data)
	bm.free()
	lo.name = "can_crushed"
	return [body], lo, 0.005


def tarp_heap():
	"""A tarp dumped in a heap: big folds, sharp creases, dirt in the hollows."""
	bm = bmesh.new()
	bmesh.ops.create_icosphere(bm, subdivisions=5, radius=0.5)
	for v in bm.verts:
		v.co = Vector((v.co.x * 0.5, v.co.y * 0.42, max(v.co.z, -0.14) * 0.34 + 0.05))
	o = new_obj("tarp", bm, tarp())
	displace(o, 0.10, 0.2, 21, 'CLOUDS')
	tex = bpy.data.textures.new("fold", 'MUSGRAVE') if 'MUSGRAVE' in [e.identifier for e in bpy.types.Texture.bl_rna.properties['type'].enum_items] else bpy.data.textures.new("fold", 'VORONOI')
	tex.noise_scale = 0.11
	md = o.modifiers.new("fold", 'DISPLACE')
	md.texture = tex
	md.strength = 0.06
	md.mid_level = 0.5
	md.texture_coords = 'GLOBAL'
	displace(o, 0.012, 0.04, 22, 'CLOUDS')
	apply_mods(o)
	bm = bmesh.new()
	bm.from_mesh(o.data)
	zmin = min(v.co.z for v in bm.verts)
	for v in bm.verts:
		v.co.z = max(v.co.z - zmin - 0.03, 0.0)
		# spread at the ground like cloth
		k = max(0.0, 1.0 - v.co.z / 0.08)
		v.co.x *= 1.0 + 0.12 * k
		v.co.y *= 1.0 + 0.12 * k
	bm.to_mesh(o.data)
	bm.free()
	for p in o.data.polygons:
		p.use_smooth = True
	lo = heightcap("tarp_heap", [o], 10, 9)
	return [o], lo, -0.06


def paper_pile():
	"""Office paper and a magazine or two, slid off a stack and rained on."""
	hi = []
	rnd = random.Random(11)
	paper = striped("paper_print", (0.50, 0.48, 0.42), (0.17, 0.16, 0.145), 110.0, 0.8, 1, 0.55, 0.5)
	blank = flat("paper_blank", (0.48, 0.46, 0.40), 0.85, var=0.15)
	z = 0.0
	for k in range(9):
		w, d = (0.21, 0.297) if k % 3 else (0.23, 0.30)
		th = 0.004 if k % 3 else 0.008
		m = paper if k in (8, 5, 2) else blank
		if k == 6:
			m = striped("mag_cover", (0.40, 0.16, 0.12), (0.58, 0.55, 0.47), 9.0, 0.5, 1, 0.3, 0.4)
		s = box("sheet%d" % k, (w, d, th), (rnd.uniform(-0.035, 0.035) * (k / 4.0), rnd.uniform(-0.03, 0.03) * (k / 4.0), z + th * 0.5), m, rot=(0, 0, rnd.uniform(-24, 24) * (0.3 + k / 8.0)))
		z += th * 0.9
		subdivide(s, 6)
		displace(s, 0.012, 0.09, 30 + k, direction='Z')
		apply_mods(s)
		hi.append(s)
	# a few loose sheets beside the stack, one curled
	for k, (x, y, rz) in enumerate(((0.16, 0.05, 40), (-0.15, -0.09, -65), (0.05, -0.19, 12))):
		s = box("loose%d" % k, (0.21, 0.297, 0.0015), (x, y, 0.003 + 0.002 * k), paper if k != 1 else blank, rot=(0, 0, rz))
		subdivide(s, 8)
		displace(s, 0.03, 0.08, 40 + k, direction='Z')
		apply_mods(s)
		bm = bmesh.new()
		bm.from_mesh(s.data)
		zmin = min(v.co.z for v in bm.verts)
		for v in bm.verts:
			v.co.z -= zmin
		bm.to_mesh(s.data)
		bm.free()
		hi.append(s)
	for o in hi:
		bake_xf(o)
	lo = heightcap("paper_pile", hi, 9, 9, floor=0.0015)
	return hi, lo, -0.03


def ewaste_pile():
	"""A scatter of dead electronics: a bare board, a hard drive, a power brick, a tangle of cable."""
	hi = []
	chip = flat("chip", (0.03, 0.03, 0.035), 0.4, var=0.05)
	hi.append(box("board", (0.24, 0.19, 0.003), (-0.06, 0.05, 0.012), pcb(), rot=(3, -4, 18)))
	m = Matrix.Translation(Vector((-0.06, 0.05, 0.014))) @ Matrix.Rotation(math.radians(18), 4, 'Z')
	for (x, y, sx, sy, sz, mt) in ((0.0, 0.0, 0.04, 0.04, 0.004, chip), (0.07, 0.04, 0.03, 0.02, 0.004, chip), (-0.07, -0.04, 0.02, 0.05, 0.004, chip),
			(-0.08, 0.05, 0.012, 0.07, 0.012, flat("slot_white", (0.62, 0.6, 0.52), 0.5)), (0.05, -0.06, 0.07, 0.012, 0.012, M_BLACK())):
		o = box("comp", (sx, sy, sz), (x, y, sz * 0.5 + 0.003), mt, 0.0008)
		o.matrix_world = m @ o.matrix_world
		hi.append(o)
	for k in range(4):
		o = cyl("cap%d" % k, 0.006, 0.016, (0.085 - k * 0.016, -0.02, 0.011), M_ALU(), 10)
		o.matrix_world = m @ o.matrix_world
		hi.append(o)
	hi.append(box("hdd", (0.10, 0.146, 0.026), (0.11, -0.07, 0.016), M_ALU(), 0.002, rot=(0, 6, -28)))
	hi.append(box("hdd_label", (0.07, 0.09, 0.002), (0.111, -0.07, 0.031), flat("label_white", (0.66, 0.65, 0.6), 0.6), rot=(0, 6, -28)))
	hi.append(box("brick", (0.06, 0.11, 0.035), (-0.12, -0.12, 0.0175), M_BLACK(), 0.006, rot=(0, 0, 50)))
	rnd = random.Random(5)
	cols = [(0.03, 0.03, 0.03), (0.42, 0.06, 0.04), (0.03, 0.03, 0.03), (0.50, 0.40, 0.06), (0.45, 0.45, 0.43)]
	for k in range(5):
		cx, cy = rnd.uniform(-0.08, 0.1), rnd.uniform(-0.1, 0.1)
		pts = []
		for i in range(9):
			a = i * 0.9 + k
			rr = 0.06 + 0.05 * rnd.random()
			pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.8, 0.006 + 0.03 * rnd.random() * (1 if 1 < i < 7 else 0)))
		hi.append(tube("cab%d" % k, pts, 0.004 if k % 2 else 0.0055, flat("wire%d" % ((k + 2) % 5), cols[k], 0.55, var=0.1), 6))
	for o in hi:
		bake_xf(o)
	lo = heightcap("ewaste_pile", hi, 10, 10, floor=0.002)
	return hi, lo, -0.04


PIECES = [crt_monitor, pc_case, keyboard, box_open, box_crushed, crate_parts, bottle_pet, can_crushed, tarp_heap, paper_pile, ewaste_pile]
# Texel share: small things get more of the atlas than their area (they are seen as close as big ones).
UV_BOOST = {"bottle_pet": 2.2, "can_crushed": 2.6, "keyboard": 1.5, "paper_pile": 1.1, "ewaste_pile": 1.3, "tarp_heap": 0.75, "box_crushed": 0.85}
# LOD1 triangle share of LOD0
LOD1 = {"crt_monitor": 0.3, "pc_case": 0.35, "keyboard": 0.35, "box_open": 0.5, "box_crushed": 0.3, "crate_parts": 0.45, "bottle_pet": 0.35, "can_crushed": 0.4, "tarp_heap": 0.25, "paper_pile": 0.25, "ewaste_pile": 0.22}


# ----------------------------------------------------------------------------------------------
# Build, unwrap, pack, bake

built = []
for fn in PIECES:
	if ONLY and fn.__name__ not in ONLY:
		continue
	hi, lo, cage = fn()
	lo.name = fn.__name__
	for o in hi:
		bake_xf(o)
	bake_xf(lo)
	# triangulate the low mesh now, so the bake and the game shade the same triangles
	bm = bmesh.new()
	bm.from_mesh(lo.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bmesh.ops.triangulate(bm, faces=bm.faces)
	bm.to_mesh(lo.data)
	bm.free()
	lo.data.materials.clear()
	for p in lo.data.polygons:
		p.use_smooth = True
	select_only(lo)
	bpy.ops.object.shade_smooth_by_angle(angle=math.radians(42))
	bpy.ops.object.mode_set(mode='EDIT')
	bpy.ops.mesh.select_all(action='SELECT')
	bpy.ops.uv.smart_project(angle_limit=math.radians(58), island_margin=0.0, area_weight=0.0)
	bpy.ops.object.mode_set(mode='OBJECT')
	built.append((fn.__name__, hi, lo, cage))
	print("[junk] %s: high %d tris in %d parts, low %d tris" % (fn.__name__, sum(tri_count(o) for o in hi), len(hi), tri_count(lo)))

los = [b[2] for b in built]
select_only(*los)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.select_all(action='SELECT')
bpy.ops.uv.average_islands_scale()
bpy.ops.object.mode_set(mode='OBJECT')
for name, hi, lo, cage in built:
	k = math.sqrt(UV_BOOST.get(name, 1.0))
	uv = lo.data.uv_layers.active.data
	arr = np.zeros(len(uv) * 2, dtype=np.float32)
	uv.foreach_get("uv", arr)
	uv.foreach_set("uv", arr * k)
select_only(*los)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.select_all(action='SELECT')
bpy.ops.uv.pack_islands(rotate=True, margin=6.0 / SIZE * 2.0, scale=True)
bpy.ops.object.mode_set(mode='OBJECT')


def new_image(name, color, is_data):
	img = bpy.data.images.new(name, SIZE, SIZE, alpha=False, float_buffer=False)
	img.generated_color = color
	if is_data:
		img.colorspace_settings.name = 'Non-Color'
	return img


IMAGES = {"color": new_image("bake_color", (0.05, 0.043, 0.036, 1), False), "rough": new_image("bake_rough", (0.7, 0.7, 0.7, 1), True),
	"metal": new_image("bake_metal", (0, 0, 0, 1), True), "normal": new_image("bake_normal", (0.5, 0.5, 1, 1), True), "ao": new_image("bake_ao", (1, 1, 1, 1), True)}

lo_mat = bpy.data.materials.new("junk_kit")
lo_mat.use_nodes = True
tex_node = lo_mat.node_tree.nodes.new("ShaderNodeTexImage")
lo_mat.node_tree.nodes.active = tex_node
for lo in los:
	lo.data.materials.append(lo_mat)


def metal_to_emit(on):
	"""Cycles has no metal pass: wire each high material's Metallic into Emission and bake EMIT."""
	for m in bpy.data.materials:
		if m is lo_mat or not m.use_nodes:
			continue
		nt = m.node_tree
		out = [n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'][0]
		bsdf = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
		if on:
			em = nt.nodes.new("ShaderNodeEmission")
			em.name = "_metal_emit"
			s = bsdf.inputs["Metallic"]
			if s.is_linked:
				nt.links.new(s.links[0].from_socket, em.inputs["Color"])
			else:
				v = s.default_value
				em.inputs["Color"].default_value = (v, v, v, 1)
			nt.links.new(em.outputs[0], out.inputs[0])
		else:
			em = nt.nodes.get("_metal_emit")
			if em:
				nt.nodes.remove(em)
			nt.links.new(bsdf.outputs[0], out.inputs[0])


bs = scene.render.bake
bs.use_selected_to_active = True
bs.margin = 6
bs.use_clear = False
bs.use_pass_direct = False
bs.use_pass_indirect = False
bs.use_pass_color = True
bs.normal_space = 'TANGENT'


def bake_pass(kind, bake_type, samples):
	tex_node.image = IMAGES[kind]
	scene.cycles.samples = samples
	for name, hi, lo, cage in built:
		for o in bpy.context.view_layer.objects:
			o.hide_render = not (o in hi or o is lo)
		select_only(*hi)
		lo.select_set(True)
		bpy.context.view_layer.objects.active = lo
		bs.cage_extrusion = abs(cage)  # negative: a heap, baked with unlimited rays
		bs.max_ray_distance = cage * 2.5 if cage > 0 else 0.0
		bpy.ops.object.bake(type=bake_type)
	print("[junk] baked %s" % kind)


bake_pass("color", 'DIFFUSE', 2)
bake_pass("rough", 'ROUGHNESS', 2)
bake_pass("normal", 'NORMAL', 2)
bake_pass("ao", 'AO', AO_SAMPLES)
metal_to_emit(True)
bake_pass("metal", 'EMIT', 2)
metal_to_emit(False)
for o in bpy.context.view_layer.objects:
	o.hide_render = False


def pixels(img):
	a = np.zeros(SIZE * SIZE * 4, dtype=np.float32)
	img.pixels.foreach_get(a)
	return a.reshape(SIZE, SIZE, 4)[:, :, :3]


def save(name, rgb, data):
	img = bpy.data.images.new(name, SIZE, SIZE, alpha=False)
	if data:
		img.colorspace_settings.name = 'Non-Color'
	a = np.ones((SIZE, SIZE, 4), dtype=np.float32)
	a[:, :, :3] = np.clip(rgb, 0.0, 1.0)
	img.pixels.foreach_set(a.ravel())
	img.filepath_raw = os.path.join(HERE, name + ".png")
	img.file_format = 'PNG'
	img.save()
	return img


def to_srgb(x):
	return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(np.maximum(x, 1e-6), 1 / 2.4) - 0.055)


col = pixels(IMAGES["color"])
ao = pixels(IMAGES["ao"])[:, :, :1]
nrm_px = pixels(IMAGES["normal"])
rough_px = pixels(IMAGES["rough"])
metal_px = pixels(IMAGES["metal"])
miss = (nrm_px.sum(axis=2, keepdims=True) < 0.2)
col = np.where(miss, np.array([0.05, 0.043, 0.036], dtype=np.float32)[None, None, :], col)
ao = np.where(miss, 0.75, ao)
nrm_px = np.where(miss, np.array([0.5, 0.5, 1.0], dtype=np.float32)[None, None, :], nrm_px)
rough_px = np.where(miss, 0.9, rough_px)
metal_px = np.where(miss, 0.0, metal_px)
print("[junk] texels with no surface under them (filled as dirt): %.2f%%" % (100.0 * miss.mean()))
# Cavity shading (04: multiplied into the colour so it reads in shade and under flat ambient).
cav = np.clip((ao - 0.15) / 0.75, 0.0, 1.0) ** 0.8
albedo = col * (0.42 + 0.58 * cav)
img_albedo = save("junk_kit_albedo", albedo, False)  # the image is sRGB: Blender encodes linear floats on save
orm = np.concatenate([np.clip(ao, 0, 1) ** 0.7, rough_px[:, :, :1], metal_px[:, :, :1]], axis=2)
img_orm = save("junk_kit_orm", orm, True)
img_nrm = save("junk_kit_normal", nrm_px, True)

# LODs and export
exports = []
for name, hi, lo, cage in built:
	lo.name = name + "_lod0"
	l1 = decimated(name + "_lod1", lo, LOD1.get(name, 0.3))
	exports += [lo, l1]
	print("[junk] %s: lod0 %d tris, lod1 %d tris" % (name, tri_count(lo), tri_count(l1)))
for name, hi, lo, cage in built:
	for o in hi:
		o.hide_render = True
		o.hide_set(True)

if PREVIEW:
	# A still of the LOW meshes with the baked maps, under a low warm sun and a cool sky (02: stills first).
	nt = lo_mat.node_tree
	bsdf = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
	tex_node.image = img_albedo
	nt.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
	t2 = nt.nodes.new("ShaderNodeTexImage")
	t2.image = img_orm
	sep = nt.nodes.new("ShaderNodeSeparateColor")
	nt.links.new(t2.outputs["Color"], sep.inputs[0])
	nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
	nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
	t3 = nt.nodes.new("ShaderNodeTexImage")
	t3.image = img_nrm
	nm = nt.nodes.new("ShaderNodeNormalMap")
	nt.links.new(t3.outputs["Color"], nm.inputs["Color"])
	nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
	cols = 4
	for i, (name, hi, lo, cage) in enumerate(built):
		for o, dy in ((lo, 0.0), (bpy.data.objects[name + "_lod1"], 0.0)):
			o.location = ((i % cols) * 0.95, -(i // cols) * 0.95, 0)
		bpy.data.objects[name + "_lod1"].hide_render = True
	g = bpy.data.materials.new("ground")
	g.use_nodes = True
	gb = [n for n in g.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'][0]
	gb.inputs["Base Color"].default_value = (0.045, 0.043, 0.04, 1)
	gb.inputs["Roughness"].default_value = 0.35
	bm = bmesh.new()
	bmesh.ops.create_grid(bm, size=6.0)
	new_obj("ground", bm, g)
	sun = bpy.data.lights.new("sun", 'SUN')
	sun.energy = 4.0
	sun.color = (1.0, 0.86, 0.68)
	sun.angle = math.radians(3)
	so = link(bpy.data.objects.new("sun", sun))
	so.rotation_euler = (math.radians(62), 0, math.radians(140))
	w = bpy.data.worlds.new("w")
	scene.world = w
	w.use_nodes = True
	w.node_tree.nodes["Background"].inputs[0].default_value = (0.32, 0.42, 0.6, 1)
	w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
	cam = bpy.data.cameras.new("cam")
	cam.lens = 45
	co = link(bpy.data.objects.new("cam", cam))
	rows = (len(built) + cols - 1) // cols
	cx = (min(len(built), cols) - 1) * 0.475
	cy = -(rows - 1) * 0.475
	co.location = (cx, cy - 1.9 - 0.62 * rows, 1.7 + 0.45 * rows)
	co.rotation_euler = (math.radians(50), 0, 0)
	scene.camera = co
	scene.cycles.samples = 24
	scene.cycles.use_denoising = False
	scene.render.resolution_x = 1400
	scene.render.resolution_y = 900
	scene.view_settings.view_transform = 'AgX'
	scene.render.filepath = PREVIEW
	bpy.ops.render.render(write_still=True)
	for i, (name, hi, lo, cage) in enumerate(built):
		lo.location = (0, 0, 0)
		bpy.data.objects[name + "_lod1"].location = (0, 0, 0)

if not ONLY:
	# The glb carries geometry and UVs only; the game builds the material from the three maps.
	for o in exports:
		o.data.materials.clear()
		o.hide_render = False
	select_only(*exports)
	bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, "junk_kit.glb"), export_format='GLB', use_selection=True, export_apply=True,
		export_materials='NONE', export_normals=True, export_tangents=False, export_texcoords=True, export_yup=True)
	print("[junk] wrote junk_kit.glb with %d meshes" % len(exports))
