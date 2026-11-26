#!/usr/bin/env python3
"""[art2] A fast look at aurora.glb without Godot: flat-shaded views of the posed hero in a few
seconds (the rendered runs queue for minutes on the shared box), for the shape loop with
tools/hero/overlay.py. NOT the look of the game: no wear, no glow, painter's-order hidden surfaces.
Usage: tools/hero/quick_views.py OUT_PREFIX [GLB] [--design=ID]  -> OUT_PREFIX_0..4.png (the turnaround views)
--design=bolt|sprout|pixel|nova|patch adds that design's add-ons from designs.glb where
PatchModel.ACC_FIT seats them (head pieces, shoulder pads, toolbox, chest icon) in its paint colour.
--pose=scoop|carry|hold|pet shows the arms at the end of that move (PatchModel._process's targets).
The pose (ARM_REST, ARM_SCALE, CLAW_SCALE) and the view list (TURN_VIEWS) are read from
player/patch_model.gd and scenes/hero_preview.gd, so it shows what the preview scene would."""
import json
import math
import re
import struct
import sys
import numpy as np
from PIL import Image, ImageDraw

COLS = {"rust": (110, 92, 78), "leaf": (80, 150, 50), "moss": (64, 92, 28), "wing": (250, 160, 70), "paint": (214, 204, 192), "plate": (220, 212, 200), "trim": (52, 56, 62), "side": (52, 56, 62), "dark": (30, 33, 37), "steel": (120, 122, 126),
	"accent": (240, 107, 3), "latch": (241, 107, 3), "lamp_accent": (248, 175, 9), "glow": (64, 226, 240), "glow_soft": (64, 226, 240),
	"thruster": (64, 226, 240), "thruster_core": (150, 240, 250), "screen": (8, 10, 12), "face": (6, 8, 10), "paddle": (243, 192, 64),
	"paddle_edge": (250, 215, 130), "fin": (51, 57, 62), "claw": (150, 146, 140), "cable": (16, 16, 18)}
LIT = ("glow", "glow_soft", "thruster", "thruster_core", "latch", "lamp_accent", "paddle_edge")
KEY = (0, 150, 0)   # the green key backdrop overlay.py expects
# End poses of PatchModel._process: {side: (shoulder x, shoulder z, elbow x)}; None = the idle rest.
POSES = {"scoop": {1.0: (-0.9, -0.25, 0.0), -1.0: None}, "carry": {1.0: (-2.7, 0.22, 0.0), -1.0: (-2.7, -0.22, 0.0)},
	"hold": {1.0: (-1.25, 0.35, 0.9), -1.0: None}, "pet": {1.0: (-0.78, -0.12, 0.35), -1.0: None}}
HEAD_PARTS = {"head", "ears", "visor", "antenna"}
DESIGNS_GLB = "art/models/aurora/designs.glb"


def load_glb(path):
	data = open(path, "rb").read()
	jl = struct.unpack_from("<I", data, 12)[0]
	js = json.loads(data[20:20 + jl])
	bin_ = data[20 + jl + 8:]

	def acc(i):
		a = js["accessors"][i]
		v = js["bufferViews"][a["bufferView"]]
		n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
		dt = np.float32 if a["componentType"] == 5126 else np.uint32
		return np.frombuffer(bin_, dt, a["count"] * n, v["byteOffset"]).reshape(-1, n)

	parts = {}
	for node in js["nodes"]:
		prims = []
		for p in js["meshes"][node["mesh"]]["primitives"]:
			prims.append((js["materials"][p["material"]]["name"], acc(p["attributes"]["POSITION"]).astype(np.float64), acc(p["indices"]).reshape(-1, 3)))
		parts[node["name"]] = (np.array(node.get("translation", [0, 0, 0]), np.float64), prims)
	return parts


def rot(axis, a):
	c, s = math.cos(a), math.sin(a)
	m = np.eye(4)
	i, j = {"x": (1, 2), "y": (2, 0), "z": (0, 1)}[axis]
	m[i, i], m[i, j], m[j, i], m[j, j] = c, -s, s, c
	return m


def euler(v):
	"""Godot's default YXZ euler order."""
	return rot("y", v[1]) @ rot("x", v[0]) @ rot("z", v[2])


def xf(pos=(0, 0, 0), r=(0, 0, 0), s=1.0):
	m = euler(r)
	m[:3, :3] *= s
	m[:3, 3] = pos
	return m


