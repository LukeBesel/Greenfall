"""[fauna2] The stray cat: a cute, believable house cat with a skeletal rig and baked actions.

Run: blender -b --python art/models/fauna/build_cat.py -- [--preview=DIR] [--out=art/models/fauna/cat.glb]
Body: one seamless remeshed skin (big round head with full cheeks, short muzzle, deep chest,
slim waist, round haunches, neat legs with round paws, a long tapering tail). Vertex colours
carry the coat masks the game's fur shader reads (R white areas, G tabby stripes, B calico
patches, A soft occlusion); UVs on the eyes give the iris / pupil disc. Actions: Idle, Walk,
Trot, Sit, Groom, Sleep, Pet, Stretch.
"""
import bpy
import sys
import os
import math
from mathutils import Vector, noise

sys.path.append(os.path.dirname(__file__))
import fauna_blend as fb

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opt = {a.split("=")[0].lstrip("-"): (a.split("=", 1)[1] if "=" in a else "1") for a in args}
OUT = opt.get("out", os.path.join(os.path.dirname(__file__), "cat.glb"))
PREVIEW = opt.get("preview", "")

fb.reset()
FUR = fb.material("Fur", (0.9, 0.55, 0.25, 1), 0.7)
EYE = fb.material("Eye", (0.6, 0.65, 0.2, 1), 0.05)
NOSE = fb.material("Nose", (0.85, 0.5, 0.5, 1), 0.35)
SKIN = fb.material("Skin", (0.95, 0.72, 0.7, 1), 0.6)
WHISK = fb.material("Whisker", (0.97, 0.96, 0.92, 1), 0.4)

# ------------------------------------------------------------------------- body (one skin)
HEAD = Vector((0, 0.215, 0.315))
P = []
P.append(fb.ellipsoid((0, 0.1, 0.205), (0.066, 0.075, 0.078)))           # chest
P.append(fb.capsule((0, -0.1, 0.212), (0, 0.08, 0.207), 0.068, 0.066))    # barrel
P.append(fb.ellipsoid((0, -0.012, 0.19), (0.058, 0.13, 0.05)))            # belly line
P.append(fb.ellipsoid((0, -0.13, 0.215), (0.075, 0.08, 0.078)))          # haunches
P.append(fb.capsule((0, 0.13, 0.235), (0, 0.18, 0.285), 0.05, 0.046))    # neck
P.append(fb.ellipsoid(HEAD, (0.07, 0.064, 0.064)))                        # cranium
for x in (-1, 1):
	P.append(fb.ellipsoid(HEAD + Vector((0.034 * x, 0.022, -0.026)), (0.042, 0.036, 0.036)))  # cheeks
	P.append(fb.ellipsoid(HEAD + Vector((0.014 * x, 0.06, -0.024)), (0.02, 0.016, 0.017)))    # whisker pads
P.append(fb.ellipsoid(HEAD + Vector((0, 0.052, -0.04)), (0.016, 0.014, 0.012)))             # chin
P.append(fb.ellipsoid(HEAD + Vector((0, 0.05, -0.006)), (0.018, 0.02, 0.016)))              # nose bridge
for x in (-1, 1):
	# Front legs: shoulder blade, forearm, round paw.
	P.append(fb.ellipsoid((0.04 * x, 0.11, 0.19), (0.03, 0.04, 0.055)))
	P.append(fb.capsule((0.041 * x, 0.118, 0.15), (0.04 * x, 0.122, 0.03), 0.024, 0.018))
	P.append(fb.ellipsoid((0.04 * x, 0.132, 0.014), (0.021, 0.027, 0.015)))
	# Hind legs: round thigh, shin back to the hock, foot down to the paw.
	P.append(fb.ellipsoid((0.047 * x, -0.12, 0.17), (0.034, 0.055, 0.06), rot=(-20, 0, 0)))
	P.append(fb.capsule((0.047 * x, -0.105, 0.12), (0.046 * x, -0.165, 0.06), 0.025, 0.017))
	P.append(fb.capsule((0.046 * x, -0.165, 0.06), (0.045 * x, -0.145, 0.018), 0.017, 0.016))
	P.append(fb.ellipsoid((0.045 * x, -0.132, 0.014), (0.021, 0.028, 0.015)))
