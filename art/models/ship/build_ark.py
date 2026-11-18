# Builds the ark *Cradle* in the Seedglider design language and exports art/models/ship/ark.glb plus
# ark_points.json for story/cradle_ship.gd.
#   blender -b --python art/models/ship/build_ark.py        (PREVIEW=/path/prefix for Cycles stills)
# Reuses the modelling helpers of build_ship.py (same materials, bevels, seams, baked vertex colours)
# so the mothership reads as the big sister of Lumi's glider: a faceted manta hull with layered
# plates, huge swept wings with drooping tip fins, a faceted cyan bridge canopy with Lumi's C eyes on
# the nose sensor, a glass seed-vault greenhouse at its heart, a fold ring, a twin-pair engine
# block, and a keel with the escape-pod rack underneath. Godot coordinates (Y up); the ark flies
# toward -Z (CradleShip's frame). About 40 m long and 50 m across the wings.
import os
import math
import json

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "build_ship.py")).read()
# Helpers only (everything before the glider's hull), then the GLB writer.
exec(_src.split("# ---------------------------------------------------------------- HULL")[0])
import ast as _ast
import struct
for _n in _ast.parse(_src).body:
	if isinstance(_n, _ast.FunctionDef) and _n.name in ("catmull", "nacelle", "curvature", "write_glb"):
		exec(_ast.get_source_segment(_src, _n))

OUT = os.path.join(HERE, "ark.glb")
OUT_PTS = os.path.join(HERE, "ark_points.json")
PTS = {"nozzles": [], "spine": [], "flank": [], "lamps": []}

# Must match story/cradle_ship.gd.
DOME_AT = Vector((0, 6.3, -4.5))
DOME_R = 4.4
POD_Y, POD_Z0, POD_DZ = -7.05, -8.5, 2.7

# Stations: (z, half-width, top, chine, bottom); nose at -Z.
AST = [(-21.5, 0.5, 0.7, 0.1, -0.5), (-19.5, 2.6, 2.0, 0.2, -1.5), (-16.0, 5.0, 3.6, 0.3, -2.7),
	(-10.0, 7.2, 4.8, 0.4, -3.6), (-4.0, 8.4, 5.3, 0.4, -4.0), (2.0, 8.6, 5.3, 0.4, -4.0),
	(8.0, 8.1, 4.8, 0.4, -3.7), (13.0, 6.9, 4.0, 0.4, -3.1), (17.0, 5.6, 3.3, 0.4, -2.6)]


def ast(z):
	zs = [s[0] for s in AST]
	z = min(max(z, zs[0]), zs[-1])
	k = 0
	while k < len(zs) - 2 and z > zs[k + 1]:
		k += 1
	t = k + (z - zs[k]) / (zs[k + 1] - zs[k])
	return tuple(catmull([s[j] for s in AST], t) for j in range(1, 5))


def asec(z, grow=0.0):
	w, yt, yc, yb = ast(z)
	w += grow
	yt += grow
	yb -= grow
	right = [(0.0, yt), (0.42 * w, yt - 0.18), (0.84 * w, yc + 0.95), (w, yc), (0.8 * w, yb + 0.6), (0.0, yb)]
	left = [(-x, y) for (x, y) in reversed(right[1:-1])]
	return [(x, y, z) for (x, y) in right + left]


def atop(x, z):
	w, yt, yc, yb = ast(z)
	ax = abs(x)
	if ax <= 0.42 * w:
		return yt - 0.18 * ax / (0.42 * w + 1e-6)
	if ax <= 0.84 * w:
		u = (ax - 0.42 * w) / (0.42 * w)
		return (yt - 0.18) * (1 - u) + (yc + 0.95) * u
	u = (ax - 0.84 * w) / (0.16 * w)
	return (yc + 0.95) * (1 - u) + yc * u


