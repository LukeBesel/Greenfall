class_name SeasKit
extends RefCounted
## [p_seas] Placement layer for the Tidewell and Rime hub sites on top of the shared art kit
## (art/kit, docs/ART_KIT.md): every part goes into a KitMesh.Builder under a kit material KEY
## ("paint:#rrggbb", "steel", "hazard", "trim:warm", ...), so materials, wear states (broken /
## repaired / restored) and power come from KitMat. What this file adds for the seas sites:
## framed placement (origin + basis), chunkier bevels, greebles (bolts, ribs, rails, ladders,
## vents, flanged pipes, lamp housings, trusses, lattice towers), a lofted ship hull with a
## boot-top, mesh->kit-primitive conversion (rocks, coils), the helipad image decal, and simple
## static colliders on the PROP / WORLD layers.
## bevel_box / bevel_cyl (ArrayMesh) remain for custom-material batches (Rime's glassy ice).

static var _cache: Dictionary = {}


# --- Meshes ----------------------------------------------------------------------------------

## A box of `size` with chamfered edges `b` wide (flat-shaded faces, chamfers marked in COLOR.r).
static func bevel_box(size: Vector3, b: float = -1.0) -> ArrayMesh:
	var s: Vector3 = size.snapped(Vector3.ONE * 0.02).max(Vector3.ONE * 0.02)
	if b < 0.0:
		b = clampf(minf(s.x, minf(s.y, s.z)) * 0.16, 0.012, 0.22)
	b = minf(b, minf(s.x, minf(s.y, s.z)) * 0.45)
	b = snappedf(b, 0.005)
	var key: String = "bb_%s_%.3f" % [str(s), b]
	if _cache.has(key):
		return _cache[key]
	var h: Vector3 = s * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Faces of a chamfered box: for each sign pattern (sx, sy, sz in -1/0/1, not all 0), the hull
	# points whose "pushed" axes match. Main faces (one non-zero), edges (two), corners (three).
	for sx: int in [-1, 0, 1]:
		for sy: int in [-1, 0, 1]:
			for sz: int in [-1, 0, 1]:
				var sg := Vector3i(sx, sy, sz)
				var nz: int = absi(sx) + absi(sy) + absi(sz)
				if nz == 0:
					continue
				var pts: Array[Vector3] = []
				# Hull point: on axis k push to h[k], others at +-(h - b) (or the face's sign).
				for cx: int in [-1, 1]:
					for cy: int in [-1, 1]:
						for cz: int in [-1, 1]:
							var c := Vector3i(cx, cy, cz)
							for k: int in 3:
								var ok: bool = true
								for a: int in 3:
									if sg[a] != 0 and sg[a] != c[a]:
										ok = false
								if not ok or sg[k] == 0:
									continue
								# The point must lie on this face: pushed axis k; for the other
								# face axes (sg != 0) the point sits at h - b.
								var p := Vector3()
								for a: int in 3:
									p[a] = float(c[a]) * (h[a] if a == k else h[a] - b)
								if not pts.has(p):
									pts.append(p)
				if pts.size() < 3:
					continue
				var edge: float = 0.0 if nz == 1 else 1.0
				_emit_face(st, pts, Vector3(sg).normalized(), edge)
	st.generate_tangents()
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


## Emits a convex planar face (unordered points) with outward direction `out`.
static func _emit_face(st: SurfaceTool, pts: Array[Vector3], out: Vector3, edge: float) -> void:
	var c := Vector3()
	for p: Vector3 in pts:
		c += p
	c /= pts.size()
	# Plane normal from the points (fallback: out).
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
	if n.length() < 1e-6 and pts.size() > 3:
		n = (pts[1] - pts[0]).cross(pts[3] - pts[0])
	n = n.normalized() if n.length() > 1e-6 else out
	if n.dot(out) < 0.0:
		n = -n
	var u: Vector3 = (pts[0] - c).normalized()
	var v: Vector3 = n.cross(u)
	var sorted: Array = []
	for p: Vector3 in pts:
		sorted.append([atan2((p - c).dot(v), (p - c).dot(u)), p])
	sorted.sort_custom(func(a: Array, bb: Array) -> bool: return a[0] < bb[0])
	# Counter-clockwise around n; Godot's front faces are clockwise seen from outside, so emit reversed.
	for i: int in range(1, sorted.size() - 1):
		for p: Vector3 in [sorted[0][1], sorted[i + 1][1], sorted[i][1]]:
			st.set_color(Color(edge, 0, 0))
			st.set_normal(n)
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.add_vertex(p)


