"""[hero v2] Bake the hero's per-pixel wear-mask atlas from art/models/aurora/aurora.glb.

Needs a Blender whose Cycles bakes correctly. Debian's blender 4.0.2 bakes every shaded pass black,
so this runs on the official `bpy` wheel from PyPI (Blender 4.2) in its own Python 3.11 venv:
    uv venv -p 3.11 /tmp/bpyenv && uv pip install -p /tmp/bpyenv/bin/python bpy==4.2.0 numpy
    /tmp/bpyenv/bin/python tools/hero/bake_masks.py [SIZE=2048] [SAMPLES=16]

build_aurora.py lays every hero part into ONE shared UV atlas (TEXCOORD_0), so a single image
serves every hero material. Channels (linear, written as PNG):
  R = ambient occlusion (12 cm reach), the grime / shadow mask
  G = convex edge wear: a Bevel-node normal deviation (5 mm), kept only where the surface is not
      in a crease (short-range AO), so panel lips, bevels and screw rims light up crisply
  B = cavity: occlusion over 2 cm (seams, grooves, the gaps round plates and latches)
  A = 1
The fingers sit at the origin inside the pod in the glb, so they bake in a second pass on their own.
"""
import os
import sys
import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GLB = os.path.join(ROOT, "art/models/aurora/aurora.glb")
OUT = os.path.join(ROOT, "art/models/aurora/aurora_masks.png")
SIZE = int(os.environ.get("SIZE", "2048"))
SAMPLES = int(os.environ.get("SAMPLES", "16"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
print("imported", len(objs), "parts")

img = bpy.data.images.new("masks", SIZE, SIZE, alpha=True, float_buffer=True)
img.colorspace_settings.name = 'Non-Color'
img.generated_color = (1.0, 0.0, 0.0, 1.0)

m = bpy.data.materials.new("bake")
m.use_nodes = True
nt = m.node_tree
N = nt.nodes
L = nt.links
for n in list(N):
	N.remove(n)
out = N.new("ShaderNodeOutputMaterial")
emit = N.new("ShaderNodeEmission")
L.new(emit.outputs[0], out.inputs["Surface"])
comb = N.new("ShaderNodeCombineColor")
L.new(comb.outputs[0], emit.inputs["Color"])


def ao_node(dist, samples=4):
	a = N.new("ShaderNodeAmbientOcclusion")
	a.samples = samples
	a.inputs["Distance"].default_value = dist
	return a


def math_node(op, a, b=None, clamp=False):
	n = N.new("ShaderNodeMath")
	n.operation = op
	n.use_clamp = clamp
	for i, v in enumerate((a, b)):
		if v is None:
			continue
		if isinstance(v, (int, float)):
			n.inputs[i].default_value = v
		else:
			L.new(v, n.inputs[i])
	return n.outputs[0]


ao_big = ao_node(0.12)
L.new(ao_big.outputs["AO"], comb.inputs[0])
ao_small = ao_node(0.02)
# B: cavity = remapped (1 - short AO).
cav = math_node('MULTIPLY', math_node('SUBTRACT', 1.0, ao_small.outputs["AO"]), 2.2, clamp=True)
L.new(cav, comb.inputs[2])
# G: bevel normal deviation, masked to convex spots (not in a crease).
bev = N.new("ShaderNodeBevel")
bev.samples = 4
bev.inputs["Radius"].default_value = 0.005
geo = N.new("ShaderNodeNewGeometry")
dot = N.new("ShaderNodeVectorMath")
dot.operation = 'DOT_PRODUCT'
L.new(bev.outputs[0], dot.inputs[0])
L.new(geo.outputs["Normal"], dot.inputs[1])
dev = math_node('MULTIPLY', math_node('SUBTRACT', 1.0, dot.outputs["Value"]), 9.0, clamp=True)
convex = math_node('GREATER_THAN', ao_small.outputs["AO"], 0.82)
L.new(math_node('MULTIPLY', dev, convex), comb.inputs[1])
tex = N.new("ShaderNodeTexImage")
tex.image = img
N.active = tex

for o in objs:
	o.data.materials.clear()
	o.data.materials.append(m)

sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = SAMPLES
sc.render.bake.margin = 6
sc.world = bpy.data.worlds.new("w")

fingers = [o for o in objs if o.name.startswith("finger")]
rest = [o for o in objs if o not in fingers]


def bake(targets, clear):
	for o in objs:
		o.hide_render = o not in targets
	bpy.ops.object.select_all(action='DESELECT')
	for o in targets:
		o.select_set(True)
	bpy.context.view_layer.objects.active = targets[0]
	bpy.ops.object.bake(type='EMIT', use_clear=clear, margin=6)
	print("baked", len(targets), "parts")


bake(rest, True)
for f in fingers:
	bake([f], False)

px = np.array(img.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)
px[..., 3] = 1.0
cov = (px[..., 1] > 0).mean()
print("ao mean %.3f  edge>0.5 %.3f  cav>0.5 %.3f" % (px[..., 0].mean(), (px[..., 1] > 0.5).mean(), (px[..., 2] > 0.5).mean()))
img.pixels[:] = px.ravel()
img.filepath_raw = OUT
img.file_format = 'PNG'
img.save()
print("wrote", OUT)

sys.stdout.flush()
os._exit(0)  # bpy 4.2 can segfault while tearing down after the bake
