"""[fauna2] Sculpted small animals for the MultiMesh path: birds (pigeon, sparrow, robin, gull)
and the mallard. Each species is written to art/models/fauna/<id>_parts.glb with two poses,
"stand" (perched / swimming) and "fly", each a set of smooth parts whose object origin is the
rig pivot and whose name is the rig part (fauna/fauna_models.gd `sculpted()` assembles them and
art/shaders/fauna.gdshader animates them: head pecks and turns, tail flicks, two-part wings flap).

Parts are unions of solids, voxel-remeshed and smoothed (no seams, soft forms); wings are cut
from a feathered planform (scalloped trailing edge, separated primaries) and thickened. Vertex
colours carry the plumage (alpha = coat mask, unused for birds); eyes and bills use "Gloss".
Authoring is in game coordinates (x right, y up, -z forward) and converted for Blender.

Run: blender -b --python art/models/fauna/build_small.py -- [--only=pigeon,duck] [--preview=DIR]
"""
import bpy
import bmesh
import sys
import os
import math
from mathutils import Vector, Matrix, noise

sys.path.append(os.path.dirname(__file__))
import fauna_blend as fb

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opt = {a.split("=")[0].lstrip("-"): (a.split("=", 1)[1] if "=" in a else "1") for a in args}
HERE = os.path.dirname(__file__)
G = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # game (x, y, z) -> Blender (x, -z, y)


def V(x, y, z):
	return Vector((x, y, z))


def rot_bm(bm, rot_deg, about):
	m = Matrix.Translation(about) @ __import__("mathutils").Euler([math.radians(a) for a in rot_deg]).to_matrix().to_4x4() @ Matrix.Translation(-about)
	bmesh.ops.transform(bm, matrix=m, verts=bm.verts)


class Part:
	def __init__(self, name, pivot, solids, color, voxel=None, smooth=6, gloss=False, sub=0):
		self.name, self.pivot, self.solids, self.color = name, Vector(pivot), solids, color
		self.voxel, self.smooth, self.gloss, self.sub = voxel, smooth, gloss, sub


def build(parts, root_name):
	root = fb.link(bpy.data.objects.new(root_name, None))
	mat = fb.material("Mat", (1, 1, 1, 1), 0.7)
	gl = fb.material("Gloss", (0.05, 0.05, 0.05, 1), 0.05)
	for p in parts:
		bm = bmesh.new()
		for s in p.solids:
			fb.merge_bm(bm, s)
		o = fb.mesh_obj(p.name, bm, gl if p.gloss else mat)
		fb.activate(o)
		if p.voxel:
			r = o.modifiers.new("r", 'REMESH')
			r.mode = 'VOXEL'
			r.voxel_size = p.voxel
			sm = o.modifiers.new("s", 'SMOOTH')
			sm.factor = 0.7
			sm.iterations = p.smooth
		if p.sub:
			ss = o.modifiers.new("ss", 'SUBSURF')
			ss.levels = p.sub
		for m in list(o.modifiers):
			bpy.ops.object.modifier_apply(modifier=m.name)
		# Triangle budget per part (dozens of birds share one MultiMesh).
		key = p.name.split("__")[0].rstrip("0123456789").rstrip("_")
		budget = {"BODY": 1100, "HEAD": 700, "TAIL": 160, "LEG_BL": 120, "LEG_BR": 120, "WING_L": 260, "WING_R": 260, "WINGTIP_L": 320, "WINGTIP_R": 320}.get(key, 300)
		if p.name.startswith("HEAD2") or p.name.startswith("HEAD3"):
			budget = 160
		if p.name.startswith("BODY") and p.name != "BODY":
			budget = 320
		tris = sum(len(f.vertices) - 2 for f in o.data.polygons)
		if tris > budget:
			d = o.modifiers.new("d", 'DECIMATE')
			d.ratio = budget / tris
			bpy.ops.object.modifier_apply(modifier="d")
		bpy.ops.object.shade_smooth()
		# Colours in game coordinates, then move the mesh so its origin is the pivot.
		fb.colors(o, lambda co, n: p.color(co, n))
		o.data.transform(Matrix.Translation(-p.pivot))
		o.data.transform(G)
		o.location = G @ p.pivot
		o.parent = root
	return root


# ----------------------------------------------------------------------------------- birds
def c3(c):
	return (c[0], c[1], c[2])


def rgba(c, a=0.0):
	return (c[0], c[1], c[2], a)