# Tail: rest pose straight back and a little down, tapering.
TAIL = [Vector((0, -0.19, 0.225)), Vector((0, -0.25, 0.215)), Vector((0, -0.31, 0.205)), Vector((0, -0.37, 0.197)), Vector((0, -0.43, 0.19)), Vector((0, -0.47, 0.187))]
TR = [0.021, 0.019, 0.018, 0.017, 0.016, 0.013]
for i in range(len(TAIL) - 1):
	P.append(fb.capsule(TAIL[i], TAIL[i + 1], TR[i], TR[i + 1], segs=12))
body = fb.skin("CatBody", P, voxel=0.0055, smooth_repeat=10, ratio=1.0, mat=FUR)

# ------------------------------------------------------------------------- face parts
parts = []
EYES = []
for x in (-1, 1):
	ec = HEAD + Vector((0.031 * x, 0.044, 0.012))
	fwd = Vector((0.32 * x, 1.0, 0.05)).normalized()
	e = fb.mesh_obj("Eye%d" % x, fb.ellipsoid(ec, (0.0175, 0.0175, 0.0185), segs=28, rings=16), EYE)
	fb.eye_uv(e, ec, fwd)
	fb.bind_rigid(e, "head")
	parts.append(e)
	EYES.append(ec)
	# Ears: a soft rounded triangle, furry outside, pink inside; a little tilted out.
	eb = HEAD + Vector((0.038 * x, -0.004, 0.05))
	bm = fb.capsule(eb, eb + Vector((0.016 * x, 0.004, 0.05)), 0.026, 0.004, segs=10)
	import bmesh
	bmesh.ops.scale(bm, vec=(1.0, 0.42, 1.0), space=__import__("mathutils").Matrix.Translation(-eb), verts=bm.verts)
	ear = fb.mesh_obj("Ear%d" % x, bm, FUR)
	fb.bind_rigid(ear, "ear.L" if x > 0 else "ear.R")
	parts.append(ear)
	bm2 = fb.capsule(eb + Vector((0.0, 0.009, 0.004)), eb + Vector((0.014 * x, 0.012, 0.045)), 0.017, 0.003, segs=10)
	bmesh.ops.scale(bm2, vec=(1.0, 0.25, 1.0), space=__import__("mathutils").Matrix.Translation(-(eb + Vector((0, 0.009, 0)))), verts=bm2.verts)
	inner = fb.mesh_obj("EarIn%d" % x, bm2, SKIN)
	fb.bind_rigid(inner, "ear.L" if x > 0 else "ear.R")
	parts.append(inner)
	# Whiskers: three fine hairs from each pad, fanning out and drooping a little.
	for k in range(3):
		o = HEAD + Vector((0.022 * x, 0.064, -0.022 - 0.005 * k))
		t = o + Vector((0.085 * x, 0.012 - 0.008 * k, 0.012 - 0.014 * k))
		w = fb.mesh_obj("Wh%d%d" % (x, k), fb.capsule(o, t, 0.0009, 0.0004, segs=5), WHISK)
		fb.bind_rigid(w, "head")
		parts.append(w)
nose = fb.mesh_obj("Nose", fb.ellipsoid(HEAD + Vector((0, 0.07, -0.004)), (0.0105, 0.006, 0.0065), rot=(15, 0, 0)), NOSE)
fb.bind_rigid(nose, "head")
parts.append(nose)
mouth = fb.mesh_obj("Mouth", fb.capsule(HEAD + Vector((0, 0.072, -0.012)), HEAD + Vector((0, 0.07, -0.024)), 0.0014, 0.0014, segs=5), NOSE)
fb.bind_rigid(mouth, "head")
parts.append(mouth)

# ------------------------------------------------------------------------- coat masks
def fbm(p, s):
	return noise.noise(p * s) * 0.6 + noise.noise(p * s * 2.3) * 0.3