def aplate(name, z0, z1, idx, off, material, n=12):
	def outward(z, i, d):
		w, yt, yc, yb = ast(z)
		p = Vector(asec(z)[i])
		c = Vector((0, (yt + yb) * 0.5, z))
		v = p - c
		v.z = 0
		return p + v.normalized() * d
	bm = bmesh.new()
	O = [[bm.verts.new(outward(z0 + (z1 - z0) * k / n, i, off)) for i in idx] for k in range(n + 1)]
	I = [[bm.verts.new(outward(z0 + (z1 - z0) * k / n, i, -0.05)) for i in idx] for k in range(n + 1)]
	m = len(idx)
	for k in range(n):
		for i in range(m - 1):
			bm.faces.new((O[k][i], O[k][i + 1], O[k + 1][i + 1], O[k + 1][i]))
			bm.faces.new((I[k][i], I[k + 1][i], I[k + 1][i + 1], I[k][i + 1]))
		bm.faces.new((O[k][0], O[k + 1][0], I[k + 1][0], I[k][0]))
		bm.faces.new((O[k][m - 1], I[k][m - 1], I[k + 1][m - 1], O[k + 1][m - 1]))
	bm.faces.new([O[0][i] for i in range(m)] + [I[0][i] for i in reversed(range(m))])
	bm.faces.new([O[n][i] for i in reversed(range(m))] + [I[n][i] for i in range(m)])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	o = from_bm(bm, name, material)
	tri_fill(o)
	return finish(o, 0.06, angle=25)


def aring_cut(target, z, depth=0.08, width=0.07):
	outer = loft("gr_o", [asec(z - width, 0.3), asec(z + width, 0.3)], "trim")
	inner = loft("gr_i", [asec(z - width * 2, -depth), asec(z + width * 2, -depth)], "trim")
	boolean(outer, inner)
	return boolean(target, outer)


# ---------------------------------------------------------------- HULL
hull = loft("ark_hull", [asec(-21.5 + 38.5 * i / 40) for i in range(41)], "paint")
tri_fill(hull)
finish(hull, 0.08, angle=24)
for z in (-13.0, -7.5, 6.0, 11.5):
	aring_cut(hull, z)
# Bay opening under the belly (the Homecoming ship docks here) and side vent slots.
boolean(hull, box("bay_cut", (4.2, 2.0, 5.0), (0, -4.0, 0.5), "trim", 0.2))
for sx in (1, -1):
	boolean(hull, box("vent", (2.2, 0.6, 4.0), (sx * 8.2, 1.6, 7.5), "trim", 0.1))
bits = [hull]
bits.append(aplate("pl_dorsal_f", -18.0, -9.5, [8, 9, 0, 1, 2], 0.14, "panel"))
bits.append(aplate("pl_dorsal_r", 0.5, 15.0, [8, 9, 0, 1, 2], 0.14, "panel"))
bits.append(aplate("pl_sh_r", -15.0, 12.0, [2, 3], 0.1, "paint", n=20))
bits.append(aplate("pl_sh_l", -15.0, 12.0, [7, 8], 0.1, "paint", n=20))
bits.append(aplate("pl_belly", -16.0, 14.0, [4, 5, 6], 0.1, "panel", n=20))
bits.append(aplate("pl_nose", -20.4, -19.2, [8, 9, 0, 1, 2], 0.06, "accent", n=3))
# Bay rim light and hangar glow, vent grilles.
bits.append(box("bay_floor", (3.8, 0.1, 4.6), (0, -3.3, 0.5), "dark", 0.0))
for (a, b) in (((-2.1, -4.05, -2.0), (2.1, -4.05, -2.0)), ((-2.1, -4.05, 3.0), (2.1, -4.05, 3.0)),
		((-2.1, -4.05, -2.0), (-2.1, -4.05, 3.0)), ((2.1, -4.05, -2.0), (2.1, -4.05, 3.0))):
	bits.append(rod("bay_gl", a, b, 0.04, "glow", verts=5))
for sx in (1, -1):
	for k in range(8):
		bits.append(box("vane", (1.6, 0.05, 0.12), (sx * 8.1, 1.6, 5.8 + k * 0.48), "steel", 0.0))
	# Chine light line and flank running-light rows.
	pts = [(sx * (ast(z)[0] + 0.03), ast(z)[2], z) for z in range(-18, 17, 3)]
	for i in range(len(pts) - 1):
		bits.append(rod("chl", pts[i], pts[i + 1], 0.035, "glow", verts=5))
	for z in range(-17, 16, 2):
		PTS["flank"].append([sx * (ast(z)[0] * 0.92), ast(z)[2] + 0.75, z])
	for z in (-19.0, 16.6):
		bits.append(lamp("nav", (sx * ast(z)[0] * 0.8, ast(z)[2] + 0.4, z), 0.16))
for z in range(-17, 16, 2):
	if abs(z - DOME_AT.z) > DOME_R + 1.2:
		PTS["spine"].append([0.0, atop(0, z) + 0.2, z])
