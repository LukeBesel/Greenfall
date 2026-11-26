"""[art7] Stills of the flora kit without the game (Cycles on the CPU, no GL needed):
  python3 art/models/flora/preview_flora.py OUT_PREFIX [sun_elevation_deg] [sun_azimuth_deg]
Reads flora.glb and flora_atlas.png next to this file; writes OUT_PREFIX_trees.png and _small.png.
The game's own look is plants/flora.gdshader (tools/flora_lineup.tscn renders that).
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
args = [a for a in sys.argv[1:] if not a.startswith("-")]
out = args[0] if args else "/tmp/flora"
elev = float(args[1]) if len(args) > 1 else 32.0
azim = float(args[2]) if len(args) > 2 else 140.0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "flora.glb"))
img = bpy.data.images.load(os.path.join(HERE, "flora_atlas.png"))
mat = bpy.data.materials.new("flora_preview")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
col = nt.nodes.new("ShaderNodeVertexColor")
sep = nt.nodes.new("ShaderNodeSeparateColor")
mul = nt.nodes.new("ShaderNodeMix")
mul.data_type = "RGBA"
mul.blend_type = "MULTIPLY"
mul.inputs[0].default_value = 0.6
nt.links.new(col.outputs["Color"], sep.inputs[0])
nt.links.new(tex.outputs["Color"], mul.inputs[6])
nt.links.new(sep.outputs[1], mul.inputs[7])
nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
bsdf.inputs["Roughness"].default_value = 0.7
for name in ("Subsurface Weight", "Transmission Weight"):
    pass
for ob in bpy.data.objects:
    if ob.type == "MESH":
        ob.data.materials.clear()
        ob.data.materials.append(mat)

bpy.ops.mesh.primitive_plane_add(size=400, location=(50, 0, 0))
g = bpy.context.object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.09, 0.08, 0.06, 1)
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
gm.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.0
g.data.materials.append(gm)

sun = bpy.data.lights.new("sun", "SUN")
sun.energy = 4.0
sun.color = (1.0, 0.9, 0.75)
sun.angle = 0.02
so = bpy.data.objects.new("sun", sun)
bpy.context.scene.collection.objects.link(so)
so.rotation_euler = (math.radians(90 - elev), 0, math.radians(azim))
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.5, 0.75, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
bpy.context.scene.world = world

cam = bpy.data.cameras.new("cam")
co = bpy.data.objects.new("cam", cam)
bpy.context.scene.collection.objects.link(co)
sc = bpy.context.scene
sc.camera = co
sc.render.engine = "CYCLES"
sc.cycles.samples = 24
sc.cycles.use_denoising = False
sc.cycles.transparent_max_bounces = 96
sc.render.resolution_x = 1280
sc.render.resolution_y = 540
sc.view_settings.view_transform = "AgX"


def shoot(name, x0, x1, height, dist, lens):
    cam.lens = lens
    co.location = ((x0 + x1) / 2, -dist, height)
    co.rotation_euler = (math.radians(90 - 6), 0, 0)
    sc.render.filepath = "%s_%s.png" % (out, name)
    bpy.ops.render.render(write_still=True)


objs = {o.name: o for o in bpy.data.objects if o.type == "MESH" and o.name != g.name}
trees = sorted(o.location.x for n, o in objs.items() if n.startswith("tree"))
small = sorted(o.location.x for n, o in objs.items() if not n.startswith("tree"))
shoot("small", small[0] - 1, small[len(small) // 2], 1.2, 9, 24)
shoot("small_b", small[len(small) // 2], small[-1] + 1, 1.2, 9, 24)
shoot("trees_a", trees[0] - 2, trees[len(trees) // 2], 4.0, 30, 30)
shoot("trees_b", trees[len(trees) // 2], trees[-1] + 2, 4.0, 30, 30)