## A cylinder along +Y (centred), radius r, height hgt, chamfered rims.
static func bevel_cyl(r: float, hgt: float, segs: int = 14, b: float = -1.0) -> ArrayMesh:
	r = maxf(snappedf(r, 0.01), 0.01)
	hgt = maxf(snappedf(hgt, 0.02), 0.02)
	if b < 0.0:
		b = clampf(minf(r, hgt) * 0.2, 0.01, 0.18)
	b = minf(b, minf(r * 0.45, hgt * 0.45))
	var key: String = "bc_%.2f_%.2f_%d_%.3f" % [r, hgt, segs, b]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hh: float = hgt * 0.5
	# Profile (radius, y, edge flag) from bottom centre to top centre.
	var prof: Array = [[0.0, -hh, 0.0], [r - b, -hh, 0.0], [r, -hh + b, 1.0], [r, hh - b, 0.0], [r - b, hh, 1.0], [0.0, hh, 0.0]]
	for k: int in prof.size() - 1:
		var p0: Array = prof[k]
		var p1: Array = prof[k + 1]
		var e: float = maxf(float(p0[2]), float(p1[2])) if k != 2 else 0.0
		for j: int in segs:
			var a0: float = TAU * j / segs
			var a1: float = TAU * (j + 1) / segs
			var am: float = (a0 + a1) * 0.5
			var dr := Vector2(float(p1[0]) - float(p0[0]), float(p1[1]) - float(p0[1]))
			var nr := Vector2(dr.y, -dr.x).normalized()  # outward in (radial, y)
			var smooth: bool = k == 2
			var q: Array[Vector3] = [
				Vector3(cos(a0) * float(p0[0]), float(p0[1]), sin(a0) * float(p0[0])),
				Vector3(cos(a1) * float(p0[0]), float(p0[1]), sin(a1) * float(p0[0])),
				Vector3(cos(a1) * float(p1[0]), float(p1[1]), sin(a1) * float(p1[0])),
				Vector3(cos(a0) * float(p1[0]), float(p1[1]), sin(a0) * float(p1[0])),
			]
			var ns: Array[Vector3] = []
			for a: float in [a0, a1, a1, a0]:
				var aa: float = a if smooth else am
				ns.append(Vector3(cos(aa) * nr.x, nr.y, sin(aa) * nr.x).normalized())
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(e, 0, 0))
				st.set_normal(ns[idx])
				st.set_uv(Vector2(float(j) / segs, q[idx].y))
				st.add_vertex(q[idx])
	st.generate_tangents()
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


## Chunky default bevel for a box of `size` (sites read from far away: a bit more than the kit's).
static func _bev(size: Vector3, b: float) -> float:
	if b >= 0.0:
		return minf(b, minf(size.x, minf(size.y, size.z)) * 0.45)
	return clampf(minf(size.x, minf(size.y, size.z)) * 0.16, 0.008, 0.2)


## Transform placing a +Y unit-axis mesh from a to c.
static func axis_xf(a: Vector3, c: Vector3) -> Transform3D:
	var d: Vector3 = c - a
	var y: Vector3 = d.normalized() if d.length() > 1e-5 else Vector3.UP
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), (a + c) * 0.5)


# --- Placement helpers (into a KitMesh.Builder) ------------------------------------------------

## A bevelled box at local `pos` in frame (o, bs) with extra rotation `rot` (degrees, local).
static func box(bt: KitMesh.Builder, o: Vector3, bs: Basis, pos: Vector3, size: Vector3, mat: String, rot: Vector3 = Vector3.ZERO, bev: float = -1.0) -> void:
	var lb: Basis = bs * Basis.from_euler(rot * (PI / 180.0))
	bt.add(mat, KitMesh.bevel_box(size.max(Vector3.ONE * 0.01), _bev(size, bev)), Transform3D(lb, o + bs * pos))


## A bevelled cylinder (pipe, post, tank) between local points a and c, radius r.
static func pipe(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, r: float, mat: String, segs: int = 12) -> void:
	var wa: Vector3 = o + bs * a
	var wc: Vector3 = o + bs * c
	var ln: float = wa.distance_to(wc)
	if ln < 0.001:
		return
	if r < 0.05:
		bt.rod(mat, wa, wc, r, mini(segs, 6))
	else:
		bt.add(mat, KitMesh.bevel_cylinder(r, ln, clampf(minf(r, ln) * 0.2, 0.01, 0.16), segs), KitMesh.look_y(wa, wc - wa))