# Antenna mast and sensor domes on the back.
bits.append(rod("mast", (0, atop(0, 12.0) + 0.1, 12.0), (0, atop(0, 12.0) + 3.2, 13.0), 0.06, "steel"))
for sx in (1, -1):
	bits.append(cyl("sdome", 0.6, 0.5, (sx * 2.6, atop(2.6, 9.0) + 0.15, 9.0), "glass", axis='Y', verts=16, r2=0.35))
parts = {"ark_hull": join("ark_hull", bits)}

# ---------------------------------------------------------------- BRIDGE CANOPY + C-EYE SENSOR
seg = 6
rings = []
for i in range(seg + 1):
	u = i / seg
	z = -17.0 + 6.5 * u
	w = max(0.2, 2.6 * math.sin(math.pi * min(1.0, 0.12 + u * 0.95)) ** 0.6)
	hh = max(0.05, 1.3 * math.sin(math.pi * min(1.0, 0.1 + u * 0.92)) ** 0.8)
	top = atop(0, z)
	base = atop(w, z) - 0.1
	rings.append([(w, base, z), (w * 0.72, top + hh * 0.62, z), (w * 0.3, top + hh, z), (-w * 0.3, top + hh, z), (-w * 0.72, top + hh * 0.62, z), (-w, base, z)])
g = loft("ark_canopy_glass", rings, "glass")
finish(g, 0.0, smooth_angle=8)
cbits = [g]
for j in (1, 4):
	for i in range(seg):
		cbits.append(rod("cfb", rings[i][j], rings[i + 1][j], 0.07, "paint", verts=6))
for i in (2, 4):
	for j in range(5):
		cbits.append(rod("cfx", rings[i][j], rings[i][j + 1], 0.07, "paint", verts=6))
# Nose sensor bezel (the C eyes are drawn at runtime facing -Z).
cbits.append(box("eye_bezel", (2.6, 0.75, 0.25), (0, 0.45, -21.25), "dark", 0.12, rot=(14, 0, 0)))
PTS["eyes"] = [0.0, 0.45, -21.39]
parts["ark_canopy"] = join("ark_canopy", cbits)

# ---------------------------------------------------------------- WINGS
AW = [(7.0, -11.0), (12.0, -6.0), (22.5, 4.0), (24.5, 5.5), (25.0, 8.6), (23.5, 9.6), (17.5, 9.0), (14.0, 11.8), (8.0, 13.0)]


def awt(x, z):
	t = max(0.35, 1.3 - 0.05 * (x - 7.0))
	y = 0.4 - (x - 7.0) * 0.06
	return (y - t * 0.45, y + t * 0.55)


def build_wings():
	wb = []
	w = prism_y("awing", AW, 0, 0, "paint", thick_fn=awt)
	tri_fill(w)
	finish(w, 0.08, angle=25)
	wb.append(w)
	plate = [(9.0, -7.5), (12.5, -4.2), (20.0, 3.5), (20.0, 8.2), (15.0, 8.0), (12.0, 10.6), (9.0, 11.0)]
	p = prism_y("awplate", plate, 0, 0, "panel", thick_fn=lambda x, z: (awt(x, z)[1] - 0.06, awt(x, z)[1] + 0.09))
	tri_fill(p)
	wb.append(finish(p, 0.04))
	tip = [(21.0, 2.6), (22.5, 4.0), (24.5, 5.5), (25.0, 8.6), (23.5, 9.6), (21.0, 9.2)]
	t = prism_y("awtip", tip, 0, 0, "accent", thick_fn=lambda x, z: (awt(x, z)[0] - 0.03, awt(x, z)[1] + 0.03))
	tri_fill(t)
	wb.append(finish(t, 0.03))
	for i in range(3):
		a = (7.6 + (21.8 - 7.6) * i / 3, None, None)
	le = [(7.6 + (22.0 - 7.6) * u, -10.4 + (3.6 + 10.4) * u) for u in (0.0, 0.33, 0.66, 1.0)]
	for i in range(3):
		a = (le[i][0], awt(*le[i])[1] + 0.02, le[i][1] + 0.6)
		b = (le[i + 1][0], awt(*le[i + 1])[1] + 0.02, le[i + 1][1] + 0.6)
		wb.append(rod("awle", a, b, 0.035, "glow", verts=5))
	te = [(8.5, 12.6), (14.0, 11.5), (17.5, 8.7), (23.4, 9.3)]
	for i in range(3):
		a = (te[i][0], awt(*te[i])[1] + 0.02, te[i][1] - 0.4)
		b = (te[i + 1][0], awt(*te[i + 1])[1] + 0.02, te[i + 1][1] - 0.4)
		wb.append(rod("awte", a, b, 0.03, "glow", verts=5))
	wb.append(lamp("awlamp", (24.8, awt(24.8, 8.0)[1] + 0.05, 8.0), 0.18))
	# Drooping tip fin.
	fin = [(0.0, 4.6), (2.0, 5.2), (4.6, 7.8), (4.2, 9.6), (2.6, 9.8), (0.0, 9.0)]
	f = prism_y("afin", fin, 0, 0, "paint", thick_fn=lambda x, z: (-0.18, 0.18))
	tri_fill(f)
	finish(f, 0.05)
	f.data.transform(Matrix.Translation((24.6, awt(24.6, 7.0)[1] - 0.2, 0)) @ Matrix.Rotation(math.radians(-55), 4, 'Z'))
	wb.append(f)
	ft = prism_y("afint", [(3.0, 6.6), (4.6, 7.8), (4.2, 9.6), (3.2, 9.7)], 0, 0, "accent", thick_fn=lambda x, z: (-0.2, 0.2))
	tri_fill(ft)
	ft.data.transform(Matrix.Translation((24.6, awt(24.6, 7.0)[1] - 0.2, 0)) @ Matrix.Rotation(math.radians(-55), 4, 'Z'))
	wb.append(ft)
	o = join("ark_wings", wb)
	return join("ark_wings", [o, mirror(o)])


