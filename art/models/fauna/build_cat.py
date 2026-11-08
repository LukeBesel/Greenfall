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
# Kitten-ish proportions: a big round head with chubby cheeks and a small muzzle, a short round
# body, slightly short legs on soft round paws.
import bmesh
from mathutils import Matrix, Euler
HEAD = Vector((0, 0.175, 0.292))
BZ = 0.183  # body centre height
P = []
P.append(fb.ellipsoid((0, 0.068, BZ - 0.002), (0.068, 0.07, 0.074)))         # chest
P.append(fb.capsule((0, -0.07, BZ), (0, 0.05, BZ - 0.004), 0.068, 0.067))      # barrel
P.append(fb.ellipsoid((0, -0.01, BZ - 0.025), (0.06, 0.1, 0.05)))             # belly
P.append(fb.ellipsoid((0, -0.1, BZ + 0.002), (0.077, 0.074, 0.074)))          # haunches
P.append(fb.capsule((0, 0.1, BZ + 0.02), (0, 0.145, 0.255), 0.054, 0.05))     # neck
P.append(fb.ellipsoid(HEAD, (0.08, 0.072, 0.072)))                             # round skull
for x in (-1, 1):
	P.append(fb.ellipsoid(HEAD + Vector((0.04 * x, 0.02, -0.03)), (0.048, 0.04, 0.04)))     # chubby cheeks
	P.append(fb.ellipsoid(HEAD + Vector((0.015 * x, 0.062, -0.03)), (0.019, 0.015, 0.016)))  # whisker pads
	P.append(fb.ellipsoid(HEAD + Vector((0.036 * x, 0.04, 0.03)), (0.026, 0.02, 0.016)))     # brow over the eye socket
P.append(fb.ellipsoid(HEAD + Vector((0, 0.055, -0.047)), (0.014, 0.012, 0.011)))       # chin
P.append(fb.ellipsoid(HEAD + Vector((0, 0.056, -0.01)), (0.016, 0.018, 0.015)))        # nose bridge
for x in (-1, 1):
	P.append(fb.ellipsoid((0.043 * x, 0.075, 0.16), (0.032, 0.04, 0.052)))
	P.append(fb.capsule((0.043 * x, 0.082, 0.125), (0.042 * x, 0.09, 0.03), 0.025, 0.02))
	P.append(fb.ellipsoid((0.042 * x, 0.101, 0.016), (0.025, 0.031, 0.017)))
	P.append(fb.ellipsoid((0.05 * x, -0.095, 0.15), (0.037, 0.056, 0.056), rot=(-20, 0, 0)))
	P.append(fb.capsule((0.05 * x, -0.085, 0.105), (0.049 * x, -0.135, 0.055), 0.027, 0.018))
	P.append(fb.capsule((0.049 * x, -0.135, 0.055), (0.048 * x, -0.115, 0.018), 0.018, 0.017))
	P.append(fb.ellipsoid((0.048 * x, -0.1, 0.016), (0.025, 0.031, 0.017)))
TAIL = [Vector((0, -0.16, 0.2)), Vector((0, -0.21, 0.192)), Vector((0, -0.26, 0.184)), Vector((0, -0.31, 0.177)), Vector((0, -0.36, 0.172)), Vector((0, -0.4, 0.17))]
TR = [0.022, 0.021, 0.02, 0.019, 0.018, 0.015]
for i in range(len(TAIL) - 1):
	P.append(fb.capsule(TAIL[i], TAIL[i + 1], TR[i], TR[i + 1], segs=12))
body = fb.skin("CatBody", P, voxel=0.0052, smooth_repeat=10, ratio=1.0, mat=FUR)