def coat(co, n):
	x, y, z = co.x, co.y, co.z
	white = 0.0
	# Muzzle and chin, chest bib, belly, paws ("socks").
	if (co - (HEAD + Vector((0, 0.055, -0.03)))).length < 0.04:
		white = 1.0
	if y > 0.06 and z < 0.27 and n.y > -0.1 and abs(x) < 0.055 and y > 0.09 + (z - 0.18) * 0.4:
		white = max(white, 1.0)
	if -0.16 < y < 0.15 and z < 0.165 and n.z < 0.2:
		white = max(white, 1.0)
	if z < 0.045:
		white = 1.0
	edge = fbm(co, 40.0)
	white = max(0.0, min(1.0, white * (0.75 + edge)))
	# Tabby: bands round the body and legs, rings on the tail, an M on the forehead.
	if y < -0.18 and z > 0.16:
		s = math.sin((-y) * 95.0 + fbm(co, 30) * 2.0)
	elif z < 0.15:
		s = math.sin(z * 110.0 + fbm(co, 30) * 2.0)
	elif (co - HEAD).length < 0.08:
		s = math.sin(x * 120.0 + fbm(co, 25) * 1.5) if z > HEAD.z + 0.02 else -1.0
	else:
		s = math.sin(y * 70.0 + z * 25.0 * (1 if x > 0 else -1) + fbm(co, 12) * 0.9)
	stripe = max(0.0, min(1.0, (s - 0.35) * 2.2)) * (1.0 if n.z > -0.4 else 0.3)
	patch = max(0.0, min(1.0, fbm(co, 9.0) * 1.6 + 0.5))
	occ = 0.75 + 0.25 * max(0.0, min(1.0, n.z * 0.6 + 0.6))
	return (white, stripe, patch, occ)


fb.colors(body, coat)
for o in parts:
	if o.name.startswith("Ear") and not o.name.startswith("EarIn"):
		fb.colors(o, coat)
	elif o.name.startswith("Eye"):
		fb.colors(o, lambda co, n: (0, 0, 0, 1))
	else:
		fb.colors(o, lambda co, n: (1, 0, 0, 1))

# ------------------------------------------------------------------------- rig
J = HEAD
bones = [
	("root", (0, 0, 0), (0, 0.06, 0), None, False),
	("hips", (0, -0.1, 0.21), (0, -0.01, 0.21), "root", True),
	("spine", (0, -0.01, 0.21), (0, 0.08, 0.212), "hips", True),
	("chest", (0, 0.08, 0.212), (0, 0.13, 0.235), "spine", True),
	("neck", (0, 0.13, 0.235), (0, 0.18, 0.285), "chest", True),
	("head", (0, 0.18, 0.285), (J.x, J.y + 0.04, J.z + 0.05), "neck", True),
	("ear.L", (0.038, J.y, J.z + 0.05), (0.054, J.y + 0.004, J.z + 0.1), "head", True),
	("ear.R", (-0.038, J.y, J.z + 0.05), (-0.054, J.y + 0.004, J.z + 0.1), "head", True),
]
prev = "hips"
for i in range(len(TAIL) - 1):
	bones.append(("tail%d" % i, tuple(TAIL[i]), tuple(TAIL[i + 1]), prev, True))
	prev = "tail%d" % i
for x, s in ((1, "L"), (-1, "R")):
	bones += [
		("upperarm." + s, (0.04 * x, 0.11, 0.21), (0.041 * x, 0.118, 0.12), "chest", True),
		("forearm." + s, (0.041 * x, 0.118, 0.12), (0.04 * x, 0.122, 0.03), "upperarm." + s, True),
		("fpaw." + s, (0.04 * x, 0.122, 0.03), (0.04 * x, 0.15, 0.01), "forearm." + s, True),
		("thigh." + s, (0.047 * x, -0.12, 0.21), (0.047 * x, -0.105, 0.12), "hips", True),
		("shin." + s, (0.047 * x, -0.105, 0.12), (0.046 * x, -0.165, 0.06), "thigh." + s, True),
		("foot." + s, (0.046 * x, -0.165, 0.06), (0.045 * x, -0.145, 0.018), "shin." + s, True),
		("hpaw." + s, (0.045 * x, -0.145, 0.018), (0.045 * x, -0.11, 0.01), "foot." + s, True),
	]
arm = fb.armature("CatRig", bones)
fb.auto_weights(body, arm)
for o in parts:
	fb.parent_groups(o, arm)
cnt = {vg.name: 0 for vg in body.vertex_groups}
for v in body.data.vertices:
	for g in v.groups:
		if g.weight > 0.5:
			cnt[body.vertex_groups[g.group].name] += 1
print("[cat] weights", cnt)

# ------------------------------------------------------------------------- actions (30 fps)
A = fb.Anim(arm)
L, R = "L", "R"


def legs(phase, amp=1.0, lift=1.0):
	"""Walk-cycle leg rotations for phase 0..1 (diagonal pairs)."""
	out = {}
	for s, off_f, off_h in ((L, 0.0, 0.5), (R, 0.5, 0.0)):
		pf = (phase + off_f) % 1.0
		ph = (phase + off_h) % 1.0
		sw_f = math.sin(pf * math.tau)
		sw_h = math.sin(ph * math.tau)
		up_f = max(0.0, math.cos(pf * math.tau)) * lift
		up_h = max(0.0, math.cos(ph * math.tau)) * lift
		out["upperarm." + s] = (-22 * sw_f * amp, 0, 0)
		out["forearm." + s] = (30 * up_f * amp, 0, 0)
		out["fpaw." + s] = (-25 * up_f * amp, 0, 0)
		out["thigh." + s] = (-20 * sw_h * amp, 0, 0)
		out["shin." + s] = (-18 * up_h * amp, 0, 0)
		out["foot." + s] = (25 * up_h * amp, 0, 0)
	return out