parts["ark_wings"] = build_wings()

# ---------------------------------------------------------------- SEED VAULT (glass greenhouse)
n_a, n_b = 12, 4
base_y = atop(0, DOME_AT.z) - 0.2
vb = []
bm = bmesh.new()
rows = []
for j in range(n_b + 1):
	el = (math.pi * 0.5) * j / n_b
	row = []
	for i in range(n_a):
		a = 2 * math.pi * (i + 0.5 * (j % 2)) / n_a
		r = DOME_R * math.cos(el) if j < n_b else 0.0
		row.append(bm.verts.new((DOME_AT.x + math.cos(a) * r, base_y + math.sin(el) * DOME_R * 0.82, DOME_AT.z + math.sin(a) * r * 1.25)))
	rows.append(row)
for j in range(n_b):
	for i in range(n_a):
		a0, a1 = rows[j][i], rows[j][(i + 1) % n_a]
		b0, b1 = rows[j + 1][i], rows[j + 1][(i + 1) % n_a]
		if j < n_b - 1:
			bm.faces.new((a0, a1, b1, b0)) if j % 2 == 0 else bm.faces.new((a0, a1, b1, b0))
		else:
			bm.faces.new((a0, a1, b0))
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
dome = from_bm(bm, "ark_vault_glass", "vault_glass")
finish(dome, 0.0, smooth_angle=5)
# Frame ribs along the facet edges and a pearl sill with a tangerine band.
fr = []
me = dome.data
for e in me.edges:
	a = me.vertices[e.vertices[0]].co
	b = me.vertices[e.vertices[1]].co
	if (a - b).length > 0.05:
		fr.append(rod("rib", tuple(a), tuple(b), 0.07, "paint", verts=6))
sill = loft("vsill", [[(DOME_AT.x + math.cos(2 * math.pi * i / 32) * (DOME_R + 0.5 + dr), base_y + dy, DOME_AT.z + math.sin(2 * math.pi * i / 32) * (DOME_R + 0.5 + dr) * 1.25) for i in range(32)] for (dr, dy) in ((0.0, -0.6), (0.0, 0.1))], "paint")
fr.append(finish(sill, 0.04))
band = loft("vband", [[(DOME_AT.x + math.cos(2 * math.pi * i / 32) * (DOME_R + 0.53), base_y + dy, DOME_AT.z + math.sin(2 * math.pi * i / 32) * (DOME_R + 0.53) * 1.25) for i in range(32)] for dy in (-0.35, -0.15)], "accent")
fr.append(finish(band))
for i in range(32):
	a0, a1 = 2 * math.pi * i / 32, 2 * math.pi * (i + 1) / 32
	fr.append(rod("vgl", (math.cos(a0) * (DOME_R + 0.55), base_y + 0.12, DOME_AT.z + math.sin(a0) * (DOME_R + 0.55) * 1.25),
		(math.cos(a1) * (DOME_R + 0.55), base_y + 0.12, DOME_AT.z + math.sin(a1) * (DOME_R + 0.55) * 1.25), 0.03, "glow", verts=4))