BIRDS = {
	"pigeon": {"s": 1.0, "body": (0.6, 0.62, 0.68), "breast": (0.68, 0.6, 0.68), "head": (0.47, 0.49, 0.56), "neck": (0.34, 0.55, 0.47),
		"wing": (0.66, 0.68, 0.73), "bar": (0.15, 0.15, 0.18), "tip": (0.22, 0.22, 0.26), "beak": (0.2, 0.18, 0.18), "leg": (0.85, 0.36, 0.36),
		"eye": (0.95, 0.45, 0.08), "tail": 0.1, "tailc": (0.55, 0.57, 0.63), "band": (0.18, 0.18, 0.2), "legh": 0.035, "neckl": 0.03, "span": 0.64,
		"tilt": -8, "bars": 2, "cere": True, "gloss_neck": True},
	"sparrow": {"s": 0.55, "body": (0.6, 0.44, 0.28), "breast": (0.8, 0.77, 0.7), "head": (0.52, 0.52, 0.55), "neck": (0.6, 0.38, 0.22),
		"wing": (0.58, 0.4, 0.24), "bar": (0.95, 0.93, 0.88), "tip": (0.32, 0.23, 0.16), "beak": (0.22, 0.18, 0.16), "leg": (0.62, 0.5, 0.4),
		"eye": (0.03, 0.025, 0.02), "tail": 0.085, "tailc": (0.42, 0.3, 0.2), "legh": 0.03, "neckl": 0.0, "span": 0.42, "tilt": -22, "bars": 1,
		"streaks": (0.2, 0.14, 0.1), "cap": (0.52, 0.52, 0.55), "cheek": (0.92, 0.9, 0.86), "bib": (0.1, 0.09, 0.09), "nape": (0.6, 0.36, 0.2)},
	"songbird": {"s": 0.56, "body": (0.5, 0.44, 0.34), "breast": (0.95, 0.47, 0.18), "head": (0.5, 0.44, 0.34), "neck": (0.95, 0.47, 0.18),
		"wing": (0.46, 0.4, 0.31), "bar": (0.46, 0.4, 0.31), "tip": (0.3, 0.26, 0.2), "beak": (0.15, 0.12, 0.1), "leg": (0.5, 0.4, 0.33),
		"eye": (0.03, 0.025, 0.02), "tail": 0.09, "tailc": (0.4, 0.35, 0.28), "legh": 0.035, "neckl": 0.0, "span": 0.42, "tilt": -25, "bars": 0,
		"face": (0.95, 0.47, 0.18), "belly": (0.96, 0.95, 0.91)},
	"gull": {"s": 1.45, "body": (0.97, 0.97, 0.97), "breast": (0.99, 0.99, 0.99), "head": (0.99, 0.99, 0.99), "neck": (0.98, 0.98, 0.98),
		"wing": (0.66, 0.7, 0.77), "bar": (0.1, 0.1, 0.12), "tip": (0.08, 0.08, 0.1), "beak": (0.96, 0.82, 0.22), "leg": (0.95, 0.7, 0.6),
		"eye": (0.92, 0.86, 0.45), "tail": 0.08, "tailc": (0.98, 0.98, 0.98), "legh": 0.045, "neckl": 0.02, "span": 1.0, "tilt": -6, "bars": 0,
		"gonys": (0.85, 0.2, 0.15), "chord": 0.85},
}


