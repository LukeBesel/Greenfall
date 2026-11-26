# [art5] Lumi's short-hop shuttle: a used far-future VTOL working craft, built as modular parts.
#   blender -b --python art/models/shuttle/build_shuttle.py      (or: python3 art/models/shuttle/build_shuttle.py with bpy)
# Writes shuttle.glb, shuttle_points.json and shuttle_decals.png next to this file, for
# automation/ship_model.gd. Everything is code; only bmesh and mathutils are used (no scene, no
# bake), so Blender 4.0 and the 5.x module give the same file.
#
# Frame: Godot's (Y up, nose +Z, ground y = 0 with the gear down, metres).
# Parts keep the names automation/ship_tiers.gd asks for (parts_for): hull_rear, hull_front,
# hull_mid, wing, wing_ext, wing_big, canopy_a/b, eng_a/b/c/tip/core, skid_l/r, gear_n/l/r, pods,
# fins, ring, vault, rotor. Moving pieces of a part have their own pivot and are listed under
# "subs" in the points file:
#   <part>_foot    the gear's piston rods and foot pads (slide up as the gear takes the weight)
#   <part>_bell_N  an engine bell on its gimbal
# Material slots (ShipModel maps them; the Locker recolours paint / accent / glow):
#   paint  hull paint        panel  grey second paint      accent  the trim colour
#   patch  a mismatched replacement panel / riveted repair plate (primer)
#   tile   heat-shield tiles steel  bare alloy (A = heat tint)   trim  dark anodised metal
#   dark   rubber seals, pads, the cockpit tub             glass   glazing
#   lamp   beacons           glow   line lights            thruster  bell throats and duct nozzles
#   land   landing lamps     decal  painted marks and soot (UVs into shuttle_decals.png)
# Vertex colour: R = ambient occlusion, G = worn convex edge, B = seam / cavity,
#   A = grime (dirt from the ground up, soot behind nozzles) or, on steel, heat tint.
import bpy  # noqa: F401 (the module build needs it loaded before bmesh)
import bmesh
import json
import math
import os
import random
import struct
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "shuttle.glb")
OUT_PTS = os.path.join(HERE, "shuttle_points.json")
OUT_DECAL = os.path.join(HERE, "shuttle_decals.png")
random.seed(7)

MID = 2.2          # hull_mid length: Mk V+ moves the front parts forward by this
LIFT = 0.74        # belly line above the ground
MATS = ["paint", "panel", "accent", "patch", "tile", "steel", "trim", "dark", "glass", "lamp", "glow", "thruster", "land", "decal",
	"vault", "vault_glass", "leaf"]
MI = {n: i for i, n in enumerate(MATS)}
PARTS = {}         # name -> bmesh
PIVOT = {}         # name -> Vector (ship space)
SUBS = {}          # part -> its moving pieces (the glTF importer folds "__", so the map goes into the points file)


def base_of(name):
	for k, v in SUBS.items():
		if name in v:
			return k
	return name
POINTS = {"nozzles": [], "fans": [], "lamps": [], "mid": MID, "lift": LIFT, "strips": [], "landing": [], "marks": [], "feet": {}}


def part(name, pivot=None):
	if name not in PARTS:
		bm = bmesh.new()
		bm.verts.layers.float.new("cav")
		bm.verts.layers.float.new("heat")
		bm.verts.layers.float.new("hasheat")
		bm.loops.layers.uv.new("uv")
		PARTS[name] = bm
		if pivot is not None:
			PIVOT[name] = Vector(pivot)
	return PARTS[name]


def merge(dst, src, mat=None, M=None, heat=None):
	"""Copies src (a temp bmesh) into dst; mat overrides every face's material."""
	cav_s = src.verts.layers.float.get("cav")
	cav_d = dst.verts.layers.float["cav"]
	heat_d = dst.verts.layers.float["heat"]
	has_d = dst.verts.layers.float["hasheat"]
	vm = {}
	for v in src.verts:
		nv = dst.verts.new(M @ v.co if M else v.co)
		if cav_s:
			nv[cav_d] = v[cav_s]
		if heat is not None:
			nv[heat_d] = heat(nv.co) if callable(heat) else heat
			nv[has_d] = 1.0
		vm[v] = nv
	out = []
	for f in src.faces:
		try:
			nf = dst.faces.new([vm[v] for v in f.verts])
		except ValueError:
			continue
		nf.material_index = MI[mat] if mat else f.material_index
		out.append(nf)
	src.free()
	return out


def rot(ax, deg):
	return Matrix.Rotation(math.radians(deg), 4, ax)


def tr(x, y, z):
	return Matrix.Translation((x, y, z))


def aim(a, b):
	"""Matrix taking +Y to the direction a -> b, origin at a."""
	d = (Vector(b) - Vector(a)).normalized()
	return Matrix.Translation(Vector(a)) @ Vector((0, 1, 0)).rotation_difference(d).to_matrix().to_4x4()


def box(dst, size, center, mat, bevel=0.008, M=None, heat=None):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
	if bevel > 0:
		bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.4), segments=1, affect='EDGES')
	T = tr(*center)
	return merge(dst, bm, mat, (M @ T) if M else T, heat)


def lathe(dst, prof, mat, segs=20, M=None, heat=None, arc=(0.0, 360.0), close=False):
	"""Revolves prof [(r, y)...] about +Y. close joins the last profile point to the first."""
	bm = bmesh.new()
	full = abs(arc[1] - arc[0]) >= 359.9
	n = segs if full else segs + 1
	cols = []
	for k in range(n):
		a = math.radians(arc[0] + (arc[1] - arc[0]) * k / segs)
		cols.append([bm.verts.new((r * math.cos(a), y, r * math.sin(a))) for (r, y) in prof])
	m = len(prof)
	for k in range(n if full else n - 1):
		c0, c1 = cols[k], cols[(k + 1) % n]
		for i in range(m if close else m - 1):
			j = (i + 1) % m
			if prof[i][0] < 1e-6 and prof[j][0] < 1e-6:
				continue
			try:
				bm.faces.new((c0[i], c0[j], c1[j], c1[i]))
			except ValueError:
				pass
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return merge(dst, bm, mat, M, heat)


def tube(dst, a, b, r, mat, segs=10, r2=None, heat=None, caps=True):
	L = (Vector(b) - Vector(a)).length
	r2 = r if r2 is None else r2
	prof = ([(0, 0)] if caps else []) + [(r, 0), (r2, L)] + ([(0, L)] if caps else [])
	return lathe(dst, prof, mat, segs, aim(a, b), heat)


def loft(dst, rings, mat, cap0=True, cap1=True, closed=True, M=None):
	bm = bmesh.new()
	R = [[bm.verts.new(p) for p in ring] for ring in rings]
	n = len(rings[0])
	for k in range(len(R) - 1):
		for i in range(n if closed else n - 1):
			j = (i + 1) % n
			try:
				bm.faces.new((R[k][i], R[k][j], R[k + 1][j], R[k + 1][i]))
			except ValueError:
				pass
	if cap0:
		bm.faces.new(R[0])
	if cap1:
		bm.faces.new(list(reversed(R[-1])))
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return merge(dst, bm, mat, M)


def aim_faces(dst, faces, toward=None, away=None, along=None):
	"""Turns open surfaces the right way round (recalc cannot know): each face looks toward a
	point, away from one, or along a direction."""
	flip = []
	for f in faces:
		if not f.is_valid:
			continue
		f.normal_update()
		c = f.calc_center_median()
		d = (Vector(toward) - c) if toward is not None else ((c - Vector(away)) if away is not None else Vector(along))
		if f.normal.dot(d) < 0:
			flip.append(f)
	if flip:
		bmesh.ops.reverse_faces(dst, faces=flip)
	return faces


def setmat(faces, mat):
	for f in faces:
		f.material_index = MI[mat]


def rivets(dst, pts, normal, r=0.011, mat="steel"):
	n = Vector(normal).normalized()
	for p in pts:
		M = aim(Vector(p) - n * 0.002, Vector(p) + n)
		lathe(dst, [(r, 0), (r * 0.8, r * 0.55), (0, r * 0.7)], mat, 6, M)


# ---------------------------------------------------------------- fuselage (a seamed grid)
#        z      half-w  belly  chine  top
ST = [(-2.95, 0.60, 1.00, 1.24, 1.60), (-2.55, 0.80, 0.86, 1.18, 1.74), (-1.60, 0.94, 0.76, 1.12, 1.82),
	(0.00, 0.95, 0.74, 1.10, 1.84), (0.90, 0.91, 0.74, 1.10, 1.83), (1.50, 0.82, 0.75, 1.09, 1.78),
	(2.05, 0.66, 0.78, 1.07, 1.56), (2.50, 0.50, 0.82, 1.05, 1.36), (2.90, 0.33, 0.88, 1.03, 1.20), (3.18, 0.13, 0.95, 1.02, 1.09)]


def catmull(vals, t):
	n = len(vals)
	i = min(int(t), n - 2)
	u = t - i
	p0, p1, p2, p3 = vals[max(i - 1, 0)], vals[i], vals[i + 1], vals[min(i + 2, n - 1)]
	return 0.5 * (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)


def station(z):
	zs = [s[0] for s in ST]
	z = min(max(z, zs[0]), zs[-1])
	k = 0
	while k < len(zs) - 2 and z > zs[k + 1]:
		k += 1
	t = k + (z - zs[k]) / (zs[k + 1] - zs[k])
	return tuple(catmull([s[j] for s in ST], t) for j in range(1, 5))


def spow(v, e):
	return math.copysign(abs(v) ** e, v)


def hull_pt(a_deg, z, off=0.0, zs=None):
	"""Point on the hull skin at section angle a (-90 belly centre, 0 chine, 90 top centre, on to 270)."""
	w, yb, yc, yt = station(z if zs is None else zs)
	a = math.radians(a_deg)
	c, s = math.cos(a), math.sin(a)
	if s >= 0:
		x, y = w * spow(c, 2 / 2.7), yc + (yt - yc) * spow(s, 2 / 2.7)
	else:
		x, y = w * spow(c, 2 / 5.0), yc + (yc - yb) * spow(s, 2 / 5.0)
	p = Vector((x, y, z))
	if off != 0.0:
		ctr = Vector((0, yc + (yt - yc) * 0.25, z))
		p += (p - ctr).normalized() * off
	return p


def fold(a):
	"""Section angle folded to the right half (-90..90)."""
	a = (a + 90.0) % 360.0 - 90.0
	return a if a <= 90.0 else 180.0 - a


def triple(vals, seams, d):
	out = []
	for v in vals:
		if any(abs(v - s) < 1e-6 for s in seams):
			out += [(v - d, 0), (v, 1), (v + d, 0)]
		else:
			out.append((v, 0))
	return out