parts["ark_vault_glass"] = dome
parts["ark_vault_frame"] = join("ark_vault_frame", fr)
PTS["vault"] = [DOME_AT.x, base_y, DOME_AT.z, DOME_R]

# ---------------------------------------------------------------- ENGINES
eb = []
ENG = ((3.0, 1.5, 4.9), (-3.0, 1.5, 4.9), (9.6, 1.3, 1.7), (-9.6, 1.3, 1.7))
for (x, r, y) in ENG:
	nac = nacelle("ark_n", x, y, -14.0, -6.0, r, big=True)
	nac.data.transform(Matrix.Scale(-1, 4, Vector((0, 0, 1))))   # nacelle() builds nose +Z: flip to the ark's -Z
	nac.data.flip_normals()
	nac.data.transform(Matrix.Translation((0, 0, 4.0)))
	eb.append(nac)
POINTS["nozzles"].clear()
for (x, r, y) in ENG:
	PTS["nozzles"].append({"pos": [x, y, 18.23], "r": r * 0.62})
eb.append(cyl("core_cowl", 2.2, 2.2, (0, 2.6, 17.6), "panel", verts=8, r2=1.9, bevel=0.06))
eb.append(cyl("core_bell", 1.5, 1.2, (0, 2.6, 19.1), "trim", verts=16, r2=1.25))
eb.append(cyl("core_noz", 1.15, 0.05, (0, 2.6, 19.72), "thruster", verts=16))
eb.append(torus("core_ring", 2.15, 0.05, (0, 2.6, 18.6), "glow", major=8, minor=4))
PTS["nozzles"].append({"pos": [0.0, 2.6, 19.75], "r": 1.15})
parts["ark_engines"] = join("ark_engines", eb)

# ---------------------------------------------------------------- FOLD RING
nr = 16
cy, rx, ry = 0.6, 12.5, 8.4
z0, z1 = 8.6, 10.8


def rpt(i, grow, z):
	a = 2 * math.pi * (i + 0.5) / nr
	return (math.cos(a) * (rx + grow), cy + math.sin(a) * (ry + grow), z)