def gd_const(src, name):
	m = re.search(r"const %s\s*:?=\s*(?:Vector3\(([^)]*)\)|([-0-9.]+))" % name, src)
	return tuple(float(x) for x in m.group(1).split(",")) if m.group(1) else float(m.group(2))


def design(src, name):
	"""(paint rgb, [add-on names], chest icon) of a design from PatchModel.VARIANTS."""
	line = re.search(r'^\t"%s": \{(.*)\},?$' % name, src, re.M).group(1)
	c = [float(x) for x in re.search(r'"paint": Color\(([^)]*)\)', line).group(1).split(",")]
	acc = re.findall(r'"([a-z_]+)"', re.search(r'"acc": \[([^\]]*)\]', line).group(1))
	icon = re.search(r'"icon": "([a-z]+)"', line).group(1)
	return tuple(int(255 * v ** (1 / 2.2)) for v in c[:3]), acc, icon


def acc_fit(src, part):
	m = re.search(r'"%s": \{([^}]*)\}' % part, src[src.index("const ACC_FIT"):src.index("const SLOT_DEFAULTS")])
	pos, scl = np.zeros(3), np.ones(3)
	if m:
		for key, val in re.findall(r'"(pos|scale)": Vector3\(([^)]*)\)', m.group(1)):
			v = np.array([float(x) for x in val.split(",")])
			if key == "pos":
				pos = v
			else:
				scl = v
	return pos, scl


def posed(parts, variant="aurora", pose=""):
	"""[(world matrix, part name)] for the idle pose, as PatchModel._build / _process place them."""
	src = open("player/patch_model.gd").read()
	rest = gd_const(src, "ARM_REST")
	arm_s = gd_const(src, "ARM_SCALE")
	claw_s = gd_const(src, "CLAW_SCALE")
	P = {n: parts[n][0] for n in parts}
	paint, acc, icon = design(src, variant)
	COLS["paint"] = paint
	COLS["plate"] = paint
	out = [(xf(), "body"), (xf(), "thruster"), (xf(P["hatch"]), "hatch")]
	if icon == "recycle":
		out.append((xf(P["icon_recycle"]), "icon_recycle"))
	else:
		anchor = [float(x) for x in re.search(r'"chest_plate": Vector3\(([^)]*)\)', src).group(1).split(",")]
		out.append((xf(np.array(anchor) + (0, 0, -0.004)), "acc_icon_" + icon))
	for n in ("head", "ears", "visor"):
		out.append((xf(P[n]), n))

	def fitted(name):
		pos, scl = acc_fit(src, name)
		m = xf(P[name] + pos)
		m[:3, :3] = m[:3, :3] * scl[None, :]
		return m

	for a in acc:
		if a in ("antenna", "acc_catears", "acc_pixel", "acc_sprout", "acc_toolbox"):
			if a != "acc_toolbox":
				HEAD_PARTS.add(a)
			out.append((fitted(a), a))
			if a == "acc_pixel":
				HEAD_PARTS.add("acc_pixel_hearts")
				pos, scl = acc_fit(src, "acc_pixel_hearts")
				m = xf(P[a] + pos)
				m[:3, :3] = m[:3, :3] * scl[None, :]
				out.append((m, "acc_pixel_hearts"))
	shoulder_acc = [a for a in acc if a.startswith("acc_pad")]
	for side, sfx in ((1.0, "_r"), (-1.0, "_l")):
		sp, ep, wp = P["arm_shoulder" + sfx], P["arm_elbow" + sfx], P["arm_wrist" + sfx]
		a3 = POSES.get(pose, {}).get(side) or (rest[0], side * rest[2], rest[1])
		sh = xf(sp, (a3[0], 0, a3[1]), arm_s)
		el = sh @ xf(ep - sp, (a3[2], 0, 0))
		wr = el @ xf(wp - ep)
		out += [(sh, "arm_shoulder" + sfx), (el, "arm_elbow" + sfx), (wr, "arm_wrist" + sfx)]
		for a in shoulder_acc:
			if a.endswith(sfx):
				out.append((sh, a))
		for k in range(3):
			a = 2 * math.pi * k / 3.0 + math.pi * 0.5
			d = (math.cos(a), math.sin(a))
			f = wr @ xf((d[0] * 0.036, d[1] * 0.036, -0.058), (-d[1] * 0.12, d[0] * 0.12, 0), claw_s) @ xf(r=(0, 0, a - math.pi * 0.5))
			out.append((f, "finger"))
			out.append((f @ xf((0, 0, -0.05), (-0.35, 0, 0)), "finger_tip"))
	return out


