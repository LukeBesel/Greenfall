"""[art4] The start pad's mesh: blender -b --python art/models/outpost/build_pad.py

A raised concrete quay, 21 x 21 m, built of real parts (not a flat slab):
  36 cast slabs 3.3 m square with open joints you can see into, each settled a few mm its own way;
  an iron drain channel inside the kerb; kerb stones 1.1 m long with worn chamfers and a face that
  runs down below the ground; a steel ramp plate on the way out north; deck-edge light lenses in
  the drain channel and round the landing ring (their own material: dark until the yard has power).
Everything is unwrapped straight down onto the painted maps of build_pad_maps.py (run it first:
it writes pad_layout.json, which this reads). Out: outpost_pad.glb with two materials,
"pad_deck" and "pad_lights". Godot side: planet/sites/yard_pad.gd.
Coordinates here are the game's (x east, y up, z south); they are turned into Blender's on write.
"""
import json
import math
import os
import random
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
L = json.load(open(os.path.join(HERE, "pad_layout.json")))
PAD = L["pad"]
S = PAD["size"]
H = S / 2
TRAY = PAD["tray_in"]
KERB = PAD["kerb_in"]
P = PAD["pitch"]
G = PAD["gap"]
RAMP = PAD["ramp_half"]
TOP = 0.075  # the walking surface, as the old pad had it

verts = []
faces = []
mats = []
rnd = random.Random(4471)


def v(x, y, z):
	verts.append((x, -z, y))  # game -> Blender
	return len(verts) - 1


def quad(a, b, c, d, m=0):
	faces.append((a, b, c, d))
	mats.append(m)


def tri(a, b, c, m=0):
	faces.append((a, b, c))
	mats.append(m)


def slab(x0, x1, z0, z1, y0, tops, ch=0.008, m=0):
	"""A block with a chamfered top. tops = heights of the four top corners (x0z0, x1z0, x1z1, x0z1)."""
	c = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
	ins = [(x0 + ch, z0 + ch), (x1 - ch, z0 + ch), (x1 - ch, z1 - ch), (x0 + ch, z1 - ch)]
	t = [v(ins[i][0], tops[i], ins[i][1]) for i in range(4)]
	s = [v(c[i][0], tops[i] - ch, c[i][1]) for i in range(4)]
	b = [v(c[i][0], y0, c[i][1]) for i in range(4)]
	quad(t[3], t[2], t[1], t[0], m)
	for i in range(4):
		j = (i + 1) % 4
		quad(t[i], t[j], s[j], s[i], m)
		quad(s[i], s[j], b[j], b[i], m)


# the bedding under the slabs (what you see down the joints)
b0 = [v(-KERB, 0.02, -KERB), v(KERB, 0.02, -KERB), v(KERB, 0.02, KERB), v(-KERB, 0.02, KERB)]
quad(b0[3], b0[2], b0[1], b0[0])

# 36 slabs, each settled a little
for i in range(6):
	for j in range(6):
		x0 = -TRAY + i * P + G / 2
		z0 = -TRAY + j * P + G / 2
		base = TOP + rnd.uniform(-0.005, 0.004)
		tilt = [base + rnd.uniform(-0.004, 0.004) for _ in range(4)]
		slab(x0, x0 + P - G, z0, z0 + P - G, 0.02, tilt)

# the drain channel: four strips (north one split by the ramp)
ty = TOP - 0.008
for (x0, x1, z0, z1) in [(-KERB, -RAMP, -KERB, -TRAY), (RAMP, KERB, -KERB, -TRAY), (-KERB, KERB, TRAY, KERB),
		(-KERB, -TRAY, -TRAY, TRAY), (TRAY, KERB, -TRAY, TRAY)]:
	slab(x0 + 0.004, x1 - 0.004, z0 + 0.004, z1 - 0.004, 0.02, [ty] * 4, 0.004)