def tail(curve, sway=0.0, lift=0.0):
	"""lift: the base raises the whole tail; curve: added per joint (+ up); sway: side to side."""
	out = {}
	for i in range(5):
		out["tail%d" % i] = ((lift if i == 0 else 0.0) + curve, 0, sway * (0.3 + i * 0.2))
	return out


def merge(*ds):
	out = {}
	for d in ds:
		out.update(d)
	return out


# Idle: breathing, tail slowly swaying up, a look round, an ear flick.
A.action("Idle", 90)
for f in range(1, 92, 6):
	t = (f - 1) / 90.0
	sw = math.sin(t * math.tau) * 18
	look = math.sin(t * math.tau * 2) * 12 if 0.3 < t < 0.8 else 0.0
	ear = -18 if 0.55 < t < 0.6 else 0.0
	A.key(f, merge(tail(7, sw, -50), {"head": (4, 0, look), "ear.L": (ear, 0, 0)}),
		scales={"chest": (1.0 + 0.02 * math.sin(t * math.tau * 3), 1, 1.0 + 0.02 * math.sin(t * math.tau * 3))})
A.done()

# Walk (0.9 s) and Trot (0.5 s): same gait, the trot with more swing and a bob.
for name, n, amp, bob in (("Walk", 27, 1.0, 0.004), ("Trot", 15, 1.35, 0.01)):
	A.action(name, n)
	for f in range(1, n + 2, 1 if n < 20 else 2):
		t = (f - 1) / float(n)
		y = abs(math.sin(t * math.tau)) * bob
		A.key(f, merge(legs(t, amp), tail(6, math.sin(t * math.tau) * 8, -40), {"head": (6, 0, 0), "neck": (-4, 0, 0)}),
			locs={"hips": (0, 0, 0)}, scales={})
	A.done()

SIT = {
	"hips": (40, 0, 0), "chest": (-6, 0, 0), "neck": (-10, 0, 0), "head": (2, 0, 0),
	"upperarm.L": (-38, 0, 0), "upperarm.R": (-38, 0, 0), "fpaw.L": (4, 0, 0), "fpaw.R": (4, 0, 0),
	"thigh.L": (62, 0, 0), "thigh.R": (62, 0, 0), "shin.L": (-125, 0, 0), "shin.R": (-125, 0, 0), "foot.L": (58, 0, 0), "foot.R": (58, 0, 0),
	"hpaw.L": (-20, 0, 0), "hpaw.R": (-20, 0, 0),
	"tail0": (35, 0, 35), "tail1": (0, 0, 35), "tail2": (0, 0, 40), "tail3": (0, 0, 40), "tail4": (0, 0, 30),
}
SIT_LOC = {"root": (0, 0, -0.075)}

A.action("Sit", 90)
for f in range(1, 92, 15):
	t = (f - 1) / 90.0
	p = dict(SIT)
	p["tail4"] = (8 * math.sin(t * math.tau), 0, 30)
	p["head"] = (2, 0, 10 * math.sin(t * math.tau))
	A.key(f, p, locs=SIT_LOC)
A.done()

A.action("Groom", 60)
for f in range(1, 62, 5):
	t = (f - 1) / 60.0
	p = dict(SIT)
	lick = math.sin(t * math.tau * 3)
	p["upperarm.L"] = (35, 0, -8)
	p["forearm.L"] = (75, 0, 0)
	p["fpaw.L"] = (30, 0, 0)
	p["neck"] = (-25, 0, -12)
	p["head"] = (-20 + 7 * lick, 0, -18)
	A.key(f, p, locs=SIT_LOC)
A.done()

A.action("Pet", 60)
for f in range(1, 62, 5):
	t = (f - 1) / 60.0
	p = dict(SIT)
	p["head"] = (14, 18 + 6 * math.sin(t * math.tau * 2), 0)
	p["neck"] = (8, 0, 0)
	p["ear.L"] = (-25, 0, 0)
	p["ear.R"] = (-25, 0, 0)
	p["tail0"] = (55, 0, 0)
	p["tail3"] = (25, 0, 0)
	p["tail4"] = (30, 0, 25 * math.sin(t * math.tau * 2))
	A.key(f, p, locs=SIT_LOC)