# ------------------------------------------------------------------------- face parts
parts = []
EYES = []
ER = Vector((0.021, 0.019, 0.0185))  # almond: a little wider than tall
for x in (-1, 1):
	ec = HEAD + Vector((0.034 * x, 0.05, 0.012))
	fwd = Vector((0.3 * x, 1.0, 0.04)).normalized()
	ebm = fb.ellipsoid(ec, (ER.x, ER.y, ER.z), segs=48, rings=28)
	e = fb.mesh_obj("Eye%d" % x, ebm, EYE)
	fb.eye_uv(e, ec, fwd)
	fb.bind_rigid(e, "head")
	parts.append(e)
	EYES.append(ec)
	# Eyelids: an upper lid (a fur-coloured shell that rolls down over the eye to blink and
	# sleep, on its own bone) and a fixed lower lid that sets the eye into a soft socket.
	def shell(keep, r=1.13):
		bm = bmesh.new()
		bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=16, radius=1.0)
		bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context='VERTS')
		bmesh.ops.transform(bm, matrix=Matrix.Diagonal((ER.x * r, ER.y * r, ER.z * r, 1)), verts=bm.verts)
		bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.0015)
		return bm
	up = shell(lambda c: c.z > -0.05)
	bmesh.ops.transform(up, matrix=Euler((math.radians(72), 0, 0)).to_matrix().to_4x4(), verts=up.verts)  # open: rolled up and back
	bmesh.ops.translate(up, vec=ec, verts=up.verts)
	lid = fb.mesh_obj("Lid%d" % x, up, FUR)
	fb.bind_rigid(lid, "lid.L" if x > 0 else "lid.R")
	parts.append(lid)
	lo = shell(lambda c: c.z < -0.62, 1.1)
	bmesh.ops.translate(lo, vec=ec, verts=lo.verts)
	low = fb.mesh_obj("LowLid%d" % x, lo, FUR)
	fb.bind_rigid(low, "head")
	parts.append(low)
	# Ears: larger, set wider, soft rounded triangles; furry outside, pink inside.
	eb = HEAD + Vector((0.046 * x, -0.006, 0.05))
	bm = fb.capsule(eb, eb + Vector((0.022 * x, 0.004, 0.058)), 0.031, 0.005, segs=12)
	bmesh.ops.scale(bm, vec=(1.0, 0.42, 1.0), space=Matrix.Translation(-eb), verts=bm.verts)
	ear = fb.mesh_obj("Ear%d" % x, bm, FUR)
	fb.bind_rigid(ear, "ear.L" if x > 0 else "ear.R")
	parts.append(ear)
	bm2 = fb.capsule(eb + Vector((0.0, 0.01, 0.004)), eb + Vector((0.019 * x, 0.013, 0.052)), 0.021, 0.004, segs=12)
	bmesh.ops.scale(bm2, vec=(1.0, 0.25, 1.0), space=Matrix.Translation(-(eb + Vector((0, 0.01, 0)))), verts=bm2.verts)
	inner = fb.mesh_obj("EarIn%d" % x, bm2, SKIN)
	fb.bind_rigid(inner, "ear.L" if x > 0 else "ear.R")
	parts.append(inner)
	for k in range(3):
		o = HEAD + Vector((0.024 * x, 0.064, -0.03 - 0.005 * k))
		t = o + Vector((0.09 * x, 0.012 - 0.008 * k, 0.012 - 0.014 * k))
		w = fb.mesh_obj("Wh%d%d" % (x, k), fb.capsule(o, t, 0.0009, 0.0004, segs=5), WHISK)
		fb.bind_rigid(w, "head")
		parts.append(w)
nose = fb.mesh_obj("Nose", fb.ellipsoid(HEAD + Vector((0, 0.074, -0.012)), (0.0095, 0.0055, 0.006), rot=(15, 0, 0)), NOSE)
fb.bind_rigid(nose, "head")
parts.append(nose)
mouth = fb.mesh_obj("Mouth", fb.capsule(HEAD + Vector((0, 0.074, -0.019)), HEAD + Vector((0, 0.072, -0.03)), 0.0013, 0.0013, segs=5), NOSE)
fb.bind_rigid(mouth, "head")
parts.append(mouth)

# ------------------------------------------------------------------------- coat masks
def fbm(p, s):
	return noise.noise(p * s) * 0.6 + noise.noise(p * s * 2.3) * 0.3


def soft(d, r, w):
	"""1 inside radius r, fading to 0 over w."""
	return max(0.0, min(1.0, (r + w - d) / w))


