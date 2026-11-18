"""[fauna2] Turns Quaternius's CC0 animated animals (art/vendor/quaternius/*.gltf) into the game's
look: smooth shading and one subdivision level (weights carry over), flat material colours
baked into vertex colours (the fur shader reads them as albedo when the coat masks are unused),
eyes kept glossy, then re-exported with all actions.

Run: blender -b --python art/models/fauna/build_quaternius.py -- --in=Deer --out=deer [--preview=DIR]
"""
import bpy
import sys
import os
import math
from mathutils import Vector

sys.path.append(os.path.dirname(__file__))
import fauna_blend as fb

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opt = {a.split("=")[0].lstrip("-"): (a.split("=", 1)[1] if "=" in a else "1") for a in args}
HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "../../vendor/quaternius/%s.gltf" % opt.get("in", "Deer"))
OUT = os.path.join(HERE, "%s.glb" % opt.get("out", "deer"))

import json
_GL = json.load(open(SRC))
GL_COLORS = {m["name"]: m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [0.7, 0.7, 0.7, 1]) for m in _GL.get("materials", [])}
fb.reset()
bpy.ops.import_scene.gltf(filepath=SRC)
for o in [o for o in bpy.data.objects if o.type == 'MESH' and len(o.data.materials) == 0]:
	bpy.data.objects.remove(o)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
FUR = fb.material("FurBaked", (1, 1, 1, 1), 0.8)
GLOSS = fb.material("Gloss", (0.05, 0.05, 0.05, 1), 0.08)


RECOLOR = {}
for kv in [x for x in opt.get("recolor", "").split(";") if x]:
	k, v = kv.split(":")
	RECOLOR[k] = tuple(float(f) for f in v.split(","))


def mat_color(m):
	if m is None:
		return (0.7, 0.7, 0.7)
	if m.name in RECOLOR:
		return RECOLOR[m.name]
	key = m.name if m.name in GL_COLORS else m.name.split(".")[0]
	if key in GL_COLORS:
		c = GL_COLORS[key]
		return (c[0], c[1], c[2])
	if m.use_nodes:
		b = m.node_tree.nodes.get("Principled BSDF")
		if b:
			c = b.inputs["Base Color"].default_value
			return (c[0], c[1], c[2])
	c = m.diffuse_color
	return (c[0], c[1], c[2])


for o in meshes:
	me = o.data
	for ca in list(me.color_attributes):
		me.color_attributes.remove(ca)
	fb.activate(o)
	bpy.ops.object.mode_set(mode='EDIT')
	bpy.ops.mesh.select_all(action='SELECT')
	bpy.ops.mesh.remove_doubles(threshold=0.0005)
	bpy.ops.object.mode_set(mode='OBJECT')
	cols = [mat_color(m) for m in me.materials]
	print("[q] mats", [m.name for m in me.materials], [tuple(round(x, 2) for x in c) for c in cols])
	names = [m.name.lower() if m else "" for m in me.materials]
	attr = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
	me.color_attributes.active_color = attr
	for poly in me.polygons:
		c = cols[poly.material_index] if poly.material_index < len(cols) else (0.7, 0.7, 0.7)
		for li in poly.loop_indices:
			attr.data[li].color = (c[0], c[1], c[2], 1.0)
	# Eyes stay glossy; everything else is fur.
	eye_idx = [i for i, n in enumerate(names) if "eye" in n]
	for poly in me.polygons:
		poly.material_index = 1 if poly.material_index in eye_idx else 0
		poly.use_smooth = True
	me.materials.clear()
	me.materials.append(FUR)
	me.materials.append(GLOSS)
	fb.activate(o)
	sub = o.modifiers.new("sub", 'SUBSURF')
	sub.levels = 1
	sub.render_levels = 1
	# Keep the armature modifier last so the subdivision is applied in rest pose.
	for m in list(o.modifiers):
		if m.type == 'SUBSURF':
			bpy.ops.object.modifier_move_to_index(modifier=m.name, index=0)
	bpy.ops.object.modifier_apply(modifier="sub")
	print("[q] mesh", o.name, len(me.vertices), "verts")

for a in bpy.data.actions:
	a.name = a.name.replace("_AnimalArmature", "").replace("_Armature", "")
	a.use_fake_user = True
print("[q] actions", [a.name for a in bpy.data.actions])
if opt.get("preview"):
	act = bpy.data.actions.get(opt.get("anim", "Idle")) or bpy.data.actions[0]
	arm.animation_data_create()
	arm.animation_data.action = act
	bpy.context.scene.frame_set(5)
	bb = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
	ctr = sum(bb, Vector()) / len(bb)
	size = max((b - ctr).length for b in bb)
	pv = fb.material("Prev", (1, 1, 1, 1), 0.7)
	vc = pv.node_tree.nodes.new("ShaderNodeVertexColor")
	vc.layer_name = "Col"
	pv.node_tree.links.new(vc.outputs["Color"], pv.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
	for o in meshes:
		o.data.materials[0] = pv
	fb.preview(os.path.join(opt["preview"], "q_%s.png" % opt.get("out", "deer")), ctr + Vector((size * 1.6, -size * 1.9, size * 0.6)), ctr)
	for o in meshes:
		o.data.materials[0] = FUR
	arm.animation_data.action = None
fb.export(OUT)
print("[q] exported", OUT)