def turn_views():
	"""[(yaw deg, elevation deg, head yaw deg)] from scenes/hero_preview.gd's TURN_VIEWS."""
	import os
	if os.environ.get("QUICK_VIEWS"):
		return [tuple(float(x) for x in g.split(",")) for g in os.environ["QUICK_VIEWS"].split(";")]
	src = open("scenes/hero_preview.gd").read()
	m = re.search(r"const TURN_VIEWS\s*:?=\s*\[(.*?)\]\s*\n", src, re.S)
	return [tuple(float(x) for x in g.split(",")) for g in re.findall(r"\[([^\[\]]*)\]", m.group(1))]


def render(parts, placed, yaw, elev, head_yaw, size=(640, 800), span=1.5, centre_y=0.68):
	r, e = math.radians(yaw), math.radians(elev)
	cam = np.array([math.sin(r) * math.cos(e), math.sin(e), -math.cos(r) * math.cos(e)])
	fwd = -cam
	right = np.cross(fwd, (0, 1, 0))
	right /= np.linalg.norm(right)
	up = np.cross(right, fwd)
	light = np.array([0.5, 0.75, -0.45]) + cam * 0.6
	light /= np.linalg.norm(light)
	head_p = parts["head"][0]
	turn = xf(head_p) @ xf(r=(0, math.radians(head_yaw), 0)) @ xf(-head_p)
	tris, cols, depth = [], [], []
	for (m, name) in placed:
		if name in HEAD_PARTS:
			m = turn @ m
		for (mat, pos, idx) in parts[name][1]:
			w = pos @ m[:3, :3].T + m[:3, 3]
			t = w[idx]
			n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
			ln = np.linalg.norm(n, axis=1) + 1e-12
			facing = (n @ cam) / ln
			keep = facing > 0
			t = t[keep]
			lam = np.clip((n[keep] @ light) / ln[keep], 0, 1)
			base = np.array(COLS.get(mat, (128, 128, 128)), np.float64)
			shade = np.ones(len(t)) if mat in LIT else 0.35 + 0.65 * lam
			tris.append(np.stack([t @ right, t @ up], axis=2))
			depth.append((t @ fwd).mean(axis=1))
			cols.append(np.clip(base[None, :] * shade[:, None], 0, 255))
	tris, cols, depth = np.concatenate(tris), np.concatenate(cols).astype(np.uint8), np.concatenate(depth)
	order = np.argsort(-depth)
	ss = 2
	wpx, hpx = size[0] * ss, size[1] * ss
	scale = hpx / span
	xy = np.empty_like(tris)
	xy[:, :, 0] = wpx * 0.5 + tris[:, :, 0] * scale
	xy[:, :, 1] = hpx * 0.5 - (tris[:, :, 1] - centre_y) * scale
	im = Image.new("RGB", (wpx, hpx), KEY)
	d = ImageDraw.Draw(im)
	for k in order:
		p = xy[k]
		d.polygon([(p[0, 0], p[0, 1]), (p[1, 0], p[1, 1]), (p[2, 0], p[2, 1])], fill=tuple(int(c) for c in cols[k]))
	return im.resize(size, Image.LANCZOS)


def main():
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	variant = ([a.split("=")[1] for a in sys.argv[1:] if a.startswith("--design=")] + ["aurora"])[0]
	prefix = args[0]
	parts = load_glb(args[1] if len(args) > 1 else "art/models/aurora/aurora.glb")
	parts.update(load_glb(DESIGNS_GLB))
	# As PatchModel._load_parts: Pixel's heart lenses (its "glow" surfaces) are their own part.
	piv, prims = parts["acc_pixel"]
	parts["acc_pixel_hearts"] = (piv, [q for q in prims if q[0] == "glow"])
	parts["acc_pixel"] = (piv, [q for q in prims if q[0] != "glow"])
	pose = ([a.split("=")[1] for a in sys.argv[1:] if a.startswith("--pose=")] + [""])[0]
	placed = posed(parts, variant, pose)
	for i, (yaw, elev, head_yaw) in enumerate(turn_views()):
		render(parts, placed, yaw, elev, head_yaw).save("%s_%d.png" % (prefix, i))
	print("tris", sum(len(idx) for (m, name) in placed for (_m, _pos, idx) in parts[name][1]))


if __name__ == "__main__":
	main()