def coat(co, n):
	x, y, z = co.x, co.y, co.z
	# White areas blend softly: muzzle and chin, bib down the chest, belly, socks.
	white = soft((co - (HEAD + Vector((0, 0.058, -0.035)))).length, 0.03, 0.02)
	white = max(white, soft(abs(x), 0.03, 0.03) * soft(max(0.0, z - 0.2), 0.0, 0.05) * (1.0 if y > 0.06 else 0.0) * max(0.0, min(1.0, n.y * 2 + 0.6)))
	white = max(white, soft(max(0.0, z - 0.135), 0.0, 0.03) * (1.0 if -0.13 < y < 0.12 else 0.0) * max(0.0, min(1.0, -n.z * 2 + 0.3)))
	white = max(white, soft(z, 0.03, 0.02))
	white = max(0.0, min(1.0, white * (0.85 + 0.3 * fbm(co, 30.0))))
	# Tabby: soft bands that wrap round the body, rings on legs and tail, an M on the forehead.
	if y < -0.15 and z > 0.15:
		s = math.sin((-y) * 85.0 + fbm(co, 14) * 0.8)
	elif z < 0.14:
		s = math.sin(z * 95.0 + fbm(co, 14) * 0.8)
	elif (co - HEAD).length < 0.09:
		s = (math.sin(x * 150.0 + fbm(co, 14) * 0.8) * 0.5 - 0.35) if z > HEAD.z + 0.035 else -1.0
	else:
		s = math.sin(y * 62.0 + (z - 0.18) * 30.0 * (1 if x > 0 else -1) * 0.5 + fbm(co, 10) * 0.7)
	stripe = max(0.0, min(1.0, (s + 0.1) * 0.85)) ** 1.25 * (1.0 if n.z > -0.4 else 0.25)
	patch = max(0.0, min(1.0, fbm(co, 9.0) * 1.6 + 0.5))
	occ = 0.78 + 0.22 * max(0.0, min(1.0, n.z * 0.6 + 0.6))
	return (white, stripe, patch, occ)


fb.colors(body, coat)
for o in parts:
	if o.name.startswith("Eye"):
		fb.colors(o, lambda co, n: (0, 0, 0, 1))
	elif o.name.startswith(("Ear", "Lid", "LowLid")) and not o.name.startswith("EarIn"):
		fb.colors(o, coat)
	else:
		fb.colors(o, lambda co, n: (1, 0, 0, 1))

# ------------------------------------------------------------------------- rig
J = HEAD
bones = [
	("root", (0, 0, 0), (0, 0.06, 0), None, False),
	("hips", (0, -0.09, BZ), (0, -0.01, BZ), "root", True),
	("spine", (0, -0.01, BZ), (0, 0.06, BZ), "hips", True),
	("chest", (0, 0.06, BZ), (0, 0.1, BZ + 0.02), "spine", True),
	("neck", (0, 0.1, BZ + 0.02), (0, 0.145, 0.255), "chest", True),
	("head", (0, 0.145, 0.255), (J.x, J.y + 0.04, J.z + 0.05), "neck", True),
	("ear.L", (0.046, J.y, J.z + 0.05), (0.068, J.y + 0.004, J.z + 0.11), "head", True),
	("ear.R", (-0.046, J.y, J.z + 0.05), (-0.068, J.y + 0.004, J.z + 0.11), "head", True),
	("lid.L", tuple(EYES[1]), tuple(EYES[1] + Vector((0, 0.02, 0))), "head", True),
	("lid.R", tuple(EYES[0]), tuple(EYES[0] + Vector((0, 0.02, 0))), "head", True),
]
prev = "hips"
for i in range(len(TAIL) - 1):
	bones.append(("tail%d" % i, tuple(TAIL[i]), tuple(TAIL[i + 1]), prev, True))
	prev = "tail%d" % i