# kerb stones, 1.1 m long (the joints match the painted map: run = k * 1.1 - 20)
KT = 0.125
FOOT = -0.3
for side in range(4):
	k = 0
	while True:
		r0 = k * 1.1 - 20.0
		r1 = r0 + 1.1
		k += 1
		if r1 <= -KERB:
			continue
		if r0 >= KERB:
			break
		a = max(r0, -KERB) + 0.006
		b = min(r1, KERB) - 0.006
		if side == 0 and a < RAMP and b > -RAMP:  # the way out north
			if a < -RAMP:
				b = -RAMP
			elif b > RAMP:
				a = RAMP
			else:
				continue
		top = KT + rnd.uniform(-0.007, 0.007)
		tops = [top + rnd.uniform(-0.003, 0.003) for _ in range(4)]
		if side == 0:
			slab(a, b, -H, -KERB, FOOT, tops, 0.022)
		elif side == 1:
			slab(a, b, KERB, H, FOOT, tops, 0.022)
		elif side == 2:
			slab(-H, -KERB, a, b, FOOT, tops, 0.022)
		else:
			slab(KERB, H, a, b, FOOT, tops, 0.022)
for sx in (-1, 1):  # corner stones, a little proud
	for sz in (-1, 1):
		x0, x1 = sorted((sx * KERB, sx * H))
		z0, z1 = sorted((sz * KERB, sz * H))
		slab(x0, x1, z0, z1, FOOT, [KT + 0.02] * 4, 0.03)

# the ramp plate north: from the slab tops down to the ground over the drain and the kerb
r = [v(-RAMP, TOP - 0.003, -TRAY), v(RAMP, TOP - 0.003, -TRAY), v(RAMP, 0.012, -H - 0.12), v(-RAMP, 0.012, -H - 0.12)]
quad(r[0], r[1], r[2], r[3])
rb = [v(-RAMP, FOOT, -TRAY), v(RAMP, FOOT, -TRAY), v(RAMP, FOOT, -H - 0.12), v(-RAMP, FOOT, -H - 0.12)]
quad(r[3], r[2], rb[2], rb[3])
quad(r[0], r[3], rb[3], rb[0])
quad(r[2], r[1], rb[1], rb[2])


def lens(x, z, hw, hd, y0, y1, m=1):
	t = [v(x - hw, y1, z - hd), v(x + hw, y1, z - hd), v(x + hw, y1, z + hd), v(x - hw, y1, z + hd)]
	b = [v(x - hw - 0.008, y0, z - hd - 0.008), v(x + hw + 0.008, y0, z - hd - 0.008), v(x + hw + 0.008, y0, z + hd + 0.008), v(x - hw - 0.008, y0, z + hd + 0.008)]
	quad(t[3], t[2], t[1], t[0], m)
	for i in range(4):
		j = (i + 1) % 4
		quad(t[i], t[j], b[j], b[i], m)


# deck-edge lights in the drain channel, and eight studs round the landing ring
for (lx, lz, turn) in L["lights"]:
	hw, hd = (0.12, 0.045) if turn == 0 else (0.045, 0.12)
	lens(lx, lz, hw, hd, ty - 0.002, ty + 0.014)
cx, cz = PAD["circle"]
for k in range(8):
	a = (k + 0.5) * math.pi / 4
	lens(cx + math.cos(a) * (PAD["circle_r"] + 0.38), cz + math.sin(a) * (PAD["circle_r"] + 0.38), 0.05, 0.05, TOP - 0.004, TOP + 0.016)

# ---------------------------------------------------------------- mesh, UVs straight down, write
bpy.ops.wm.read_factory_settings(use_empty=True)
me = bpy.data.meshes.new("CleanPad")
me.from_pydata(verts, [], faces)
me.update()
for name in ("pad_deck", "pad_lights"):
	me.materials.append(bpy.data.materials.new(name))
uv = me.uv_layers.new(name="UVMap")
for poly in me.polygons:
	poly.material_index = mats[poly.index]
	poly.use_smooth = False
	for li in poly.loop_indices:
		bx, by, bz = me.vertices[me.loops[li].vertex_index].co
		gx, gz = bx, -by
		u = min(max((gx + H) / S, 0.001), 0.999)
		w = min(max((gz + H) / S, 0.001), 0.999)
		# a hair of skew with height, so upright faces still have a tangent
		uv.data[li].uv = (u + bz * 0.004, 1.0 - (w + bz * 0.004))
ob = bpy.data.objects.new("CleanPad", me)
bpy.context.scene.collection.objects.link(ob)
out = os.path.join(HERE, "outpost_pad.glb")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_apply=True, export_tangents=False, export_materials="EXPORT")
print("wrote", out, "verts", len(verts), "faces", len(faces))