def bird_parts(id, p, flying):
	s = p["s"]
	legh = 0.0 if flying else p["legh"]
	tilt = 0.0 if flying else p["tilt"]
	by = 0.062 * s + legh * 0.55
	bc = V(0, by, 0)
	parts = []

	def at(x, y, z):
		v = V(x, y, z) * s
		v.rotate(__import__("mathutils").Euler((math.radians(tilt), 0, 0)))
		return bc + v

	def plumage(co, n):
		# Breast below/front, back colour above, belly pale; species markings by position.
		rel = co - bc
		up = n.y
		col = p["body"]
		if rel.z < -0.01 * s and up < 0.5:
			col = p["breast"]
		if rel.y < -0.02 * s and up < -0.2:
			col = p.get("belly", tuple(min(1, c * 1.12) for c in p["breast"]))
		if "streaks" in p and up > 0.4 and math.sin(rel.z * 260 / s + rel.x * 90 / s) > 0.55:
			col = p["streaks"]
		var = 1.0 + 0.05 * noise.noise(co * 60.0)
		return (col[0] * var, col[1] * var, col[2] * var, 0.0)

	body = [fb.ellipsoid(at(0, 0.004, -0.035), V(0.05, 0.054, 0.058) * s), fb.ellipsoid(at(0, 0.008, 0.02), V(0.046, 0.046, 0.085) * s),
		fb.ellipsoid(at(0, -0.018, 0.0), V(0.04, 0.034, 0.065) * s)]
	for b in body:
		pass
	parts.append(Part("BODY", bc, body, plumage, voxel=0.004 * s, smooth=8))
	# Folded wings (perched): long leaves hugging the flanks, primaries crossing over the tail.
	if not flying:
		def wingc(co, n):
			rel = co - bc
			col = p["wing"]
			zz = rel.z / s
			if zz > 0.07:
				col = p["tip"]
			for k in range(p["bars"]):
				if abs(zz - (0.03 + 0.024 * k)) < 0.006:
					col = p["bar"]
			if "streaks" in p and math.sin(zz * 300) > 0.6:
				col = p["streaks"]
			return rgba(col)
		for x in (-1, 1):
			w = fb.ellipsoid(at(0.038 * x, 0.002, 0.03), V(0.014, 0.034, 0.082) * s)
			rot_bm(w, (-4, 0, 0), at(0.038 * x, 0.002, 0.03))
			w2 = fb.ellipsoid(at(0.022 * x, 0.018, 0.115), V(0.011, 0.007, 0.055) * s)
			parts.append(Part("BODY%d" % (x + 2), bc, [w, w2], wingc, voxel=0.0028 * s, smooth=4))
	# Tail fan (with the pigeon's dark band).
	tl = p["tail"]
	tp = at(0, 0.0, 0.085)

	def tailc(co, n):
		zz = (co - tp).length / s
		if "band" in p and zz > tl * 0.85:
			return rgba(p["band"])
		return rgba(p["tailc"])
	fan = fb.ellipsoid(at(0, 0.0, 0.085 + tl * 0.5), V(0.03 + (0.01 if flying else 0.0), 0.006, tl * 0.55) * s)
	rot_bm(fan, (tilt * 0.4 + (0 if flying else -12), 0, 0), tp)
	parts.append(Part("TAIL", tp, [fan], tailc, voxel=0.0025 * s, smooth=3))
	# Legs.
	if not flying and legh > 0:
		for x, nm in ((-1, "LEG_BL"), (1, "LEG_BR")):
			hip = bc + V(0.018 * x * s, -0.03 * s, 0.005 * s)
			foot = V(0.018 * x * s, 0.004, 0.006 * s)
			lr = 0.0045 * s
			sol = [fb.capsule(hip, foot, lr, lr * 0.8, segs=8)]
			for k in range(3):
				a = math.radians(-28 + 28 * k)
				sol.append(fb.capsule(foot, foot + V(math.sin(a) * 0.022 * s, -0.002, -math.cos(a) * 0.026 * s), lr * 0.6, lr * 0.4, segs=6))
			sol.append(fb.capsule(foot, foot + V(0, -0.002, 0.016 * s), lr * 0.55, lr * 0.4, segs=6))
			parts.append(Part(nm, hip, sol, lambda co, n: rgba(p["leg"]), sub=0))
	# Flying wings: an arm and a hand cut from a feathered planform.
	if flying:
		half = p["span"] * 0.5
		ch = p.get("chord", 1.0)
		for x, sfx in ((-1, "L"), (1, "R")):
			sh = bc + V(0.034 * x * s, 0.02 * s, -0.03 * s)
			wr = sh + V(half * 0.46 * x, 0, 0.012 * s)
			arm_pts = [(0.0, -0.01), (0.46, 0.0), (0.46, 0.07), (0.36, 0.105), (0.22, 0.115), (0.1, 0.11), (0.0, 0.085)]
			hand = [(0.0, 0.0), (0.2, 0.005), (0.4, 0.03), (0.52, 0.06), (0.5, 0.075), (0.47, 0.072), (0.46, 0.09), (0.42, 0.085), (0.4, 0.1), (0.35, 0.095),
				(0.32, 0.108), (0.26, 0.1), (0.2, 0.112), (0.1, 0.105), (0.0, 0.07)]

			def planform(pts, origin, sx, sz, th):
				bm = bmesh.new()
				vs = [bm.verts.new(origin + V(px * sx * x, 0, pz * sz)) for px, pz in pts]
				f = bm.faces.new(vs if x > 0 else list(reversed(vs)))
				bmesh.ops.triangulate(bm, faces=[f])
				ext = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
				vv = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
				bmesh.ops.translate(bm, vec=V(0, -th, 0), verts=vv)
				bmesh.ops.translate(bm, vec=V(0, th * 0.5, 0), verts=bm.verts[:])
				bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
				return bm

			def armc(co, n):
				d = (co - sh)
				zz = d.z / (s * ch)
				col = p["wing"]
				for k in range(p["bars"]):
					if abs(zz - (0.045 + 0.022 * k)) < 0.007:
						col = p["bar"]
				if zz > 0.095:
					col = tuple(c * 0.85 for c in p["wing"])
				if n.y < -0.3:
					col = tuple(min(1, c * 1.15) for c in p["breast"])
				return rgba(col)

			def handc(co, n):
				d = (co - wr)
				t = abs(d.x) / half
				col = p["wing"] if t < 0.25 else p["tip"]
				if n.y < -0.3:
					col = tuple(min(1, c * 1.1) for c in (p["wing"] if t < 0.3 else p["tip"]))
				return rgba(col)
			parts.append(Part("WING_" + sfx, sh, [planform(arm_pts, sh + V(0, 0, -0.01 * s), half, s * ch, 0.01 * s)], armc, sub=2))
			parts.append(Part("WINGTIP_%s__WING_%s" % (sfx, sfx), wr, [planform(hand, wr, half, s * ch, 0.007 * s)], handc, sub=2))
	# Neck and head.
	nb = at(0, 0.03, -0.055)
	nk = p["neckl"]
	hc = (bc + V(0, 0.018 * s, -0.1 * s - nk * 0.9)) if flying else (nb + V(0, 0.04 * s + nk, -0.022 * s - nk * 0.15))

	def headc(co, n):
		rel = co - hc
		col = p["head"]
		if (co - nb).length < (hc - nb).length * 0.75 and rel.y < -0.012 * s:
			col = p["neck"]
		if "cap" in p and rel.y > 0.01 * s:
			col = p["cap"]
		if "nape" in p and rel.z > 0.008 * s and abs(rel.x) > 0.012 * s:
			col = p["nape"]
		if "cheek" in p and abs(rel.x) > 0.017 * s and -0.016 * s < rel.y < 0.004 * s and rel.z > -0.012 * s:
			col = p["cheek"]
		if "bib" in p and rel.y < -0.018 * s and rel.z < 0.0 and abs(rel.x) < 0.016 * s:
			col = p["bib"]
		if "face" in p and rel.z < -0.01 * s and rel.y < 0.006 * s:
			col = p["face"]
		if p.get("gloss_neck") and (co - nb.lerp(hc, 0.4)).length < 0.03 * s:
			col = (0.42, 0.33, 0.52) if rel.x > 0 else (0.3, 0.55, 0.45)
		return rgba(col)
	hs = [fb.capsule(nb, hc, 0.033 * s, 0.026 * s, segs=14), fb.ellipsoid(hc, V(0.031, 0.031, 0.034) * s)]
	parts.append(Part("HEAD", nb, hs, headc, voxel=0.0028 * s, smooth=6))
	bl = 0.032 * s
	bb = hc + V(0, -0.004, -0.027) * s
	bt = bb + V(0, -0.006 * s, -bl)
	beak = [fb.capsule(bb, bt, 0.0095 * s, 0.0015 * s, segs=10)]
	if p.get("cere"):
		beak.append(fb.ellipsoid(bb + V(0, 0.004, -0.004) * s, V(0.007, 0.005, 0.008) * s))

	def beakc(co, n):
		if p.get("cere") and (co - (bb + V(0, 0.004, -0.004) * s)).length < 0.009 * s:
			return rgba((0.93, 0.92, 0.9))
		if "gonys" in p and (co - bt).length < 0.012 * s and co.y < bt.y + 0.002:
			return rgba(p["gonys"])
		return rgba(p["beak"])
	parts.append(Part("HEAD2__", nb, beak, beakc, gloss=True, sub=1))
	eyes = []
	for x in (-1, 1):
		ec = hc + V(0.022 * x, 0.008, -0.012) * s
		eyes.append(fb.ellipsoid(ec, V(0.008, 0.0085, 0.0062) * s, segs=12, rings=8))
		gl = ec + V(0.004 * x, 0.004, -0.004) * s
		eyes.append(fb.ellipsoid(gl, V(0.0022, 0.0022, 0.0015) * s, segs=6, rings=4))

	def eyec(co, n):
		for x in (-1, 1):
			ec = hc + V(0.022 * x, 0.008, -0.012) * s
			gl = ec + V(0.004 * x, 0.004, -0.004) * s
			if (co - gl).length < 0.0026 * s:
				return (1, 1, 1, 0)
			d = (co - ec)
			out = abs(d.x) / s > 0.0065
			if out and p["eye"][0] > 0.3 and (d.y ** 2 + d.z ** 2) ** 0.5 > 0.0035 * s:
				return rgba(p["eye"])
		return (0.02, 0.015, 0.01, 0)
	parts.append(Part("HEAD3__", nb, eyes, eyec, gloss=True))
	return parts