def skin(dst, zs, angs, seam_z, seam_a, mat_fn, keep_fn, seam_on=None, zfix=None, groove=0.006):
	"""The hull skin over rings zs x half-angles angs (mirrored). Seam rings / lines are three
	close rows with the middle one sunk and marked as a cavity where seam_on(z, a) allows.
	Returns {(i, j): face} with the ring / column values, for windows and doors."""
	Z = triple(sorted(set(zs) | set(seam_z)), seam_z, 0.007)
	A = triple(sorted(set(angs) | set(seam_a)), seam_a, 0.55)
	full = A + [(180.0 - a, s) for (a, s) in reversed(A[:-1])][:-1]   # around the ring, without the doubled ends
	cav = dst.verts.layers.float["cav"]
	grid = []
	for (z, sz) in Z:
		row = []
		for (a, sa) in full:
			on = (sz or sa) and (seam_on is None or seam_on(z, fold(a), bool(sz), bool(sa)))
			v = dst.verts.new(hull_pt(a, z, -groove if on else 0.0, zfix))
			v[cav] = 1.0 if on else 0.0
			row.append(v)
		grid.append(row)
	faces = {}
	n = len(full)
	for i in range(len(Z) - 1):
		for j in range(n):
			j2 = (j + 1) % n
			zc = (Z[i][0] + Z[i + 1][0]) * 0.5
			a0, a1 = full[j][0], full[j2][0] if j2 else full[j][0] + (full[1][0] - full[0][0])
			ac = fold((a0 + (a1 if j2 else 270.0)) * 0.5) if j2 else -90.0 + (full[1][0] + 90.0) * 0.5
			if j2 == 0:
				ac = fold((full[j][0] + 270.0) * 0.5)
			if not keep_fn(zc, ac):
				continue
			try:
				f = dst.faces.new((grid[i][j], grid[i][j2], grid[i + 1][j2], grid[i + 1][j]))
			except ValueError:
				continue
			f.material_index = MI[mat_fn(zc, ac)]
			f.normal_update()
			side = 1 if (full[j][0] + (a1 if j2 else 270.0)) * 0.5 < 90.0 else -1
			faces[(i, j)] = (f, zc, ac, side)
	for (f, zc, ac, sd) in faces.values():
		f.normal_update()
		c = f.calc_center_median()
		if f.normal.dot(c - Vector((0, 1.28, c.z))) < 0:
			f.normal_flip()
	return faces, grid


def region(faces, z0, z1, a0, a1, side=0):
	return [f for (f, zc, ac, sd) in faces.values() if z0 < zc < z1 and a0 < ac < a1 and (side == 0 or sd == side) and f.is_valid]


def window(dst, fs, frame=0.03, depth=0.035, gasket=0.012, glass="glass"):
	"""A pane with depth: a flat frame margin, a rubber gasket wall sunk into the skin, glass at the bottom."""
	if not fs:
		return
	bmesh.ops.inset_region(dst, faces=fs, thickness=frame, depth=0.0, use_even_offset=True, use_boundary=True)
	r = bmesh.ops.inset_region(dst, faces=fs, thickness=gasket, depth=-depth, use_even_offset=True, use_boundary=True)
	setmat(r["faces"], "dark")
	setmat(fs, glass)


def recess(dst, fs, gap=0.008, depth=0.012, mat=None):
	"""A door / access panel: a dark gap line round it, the panel a little below the skin."""
	if not fs:
		return
	r = bmesh.ops.inset_region(dst, faces=fs, thickness=gap, depth=-depth, use_even_offset=True, use_boundary=True)
	setmat(r["faces"], "dark")
	if mat:
		setmat(fs, mat)


ANG = [-90, -78, -66, -58, -44, -36, -22, -12, -4, 4, 12, 22, 30, 38, 46, 54, 62, 66, 74, 82, 90]
SEAM_A = [-52, -30, 22, 52]
CAN_Z0, CAN_Z1, CAN_A = 1.02, 2.44, 22.0


def hull_mat(z, a):
	if a < -52:
		return "tile"
	if z > 2.86:
		return "dark"      # the radome
	if a < -30:
		return "panel"
	if 4 < a < 12 and -2.5 < z < 0.9:
		return "accent"
	return "paint"


def in_canopy(z, a):
	return CAN_Z0 < z < CAN_Z1 and a > CAN_A


def seam_rule(z, a, on_ring, on_line):
	"""Which seams are cut: full frames at the main joints, partial ones elsewhere."""
	if on_line:
		if abs(a - 52) < 1 and z > 0.9:
			return False
		return True
	if abs(z + 1.2) < 0.02 or abs(z + 0.3) < 0.02:      # the hatch frames stop at the chine line
		return a > -52
	if abs(z - 0.45) < 0.02:
		return a < 22
	if abs(z + 2.2) < 0.02 or abs(z - 2.86) < 0.02 or abs(z) < 0.02:
		return True
	return a > -30


def build_hull():
	# rear: z -2.95 .. 0
	hr = part("hull_rear")
	zs = [-2.95, -2.75, -2.55, -1.9, -1.6, -1.0, -0.86, -0.64, -0.5, -0.15, 0.0]
	f, g = skin(hr, zs, ANG, [-2.2, -1.2, -0.3], SEAM_A, hull_mat, lambda z, a: True, seam_rule)
	# the side hatch (both sides): a recessed door with a porthole; the left one is a mismatched replacement
	for sd in (1, -1):
		door = region(f, -1.2, -0.3, -30, 52, sd)
		recess(hr, door, 0.009, 0.012, "patch" if sd < 0 else None)
		window(hr, region(f, -0.86, -0.64, 22, 46, sd), 0.02, 0.03, 0.012)
		x = sd * 0.955
		box(hr, (0.03, 0.05, 0.16), (x, 1.2, -0.45), "steel", 0.006)      # the handle bar in its recess
		box(hr, (0.012, 0.11, 0.24), (x - sd * 0.008, 1.2, -0.45), "dark", 0.004)
		for zz in (-1.12, -0.38):                                       # hinge blocks on the roof edge
			box(hr, (0.07, 0.035, 0.1), (sd * 0.62, 1.79, zz), "steel", 0.008, heat=0.0)
	# rear bulkhead: a sunk dark engine wall
	ring = [hull_pt(a, -2.95) for a in range(-90, 270, 12)]
	ring2 = [Vector((p.x * 0.86, 1.3 + (p.y - 1.3) * 0.86, -2.9)) for p in ring]
	aim_faces(hr, loft(hr, [ring, ring2], "trim", cap0=False, cap1=False), along=(0, 0, -1))
	bm_ = bmesh.new()
	bm_.faces.new([bm_.verts.new(p) for p in ring2])
	aim_faces(hr, merge(hr, bm_, "trim"), along=(0, 0, -1))
	# dorsal fin with a beacon, a blade antenna and a whip
	fin = [(-2.75, 1.66), (-1.25, 1.8), (-1.7, 2.16), (-2.45, 2.42), (-2.8, 2.4)]
	loft(hr, [[Vector((0.035 * (1 if k == 0 else -1) * t, y, z)) for (z, y), t in zip(fin, (1, 1, 0.6, 0.45, 0.6))] for k in (0, 1)], "paint")
	loft(hr, [[Vector((s * 0.03, y, z)) for (z, y) in [(-2.45, 2.42), (-2.8, 2.4), (-2.74, 2.3), (-2.36, 2.3)]] for s in (1.25, -1.25)], "accent")
	lathe(hr, [(0.03, 0), (0.03, 0.03), (0.0, 0.05)], "lamp", 8, tr(0, 2.41, -2.6))
	POINTS["lamps"].append({"pos": [0, 2.44, -2.6], "kind": "lamp"})
	tube(hr, (0, 1.82, -0.75), (0, 2.5, -0.95), 0.006, "trim", 5)
	loft(hr, [[Vector((s, y, z)) for (z, y) in [(-1.7, 1.81), (-1.45, 1.82), (-1.62, 2.0), (-1.72, 2.0)]] for s in (0.012, -0.012)], "trim")
	# roof vent grille and a riveted repair plate
	grille(hr, Vector((0.0, 1.835, -2.0)), Vector((0, 1, 0)), Vector((0, 0, 1)), 0.36, 0.3, 6)
	for sd in (1, -1):
		grille(hr, hull_pt(34 if sd > 0 else 146, -2.38, 0.0), None, None, 0.3, 0.2, 5, at=(34 if sd > 0 else 146, -2.38))
	patch_plate(hr, 150, -1.75, 0.32, 0.26)
	patch_plate(hr, -40, -2.05, 0.26, 0.2)
	rcs(hr, 62, -2.62)
	rcs(hr, 118, -2.62)
	# front: z 0 .. 3.18 with the canopy opening
	hf = part("hull_front")
	zs = [0.0, 0.2, 0.75, CAN_Z0, 1.2, 1.5, 1.75, 2.05, 2.25, CAN_Z1, 2.62, 2.74, 3.0, 3.1, 3.18]
	f, g = skin(hf, zs, ANG, [0.45, 2.86], SEAM_A, hull_mat, lambda z, a: not in_canopy(z, a), seam_rule)
	cap = hf.faces.new([v for v in g[-1]])
	cap.material_index = MI["dark"]
	aim_faces(hf, [cap], along=(0, 0, 1))
	sill(hf, "dark")
	recess(hf, region(f, 0.45, 0.75, -30, 22, 1), 0.007, 0.01, "panel")       # a service door, right side
	recess(hf, region(f, 2.62, 2.74, 30, 90, 0), 0.006, 0.02, "trim")          # the sensor bar across the nose
	cockpit(hf)
	patch_plate(hf, 14, 1.25, 0.34, 0.24)
	rcs(hf, 20, 2.66)
	rcs(hf, 160, 2.66)
	for sd in (1, -1):   # pitot probes
		p = hull_pt(40 if sd > 0 else 140, 2.8)
		tube(hf, p, p + Vector((sd * 0.05, 0.02, 0.2)), 0.007, "steel", 5)
	POINTS["sensor"] = {"pos": [0, hull_pt(90, 2.68).y - 0.012, 2.68], "pitch": math.degrees(math.atan2(station(2.56)[3] - station(2.8)[3], 0.24))}
	# mid: a constant section, z 0 .. MID
	hm = part("hull_mid")
	zs = [0.0, 0.3, 0.7, 1.5, 1.9, MID]
	f, g = skin(hm, zs, ANG, [1.1], SEAM_A, lambda z, a: hull_mat(0.0 if a > -52 else z, a), lambda z, a: True, lambda z, a, r, l: True, zfix=0.0)
	for sd in (1, -1):
		for zz in (0.5, 1.7):
			window(hm, region(f, zz - 0.2, zz + 0.2, 22, 46, sd), 0.02, 0.03, 0.012)
	patch_plate(hm, 160, 1.0, 0.3, 0.3)