for x, s in ((1, "L"), (-1, "R")):
	bones += [
		("upperarm." + s, (0.043 * x, 0.075, BZ), (0.043 * x, 0.082, 0.11), "chest", True),
		("forearm." + s, (0.043 * x, 0.082, 0.11), (0.042 * x, 0.09, 0.03), "upperarm." + s, True),
		("fpaw." + s, (0.042 * x, 0.09, 0.03), (0.042 * x, 0.118, 0.01), "forearm." + s, True),
		("thigh." + s, (0.05 * x, -0.095, BZ), (0.05 * x, -0.085, 0.105), "hips", True),
		("shin." + s, (0.05 * x, -0.085, 0.105), (0.049 * x, -0.135, 0.055), "thigh." + s, True),
		("foot." + s, (0.049 * x, -0.135, 0.055), (0.048 * x, -0.115, 0.018), "shin." + s, True),
		("hpaw." + s, (0.048 * x, -0.115, 0.018), (0.048 * x, -0.085, 0.01), "foot." + s, True),
	]
arm = fb.armature("CatRig", bones)
fb.auto_weights(body, arm)
# The eyelid bones only move the lids: their share of the skin goes to the head.
hg = body.vertex_groups["head"]
for lg_name in ("lid.L", "lid.R"):
	lg = body.vertex_groups.get(lg_name)
	if lg is None:
		continue
	for v in body.data.vertices:
		for g in v.groups:
			if g.group == lg.index and g.weight > 0.0:
				hg.add([v.index], g.weight, 'ADD')
	body.vertex_groups.remove(lg)
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
	"hips": (40, 0, 0), "chest": (-6, 0, 0), "neck": (-26, 0, 0), "head": (-14, 0, 0),
	"upperarm.L": (-38, 0, 0), "upperarm.R": (-38, 0, 0), "fpaw.L": (4, 0, 0), "fpaw.R": (4, 0, 0),
	"thigh.L": (62, 0, 0), "thigh.R": (62, 0, 0), "shin.L": (-125, 0, 0), "shin.R": (-125, 0, 0), "foot.L": (58, 0, 0), "foot.R": (58, 0, 0),
	"hpaw.L": (-20, 0, 0), "hpaw.R": (-20, 0, 0),
	"tail0": (35, 0, 35), "tail1": (0, 0, 35), "tail2": (0, 0, 40), "tail3": (0, 0, 40), "tail4": (0, 0, 30),
}
SIT_LOC = {"root": (0, 0, -0.065)}