bm = bmesh.new()
O = [[bm.verts.new(rpt(i, 0.0, z)) for i in range(nr)] for z in (z0, z1)]
I = [[bm.verts.new(rpt(i, -0.8, z)) for i in range(nr)] for z in (z0, z1)]
for i in range(nr):
	j = (i + 1) % nr
	bm.faces.new((O[0][i], O[0][j], O[1][j], O[1][i]))
	bm.faces.new((I[0][i], I[1][i], I[1][j], I[0][j]))
	bm.faces.new((O[0][i], I[0][i], I[0][j], O[0][j]))
	bm.faces.new((O[1][i], O[1][j], I[1][j], I[1][i]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
hoop = from_bm(bm, "hoop", "paint")
finish(hoop, 0.07, angle=25)
rb = [hoop]
for i in range(nr):
	rb.append(rod("rgl", rpt(i, -0.82, (z0 + z1) * 0.5), rpt((i + 1) % nr, -0.82, (z0 + z1) * 0.5), 0.04, "glow", verts=4))
	if i % 4 == 1:
		a = 2 * math.pi * (i + 0.5) / nr
		rb.append(box("rnode", (1.0, 1.0, 2.6), rpt(i, 0.15, (z0 + z1) * 0.5), "accent", 0.15, rot=(0, 0, math.degrees(a))))
for (x, y) in ((5.0, 4.2), (-5.0, 4.2), (5.0, -2.8), (-5.0, -2.8)):
	a = math.atan2((y - cy) / ry, x / rx)
	end = (math.cos(a) * (rx - 0.5), cy + math.sin(a) * (ry - 0.5), (z0 + z1) * 0.5)
	rb.append(rod("rstrut", (x, y, (z0 + z1) * 0.5), end, 0.22, "steel", verts=8))
parts["ark_ring"] = join("ark_ring", rb)

# ---------------------------------------------------------------- KEEL + POD RACK
kb = []
for sx in (1, -1):
	kb.append(box("keel", (0.9, 2.4, 19.0), (sx * 2.3, -4.9, -1.75), "panel", 0.15))
	kb.append(rod("kgl", (sx * 2.3 - sx * 0.46, -5.6, -10.8), (sx * 2.3 - sx * 0.46, -5.6, 7.3), 0.035, "glow", verts=4))
	kb.append(lamp("klamp", (sx * 2.3, -6.15, -11.0), 0.12))
for k in range(6):
	z = POD_Z0 + k * POD_DZ
	kb.append(box("rack_beam", (4.2, 0.35, 0.5), (0, -5.95, z), "trim", 0.06))
	kb.append(box("rack_clamp", (0.9, 0.3, 0.9), (0, -5.75, z), "accent", 0.08))
parts["ark_keel"] = join("ark_keel", kb)

# ---------------------------------------------------------------- bake + export
objs = [o for o in bpy.data.objects if o.type == 'MESH']
for o in objs:
	attr = o.data.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
	o.data.color_attributes.active_color = attr
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = int(os.environ.get("AO_SAMPLES", "32"))
scene.cycles.device = 'CPU'
scene.render.bake.target = 'VERTEX_COLORS'
scene.world = bpy.data.worlds.new("w") if scene.world is None else scene.world
scene.world.light_settings.distance = 2.2
ao = {}
if not os.environ.get("NO_BAKE"):
	bpy.ops.object.select_all(action='DESELECT')
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	try:
		bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
		for o in objs:
			ao[o.name] = [d.color[0] for d in o.data.color_attributes["Col"].data]
		print("AO bake ok")
	except Exception as ex:
		print("AO bake failed:", ex)
for o in objs:
	cur = curvature(o)
	data = o.data.color_attributes["Col"].data
	a = ao.get(o.name)
	for i, d in enumerate(data):
		c = cur[i] * 6.0   # ~6x the glider's scale: rescale the curvature thresholds
		edge = min(max((-c - 0.03) * 5.0, 0.0), 1.0)
		cav = min(max((c - 0.02) * 6.0, 0.0), 1.0)
		d.color = (a[i] if a else 1.0, edge, cav, 1.0)
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
for o in objs:
	o.data.transform(TO_BLENDER)
	o.location = (0, 0, 0)
	o.data.use_auto_smooth = True
	print("part", o.name, len(o.data.vertices))
write_glb(OUT, sorted(objs, key=lambda o: o.name))
with open(OUT_PTS, "w") as f:
	json.dump(PTS, f, indent=1)
print("exported", OUT)

if os.environ.get("PREVIEW"):
	cols = {"paint": (0.86, 0.86, 0.84), "panel": (0.25, 0.26, 0.3), "trim": (0.07, 0.075, 0.085), "accent": (1.0, 0.42, 0.1),
		"dark": (0.02, 0.02, 0.025), "steel": (0.6, 0.6, 0.62), "glow": (0.3, 0.88, 1.0), "lamp": (1.0, 0.3, 0.1),
		"glass": (0.05, 0.45, 0.6), "thruster": (0.3, 0.9, 1.0), "vault_glass": (0.6, 0.85, 0.75)}
	for name, m in MATS.items():
		b = m.node_tree.nodes["Principled BSDF"]
		b.inputs["Base Color"].default_value = (*cols.get(name, (0.5, 0.5, 0.5)), 1)
		if name in ("glow", "lamp", "thruster"):
			b.inputs["Emission Color"].default_value = (*cols[name], 1)
			b.inputs["Emission Strength"].default_value = 5.0
	scene.cycles.samples = 16
	scene.cycles.use_denoising = False
	scene.render.resolution_x = 720
	scene.render.resolution_y = 480
	w = scene.world
	w.use_nodes = True
	w.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.06, 0.08, 1)
	sun = link(bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')))
	sun.data.energy = 3.5
	sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(-35))
	cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
	cam.data.lens = 40
	scene.camera = cam
	for k, (az, el, dist) in enumerate(((215, 22, 85), (160, -30, 80))):
		a = math.radians(az)
		target = Vector((0, 0, 0))
		pos = target + Vector((math.sin(a) * dist, -math.cos(a) * dist, math.tan(math.radians(el)) * dist))
		cam.location = pos
		cam.rotation_euler = (target - pos).to_track_quat('-Z', 'Y').to_euler()
		scene.render.filepath = "%s_%d.png" % (os.environ["PREVIEW"], k)
		bpy.ops.render.render(write_still=True)