def sill(dst, mat, depth=0.06):
	"""Gives an open edge thickness: its boundary is drawn inward."""
	es = [e for e in dst.edges if e.is_boundary and all(CAN_Z0 - 0.02 < v.co.z < CAN_Z1 + 0.02 and v.co.y > 1.15 for v in e.verts)]
	r = bmesh.ops.extrude_edge_only(dst, edges=es)
	vs = [v for v in r["geom"] if isinstance(v, bmesh.types.BMVert)]
	for v in vs:
		w, yb, yc, yt = station(v.co.z)
		v.co += (Vector((0, yc + 0.15, v.co.z)) - v.co).normalized() * depth
	setmat([f for f in r["geom"] if isinstance(f, bmesh.types.BMFace)], mat)


def cockpit(dst):
	"""The tub seen through the glass: dark liner, a seat, a console with lit panels."""
	y0 = 1.16
	rings = []
	for z in (CAN_Z0 - 0.1, 1.5, 2.0, CAN_Z1 + 0.06):
		pr, pl = hull_pt(19, z, -0.05), hull_pt(161, z, -0.05)
		w = hull_pt(0, z).x - 0.1
		rings.append([pl, Vector((-w, y0, z)), Vector((w, y0, z)), pr])
	fs = loft(dst, rings, "dark", cap0=False, cap1=False, closed=False)
	for k in (0, -1):
		f_ = dst.faces.new([dst.verts.new(p) for p in rings[k]])
		f_.material_index = MI["dark"]
		fs.append(f_)
	aim_faces(dst, fs, toward=(0, y0 + 0.3, 1.7))
	box(dst, (0.42, 0.12, 0.42), (0, y0 + 0.06, 1.5), "dark", 0.03)                 # seat pan
	box(dst, (0.42, 0.5, 0.1), (0, y0 + 0.3, 1.26), "dark", 0.03)                   # seat back
	box(dst, (0.3, 0.14, 0.06), (0, y0 + 0.5, 1.24), "trim", 0.02)                  # head rest
	cw = hull_pt(0, 2.12).x * 2 - 0.3
	box(dst, (cw, 0.2, 0.2), (0, y0 + 0.1, 2.1), "trim", 0.03)                      # console
	for x in (-0.3, 0.0, 0.3):
		box(dst, (cw * 0.26, 0.012, 0.11), (x * cw, y0 + 0.205, 2.08), "glow", 0.0)
	tube(dst, (0.0, y0, 1.86), (0.0, y0 + 0.2, 1.84), 0.014, "steel", 6)            # the stick


def canopy(name, long_glass):
	hx, hy, hz = 0.0, station(CAN_Z0)[3] - 0.02, CAN_Z0 + 0.02
	c = part(name, (hx, hy, hz))
	zs = [CAN_Z0, 1.2, 1.36, 1.5, 1.75, 2.05, 2.25, 2.34, CAN_Z1]
	f, g = skin(c, zs, ANG, [], [], lambda z, a: "paint", lambda z, a: in_canopy(z, a), None)
	sill(c, "dark", 0.05)
	if long_glass:   # Mk III+: one wide screen each side and a roof eyebrow
		window(c, region(f, 1.5, 2.34, 66, 90, 0), 0.03, 0.035)
		for sd in (1, -1):
			window(c, region(f, 1.36, 2.34, 30, 62, sd), 0.03, 0.035)
		window(c, region(f, 1.2, 1.36, 66, 90, 0), 0.025, 0.03)
		lathe(c, [(0.11, 0), (0.1, 0.05), (0.05, 0.085), (0, 0.09)], "panel", 12, tr(0, station(1.1)[3] - 0.012, 1.11))   # a sensor dome
	else:            # Mk I-II: three framed panes
		window(c, region(f, 1.5, 2.25, 66, 90, 0), 0.035, 0.035)
		for sd in (1, -1):
			window(c, region(f, 1.5, 2.25, 38, 62, sd), 0.035, 0.035)
	for sd in (1, -1):   # hinge knuckles at the rear edge, a latch at the front
		tube(c, (sd * 0.3 - 0.05, hy + 0.012, hz - 0.01), (sd * 0.3 + 0.05, hy + 0.012, hz - 0.01), 0.022, "steel", 8)
		box(c, (0.06, 0.02, 0.05), hull_pt(90 - sd * 50, CAN_Z1 - 0.06, 0.008), "steel", 0.005)
	# wiper arm on the centre pane (hand-repaired craft keep theirs)
	p0 = hull_pt(90, 2.3, 0.012)
	tube(c, p0, hull_pt(80, 1.85, 0.03), 0.006, "trim", 5)
	POINTS["canopy_hinge_b" if long_glass else "canopy_hinge_a"] = [hx, hy, hz]


def grille(dst, c, n, u, w, h, slats, at=None):
	"""A vent: a dark recess with slats in a frame. `at` = (angle, z) puts it on the hull skin."""
	if at is not None:
		c = hull_pt(at[0], at[1])
		n = (hull_pt(at[0], at[1], 0.1) - c).normalized()
		u = Vector((0, 0, 1))
	n, u = Vector(n).normalized(), Vector(u).normalized()
	v = n.cross(u).normalized()
	M = Matrix((u, v, n)).transposed().to_4x4()
	M.translation = Vector(c) - n * 0.01
	box(dst, (w, h, 0.02), (0, 0, 0.0), "dark", 0.0, M)
	for k in (-1, 1):
		box(dst, (w + 0.03, 0.022, 0.036), (0, k * (h * 0.5 + 0.004), 0.008), "trim", 0.005, M)
		box(dst, (0.022, h + 0.03, 0.036), (k * (w * 0.5 + 0.004), 0, 0.008), "trim", 0.005, M)
	for i in range(slats):
		y = -h * 0.5 + h * (i + 0.5) / slats
		box(dst, (w, h / slats * 0.5, 0.012), (0, y, 0.014), "trim", 0.0, M @ tr(0, y, 0.014) @ rot('X', 28) @ tr(0, -y, -0.014))