A.done()

# Sleep: a loaf curled on its side, head tucked on the paws, tail round the front; breathing.
SLEEP = {
	"hips": (0, 0, -10), "spine": (0, 0, 18), "chest": (0, 0, 18), "neck": (-28, 0, 25), "head": (-18, 12, 22),
	"upperarm.L": (-70, 0, 0), "upperarm.R": (-70, 0, 0), "forearm.L": (125, 0, 0), "forearm.R": (125, 0, 0), "fpaw.L": (30, 0, 0), "fpaw.R": (30, 0, 0),
	"thigh.L": (75, 0, 0), "thigh.R": (75, 0, 0), "shin.L": (-120, 0, 0), "shin.R": (-120, 0, 0), "foot.L": (60, 0, 0), "foot.R": (60, 0, 0),
	"tail0": (-15, 0, 45), "tail1": (0, 0, 38), "tail2": (0, 0, 38), "tail3": (0, 0, 32), "tail4": (0, 0, 25),
	"ear.L": (-10, 0, 0), "ear.R": (-10, 0, 0),
}
A.action("Sleep", 90)
for f in range(1, 92, 15):
	t = (f - 1) / 90.0
	br = 1.0 + 0.03 * math.sin(t * math.tau * 2)
	A.key(f, SLEEP, locs={"root": (0, 0, -0.125)}, scales={"chest": (br, 1, br), "spine": (br, 1, br)})
A.done()

A.action("Stretch", 60)
for f, k in ((1, 0.0), (20, 1.0), (40, 1.0), (61, 0.0)):
	A.key(f, {"chest": (-25 * k, 0, 0), "upperarm.L": (-40 * k, 0, 0), "upperarm.R": (-40 * k, 0, 0), "hips": (10 * k, 0, 0),
		"head": (-20 * k, 0, 0), "tail0": (45 * k, 0, 0)}, locs={"chest": (0, 0, -0.03 * k)})
A.done()

# ------------------------------------------------------------------------- preview + export
if PREVIEW:
	pv = fb.material("Prev", (1, 1, 1, 1), 0.7)
	nt = pv.node_tree
	attr = nt.nodes.new("ShaderNodeVertexColor")
	attr.layer_name = "Col"
	sep = nt.nodes.new("ShaderNodeSeparateColor")
	nt.links.new(attr.outputs["Color"], sep.inputs[0])
	mix1 = nt.nodes.new("ShaderNodeMix")
	mix1.data_type = 'RGBA'
	mix1.inputs[6].default_value = (0.85, 0.45, 0.18, 1)
	mix1.inputs[7].default_value = (0.45, 0.2, 0.08, 1)
	nt.links.new(sep.outputs[1], mix1.inputs[0])
	mix2 = nt.nodes.new("ShaderNodeMix")
	mix2.data_type = 'RGBA'
	nt.links.new(mix1.outputs[2], mix2.inputs[6])
	mix2.inputs[7].default_value = (0.95, 0.93, 0.88, 1)
	nt.links.new(sep.outputs[0], mix2.inputs[0])
	nt.links.new(mix2.outputs[2], nt.nodes["Principled BSDF"].inputs["Base Color"])
	body.data.materials[0] = pv
	for name, act in [(n.lower(), n) for n in opt.get("only", "Idle,Sit,Sleep,Walk,Groom,Pet").split(",")]:
		arm.animation_data.action = bpy.data.actions[act]
		bpy.context.scene.frame_set(8)
		cl = {"side": (1.1, -0.05, 0.3), "top": (0.05, -0.05, 1.3)}.get(opt.get("cam", ""), (0.55, 0.75, 0.42))
		fb.preview(os.path.join(PREVIEW, "cat_%s.png" % name), cl, (0, -0.05, 0.17))
	fb.preview(os.path.join(PREVIEW, "cat_face.png"), (0.12, 0.62, 0.36), HEAD + Vector((0, 0.03, -0.01)))
	arm.animation_data.action = None
	body.data.materials[0] = FUR
	bpy.data.materials.remove(pv)
	for o in ("PrevCam", "PrevSun"):
		bpy.data.objects.remove(bpy.data.objects[o])

fb.export(OUT)
print("[cat] exported", OUT, len(body.data.vertices), "body verts")