## A pipe with chunky flanges at both ends (and every `every` metres).
static func flanged_pipe(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, r: float, mat: String, flange_mat: String, every: float = 4.0) -> void:
	pipe(bt, o, bs, a, c, r, mat)
	var n: int = maxi(1, int(a.distance_to(c) / every))
	for k: int in n + 1:
		var p: Vector3 = a.lerp(c, float(k) / n)
		var d: Vector3 = (c - a).normalized() * 0.09
		pipe(bt, o, bs, p - d, p + d, r * 1.45, flange_mat, 12)


## A row of n bolt heads from a to c on a face pointing `nrm` (local).
static func bolts(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, n: int, nrm: Vector3, mat: String, r: float = 0.05) -> void:
	for k: int in n:
		var p: Vector3 = a.lerp(c, (float(k) + 0.5) / n)
		pipe(bt, o, bs, p, p + nrm * r * 0.8, r, mat, 6)


## A railing along local points: posts every ~1.6 m, a top rail and a mid rail.
static func rail(bt: KitMesh.Builder, o: Vector3, bs: Basis, pts: Array[Vector3], hgt: float, mat: String, r: float = 0.04) -> void:
	for i: int in pts.size() - 1:
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var n: int = maxi(1, int(ceil(a.distance_to(c) / 1.6)))
		for k: int in n:
			var p: Vector3 = a.lerp(c, float(k) / n)
			pipe(bt, o, bs, p, p + Vector3(0, hgt, 0), r * 1.2, mat, 8)
		pipe(bt, o, bs, a + Vector3(0, hgt, 0), c + Vector3(0, hgt, 0), r, mat, 8)
		pipe(bt, o, bs, a + Vector3(0, hgt * 0.5, 0), c + Vector3(0, hgt * 0.5, 0), r * 0.75, mat, 6)
	var e: Vector3 = pts[pts.size() - 1]
	pipe(bt, o, bs, e, e + Vector3(0, hgt, 0), r * 1.2, mat, 8)


## A ladder from a (bottom) to c (top), width w, facing `out`.
static func ladder(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, w: float, out: Vector3, mat: String) -> void:
	var side: Vector3 = out.cross(Vector3.UP).normalized() * w * 0.5
	pipe(bt, o, bs, a - side, c - side, 0.035, mat, 6)
	pipe(bt, o, bs, a + side, c + side, 0.035, mat, 6)
	var n: int = maxi(2, int(a.distance_to(c) / 0.35))
	for k: int in range(1, n):
		var p: Vector3 = a.lerp(c, float(k) / n)
		pipe(bt, o, bs, p - side, p + side, 0.022, mat, 5)


## A louvred vent box on a face: frame + slats (normal `out`, local).
static func vent(bt: KitMesh.Builder, o: Vector3, bs: Basis, pos: Vector3, w: float, hgt: float, out: Vector3, frame: String, dark: String) -> void:
	var yaw: float = rad_to_deg(atan2(out.x, out.z))
	box(bt, o, bs, pos, Vector3(w, hgt, 0.12), frame, Vector3(0, yaw, 0))
	box(bt, o, bs, pos + out * 0.04, Vector3(w * 0.84, hgt * 0.8, 0.08), dark, Vector3(0, yaw, 0), 0.01)
	var n: int = maxi(2, int(hgt / 0.16))
	for k: int in n:
		var y: float = -hgt * 0.36 + hgt * 0.72 * float(k) / maxf(1.0, n - 1)
		box(bt, o, bs, pos + out * 0.09 + Vector3(0, y, 0), Vector3(w * 0.82, 0.035, 0.07), frame, Vector3(-30, yaw, 0), 0.008)


## Raised plating ribs on a flat face: n vertical strips across a span (a to c), height hgt.
static func ribs(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, n: int, hgt: float, out: Vector3, mat: String) -> void:
	var yaw: float = rad_to_deg(atan2(out.x, out.z))
	for k: int in n:
		var p: Vector3 = a.lerp(c, (float(k) + 0.5) / n) + out * 0.04
		box(bt, o, bs, p, Vector3(0.16, hgt, 0.1), mat, Vector3(0, yaw, 0), 0.03)