def patch_plate(dst, a, z, w, h):
	"""A hand-fitted repair plate riveted over the skin, in mismatched primer."""
	n = 5
	da = math.degrees(h / 0.9)
	rows = []
	for i in range(n + 1):
		zz = z - w * 0.5 + w * i / n
		rows.append([hull_pt(a - da * 0.5 + da * j / 3, zz, 0.007) for j in range(4)])
	bm = bmesh.new()
	V = [[bm.verts.new(p) for p in r] for r in rows]
	for i in range(n):
		for j in range(3):
			bm.faces.new((V[i][j], V[i][j + 1], V[i + 1][j + 1], V[i + 1][j]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	ctr = hull_pt(a, z)
	if bm.faces[0].normal.dot(ctr - Vector((0, 1.3, z))) < 0:
		bmesh.ops.reverse_faces(bm, faces=bm.faces)
	r = bmesh.ops.extrude_edge_only(bm, edges=[e for e in bm.edges if e.is_boundary])
	for v in r["geom"]:
		if isinstance(v, bmesh.types.BMVert):
			v.co += (Vector((0, 1.3, v.co.z)) - v.co).normalized() * 0.012
	merge(dst, bm, "patch")
	pts = []
	for i in range(n + 1):
		for j in (0, 3):
			pts.append(rows[i][j].lerp(rows[i][1 if j == 0 else 2], 0.18))
	for j in (1, 2):
		for i in (0, n):
			pts.append(rows[i][j].lerp(rows[1 if i == 0 else n - 1][j], 0.3))
	rivets(dst, pts, ctr - Vector((0, 1.3, z)))


def rcs(dst, a, z):
	"""A cluster of small attitude-jet ports: dark throats in a steel block, heat-stained."""
	c = hull_pt(a, z)
	n = (hull_pt(a, z, 0.1) - c).normalized()
	M = aim(c - n * 0.02, c + n)
	box(dst, (0.17, 0.035, 0.09), (0, 0.012, 0), "steel", 0.008, M, heat=0.26)
	for k in (-1, 0, 1):
		lathe(dst, [(0.022, 0.03), (0.019, 0.034), (0.016, 0.008), (0, 0.008)], "dark", 8, M @ tr(k * 0.052, 0, 0))


# ---------------------------------------------------------------- wings with lift ducts
DUCT = Vector((1.72, 1.02, -0.95))
DUCT_R = 0.4


def wing_sec(x, k_tip=1.0):
	"""(z_le, z_te, y_mid, thickness) of the stub wing at span x."""
	t = min(max((x - 0.8) / (3.2 - 0.8), 0.0), 1.0)
	return (0.45 - 1.25 * t, -2.35 + 0.15 * t, 1.06 - 0.1 * t, 0.26 - 0.15 * t)


def airfoil(x, sec=None):
	zl, zt, ym, th = sec or wing_sec(x)
	c = zl - zt
	pts = []
	prof = [(0.0, 0.0), (0.012, 0.42), (0.06, 0.8), (0.18, 1.0), (0.45, 0.95), (0.75, 0.6), (1.0, 0.12)]
	for (u, h) in prof:            # upper, leading edge -> trailing edge
		pts.append(Vector((x, ym + th * 0.5 * h, zl - c * u)))
	for (u, h) in reversed(prof[1:]):   # lower, back to the leading edge
		pts.append(Vector((x, ym - th * 0.5 * h * 0.85, zl - c * u)))
	return pts


def wing_faces_mat(fs):
	for f in fs:
		n = f.normal
		c = f.calc_center_median()
		zl = wing_sec(abs(c.x))[0]
		if n.y < -0.35:
			f.material_index = MI["tile"]
		elif c.z > zl - 0.16:
			f.material_index = MI["panel"]     # the grey leading edge


def build_wing():
	w = part("wing")
	for sd in (1, -1):
		xs = [0.8, 1.15, 1.6, 2.3, 2.95, 3.2]
		fs = loft(w, [airfoil(sd * x, wing_sec(x)) for x in xs], "paint", cap0=False, cap1=True)
		for f in fs:
			f.normal_update()
		wing_faces_mat(fs)
		# seam lines on top: thin sunk strips would cost polys; the flap and the tip are separate plates
		zl, zt, ym, th = wing_sec(2.6)
		box(w, (0.9, 0.02, 0.36), (sd * 2.6, ym + 0.028, zt + 0.25), "panel", 0.006, M=tr(sd * 2.6, 0, 0) @ rot('Z', sd * -2.4) @ tr(-sd * 2.6, 0, 0))   # flap plate
		for xx in (2.2, 3.0):
			box(w, (0.05, 0.035, 0.12), (sd * xx, ym + 0.02, zt + 0.42), "steel", 0.006)       # flap hinges
		zl, zt, ym, th = wing_sec(3.2)
		loft(w, [airfoil(sd * 3.12, (zl + 0.01, zt - 0.01, ym, th + 0.012)), airfoil(sd * 3.215, (zl + 0.01, zt - 0.01, ym, th + 0.012))], "accent", True, True)
		lathe(w, [(0.03, 0), (0.03, 0.05), (0, 0.075)], "lamp", 8, aim((sd * 3.21, ym, zl - 0.2), (sd * 4, ym, zl - 0.2)))
		POINTS["lamps"].append({"pos": [sd * 3.26, ym, zl - 0.2], "kind": "lamp"})
		# the lift duct: a ring proud of the wing, stators and hub on top, vanes and a nozzle plate below
		D = Vector((sd * DUCT.x, 0, DUCT.z))
		y0, y1 = 0.80, 1.27
		prof = [(DUCT_R + 0.02, y0), (DUCT_R + 0.1, y0 + 0.05), (DUCT_R + 0.115, y1 - 0.06), (DUCT_R + 0.085, y1), (DUCT_R + 0.02, y1), (DUCT_R, y1 - 0.03), (DUCT_R, y0 + 0.03)]
		fs = lathe(w, prof, "panel", 28, tr(D.x, 0, D.z), close=True)
		for f in fs:
			c = f.calc_center_median()
			rr = math.hypot(c.x - D.x, c.z - D.z)
			if rr < DUCT_R + 0.015:
				f.material_index = MI["steel"]
		heat_l, has_l = w.verts.layers.float["heat"], w.verts.layers.float["hasheat"]
		for f in fs:
			for v in f.verts:
				if math.hypot(v.co.x - D.x, v.co.z - D.z) < DUCT_R + 0.03:
					v[has_l] = 1.0
					v[heat_l] = max(0.0, 1.0 - (v.co.y - y0) / 0.25)
		aim_faces(w, lathe(w, [(0, y1 - 0.105), (DUCT_R, y1 - 0.105)], "dark", 20, tr(D.x, 0, D.z)), along=(0, 1, 0))   # intake floor
		lathe(w, [(0, y1 - 0.02), (0.07, y1 - 0.03), (0.09, y1 - 0.1)], "trim", 12, tr(D.x, 0, D.z))            # hub cap
		for k in range(5):
			box(w, (DUCT_R - 0.06, 0.03, 0.022), (0.07 + (DUCT_R - 0.06) * 0.5, y1 - 0.035, 0), "trim", 0.004, tr(D.x, 0, D.z) @ rot('Y', 72 * k + 18))
		aim_faces(w, lathe(w, [(DUCT_R, y0 + 0.07), (0, y0 + 0.07)], "thruster", 20, tr(D.x, 0, D.z)), along=(0, -1, 0))   # the nozzle plate
		for k in (-1, 0, 1):
			box(w, (2 * math.sqrt(DUCT_R ** 2 - (k * 0.2) ** 2) - 0.02, 0.075, 0.014), (D.x, y0 + 0.035, D.z + k * 0.2), "steel", 0.003, heat=0.85)
		rivets(w, [(D.x + math.cos(a) * (DUCT_R + 0.062), y1 + 0.001, D.z + math.sin(a) * (DUCT_R + 0.062)) for a in [i * math.tau / 12 for i in range(12)]], (0, 1, 0), 0.009)
		POINTS["landing"].append([sd * 1.02, 0.88, 0.1])
		lathe(w, [(0.05, 0), (0.05, 0.02), (0.0, 0.02)], "land", 10, tr(sd * 1.02, 0.905, 0.1) @ rot('X', 180))
		lathe(w, [(0.066, -0.004), (0.066, 0.012), (0.05, 0.012)], "trim", 10, tr(sd * 1.02, 0.905, 0.1) @ rot('X', 180))
	# the lift engine's turbine rotor (one mesh, spun by ShipModel)
	ro = part("rotor")
	for k in range(11):
		box(ro, (DUCT_R * 0.74, 0.008, 0.075), (0.09 + DUCT_R * 0.37, 0, 0), "steel", 0.0, rot('Y', 360.0 * k / 11) @ tr(0.09 + DUCT_R * 0.37, 0, 0) @ rot('X', 24) @ tr(-(0.09 + DUCT_R * 0.37), 0, 0), heat=0.15)
	lathe(ro, [(0.09, -0.02), (0.09, 0.02), (0, 0.02)], "trim", 10)
	POINTS["fans"].append({"pos": [DUCT.x, 1.0, DUCT.z], "r": DUCT_R * 0.9, "y_nozzle": 0.86, "y_rotor": 1.185})
	# Mk II..V: drooped tip fins
	e = part("wing_ext")
	for sd in (1, -1):
		s0 = wing_sec(3.2)
		tipsec = (s0[0] - 0.35, s0[1] + 0.05, s0[2] - 0.34, 0.05)
		midsec = (s0[0] - 0.12, s0[1], s0[2] - 0.06, 0.09)
		fs = loft(e, [airfoil(sd * 3.2, s0), airfoil(sd * 3.55, midsec), airfoil(sd * 3.85, tipsec)], "paint", True, True)
		for f in fs:
			f.normal_update()
			if f.calc_center_median().y < tipsec[2] + 0.16:
				f.material_index = MI["accent"]
		POINTS["strips"].append({"a": [0.98, 1.2, -2.3], "b": [3.1, 1.04, -2.2], "w": 0.012, "tier": 2})
	# Mk VI+: long outer wings
	b = part("wing_big")
	for sd in (1, -1):
		s0 = wing_sec(3.2)
		secs = [(3.2, s0), (4.4, (s0[0] - 0.75, s0[1] - 0.25, s0[2] - 0.06, 0.1)), (5.6, (s0[0] - 1.5, s0[1] - 0.55, s0[2] - 0.14, 0.07)), (5.9, (s0[0] - 1.75, s0[1] - 0.7, s0[2] - 0.16, 0.04))]
		fs = loft(b, [airfoil(sd * x, s) for (x, s) in secs], "paint", True, True)
		for f in fs:
			f.normal_update()
			c = f.calc_center_median()
			if f.normal.y < -0.35:
				f.material_index = MI["tile"]
			elif abs(c.x) > 5.55:
				f.material_index = MI["accent"]
		box(b, (1.6, 0.02, 0.3), (sd * 4.4, s0[2] - 0.02, -2.42), "panel", 0.006, M=tr(0, 0, 0))
	POINTS["wing_big_tip"] = [5.45, wing_sec(3.2)[2] - 0.13, -2.75]


# ---------------------------------------------------------------- engines
def bell(dst, r, length, heat_k=1.0, petals=0):
	"""An engine bell hanging down -Y from its gimbal at the origin: wall with thickness, stiffener
	rings, a glowing throat. Heat tint grows to the lip."""
	th = 0.012
	prof = []
	n = 9
	for i in range(n + 1):
		u = i / n
		rr = r * (0.36 + 0.64 * math.sin(u * math.pi * 0.5) ** 0.8)
		prof.append((rr, -0.06 - length * u))
	inner = [(rr - th, y) for (rr, y) in reversed(prof)]
	hf = lambda p: heat_k * min(1.0, 0.14 + 0.8 * max(0.0, (-p.y - 0.06) / length) ** 1.3)
	for f in lathe(dst, prof + [(prof[-1][0] - th * 0.5, prof[-1][1] - 0.006)], "steel", 20, heat=hf):
		f.normal_update()
		c = f.calc_center_median()
		if f.normal.dot(Vector((c.x, 0, c.z))) < 0:
			f.normal_flip()
	for f in lathe(dst, inner, "thruster", 20):
		f.normal_update()
		c = f.calc_center_median()
		if f.normal.dot(Vector((c.x, 0, c.z))) > 0:
			f.normal_flip()
	aim_faces(dst, lathe(dst, [(r * 0.36 - th, -0.06), (0, -0.06)], "thruster", 12), along=(0, -1, 0))
	for u in ((0.3, 0.62, 0.9) if not petals else (0.3,)):   # stiffener hoops
		i = int(u * n)
		rr, y = prof[i]
		lathe(dst, [(rr, y + 0.012), (rr + 0.014, y + 0.008), (rr + 0.014, y - 0.008), (rr, y - 0.012)], "steel", 20, heat=hf)
	for k in range(petals):     # Mk III+: overlapping nozzle petals over the lower bell
		a = 360.0 * k / petals
		rr0, y0 = prof[5]
		rr1, y1 = prof[-1]
		Mp = rot('Y', a)
		wdt = 2 * math.pi * rr1 / petals * 0.92
		pts0 = [Vector((rr0 + 0.016, y0, -wdt * 0.36)), Vector((rr0 + 0.016, y0, wdt * 0.36))]
		pts1 = [Vector((rr1 + 0.02, y1 - 0.02, -wdt * 0.5)), Vector((rr1 + 0.02, y1 - 0.02, wdt * 0.5))]
		bm = bmesh.new()
		vs = [bm.verts.new(p) for p in (pts0[0], pts0[1], pts1[1], pts1[0])]
		bm.faces.new(vs)
		r_ = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
		for v in r_["geom"]:
			if isinstance(v, bmesh.types.BMVert):
				v.co.x -= 0.008
		bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
		merge(dst, bm, "steel", Mp, heat=hf)
	# gimbal: ball, yoke and two actuator rods
	lathe(dst, [(0, 0.05), (0.07, 0.03), (0.085, -0.02), (r * 0.4, -0.07)], "steel", 12, heat=0.2)
	for a in (45, 135):
		M = rot('Y', a)
		tube(dst, M @ Vector((r * 0.7, 0.06, 0)), M @ Vector((r * 0.62, -length * 0.3, 0)), 0.012, "steel", 6, heat=0.25)


def engine(name, positions, r, length, z_mount, petals=0, pod=None, heat_k=1.0):
	e = part(name)
	for i, (x, y) in enumerate(positions):
		sub = "%s_bell_%d" % (name, i)
		piv = Vector((x, y, z_mount))
		b = part(sub, piv)
		SUBS.setdefault(name, []).append(sub)
		tmp = bmesh.new()
		for lay in ("cav", "heat", "hasheat"):
			tmp.verts.layers.float.new(lay)
		tmp.loops.layers.uv.new("uv")
		bell(tmp, r, length, heat_k, petals)
		M = tr(*piv) @ rot('X', 90)       # -Y of the bell becomes -Z (astern)
		for v in tmp.verts:
			v.co = M @ v.co
		copy_into(b, tmp)
		# the fixed mount on the bulkhead: a thrust ring and feed lines
		lathe(e, [(0.1, 0), (0.12, 0.03), (0.1, 0.07), (0.05, 0.09)], "trim", 12, tr(x, y, z_mount + 0.1) @ rot('X', -90))
		tube(e, (x + 0.11, y + 0.05, z_mount + 0.1), (x + 0.07, y + 0.03, z_mount - 0.05), 0.012, "steel", 6, heat=0.3)
		POINTS["nozzles"].append({"part": name, "pos": [x, y, z_mount - 0.06 - length], "r": r, "bell": sub})
	if pod:
		pod(e)
	return e


def copy_into(dst, src):
	cs, hs, ss = (src.verts.layers.float[k] for k in ("cav", "heat", "hasheat"))
	cd, hd, sd = (dst.verts.layers.float[k] for k in ("cav", "heat", "hasheat"))
	vm = {}
	for v in src.verts:
		nv = dst.verts.new(v.co)
		nv[cd], nv[hd], nv[sd] = v[cs], v[hs], v[ss]
		vm[v] = nv
	for f in src.faces:
		nf = dst.faces.new([vm[v] for v in f.verts])
		nf.material_index = f.material_index
	src.free()


def nacelle(dst, x, y, z0, z1, r, mat="panel"):
	prof = [(0, 0), (r * 0.55, 0.02), (r * 0.92, 0.18), (r, 0.5), (r, (z0 - z1) - 0.1), (r * 0.9, (z0 - z1))]
	lathe(dst, prof, mat, 14, tr(x, y, z0) @ rot('X', -90))


def build_engines():
	engine("eng_a", [(0.31, 1.3), (-0.31, 1.3)], 0.2, 0.34, -2.9)
	engine("eng_b", [(0.31, 1.3), (-0.31, 1.3)], 0.245, 0.44, -2.9, petals=10)

	def pods_c(e):
		for sd in (1, -1):
			nacelle(e, sd * 1.12, 1.5, -1.5, -2.82, 0.2)
			box(e, (0.3, 0.1, 0.9), (sd * 0.95, 1.45, -2.2), "paint", 0.02)
			grille(e, Vector((sd * 1.12, 1.71, -2.0)), Vector((0, 1, 0)), Vector((0, 0, 1)), 0.3, 0.14, 5)
	engine("eng_c", [(1.12, 1.5), (-1.12, 1.5)], 0.15, 0.26, -2.82, pod=pods_c)
	tx, ty, tz = POINTS["wing_big_tip"]

	def pods_t(e):
		for sd in (1, -1):
			nacelle(e, sd * tx, ty, tz + 1.3, tz, 0.15, "accent")
	engine("eng_tip", [(tx, ty), (-tx, ty)], 0.115, 0.2, tz, pod=pods_t)
	engine("eng_core", [(0.0, 1.58), (0.0, 1.03)], 0.085, 0.16, -2.9)


# ---------------------------------------------------------------- landing gear
def leg(name, hinge, foot, sc=1.0, twin=False, feet=None):
	"""One gear leg: a painted upper strut from the hull hinge to a knee block, a vertical oleo
	sleeve under the knee, drag brace and torque links. The rod and the foot pad go to <name>_foot."""
	g = part(name)
	fp = part(name + "_foot")
	SUBS.setdefault(name, [])
	if name + "_foot" not in SUBS[name]:
		SUBS[name].append(name + "_foot")
	H, F = Vector(hinge), Vector(foot)
	K = Vector((F.x, 0.5 * sc + 0.02, F.z))             # the knee, right above the foot
	tube(g, H, K, 0.05 * sc, "panel", 10, r2=0.042 * sc)
	box(g, (0.13 * sc, 0.12 * sc, 0.13 * sc), K, "steel", 0.02)
	lathe(g, [(0, 0), (0.07 * sc, 0), (0.07 * sc, 0.05), (0, 0.05)], "steel", 10, aim(H - Vector((0, 0, 0.05)), H + Vector((0, 0, 1))))   # hinge lug
	tube(g, K + Vector((0, -0.02, 0)), Vector((K.x, 0.27 * sc, K.z)), 0.05 * sc, "steel", 12)      # oleo sleeve
	lathe(g, [(0.05 * sc, 0), (0.058 * sc, 0.008), (0.058 * sc, 0.03), (0.05 * sc, 0.038)], "dark", 12, tr(K.x, 0.262 * sc, K.z))   # the wiper seal
	side = 1.0 if H.x <= F.x else -1.0
	tube(g, K + Vector((0, 0.03, 0.05)), H.lerp(K, 0.15) + Vector((0, 0, 0.42 * sc * (1 if F.z < 0 else -1))), 0.016 * sc, "steel", 6)    # drag brace
	tube(g, H.lerp(K, 0.3), H.lerp(K, 0.3) + Vector((-side * 0.2, 0.12, 0)), 0.02 * sc, "steel", 6)                                         # retract jack
	# hydraulic line down the strut (hand-clipped)
	tube(g, H.lerp(K, 0.08) + Vector((0, 0.05, 0.04)), K + Vector((0, 0.06, 0.05)), 0.007, "dark", 5)
	# the moving piece: chrome rod, torque-link lug, ball joint, pad with a rubber sole
	tube(fp, Vector((F.x, 0.34 * sc, F.z)), Vector((F.x, 0.09, F.z)), 0.031 * sc, "steel", 10, heat=0.0)
	pads = [(0, 0)] if not twin else [(-0.16 * sc, 0), (0.16 * sc, 0)]
	if twin:
		tube(fp, Vector((F.x - 0.2 * sc, 0.1, F.z)), Vector((F.x + 0.2 * sc, 0.1, F.z)), 0.03 * sc, "steel", 8, heat=0.0)
	for (dx, dz) in pads:
		pr = (0.17 if not twin else 0.13) * sc
		lathe(fp, [(0, 0.115), (0.05 * sc, 0.11), (0.06 * sc, 0.075), (pr * 0.8, 0.062), (pr, 0.04), (pr, 0.026)], "steel", 16, tr(F.x + dx, 0, F.z + dz), heat=0.0)
		lathe(fp, [(pr, 0.026), (pr + 0.008, 0.02), (pr + 0.008, 0.004), (pr - 0.01, 0.0), (0, 0.0)], "dark", 16, tr(F.x + dx, 0, F.z + dz))
	box(fp, (0.03 * sc, 0.13 * sc, 0.035 * sc), (F.x, 0.2 * sc, F.z - 0.05 * sc), "steel", 0.006, M=tr(F.x, 0.2 * sc, F.z) @ rot('X', -24) @ tr(-F.x, -0.2 * sc, -F.z), heat=0.0)
	box(g, (0.03 * sc, 0.14 * sc, 0.035 * sc), (F.x, 0.36 * sc, F.z - 0.085 * sc), "steel", 0.006, M=tr(F.x, 0.36 * sc, F.z) @ rot('X', 26) @ tr(-F.x, -0.36 * sc, -F.z))
	if feet is not None:
		feet.append([F.x, 0.0, F.z])


def build_gear():
	# Mk I-III: two legs a side on one hinge line along the chine; they fold in flat under the belly
	for nm, sd in (("skid_l", -1), ("skid_r", 1)):
		hy = hull_pt(-58, 0.0).y
		hx = sd * 0.86
		PIVOT[nm] = Vector((hx, hy, 0.0))
		PIVOT[nm + "_foot"] = Vector((hx, hy, 0.0))
		feet = []
		leg(nm, (hx, hy + 0.02, 1.25), (sd * 1.2, 0, 1.3), 1.0, feet=feet)
		leg(nm, (hx, hy + 0.02, -1.75), (sd * 1.25, 0, -1.8), 1.0, feet=feet)
		g = part(nm)
		tube(g, (hx, hy, -1.95), (hx, hy, 1.45), 0.034, "steel", 8)        # the torque tube both legs turn on
		for zz in (-1.95, -0.3, 1.45):
			box(g, (0.09, 0.08, 0.1), (hx - sd * 0.01, hy + 0.02, zz), "trim", 0.012)
		POINTS["feet"][nm] = feet
	POINTS["fold"] = {"skid_l": ["z", 1.42], "skid_r": ["z", -1.42], "gear_n": ["x", 1.45], "gear_l": ["x", 1.45], "gear_r": ["x", 1.45]}
	# Mk IV+: a twin-pad nose leg and two heavy mains
	for nm, H, F, sc, twin in (("gear_n", (0, 0.86, 2.0), (0, 0, 2.0), 1.05, True), ("gear_l", (-1.22, 0.95, -1.5), (-1.35, 0, -1.55), 1.25, False),
			("gear_r", (1.22, 0.95, -1.5), (1.35, 0, -1.55), 1.25, False)):
		PIVOT[nm] = Vector(H)
		PIVOT[nm + "_foot"] = Vector(H)
		feet = []
		leg(nm, H, F, sc, twin, feet)
		POINTS["feet"][nm] = feet


# ---------------------------------------------------------------- pods, fins, ring, vault
def build_extras():
	p = part("pods")
	for sd in (1, -1):
		x, y, z0, z1, r = sd * 2.62, 0.74, 0.0, -1.5, 0.19
		prof = [(0, 0), (r * 0.5, 0.04), (r * 0.9, 0.2), (r, 0.42), (r, 1.1), (r * 0.85, 1.34), (r * 0.4, 1.5), (0, 1.5)]
		fs = lathe(p, prof, "panel", 14, tr(x, y, z0) @ rot('X', -90))
		for f in fs:
			c = f.calc_center_median()
			if -1.0 < c.z < -0.82:
				f.material_index = MI["accent"]
		for zz in (-0.45, -1.05):   # pylon and sway straps
			box(p, (0.07, 0.2, 0.2), (x, y + r + 0.05, zz), "steel", 0.012)
			lathe(p, [(r + 0.004, -0.02), (r + 0.012, -0.012), (r + 0.012, 0.012), (r + 0.004, 0.02)], "trim", 14, tr(x, y, zz) @ rot('X', -90))
	f = part("fins")
	for sd in (1, -1):
		base = Vector((sd * 0.62, 1.7, 0))
		poly = [(-2.8, 0.0), (-1.55, 0.0), (-2.05, 0.75), (-2.6, 1.0), (-2.9, 0.98)]
		M = tr(*base) @ rot('Z', -sd * 32)
		fs = loft(f, [[Vector((s * (0.04 if i < 2 else 0.02), h, z)) for i, (z, h) in enumerate(poly)] for s in (1, -1)], "paint", M=M)
		loft(f, [[Vector((s * 0.026, h, z)) for (z, h) in [(-2.6, 1.0), (-2.9, 0.98), (-2.86, 0.86), (-2.52, 0.88)]] for s in (1, -1)], "accent", M=M)
		q = M @ Vector((0, 1.0, -2.75))
		POINTS["lamps"].append({"pos": [q.x, q.y, q.z], "kind": "lamp"})
		lathe(f, [(0.025, 0), (0.025, 0.03), (0, 0.045)], "lamp", 8, tr(q.x, q.y - 0.01, q.z))
	# the fold ring (Mk VI+): an elliptical hoop round the rear hull on four struts
	r = part("ring")
	RX, RY, C = 1.4, 0.84, Vector((0, 1.3, -1.975))
	bm = bmesh.new()
	seg, minor = 48, 8
	rows = []
	for i in range(seg):
		a = math.tau * i / seg
		c = Vector((RX * math.cos(a), RY * math.sin(a), 0))
		nrm = Vector((RY * math.cos(a), RX * math.sin(a), 0)).normalized()
		rows.append([bm.verts.new(C + c + nrm * (0.075 * math.cos(b)) + Vector((0, 0, 0.11 * math.sin(b)))) for b in [math.tau * j / minor for j in range(minor)]])
	for i in range(seg):
		for j in range(minor):
			bm.faces.new((rows[i][j], rows[(i + 1) % seg][j], rows[(i + 1) % seg][(j + 1) % minor], rows[i][(j + 1) % minor]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	fs = merge(r, bm, "panel")
	for f_ in fs:
		if abs(f_.calc_center_median().z - C.z) > 0.085:
			f_.material_index = MI["trim"]
	for a in (35, 145, 215, 325):
		ar = math.radians(a)
		o = C + Vector((RX * math.cos(ar), RY * math.sin(ar), 0))
		tube(r, o, hull_pt(a if a < 180 else a, -1.975, -0.02) if a < 180 else hull_pt(fold(a) if a > 270 else 180 - (a - 180) * -1, -1.975, -0.02), 0.035, "steel", 8)
	POINTS["ring_light"] = {"pos": [C.x, C.y, C.z], "scale": [RX - 0.08, RY - 0.08]}
	# the seed vault (Mk VII): a glazed cradle on the mid hull with green inside
	v = part("vault")
	top = station(0.0)[3]
	box(v, (0.86, 0.1, 1.9), (0, top + 0.02, 1.1), "panel", 0.03)
	rings = []
	for z in (0.2, 0.45, 1.75, 2.0):
		k = 0.55 if z in (0.2, 2.0) else 1.0
		rings.append([Vector((0.36 * k * math.cos(a), top + 0.07 + 0.3 * k * math.sin(a), z)) for a in [math.pi * i / 8 for i in range(9)]])
	aim_faces(v, loft(v, rings, "vault_glass", True, True, closed=False), away=(0, top, 1.1))
	for z in (0.45, 1.1, 1.75):
		lathe(v, [(0.365, -0.02), (0.385, -0.02), (0.385, 0.02), (0.365, 0.02)], "steel", 16, tr(0, top + 0.07, z) @ rot('X', -90), arc=(0, 180))
	for i in range(7):
		z = 0.5 + i * 0.2
		lathe(v, [(0, 0), (0.07, 0.03), (0.08, 0.1), (0.04, 0.17), (0, 0.19)], "leaf", 7, tr(0.12 * (1 if i % 2 else -1), top + 0.07, z))
	box(v, (0.1, 0.02, 1.5), (0, top + 0.075, 1.1), "vault", 0.0)
	POINTS["vault_spine"] = {"a": [0, top + 0.38, 0.5], "b": [0, top + 0.38, 1.7]}
	POINTS["strips"] += [{"a": [0.955, 1.16, -2.3], "b": [0.955, 1.16, -1.3], "w": 0.012, "tier": 4}]
	POINTS["marks"] = [{"pos": [0.962, 1.4, -1.72], "side": 1}, {"pos": [-0.962, 1.4, -1.72], "side": -1}]


# ---------------------------------------------------------------- painted marks and soot (decal atlas)
ATLAS = {}   # name -> (u0, v0, u1, v1)


def make_atlas():
	try:
		from PIL import Image, ImageDraw, ImageFont, ImageFilter
	except Exception as ex:  # pragma: no cover
		print("PIL missing, decal atlas kept as is:", ex)
		return
	W, H = 1024, 512
	im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	fp = os.path.join(HERE, "..", "..", "..", "ui", "fonts", "AnonymousPro-Bold.ttf")
	font = lambda s: ImageFont.truetype(fp, s)

	def slot(name, x, y, w, h):
		ATLAS[name] = (x / W, y / H, (x + w) / W, (y + h) / H)
		return (x, y, w, h)
	ink = (36, 40, 48, 235)
	x, y, w, h = slot("reg", 4, 4, 420, 112)
	d.text((x + 6, y + 2), "VS-0417", font=font(104), fill=ink)
	x, y, w, h = slot("hazard", 4, 124, 420, 44)
	for k in range(-2, 12):
		d.polygon([(x + k * 44, y + h), (x + k * 44 + 22, y + h), (x + k * 44 + 66, y), (x + k * 44 + 44, y)], fill=(232, 178, 28, 240))
		d.polygon([(x + k * 44 + 22, y + h), (x + k * 44 + 44, y + h), (x + k * 44 + 88, y), (x + k * 44 + 66, y)], fill=(28, 28, 30, 240))
	d.rectangle([x + w, y, x + w + 60, y + h], fill=(0, 0, 0, 0))
	x, y, w, h = slot("nostep", 4, 176, 200, 44)
	d.rectangle([x, y, x + w - 1, y + h - 1], outline=(190, 40, 30, 235), width=4)
	d.text((x + 16, y + 6), "NO STEP", font=font(32), fill=(190, 40, 30, 235))
	x, y, w, h = slot("rescue", 212, 176, 212, 92)
	d.polygon([(x + 4, y + 46), (x + 60, y + 6), (x + 60, y + 28), (x + 206, y + 28), (x + 206, y + 64), (x + 60, y + 64), (x + 60, y + 86)], fill=(236, 190, 30, 240), outline=(24, 24, 26, 255))
	d.text((x + 70, y + 30), "RESCUE", font=font(30), fill=(24, 24, 26, 255))
	x, y, w, h = slot("danger", 4, 228, 96, 88)
	d.polygon([(x + 48, y + 4), (x + 92, y + 82), (x + 4, y + 82)], fill=(200, 44, 30, 240))
	d.polygon([(x + 48, y + 22), (x + 76, y + 72), (x + 20, y + 72)], fill=(236, 232, 220, 240))
	d.text((x + 39, y + 34), "!", font=font(40), fill=(24, 24, 26, 255))
	x, y, w, h = slot("plate", 108, 228, 96, 88)
	d.rectangle([x, y, x + w - 1, y + h - 1], fill=(22, 24, 28, 235))
	for i in range(6):
		d.rectangle([x + 8, y + 10 + i * 12, x + 8 + [70, 52, 78, 40, 66, 58][i], y + 14 + i * 12], fill=(190, 190, 180, 230))
	x, y, w, h = slot("jet", 4, 324, 420, 40)
	d.text((x + 4, y + 4), "CAUTION  JET BLAST", font=font(34), fill=(190, 40, 30, 235))
	x, y, w, h = slot("ticks", 4, 372, 420, 28)
	for k in range(21):
		d.rectangle([x + k * 20, y, x + k * 20 + 3, y + (26 if k % 5 == 0 else 12)], fill=ink)
	x, y, w, h = slot("leaf", 4, 408, 96, 96)
	d.ellipse([x + 2, y + 2, x + 93, y + 93], outline=(40, 110, 60, 240), width=7)
	d.polygon([(x + 48, y + 16), (x + 74, y + 44), (x + 62, y + 72), (x + 48, y + 80), (x + 34, y + 72), (x + 22, y + 44)], fill=(52, 132, 70, 240))
	d.line([(x + 48, y + 24), (x + 48, y + 80)], fill=(230, 232, 220, 255), width=4)
	x, y, w, h = slot("arrow", 108, 408, 96, 96)
	d.polygon([(x + 48, y + 88), (x + 16, y + 44), (x + 36, y + 44), (x + 36, y + 8), (x + 60, y + 8), (x + 60, y + 44), (x + 80, y + 44)], fill=(190, 40, 30, 235))
	x, y, w, h = slot("stripe", 212, 408, 212, 96)
	for k in range(3):
		d.rectangle([x, y + 6 + k * 30, x + w - 1, y + 22 + k * 30], fill=(36, 40, 48, 220))
	# soot: a long streak (blown back from a port) and a round scorch, soft and uneven
	px = im.load()

	def soot(name, x, y, w, h, streak):
		slot(name, x, y, w, h)
		for j in range(h):
			for i in range(w):
				u, v = i / (w - 1), j / (h - 1)
				if streak:
					a = max(0.0, 1.0 - u) ** 1.4 * max(0.0, 1.0 - abs(v - 0.5) * 2 / (0.35 + 0.65 * u)) ** 1.5
					a *= 0.75 + 0.25 * math.sin(v * 37.0 + u * 5.0) * math.sin(v * 91.0)
				else:
					r = math.hypot(u - 0.5, v - 0.5) * 2
					ang = math.atan2(v - 0.5, u - 0.5)
					a = max(0.0, 1.0 - r * (1.0 + 0.12 * math.sin(ang * 7) + 0.08 * math.sin(ang * 13 + 1))) ** 1.3
				px[x + i, y + j] = (16, 13, 11, int(min(1.0, a) * 225))
	soot("streak", 440, 4, 320, 150, True)
	soot("scorch", 440, 164, 200, 200, False)

	def rust(name, x, y, w, h):
		slot(name, x, y, w, h)
		for j in range(h):
			for i in range(w):
				u, v = i / (w - 1), j / (h - 1)
				a = max(0.0, 1.0 - v) ** 1.2 * max(0.0, 1.0 - abs(u - 0.5) * 2 / (0.25 + 0.5 * v)) * (0.6 + 0.4 * math.sin(u * 53.0) * math.sin(u * 17.0 + 2))
				px[x + i, y + j] = (112, 58, 26, int(min(1.0, max(0.0, a)) * 210))
	rust("rust", 780, 4, 110, 260)

	def oil(name, x, y, w, h):
		slot(name, x, y, w, h)
		for j in range(h):
			for i in range(w):
				u, v = i / (w - 1), j / (h - 1)
				a = max(0.0, 1.0 - v) ** 0.8 * max(0.0, 1.0 - abs(u - 0.5 - 0.06 * math.sin(v * 9)) * 2 / (0.5 - 0.3 * v))
				px[x + i, y + j] = (20, 17, 14, int(min(1.0, max(0.0, a)) * 200))
	oil("oil", 900, 4, 80, 300)
	im.save(OUT_DECAL)
	print("atlas", OUT_DECAL)


def uv_rect(name):
	return ATLAS.get(name, (0, 0, 1, 1))


def decal_quad(dst, P, name, flip_u=False):
	"""P: rows of points (v down) x columns (u right), any grid size; lifted points expected."""
	u0, v0, u1, v1 = uv_rect(name)
	uvl = dst.loops.layers.uv["uv"]
	nr, nc = len(P), len(P[0])
	V = [[dst.verts.new(p) for p in row] for row in P]
	for i in range(nr - 1):
		for j in range(nc - 1):
			f = dst.faces.new((V[i][j], V[i + 1][j], V[i + 1][j + 1], V[i][j + 1]))
			f.material_index = MI["decal"]
			idx = {V[i][j]: (i, j), V[i + 1][j]: (i + 1, j), V[i + 1][j + 1]: (i + 1, j + 1), V[i][j + 1]: (i, j + 1)}
			for lp in f.loops:
				ii, jj = idx[lp.vert]
				uu = jj / (nc - 1)
				if flip_u:
					uu = 1.0 - uu
				lp[uvl].uv = (u0 + (u1 - u0) * uu, v0 + (v1 - v0) * ii / (nr - 1))


def hull_decal(dst, name, side, z0, z1, a_top, a_bot, reads_forward=None, zfix=None, lift=0.004):
	"""A mark on the hull side between z0..z1 and section angles a_top..a_bot (right-half angles).
	Text reads left to right seen from outside."""
	rows = []
	nz, na = 7, 4
	for i in range(na):
		a = a_top + (a_bot - a_top) * i / (na - 1)
		aa = a if side > 0 else 180.0 - a
		row = []
		for j in range(nz):
			# seen from outside: on the right side (+X) the nose (+Z) is to the viewer's left
			u = j / (nz - 1)
			z = (z1 + (z0 - z1) * u) if side > 0 else (z0 + (z1 - z0) * u)
			row.append(hull_pt(aa, z, lift, zfix))
		rows.append(row)
	if reads_forward is False:
		rows = [list(reversed(r)) for r in rows]
		decal_quad(dst, rows, name, flip_u=True)
		return
	decal_quad(dst, rows, name)
	# winding: make the face look outward
	dst.faces.ensure_lookup_table()


def flat_decal(dst, name, c, u, v, w, h, lift_n=None):
	"""A flat mark centred at c: u = its right, v = its down."""
	c, u, v = Vector(c), Vector(u).normalized(), Vector(v).normalized()
	n = v.cross(u).normalized()
	c = c + n * 0.004
	P = [[c - u * w * 0.5 - v * h * 0.5, c + u * w * 0.5 - v * h * 0.5], [c - u * w * 0.5 + v * h * 0.5, c + u * w * 0.5 + v * h * 0.5]]
	decal_quad(dst, P, name)


def build_decals():
	hr, hf, w = PARTS["hull_rear"], PARTS["hull_front"], PARTS["wing"]
	for sd in (1, -1):
		hull_decal(hr, "reg", sd, -2.75, -1.45, 46, 26)
		hull_decal(hr, "rescue", sd, -0.28, 0.0, 50, 36)
		hull_decal(hr, "hazard", sd, -1.2, -0.3, -24, -29)
		hull_decal(hr, "streak", sd, -2.95, -2.2, 60, 10, reads_forward=(sd < 0))          # exhaust soot swept forward along the tail
		hull_decal(hr, "rust", sd, -2.3 + 0.0, -2.12, 20, -28)
		hull_decal(hr, "oil", sd, -1.26, -1.14, -30, -50)
		hull_decal(hf, "leaf", sd, 0.5, 0.86, 48, 26)
		hull_decal(hf, "plate", sd, 0.2, 0.36, -6, -20)
		hull_decal(hf, "rust", sd, 0.42, 0.56, -30, -50)
		hull_decal(hf, "streak", sd, 2.3, 2.75, 34, 6, reads_forward=(sd > 0))             # the nose jets' soot
		hull_decal(hf, "ticks", sd, 0.95, 1.6, 20, 16)
		# wing top: no-step boxes, jet-blast caution round the duct, soot on the wing behind / under the duct
		zl, zt, ym, th = wing_sec(2.6)
		top = lambda x, z: Vector((sd * x, wing_top(x, z) + 0.004, z))
		X = Vector((sd, 0, 0))
		flat_decal(w, "nostep", top(2.72, -1.95) + Vector((0, 0.03, 0)), -X if sd > 0 else X, Vector((0, 0, 1)) if sd > 0 else Vector((0, 0, -1)), 0.5, 0.11)
		flat_decal(w, "jet", top(1.75, -1.72), Vector((-1, 0, 0)) * sd * 1.0, Vector((0, 0, sd)), 0.9, 0.085)
		flat_decal(w, "arrow", top(2.45, -0.95), X, Vector((0, 0, -1)), 0.16, 0.16)
		under = Vector((sd * DUCT.x, 0.795, DUCT.z))
		flat_decal(w, "scorch", Vector((sd * DUCT.x, wing_bot(DUCT.x, DUCT.z) - 0.006, DUCT.z)), Vector((1, 0, 0)), Vector((0, 0, 1)), 1.7, 1.7)
		flat_decal(w, "streak", top(DUCT.x + 0.1, DUCT.z - 0.95), Vector((0, 0, -1)), Vector((1, 0, 0)), 0.9, 0.8)
	hm = PARTS["hull_mid"]
	for sd in (1, -1):
		hull_decal(hm, "stripe", sd, 0.9, 1.3, 16, -10, zfix=0.0)
		hull_decal(hm, "rust", sd, 1.05, 1.2, -30, -50, zfix=0.0)


def wing_top(x, z):
	zl, zt, ym, th = wing_sec(x)
	u = min(max((zl - z) / (zl - zt), 0.0), 1.0)
	prof = [(0.0, 0.0), (0.012, 0.42), (0.06, 0.8), (0.18, 1.0), (0.45, 0.95), (0.75, 0.6), (1.0, 0.12)]
	for k in range(len(prof) - 1):
		if prof[k][0] <= u <= prof[k + 1][0]:
			t = (u - prof[k][0]) / (prof[k + 1][0] - prof[k][0])
			return ym + th * 0.5 * (prof[k][1] + (prof[k + 1][1] - prof[k][1]) * t)
	return ym


def wing_bot(x, z):
	zl, zt, ym, th = wing_sec(x)
	return ym - (wing_top(x, z) - ym) * 0.85


# ---------------------------------------------------------------- build everything
make_atlas()
build_hull()
canopy("canopy_a", False)
canopy("canopy_b", True)
build_wing()
build_engines()
build_gear()
build_extras()
build_decals()

FRONT = ["hull_front", "canopy_a", "canopy_b", "gear_n"]
LOW = ["hull_rear", "hull_front", "wing", "wing_ext", "canopy_a", "eng_a", "eng_a_bell_0", "eng_a_bell_1", "skid_l", "skid_r", "skid_l_foot", "skid_r_foot"]
SMOOTH = math.cos(math.radians(42))


def tris_of(bm, shift=0.0):
	bm.verts.ensure_lookup_table()
	verts = [Vector((v.co.x, v.co.y, v.co.z + shift)) for v in bm.verts]
	polys = [[v.index for v in f.verts] for f in bm.faces if f.material_index != MI["decal"]]
	return verts, polys


def make_bvh(names, high):
	verts, polys = [], []
	for n in names:
		bm = PARTS[n]
		bm.verts.index_update()
		v, p = tris_of(bm, MID if (high and n in FRONT) else 0.0)
		off = len(verts)
		verts += v
		polys += [[i + off for i in q] for q in p]
	return BVHTree.FromPolygons(verts, polys, all_triangles=False)


HIGH = [n for n in PARTS if n not in ("rotor", "canopy_a", "eng_a", "eng_a_bell_0", "eng_a_bell_1", "skid_l", "skid_r", "skid_l_foot", "skid_r_foot", "wing_ext")]
BVH_LOW = make_bvh(LOW, False)
BVH_HIGH = make_bvh(HIGH, True)
DIRS = []
for i in range(18):   # cosine-ish hemisphere
	u, v = (i + 0.5) / 18.0, (i * 0.618034) % 1.0
	r, ph = math.sqrt(u), math.tau * v
	DIRS.append(Vector((r * math.cos(ph), r * math.sin(ph), math.sqrt(1 - u))))

SOOT = [(Vector((s * DUCT.x, 0.8, DUCT.z)), 0.75) for s in (1, -1)] + [(Vector((s * 0.31, 1.3, -3.0)), 0.7) for s in (1, -1)]


def grime_at(p, n):
	"""Dirt from the ground up, more on faces that look down or sideways; soot near the nozzles."""
	g = max(0.0, min(1.0, (1.5 - p.y) / 0.85)) * (0.55 + 0.45 * max(0.0, -n.y)) * 0.8
	g = max(g, max(0.0, 0.5 - abs(n.y)) * 0.25)
	for (q, rad) in SOOT:
		d = (p - q).length
		g = max(g, max(0.0, 1.0 - d / rad) ** 1.2)
	return min(1.0, g + 0.06 * random.random())


def finish(name, bm):
	"""Vertex colours and split normals; returns {material: (pos, nrm, col, uv, idx)}."""
	bmesh.ops.remove_doubles(bm, verts=[v for v in bm.verts if not any(f.material_index == MI["decal"] for f in v.link_faces)], dist=2e-4)
	bm.normal_update()
	# Big flat faces whose corners are all sharp edges (fins, plates, box sides) would read as one
	# worn edge: give them an inner loop so the wear stays at the rim.
	def sharp(v):
		for e in v.link_edges:
			if len(e.link_faces) == 2:
				try:
					if e.calc_face_angle_signed() > 0.6:
						return True
				except ValueError:
					pass
		return False
	paint_like = (MI["paint"], MI["panel"], MI["accent"], MI["patch"])
	big = [f for f in bm.faces if f.material_index in paint_like and f.calc_area() > 0.012 and min(e.calc_length() for e in f.edges) > 0.07 and all(sharp(v) for v in f.verts)]
	if big:
		bmesh.ops.inset_individual(bm, faces=big, thickness=0.022, use_even_offset=True)
	bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
	bm.normal_update()
	bm.verts.ensure_lookup_table()
	cav_l, heat_l, has_l = bm.verts.layers.float["cav"], bm.verts.layers.float["heat"], bm.verts.layers.float["hasheat"]
	uvl = bm.loops.layers.uv["uv"]
	high = name not in LOW
	bvh = BVH_HIGH if high else BVH_LOW
	shift = MID if (high and base_of(name) in FRONT) else 0.0
	vcol = {}
	for v in bm.verts:
		if not v.link_faces:
			continue
		convex, concave = 0.0, v[cav_l]
		for e in v.link_edges:
			if len(e.link_faces) == 2:
				try:
					a = e.calc_face_angle_signed()
				except ValueError:
					continue
				if a > 0:
					convex = max(convex, a)
				else:
					concave = max(concave, min(1.0, (-a - 0.35) / 0.9))
		edge = min(1.0, max(0.0, (convex - 0.3) / 0.75))
		n = v.normal
		t1 = n.orthogonal().normalized()
		t2 = n.cross(t1)
		o = Vector((v.co.x, v.co.y, v.co.z + shift)) + n * 0.02
		hit = 0.0
		for d in DIRS:
			w = t1 * d.x + t2 * d.y + n * d.z
			loc, nr, idx, dist = bvh.ray_cast(o, w, 1.1)
			if loc is not None:
				hit += 1.0 - 0.6 * dist / 1.1
		ao = 1.0 - min(1.0, hit / len(DIRS) * 1.5)
		if v[has_l] > 0.5:
			a = v[heat_l]
		elif any(f.material_index == MI["steel"] for f in v.link_faces):
			a = 0.0          # plain alloy: no tempering colours
		else:
			a = grime_at(v.co, n)
		vcol[v.index] = (ao, edge, min(1.0, concave), a)
	out = {}
	for f in bm.faces:
		m = MATS[f.material_index]
		pos, nrm, col, uv, idx, seen = out.setdefault(m, ([], [], [], [], [], {}))
		decal = m == "decal"
		fn = f.normal
		tri = []
		for lp in f.loops:
			v = lp.vert
			n = Vector((0, 0, 0))
			if decal:
				n = fn.copy()
			else:
				for f2 in v.link_faces:
					if f2.material_index != MI["decal"] and f2.normal.dot(fn) > SMOOTH:
						n += f2.normal * f2.calc_area()
				n = n.normalized() if n.length > 1e-9 else fn.copy()
			key = (v.index, round(n.x, 2), round(n.y, 2), round(n.z, 2), round(lp[uvl].uv.x, 4), round(lp[uvl].uv.y, 4)) if True else None
			k = seen.get(key)
			if k is None:
				k = len(pos) // 3
				seen[key] = k
				pv = PIVOT.get(name, Vector((0, 0, 0)))
				pos.extend((v.co.x - pv.x, v.co.y - pv.y, v.co.z - pv.z))
				nrm.extend((n.x, n.y, n.z))
				col.extend(vcol.get(v.index, (1, 0, 0, 0)) if not decal else (1, 0, 0, 0))
				uv.extend((lp[uvl].uv.x, lp[uvl].uv.y))
			tri.append(k)
		for i in range(1, len(tri) - 1):
			idx.extend((tri[0], tri[i], tri[i + 1]))
	return out


def write_glb(path):
	bin_data = bytearray()
	views, accessors, meshes, nodes, materials = [], [], [], [], []
	mat_index = {}

	def add(data, fmt, comp, typ, target, count, minmax=False, norm=False):
		while len(bin_data) % 4:
			bin_data.append(0)
		start = len(bin_data)
		bin_data.extend(struct.pack("<%d%s" % (len(data), fmt), *data))
		views.append({"buffer": 0, "byteOffset": start, "byteLength": len(bin_data) - start, "target": target})
		acc = {"bufferView": len(views) - 1, "componentType": comp, "count": count, "type": typ}
		if norm:
			acc["normalized"] = True
		if minmax:
			acc["min"] = [min(data[i::3]) for i in range(3)]
			acc["max"] = [max(data[i::3]) for i in range(3)]
		accessors.append(acc)
		return len(accessors) - 1
	total_tris = 0
	for name in sorted(PARTS):
		surf = finish(name, PARTS[name])
		prims = []
		for m in MATS:
			if m not in surf:
				continue
			pos, nrm, col, uv, idx, _ = surf[m]
			if not idx:
				continue
			if m not in mat_index:
				mat_index[m] = len(materials)
				materials.append({"name": m, "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.8, 1.0]}})
			n = len(pos) // 3
			attrs = {"POSITION": add(pos, "f", 5126, "VEC3", 34962, n, True), "NORMAL": add(nrm, "f", 5126, "VEC3", 34962, n),
				"COLOR_0": add([int(max(0.0, min(1.0, c)) * 255) for c in col], "B", 5121, "VEC4", 34962, n, norm=True)}
			if m == "decal":
				attrs["TEXCOORD_0"] = add(uv, "f", 5126, "VEC2", 34962, n)
			prims.append({"attributes": attrs, "indices": add(idx, "I", 5125, "SCALAR", 34963, len(idx)), "material": mat_index[m]})
			total_tris += len(idx) // 3
		meshes.append({"name": name, "primitives": prims})
		pv = PIVOT.get(name, Vector((0, 0, 0)))
		nodes.append({"name": name, "mesh": len(meshes) - 1, "translation": [pv.x, pv.y, pv.z]})
		print("part %-18s %6d tris  %s" % (name, sum(len(surf[m][4]) for m in surf) // 3, ",".join(m for m in MATS if m in surf)))
	gltf = {"asset": {"version": "2.0", "generator": "build_shuttle.py"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes,
		"meshes": meshes, "materials": materials, "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(bin_data)}]}
	js = json.dumps(gltf, separators=(",", ":")).encode()
	while len(js) % 4:
		js += b" "
	while len(bin_data) % 4:
		bin_data.append(0)
	with open(path, "wb") as f:
		f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_data)))
		f.write(struct.pack("<II", len(js), 0x4E4F534A))
		f.write(js)
		f.write(struct.pack("<II", len(bin_data), 0x004E4942))
		f.write(bin_data)
	print("exported", path, "tris", total_tris)


write_glb(OUT)
POINTS["subs"] = SUBS
POINTS["pivots"] = {k: [v.x, v.y, v.z] for k, v in PIVOT.items()}
with open(OUT_PTS, "w") as f:
	json.dump(POINTS, f, indent=1)
print("points", OUT_PTS)

# ---------------------------------------------------------------- optional Cycles stills (shape check only; the game's shaders differ)
#   PREVIEW=/path/prefix [PREVIEW_TIER=1|4|7] [PREVIEW_VIEWS=0,1] python3 art/models/shuttle/build_shuttle.py
if os.environ.get("PREVIEW"):
	sc = bpy.context.scene
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o, do_unlink=True)
	cols = {"paint": (0.8, 0.8, 0.78), "panel": (0.42, 0.43, 0.43), "accent": (0.9, 0.38, 0.08), "patch": (0.2, 0.4, 0.38), "tile": (0.03, 0.03, 0.035),
		"steel": (0.5, 0.5, 0.52), "trim": (0.05, 0.05, 0.06), "dark": (0.015, 0.015, 0.018), "glass": (0.03, 0.09, 0.11), "lamp": (1.0, 0.3, 0.1),
		"glow": (0.3, 0.88, 1.0), "thruster": (0.03, 0.03, 0.03), "land": (1, 0.95, 0.8), "decal": (0.1, 0.1, 0.12), "vault": (0.4, 1, 0.5), "vault_glass": (0.6, 0.85, 0.75), "leaf": (0.2, 0.6, 0.2)}
	bmats = []
	for n in MATS:
		m = bpy.data.materials.new(n)
		m.use_nodes = True
		b = m.node_tree.nodes["Principled BSDF"]
		b.inputs["Base Color"].default_value = (*cols[n], 1)
		b.inputs["Roughness"].default_value = 0.1 if "glass" in n else 0.45
		b.inputs["Metallic"].default_value = 0.9 if n == "steel" else 0.0
		bmats.append(m)
	T = int(os.environ.get("PREVIEW_TIER", "1"))
	want = {1: ["hull_rear", "hull_front", "wing", "canopy_a", "eng_a", "skid_l", "skid_r"],
		4: ["hull_rear", "hull_front", "wing", "wing_ext", "canopy_b", "eng_b", "gear_n", "gear_l", "gear_r", "pods"],
		7: ["hull_rear", "hull_front", "hull_mid", "wing", "wing_big", "canopy_b", "eng_b", "eng_c", "fins", "gear_n", "gear_l", "gear_r", "pods", "ring", "eng_tip", "vault", "eng_core"]}[T]
	TO_Z_UP = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))   # Godot (Y up) -> Blender (Z up)
	for name, bm in PARTS.items():
		if base_of(name) not in want:
			continue
		me = bpy.data.meshes.new(name)
		bm.to_mesh(me)
		if T >= 5 and base_of(name) in FRONT:
			me.transform(Matrix.Translation((0, 0, MID)))
		me.transform(TO_Z_UP)
		for m in bmats:
			me.materials.append(m)
		for p in me.polygons:
			p.use_smooth = True
		ob = bpy.data.objects.new(name, me)
		sc.collection.objects.link(ob)
		md = ob.modifiers.new("es", 'EDGE_SPLIT')
		md.split_angle = math.radians(42)
	gm = bpy.data.meshes.new("ground")
	gb = bmesh.new()
	bmesh.ops.create_grid(gb, x_segments=1, y_segments=1, size=40)
	gb.to_mesh(gm)
	sc.collection.objects.link(bpy.data.objects.new("ground", gm))
	sc.render.engine = 'CYCLES'
	sc.cycles.samples = int(os.environ.get("PREVIEW_SAMPLES", "12"))
	sc.cycles.use_denoising = False
	sc.render.resolution_x, sc.render.resolution_y = 800, 450
	w = bpy.data.worlds.new("w")
	sc.world = w
	w.use_nodes = True
	w.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.56, 0.66, 1)
	sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
	sc.collection.objects.link(sun)
	sun.data.energy = 3.0
	sun.rotation_euler = (math.radians(50), 0, math.radians(-40))
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	sc.collection.objects.link(cam)
	cam.data.lens = 40
	sc.camera = cam
	views = [(35, 14, 10.0, 1.0, 0.0), (145, 12, 9.5, 1.0, -0.4), (20, 8, 4.4, 1.2, 1.6), (160, -4, 4.8, 0.8, -1.6), (90, 2, 8.5, 0.9, 0.0), (0, 80, 11.0, 0.8, 0.0)]
	only = os.environ.get("PREVIEW_VIEWS")
	for k, (az, el, dist, ty, tz) in enumerate(views):
		if only and str(k) not in only.split(","):
			continue
		a, e = math.radians(az), math.radians(el)
		zc = tz + (MID * 0.5 if T >= 5 else 0)
		tg = TO_Z_UP @ Vector((0, ty, zc))
		pos = TO_Z_UP @ (Vector((0, ty, zc)) + Vector((math.sin(a) * math.cos(e), math.sin(e), math.cos(a) * math.cos(e))) * dist * (1.5 if T >= 5 else 1.0))
		cam.location = pos
		cam.rotation_euler = (tg - pos).to_track_quat('-Z', 'Y').to_euler()
		sc.render.filepath = "%s_mk%d_%d.png" % (os.environ["PREVIEW"], T, k)
		bpy.ops.render.render(write_still=True)