A.action("Sit", 90)
for f in range(1, 92, 15):
	t = (f - 1) / 90.0
	p = dict(SIT)
	p["tail4"] = (8 * math.sin(t * math.tau), 0, 30)
	p["head"] = (-14, 0, 10 * math.sin(t * math.tau))
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
	p["head"] = (-4, 18 + 6 * math.sin(t * math.tau * 2), 0)
	p["neck"] = (-14, 0, 0)
	p["ear.L"] = (-25, 0, 0)
	p["ear.R"] = (-25, 0, 0)
	p["lid.L"] = (-100, 0, 0)  # blissful squint
	p["lid.R"] = (-100, 0, 0)
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
	"ear.L": (-10, 0, 0), "ear.R": (-10, 0, 0), "lid.L": (-115, 0, 0), "lid.R": (-115, 0, 0),
}
A.action("Sleep", 90)
for f in range(1, 92, 15):
	t = (f - 1) / 90.0
	br = 1.0 + 0.03 * math.sin(t * math.tau * 2)
	A.key(f, SLEEP, locs={"root": (0, 0, -0.108)}, scales={"chest": (br, 1, br), "spine": (br, 1, br)})
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
	# Eyes in the preview: the in-game eye shader's iris, slit pupil and catchlights, as vertex colours.
	pe = fb.material("PrevEye", (1, 1, 1, 1), 0.04)
	ve = pe.node_tree.nodes.new("ShaderNodeVertexColor")
	ve.layer_name = "Col"
	pe.node_tree.links.new(ve.outputs["Color"], pe.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
	for o in parts:
		if o.name.startswith("Eye"):
			x = 1 if o.name == "Eye1" else -1
			ec = EYES[0] if x < 0 else EYES[1]
			fwd = Vector((0.3 * x, 1.0, 0.04)).normalized()
			right = fwd.cross(Vector((0, 0, 1))).normalized()
			up2 = right.cross(fwd).normalized()
			col = o.data.color_attributes["Col"]
			for i, v in enumerate(o.data.vertices):
				d = (v.co - ec).normalized()
				u, w = d.dot(right), d.dot(up2)
				r = (u * u + w * w) ** 0.5
				c = (0.75, 0.6, 0.12)
				c = tuple(k * (1.15 - 0.5 * max(0.0, min(1.0, (r - 0.35) / 0.6))) for k in c)
				if r > 0.85 or d.dot(fwd) < 0.2:
					c = (0.04, 0.03, 0.02)
				if (u / 0.55) ** 2 + w * w < 0.48 ** 2:
					c = (0.01, 0.008, 0.006)
				if ((u + 0.3 * x) ** 2 + (w - 0.38) ** 2) < 0.16 ** 2 or ((u - 0.25 * x) ** 2 + (w + 0.3) ** 2) < 0.08 ** 2:
					c = (1.0, 1.0, 1.0)
				col.data[i].color = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1)
			o.data.materials[0] = pe
	for name, act in [(n.lower(), n) for n in opt.get("only", "Idle,Sit,Sleep,Walk,Groom,Pet").split(",")]:
		arm.animation_data.action = bpy.data.actions[act]
		bpy.context.scene.frame_set(8)
		cl = {"side": (1.1, -0.05, 0.3), "top": (0.05, -0.05, 1.3)}.get(opt.get("cam", ""), (0.55, 0.75, 0.42))
		fb.preview(os.path.join(PREVIEW, "cat_%s.png" % name), cl, (0, -0.05, 0.17))
	arm.animation_data.action = bpy.data.actions["Idle"]
	bpy.context.scene.frame_set(1)
	fb.preview(os.path.join(PREVIEW, "cat_face.png"), (0.0, 0.55, 0.3), HEAD + Vector((0, 0.03, -0.01)))
	fb.preview(os.path.join(PREVIEW, "cat_face34.png"), (0.3, 0.47, 0.32), HEAD + Vector((0, 0.03, -0.01)))
	arm.animation_data.action = bpy.data.actions["Sleep"]
	bpy.context.scene.frame_set(1)
	bpy.context.view_layer.update()
	lw = arm.matrix_world @ arm.pose.bones["lid.L"].head
	lf = (arm.matrix_world.to_3x3() @ arm.pose.bones["lid.L"].matrix.to_3x3() @ Vector((0, 1, 0))).normalized()
	fb.preview(os.path.join(PREVIEW, "cat_lids.png"), lw + lf * 0.25 + Vector((0.05, 0, 0.05)), lw)
	arm.animation_data.action = None
	body.data.materials[0] = FUR
	for o in parts:
		if o.name.startswith("Eye"):
			o.data.materials[0] = EYE
	bpy.data.materials.remove(pv)
	for o in ("PrevCam", "PrevSun"):
		bpy.data.objects.remove(bpy.data.objects[o])

if opt.get("lidcheck"):
	dg = bpy.context.evaluated_depsgraph_get()
	for act in ("Idle", "Sleep", "Pet"):
		arm.animation_data.action = bpy.data.actions[act]
		bpy.context.scene.frame_set(1)
		bpy.context.view_layer.update()
		dg = bpy.context.evaluated_depsgraph_get()
		lidobj = bpy.data.objects["Lid1"]
		ob = lidobj.evaluated_get(dg)
		me = ob.to_mesh()
		pts = [ob.matrix_world @ v.co for v in me.vertices]
		ob.to_mesh_clear()
		hb = arm.pose.bones["head"]
		m = arm.matrix_world @ hb.matrix @ hb.bone.matrix_local.inverted()
		front = m @ (EYES[1] + Vector((0.3, 1.0, 0.04)).normalized() * ER.y)
		d = min((q - front).length for q in pts)
		print("[cat] lidcheck", act, round(d, 4))
	arm.animation_data.action = None
fb.export(OUT)
print("[cat] exported", OUT, len(body.data.vertices), "body verts")