## A caged work lamp on a short arm; `lit` adds the lens (warm or cool emissive material).
static func lamp(bt: KitMesh.Builder, lit_bt: KitMesh.Builder, o: Vector3, bs: Basis, pos: Vector3, out: Vector3, body: String, lens: String) -> void:
	pipe(bt, o, bs, pos, pos + out * 0.35, 0.04, body, 6)
	var hp: Vector3 = pos + out * 0.42 + Vector3(0, -0.05, 0)
	pipe(bt, o, bs, hp - Vector3(0, 0.11, 0), hp + Vector3(0, 0.11, 0), 0.14, body, 10)
	if lit_bt:
		pipe(lit_bt, o, bs, hp - Vector3(0, 0.16, 0), hp - Vector3(0, 0.1, 0), 0.11, lens, 10)


# --- Colliders ------------------------------------------------------------------------------------

## A static box collider (frame o, bs; local centre pos, rot degrees) on `layer` (default PROP).
static func solid_box(parent: Node3D, o: Vector3, bs: Basis, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO, layer: int = PhysLayers.PROP) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.transform = Transform3D(bs * Basis.from_euler(rot * (PI / 180.0)), o + bs * pos)
	parent.add_child(body)
	return body


## A static cylinder collider between local points a and c.
static func solid_cyl(parent: Node3D, o: Vector3, bs: Basis, a: Vector3, c: Vector3, r: float, layer: int = PhysLayers.PROP) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = (o + bs * a).distance_to(o + bs * c)
	cs.shape = sh
	body.add_child(cs)
	body.transform = axis_xf(o + bs * a, o + bs * c)
	parent.add_child(body)
	return body


# --- Decals and custom meshes ---------------------------------------------------------------------

## A kit atlas decal (docs/ART_KIT.md: logo, num_01..06, warn, chevrons, arrow, ...) at local pos
## on a face whose outward normal is `out` (local), w x h metres.
static func decal(bt: KitMesh.Builder, o: Vector3, bs: Basis, pos: Vector3, out: Vector3, w: float, hgt: float, name: String) -> void:
	var n: Vector3 = (bs * out).normalized()
	var up: Vector3 = Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else bs * Vector3.FORWARD
	var x: Vector3 = up.cross(n).normalized()
	var y: Vector3 = n.cross(x).normalized()
	bt.decal(name, Vector2(w, hgt), Transform3D(Basis(x, y, n), o + bs * pos + n * 0.02))