# ----------------------------------------------------------------------------------- duck
def duck_parts(flying):
	grey, chest, head, bill = (0.74, 0.74, 0.72), (0.46, 0.26, 0.17), (0.06, 0.34, 0.2), (0.92, 0.8, 0.25)
	black, backc, spec, white = (0.07, 0.07, 0.08), (0.48, 0.42, 0.34), (0.18, 0.28, 0.8), (0.95, 0.95, 0.93)
	by = 0.0 if flying else 0.065
	parts = []
	bc = V(0, by, 0)

	def bodyc(co, n):
		r = co - bc
		if r.z > 0.15:
			return rgba(black)
		if r.z < -0.07 and r.y > -0.04:
			return rgba(chest)
		if n.y > 0.55 and abs(r.x) < 0.05:
			return rgba(backc)
		v = 1.0 + 0.04 * math.sin(r.z * 400 + r.y * 120)  # fine vermiculation
		return (grey[0] * v, grey[1] * v, grey[2] * v, 0)
	body = [fb.ellipsoid(bc + V(0, 0, 0.01), V(0.1, 0.068, 0.19)), fb.ellipsoid(bc + V(0, 0.012, -0.12), V(0.082, 0.076, 0.085)),
		fb.ellipsoid(bc + V(0, 0.02, 0.17), V(0.055, 0.05, 0.06))]
	parts.append(Part("BODY", bc, body, bodyc, voxel=0.005, smooth=8))
	tp = bc + V(0, 0.03, 0.19)
	tail = [fb.ellipsoid(bc + V(0, 0.035, 0.235), V(0.045, 0.01, 0.05)), fb.capsule(bc + V(0, 0.05, 0.19), bc + V(0, 0.075, 0.185), 0.007, 0.006, segs=6),
		fb.capsule(bc + V(0, 0.075, 0.185), bc + V(0, 0.08, 0.165), 0.006, 0.004, segs=6)]
	parts.append(Part("TAIL", tp, tail, lambda co, n: rgba(black if co.y > bc.y + 0.045 else white), voxel=0.003, smooth=2))
	for x, sfx in ((-1, "L"), (1, "R")):
		if not flying:
			w = fb.ellipsoid(bc + V(0.072 * x, 0.03, 0.05), V(0.026, 0.04, 0.13))

			def wc(co, n, x=x):
				r = co - bc
				if abs(r.x) > 0.088 and 0.045 < r.z < 0.1:
					return rgba(spec if r.z < 0.095 else white)
				if r.z > 0.12:
					return rgba(tuple(c * 0.6 for c in backc))
				return rgba(tuple(min(1, c * 1.15) for c in backc))
			parts.append(Part("BODY%d" % (x + 2), bc, [w], wc, voxel=0.003, smooth=4))
		else:
			half = 0.42
			sh = bc + V(0.06 * x, 0.03, -0.05)
			wr = sh + V(half * 0.46 * x, 0, 0.01)
			arm = fb.ellipsoid(sh + V(half * 0.25 * x, 0, 0.045), V(half * 0.27, 0.011, 0.075))
			hand = fb.ellipsoid(wr + V(half * 0.26 * x, 0, 0.045), V(half * 0.29, 0.009, 0.06))
			rot_bm(hand, (0, -12 * x, 0), wr)

			def armc(co, n, sh=sh):
				d = co - sh
				if 0.075 < d.z < 0.11 and n.y > -0.3:
					return rgba(spec)
				return rgba(tuple(min(1, c * 1.15) for c in backc) if n.y > -0.3 else (0.85, 0.85, 0.83))
			parts.append(Part("WING_" + sfx, sh, [arm], armc, sub=1))
			parts.append(Part("WINGTIP_%s__WING_%s" % (sfx, sfx), wr, [hand], lambda co, n: rgba(backc if n.y > -0.3 else (0.8, 0.8, 0.78)), sub=1))
	nb = bc + V(0, 0.05, -0.13)
	c = bc + (V(0, 0.155, -0.175) if not flying else V(0, 0.05, -0.32))

	def headc(co, n):
		if (co - nb.lerp(c, 0.42)).length < 0.03 and abs((co - nb.lerp(c, 0.42)).y) < 0.008:
			return rgba(white)
		return rgba(head)
	parts.append(Part("HEAD", nb, [fb.capsule(nb, c + V(0, -0.02, 0.01), 0.046, 0.033, segs=14), fb.ellipsoid(c, V(0.04, 0.04, 0.05))], headc, voxel=0.003, smooth=6))
	bill_s = [fb.ellipsoid(c + V(0, -0.014, -0.065), V(0.021, 0.008, 0.038)), fb.ellipsoid(c + V(0, -0.012, -0.1), V(0.008, 0.005, 0.006))]
	parts.append(Part("HEAD2__", nb, bill_s, lambda co, n: rgba(black if co.z < c.z - 0.095 else bill), gloss=True, sub=1))
	eyes = []
	for x in (-1, 1):
		ec = c + V(0.03 * x, 0.01, -0.014)
		eyes += [fb.ellipsoid(ec, V(0.0085, 0.0085, 0.0065), segs=12, rings=8), fb.ellipsoid(ec + V(0.004 * x, 0.004, -0.004), V(0.0022, 0.0022, 0.0015), segs=6, rings=4)]
	parts.append(Part("HEAD3__", nb, eyes, lambda co, n: (1, 1, 1, 0) if any((co - (c + V(0.03 * x, 0.01, -0.014) + V(0.004 * x, 0.004, -0.004))).length < 0.0026 for x in (-1, 1)) else (0.02, 0.015, 0.01, 0), gloss=True))
	if flying:
		for x in (-1, 1):
			parts.append(Part("BODY%d" % (x + 5), bc, [fb.capsule(bc + V(0.025 * x, -0.02, 0.12), bc + V(0.03 * x, -0.02, 0.2), 0.008, 0.006, segs=6),
				fb.ellipsoid(bc + V(0.03 * x, -0.02, 0.22), V(0.022, 0.004, 0.025))], lambda co, n: rgba((0.95, 0.55, 0.15))))
	return parts