## The helipad marking (ring and H), an image decal on its own quad (not in the kit atlas).
static func helipad(parent: Node3D, pos: Vector3, size: float, col: Color = Color(0.96, 0.78, 0.2)) -> MeshInstance3D:
	var key: String = "helipad_%s" % col.to_html()
	if not _cache.has(key):
		var img := Image.create(128, 128, true, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y: int in 128:
			for x: int in 128:
				var d: float = Vector2(x - 63.5, y - 63.5).length()
				var hh: bool = (absf(x - 44.0) < 6.0 or absf(x - 84.0) < 6.0 or absf(y - 64.0) < 5.0) and absf(x - 64.0) < 26.0 and absf(y - 64.0) < 28.0
				if (d > 52.0 and d < 60.0) or hh:
					img.set_pixel(x, y, col)
		img.generate_mipmaps()
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.roughness = 0.7
		_cache[key] = m
	var q := PlaneMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _cache[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.03, 0)
	parent.add_child(mi)
	return mi


## Any Mesh (first surface) as kit primitive arrays [v, n, c, uv, idx]: COLOR.r edge (from the
## mesh's own colour if it has one), g = 1 (no extra AO), so it can go into a KitMesh.Builder.
## mask: -1 all triangles, 0 / 1 only triangles whose COLOR.g is below / above 0.5 (hull boot-top).
static func prim_of(mesh: Mesh, mask: int = -1) -> Array:
	var key: String = "prim_%d_%d" % [mesh.get_instance_id(), mask]
	if _cache.has(key):
		return _cache[key]
	var a: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var src_idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if src_idx.is_empty():
		src_idx.resize(v.size())
		for i: int in v.size():
			src_idx[i] = i
	var cols := PackedColorArray()
	cols.resize(v.size())
	for i: int in v.size():
		cols[i] = Color(c[i].r if c.size() > i else 0.0, 1.0, 0.0)
	if uv.size() != v.size():
		uv.resize(v.size())
	var idx := PackedInt32Array()
	for t: int in range(0, src_idx.size(), 3):
		if mask >= 0 and c.size() > 0:
			var g: float = (c[src_idx[t]].g + c[src_idx[t + 1]].g + c[src_idx[t + 2]].g) / 3.0
			if (g > 0.5) != (mask == 1):
				continue
		idx.append_array([src_idx[t], src_idx[t + 1], src_idx[t + 2]])
	var out: Array = [v, n, cols, uv, idx]
	_cache[key] = out
	return out


## Adds a Mesh (rock, coil, bulb, hull) to a builder under a kit key.
static func add_mesh(bt: KitMesh.Builder, key: String, mesh: Mesh, xf: Transform3D, mask: int = -1) -> void:
	bt.add(key, prim_of(mesh, mask), xf)


## A lofted ship hull along +Z (bow at +Z), keel at y = 0, deck at `depth` (+ sheer toward the
## bow): flared sides, a round bilge, a raked bow and a flat transom. Below `boot` metres the
## hull carries COLOR.g = 1 (seas_paint paint2: antifouling red); the gunwale is a worn edge.
## Hard edges at the deck line and transom; smooth along the sides.
static func hull_mesh(length: float, beam: float, depth: float, boot: float = -1.0, bow: float = -1.0, sheer: float = -1.0) -> ArrayMesh:
	if boot < 0.0:
		boot = depth * 0.4
	if bow < 0.0:
		bow = length * 0.22
	if sheer < 0.0:
		sheer = depth * 0.25
	var key: String = "hull_%.2f_%.2f_%.2f_%.2f_%.2f_%.2f" % [length, beam, depth, boot, bow, sheer]
	if _cache.has(key):
		return _cache[key]
	var w: float = beam * 0.5
	var br: float = minf(w * 0.4, depth * 0.45)  # bilge radius
	var nsec: int = 28
	var sections: Array = []  # each: Array of [Vector3, edge, boot] starboard half from deck edge to keel
	for i: int in nsec + 1:
		var t: float = float(i) / nsec
		var z: float = -length * 0.5 + t * length
		var zb: float = z - (length * 0.5 - bow)  # >0 inside the bow run
		var ws: float = 1.0
		var keel: float = 0.0
		if zb > 0.0:
			var u: float = clampf(zb / bow, 0.0, 1.0)
			ws = sqrt(maxf(0.0, 1.0 - u * u)) * 0.96 + 0.04
			keel = depth * 0.55 * u * u
		var stern_u: float = clampf((-length * 0.5 + length * 0.08 - z) / (length * 0.08), 0.0, 1.0)
		ws *= 1.0 - stern_u * 0.06
		keel = maxf(keel, depth * 0.25 * stern_u)
		var top: float = depth + sheer * pow(t, 2.2)
		var ww: float = w * ws
		var rr: float = minf(br, ww * 0.9)
		var pts: Array = []
		pts.append([Vector3(ww * 1.03, top, z), 1.0, 0.0])
		pts.append([Vector3(ww, maxf(boot, keel + rr), z), 0.0, 0.0])
		pts.append([Vector3(ww, maxf(boot, keel + rr), z), 0.0, 1.0])
		for k: int in range(0, 5):
			var a: float = PI * 0.5 * float(k) / 4.0
			var p := Vector3(ww - rr + cos(a) * rr, keel + rr - sin(a) * rr, z)
			if k == 0:
				p.y = minf(p.y, maxf(boot, keel + rr) - 0.001)
			pts.append([p, 0.0, 1.0])
		pts.append([Vector3(0.0, keel, z), 0.0, 1.0])
		sections.append(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(a: Array, b2: Array, c: Array, d: Array, grp: int) -> void:
		st.set_smooth_group(grp)
		for v: Array in [a, c, b2, a, d, c]:
			st.set_color(Color(float(v[1]), float(v[2]), 0))
			st.set_uv(Vector2((v[0] as Vector3).z, (v[0] as Vector3).y))
			st.add_vertex(v[0])
	for side: float in [1.0, -1.0]:
		for i: int in nsec:
			var s0: Array = sections[i]
			var s1: Array = sections[i + 1]
			for k: int in s0.size() - 1:
				if k == 1:
					continue  # zero-width seam between boot-top colours
				var m := func(v: Array) -> Array: return [Vector3((v[0] as Vector3).x * side, (v[0] as Vector3).y, (v[0] as Vector3).z), v[1], v[2]]
				var a: Array = m.call(s0[k])
				var b2: Array = m.call(s0[k + 1])
				var c: Array = m.call(s1[k + 1])
				var d: Array = m.call(s1[k])
				if side > 0.0:
					quad.call(a, b2, c, d, 0)
				else:
					quad.call(a, d, c, b2, 0)
	# Deck (flat, hard edge) and transom.
	for i: int in nsec:
		var s0: Array = sections[i]
		var s1: Array = sections[i + 1]
		var a0: Vector3 = s0[0][0]
		var a1: Vector3 = s1[0][0]
		var dk := func(v: Vector3, sd: float) -> Array: return [Vector3(v.x * sd, v.y - 0.02, v.z), 0.0, 0.0]
		quad.call(dk.call(a0, -1.0), dk.call(a1, -1.0), dk.call(a1, 1.0), dk.call(a0, 1.0), 1)
	var s0: Array = sections[0]
	for k: int in s0.size() - 1:
		if k == 1:
			continue
		var p0: Vector3 = s0[k][0]
		var p1: Vector3 = s0[k + 1][0]
		var col_g: float = float(s0[k + 1][2])
		quad.call([Vector3(-p0.x, p0.y, p0.z), 0.0, col_g], [Vector3(-p1.x, p1.y, p1.z), 0.0, col_g], [p1, 0.0, col_g], [p0, 0.0, col_g], 2)
	st.generate_normals()
	st.generate_tangents()
	var mesh: ArrayMesh = st.commit()
	_cache[key] = mesh
	return mesh


## A triangular lattice truss from a to c (width w, depth hgt), chords r, n bays of braces.
static func truss(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, w: float, hgt: float, mat: String, r: float = 0.1, taper: float = 1.0) -> void:
	var ax: Vector3 = (c - a).normalized()
	var ref: Vector3 = Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var side: Vector3 = ax.cross(ref).normalized() * w * 0.5
	var up: Vector3 = side.cross(ax).normalized() * hgt
	var chords: Array[Vector3] = [side, -side, up]
	for ch: Vector3 in chords:
		pipe(bt, o, bs, a + ch, c + ch * taper, r, mat, 8)
	var n: int = maxi(2, int(a.distance_to(c) / maxf(w, 1.2)))
	for k: int in n:
		var t0: float = float(k) / n
		var t1: float = float(k + 1) / n
		var p0: Vector3 = a.lerp(c, t0)
		var p1: Vector3 = a.lerp(c, t1)
		var s0: float = lerpf(1.0, taper, t0)
		var s1: float = lerpf(1.0, taper, t1)
		pipe(bt, o, bs, p0 + side * s0, p1 - side * s1, r * 0.5, mat, 6)
		pipe(bt, o, bs, p0 + side * s0, p1 + up * s1, r * 0.5, mat, 6)
		pipe(bt, o, bs, p0 - side * s0, p1 + up * s1, r * 0.5, mat, 6)
		pipe(bt, o, bs, p1 + side * s1, p1 - side * s1, r * 0.45, mat, 6)


## A vertical lattice tower (sides 3 or 4) from base y0 to top y1 at local xz, radius r0 -> r1,
## horizontal rings and X bracing every `step` metres.
static func tower(bt: KitMesh.Builder, o: Vector3, bs: Basis, c: Vector3, y0: float, y1: float, r0: float, r1: float, sides: int, mat: String, chord: float = 0.16, step: float = 2.4, rot: float = 0.0) -> void:
	var corner := func(k: int, y: float) -> Vector3:
		var t: float = (y - y0) / maxf(0.01, y1 - y0)
		var rr: float = lerpf(r0, r1, t)
		var ang: float = TAU * float(k) / sides + rot
		return c + Vector3(cos(ang) * rr, y, sin(ang) * rr)
	for k: int in sides:
		pipe(bt, o, bs, corner.call(k, y0), corner.call(k, y1), chord, mat, 8)
	var y: float = y0
	while y < y1 - 0.1:
		var yn: float = minf(y + step, y1)
		for k: int in sides:
			var k1: int = (k + 1) % sides
			pipe(bt, o, bs, corner.call(k, yn), corner.call(k1, yn), chord * 0.5, mat, 6)
			pipe(bt, o, bs, corner.call(k, y), corner.call(k1, yn), chord * 0.4, mat, 6)
		y = yn