# ----------------------------------------------------------------------------------- main
only = [x for x in opt.get("only", "pigeon,sparrow,songbird,gull,duck").split(",") if x]
for sid in only:
	fb.reset()
	if sid == "duck":
		build(duck_parts(False), "stand")
		build(duck_parts(True), "fly")
	else:
		build(bird_parts(sid, BIRDS[sid], False), "stand")
		build(bird_parts(sid, BIRDS[sid], True), "fly")
	out = os.path.join(HERE, "%s_parts.glb" % sid)
	if opt.get("preview"):
		pv = fb.material("Prev", (1, 1, 1, 1), 0.6)
		vc = pv.node_tree.nodes.new("ShaderNodeVertexColor")
		vc.layer_name = "Col"
		pv.node_tree.links.new(vc.outputs["Color"], pv.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
		saved = {}
		for o in bpy.data.objects:
			if o.type == 'MESH':
				saved[o.name] = o.data.materials[0]
				o.data.materials[0] = pv
		fly = bpy.data.objects["fly"]
		k0 = {"pigeon": 1.0, "sparrow": 0.6, "songbird": 0.6, "gull": 1.6, "duck": 1.2}[sid]
		fly.location = (-0.45 * k0, 0.1 * k0, 0.12 * k0)
		k = {"pigeon": 1.0, "sparrow": 0.6, "songbird": 0.6, "gull": 1.6, "duck": 1.2}[sid]
		fb.preview(os.path.join(opt["preview"], "s_%s.png" % sid), (0.5 * k, 0.75 * k, 0.35 * k), (-0.2 * k, 0, 0.1 * k))
		fly.location = (0, 0, 0)
		for o in bpy.data.objects:
			if o.type == 'MESH' and o.name in saved:
				o.data.materials[0] = saved[o.name]
		for o in ("PrevCam", "PrevSun"):
			bpy.data.objects.remove(bpy.data.objects[o])
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_colors=True, export_yup=True, export_apply=False, export_animations=False)
	print("[small] exported", out)
