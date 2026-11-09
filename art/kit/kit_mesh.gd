class_name KitMesh
extends RefCounted
## [kit] Procedural, cached geometry for buildings and props (docs/ART_KIT.md).
##
## Everything is built through a KitMesh.Builder: you add parts under a MATERIAL KEY
## ("paint:main", "steel", "trim:warm", "glass", "decal:arrow", ...) and commit() returns ONE
## ArrayMesh with one surface per key, each surface named after its key. KitMat.apply() then
## assigns materials for a state. A whole building is therefore a handful of draw calls.
##
## Vertex colours carry baked data for kit_surface.gdshader:
##   r = edge mask (1 on bevels, fading to 0 a few cm onto flat faces) -> paint chips on edges
##   g = ambient occlusion (darker at the bottom of every part = cheap contact shadow)
##   b = per-part seed (paint value jitter so panels read as separate pieces)
## Primitive arrays are cached by their parameters; meshes built by callers can be cached with
## KitMesh.cached(key, callable).

const ARR_V: int = 0
const ARR_N: int = 1
const ARR_C: int = 2
const ARR_UV: int = 3
const ARR_I: int = 4

static var _prims: Dictionary = {}
static var _meshes: Dictionary = {}
static var stats: Dictionary = {"prim_hits": 0, "prim_builds": 0, "mesh_hits": 0, "mesh_builds": 0}


## Cache a built mesh (or any Resource) under key. build: Callable returning the Resource.
static func cached(key: String, build: Callable) -> Resource:
	if _meshes.has(key):
		stats["mesh_hits"] = int(stats["mesh_hits"]) + 1
		return _meshes[key]
	var r: Resource = build.call()
	_meshes[key] = r
	stats["mesh_builds"] = int(stats["mesh_builds"]) + 1
	return r


static func clear_cache() -> void:
	_prims.clear()
	_meshes.clear()


static func _prim(key: String, build: Callable) -> Array:
	if _prims.has(key):
		stats["prim_hits"] = int(stats["prim_hits"]) + 1
		return _prims[key]
	var a: Array = build.call()
	_prims[key] = a
	stats["prim_builds"] = int(stats["prim_builds"]) + 1
	return a


static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos)


# ---------------------------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------------------------

class Builder:
	extends RefCounted
	var surf: Dictionary = {}
	var order: PackedStringArray = []
	var rng := RandomNumberGenerator.new()
	## Point lights requested by props (lamp posts, door lamps): {pos, color, range, energy}.
	## Assemblers turn them into OmniLight3D nodes when powered.
	var lights: Array[Dictionary] = []
	## Palette roles ("main" -> "cream") and state, resolved at build time: every "paint:<role>"
	## part lands in ONE "paint" surface with its colour per vertex (CUSTOM0), every "trim:<kind>"
	## in ONE "trim" surface, and "hazard" is paint with the stripe flag. Fewer draw calls.
	var palette: Dictionary = {}
	var state: String = "repaired"

	func _init(seed_: int = 1, palette_: Dictionary = {}, state_: String = "repaired") -> void:
		rng.seed = seed_
		palette = KitMat.ROLES.duplicate()
		palette.merge(palette_, true)
		state = state_

	## Resolve a key to (surface key, CUSTOM0 colour).
	func _route(key: String) -> Array:
		if key.begins_with("paint:"):
			var role: String = key.substr(6)
			var c: Variant = palette.get(role, role)
			if state == "broken" and palette.has("broken_" + role):
				c = palette["broken_" + role]
			var col: Color = c if c is Color else KitMat.color(str(c))
			if state == "broken":
				col = col.darkened(0.15)
			col.a = 0.0
			return ["paint", col]
		if key == "hazard":
			var hz: Color = KitMat.color(str(palette.get("hazard", "yellow")))
			hz.a = 1.0
			return ["paint", hz]
		if key.begins_with("trim:"):
			var kind: String = key.substr(5)
			kind = str(palette.get("trim_" + kind, kind))
			var g: Color = KitMat.GLOW.get(kind, KitMat.color(kind) if kind.begins_with("#") else KitMat.GLOW["cool"])
			g.a = 1.0
			return ["trim", g]
		return [key, Color(0, 0, 0, 0)]

	func _surf(key: String) -> Array:
		if not surf.has(key):
			surf[key] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedInt32Array(), PackedFloat32Array()]
			order.append(key)
		return surf[key]

	## Append primitive arrays (see KitMesh primitives) under a material key.
	## seed < 0 picks a random per-part seed; ao_bottom scales the baked bottom AO (0 = none).
	func add(key: String, prim: Array, t: Transform3D = Transform3D.IDENTITY, seed_: float = -1.0, ao_bottom: float = 1.0) -> void:
		var route: Array = _route(key)
		var s: Array = _surf(route[0])
		var cust_c: Color = route[1]
		var v: PackedVector3Array = s[0]
		var base: int = v.size()
		var pv: PackedVector3Array = prim[0]
		var pn: PackedVector3Array = prim[1]
		var pc: PackedColorArray = prim[2]
		var puv: PackedVector2Array = prim[3]
		var pi: PackedInt32Array = prim[4]
		var sd: float = seed_ if seed_ >= 0.0 else rng.randf()
		var tv: PackedVector3Array = t * pv
		var nb := Transform3D(t.basis.inverse().transposed(), Vector3.ZERO)
		var tn: PackedVector3Array = nb * pn
		var n: int = pv.size()
		var scaled: bool = not t.basis.is_conformal() or absf(t.basis.get_scale().x - 1.0) > 0.001
		var cols := PackedColorArray()
		cols.resize(n)
		var cust := PackedFloat32Array()
		cust.resize(n * 4)
		for i: int in n:
			cust[i * 4] = cust_c.r
			cust[i * 4 + 1] = cust_c.g
			cust[i * 4 + 2] = cust_c.b
			cust[i * 4 + 3] = cust_c.a
			var c: Color = pc[i]
			c.b = sd
			c.g = lerpf(1.0, c.g, ao_bottom)
			cols[i] = c
			if scaled:
				tn[i] = tn[i].normalized()
		var idx := PackedInt32Array()
		idx.resize(pi.size())
		for i: int in pi.size():
			idx[i] = pi[i] + base
		# Packed arrays are values in GDScript: append to locals, then store them back.
		v.append_array(tv)
		var sn: PackedVector3Array = s[1]
		sn.append_array(tn)
		var sc: PackedColorArray = s[2]
		sc.append_array(cols)
		var su: PackedVector2Array = s[3]
		su.append_array(puv)
		var si: PackedInt32Array = s[4]
		si.append_array(idx)
		var sx: PackedFloat32Array = s[5]
		sx.append_array(cust)
		s[5] = sx
		s[0] = v
		s[1] = sn
		s[2] = sc
		s[3] = su
		s[4] = si

	# ---- convenience wrappers (primitive + add) ----

	func box(key: String, size: Vector3, t: Transform3D = Transform3D.IDENTITY, bevel: float = -1.0, seg: int = 1) -> void:
		var b: float = bevel if bevel >= 0.0 else KitMesh.auto_bevel(size)
		add(key, KitMesh.bevel_box(size, b, seg), t)

	## Box whose bottom sits at t.origin (handy for stacking).
	func box_on(key: String, size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, bevel: float = -1.0) -> void:
		var t: Transform3D = KitMesh.xf(pos, rot_deg)
		box(key, size, t * Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)), bevel)

	## Bevelled cylinder standing on t.origin (axis +Y).
	func cyl(key: String, radius: float, height: float, t: Transform3D = Transform3D.IDENTITY, bevel: float = -1.0, sides: int = 16) -> void:
		var b: float = bevel if bevel >= 0.0 else minf(radius, height) * 0.12
		add(key, KitMesh.bevel_cylinder(radius, height, b, sides), t)

	## Cylinder between two points (struts, rails, poles).
	func rod(key: String, a: Vector3, b: Vector3, radius: float, sides: int = 8) -> void:
		var d: Vector3 = b - a
		var l: float = d.length()
		if l < 0.0001:
			return
		if radius < 0.06:
			# thin rods: plain capped cylinder (bevels are invisible at this size), ~4x cheaper
			var p := PackedVector3Array([Vector3(0, 0, 1), Vector3(radius, 0, 1), Vector3(radius, l, 1), Vector3(0, l, 1)])
			add(key, KitMesh.lathe(p, mini(sides, 6)), KitMesh.look_y(a, d))
		else:
			add(key, KitMesh.bevel_cylinder(radius, l, radius * 0.3, sides), KitMesh.look_y(a, d))

	func tube(key: String, pts: PackedVector3Array, radius: float, sides: int = 8, bend: float = 0.0) -> void:
		add(key, KitMesh.sweep(pts, radius, sides, bend), Transform3D.IDENTITY)

	## Image decal quad facing +Z of t (sits 4 mm proud of the surface). size in metres.
	## All decals share the atlas (art/kit/decals/atlas.png): one "decal" surface per mesh.
	func decal(name: String, size: Vector2, t: Transform3D) -> void:
		add("decal", KitMesh.decal_quad(name, size), t * Transform3D(Basis(), Vector3(0, 0, 0.004)), 0.5, 0.0)

	func tri_count() -> int:
		var n: int = 0
		for k: String in order:
			@warning_ignore("integer_division")
			n += (surf[k][4] as PackedInt32Array).size() / 3
		return n

	func _arrays(s: Array) -> Array:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s[0]
		arrays[Mesh.ARRAY_NORMAL] = s[1]
		arrays[Mesh.ARRAY_COLOR] = s[2]
		arrays[Mesh.ARRAY_TEX_UV] = s[3]
		arrays[Mesh.ARRAY_INDEX] = s[4]
		arrays[Mesh.ARRAY_CUSTOM0] = s[5]
		return arrays

	## Surfaces (draw calls) commit() will produce.
	func surface_count() -> int:
		return order.size()

	## lods: also generate automatic LODs (ImporterMesh) so distant copies draw far fewer
	## triangles. Slower to build (cache the result); used by KitBuilding.
	func commit(into: ArrayMesh = null, lods: bool = false) -> ArrayMesh:
		if lods and into == null:
			var im := ImporterMesh.new()
			for k: String in order:
				var s2: Array = surf[k]
				if (s2[4] as PackedInt32Array).is_empty():
					continue
				im.add_surface(Mesh.PRIMITIVE_TRIANGLES, _arrays(s2), [], {}, null, k,
					Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			im.generate_lods(25.0, 60.0, [])
			return im.get_mesh()
		var m: ArrayMesh = into if into else ArrayMesh.new()
		for k: String in order:
			var s: Array = surf[k]
			if (s[4] as PackedInt32Array).is_empty():
				continue
			var arrays: Array = _arrays(s)
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
				Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			m.surface_set_name(m.get_surface_count() - 1, k)
		return m


## Build a MeshInstance3D from a builder with kit materials applied.
## state defaults to the builder's state (palette was already resolved by the builder).
static func instance(b: Builder, state: String = "", powered: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	KitMat.apply(mi, state if state != "" else b.state, powered)
	return mi


static func auto_bevel(size: Vector3) -> float:
	return clampf(minf(size.x, minf(size.y, size.z)) * 0.14, 0.006, 0.09)


## Transform placing a +Y primitive at a, pointing along d.
static func look_y(a: Vector3, d: Vector3) -> Transform3D:
	var y: Vector3 = d.normalized()
	var ref: Vector3 = Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), a)


static func _emit_tri(idx: PackedInt32Array, a: int, b: int, c: int, va: Vector3, vb: Vector3, vc: Vector3, nrm: Vector3) -> void:
	# Godot front faces are clockwise seen from outside: flip if the geometric normal agrees with nrm.
	if (vb - va).cross(vc - va).dot(nrm) > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


# ---------------------------------------------------------------------------------------------
# Primitives (all return [verts, normals, colors, uvs, indices], cached)
# ---------------------------------------------------------------------------------------------

## Bevelled (rounded-edge) box centred at the origin. bevel: edge radius in metres; seg: arc steps
## per face side (1 = soft chamfer, 2+ = round). Flat faces get an inset ring so the edge mask
## fades over ~6 cm.
static func bevel_box(size: Vector3, bevel: float = 0.04, seg: int = 1) -> Array:
	var key: String = "box:%.3f,%.3f,%.3f:%.3f:%d" % [size.x, size.y, size.z, bevel, seg]
	return _prim(key, func() -> Array: return _bevel_box(size, bevel, seg))


static func _axis_coords(h: float, r: float, seg: int, inset: float) -> PackedFloat32Array:
	var inner: float = h - r
	var out := PackedFloat32Array()
	for k: int in seg + 1:
		out.append(-h + r * float(k) / seg)
	if inset > 0.0 and inner - inset > -inner + inset + 0.001:
		out.append(-inner + inset)
		out.append(inner - inset)
	for k: int in seg + 1:
		out.append(inner + r * float(k) / seg)
	return out


static func _bevel_box(size: Vector3, bevel: float, seg: int) -> Array:
	var h: Vector3 = size * 0.5
	var r: float = clampf(bevel, 0.0005, minf(h.x, minf(h.y, h.z)) * 0.98)
	seg = maxi(seg, 1)
	var inner: Vector3 = h - Vector3(r, r, r)
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	# face: normal axis index, sign, u axis, v axis
	var faces: Array = [[0, 1.0, 2, 1], [0, -1.0, 2, 1], [1, 1.0, 0, 2], [1, -1.0, 0, 2], [2, 1.0, 0, 1], [2, -1.0, 0, 1]]
	for f: Array in faces:
		var na: int = f[0]
		var sg: float = f[1]
		var ua: int = f[2]
		var va: int = f[3]
		# inset ring per face (thin panels still get painted faces with worn edges)
		var face_min: float = minf(size[ua], size[va])
		var inset: float = minf(0.06, minf(inner[ua], inner[va]) * 0.5) if face_min > 0.4 else 0.0
		var cu: PackedFloat32Array = _axis_coords(h[ua], r, seg, inset)
		var cv: PackedFloat32Array = _axis_coords(h[va], r, seg, inset)
		var base: int = v.size()
		var fn := Vector3.ZERO
		fn[na] = sg
		for j: int in cv.size():
			for i: int in cu.size():
				var p := Vector3.ZERO
				p[na] = h[na] * sg
				p[ua] = cu[i]
				p[va] = cv[j]
				var c: Vector3 = p.clamp(-inner, inner)
				var d: Vector3 = p - c
				var dn: Vector3 = d.normalized() if d.length() > 0.000001 else fn
				var pos: Vector3 = c + dn * r
				v.append(pos)
				nn.append(dn)
				var din: float = minf(inner[ua] - absf(cu[i]), inner[va] - absf(cv[j]))
				# small faces: edge = 1 only out on the bevel arc, 0 where the flat face starts
				var edge: float = 1.0 - clampf(din / maxf(inset, 0.001), 0.0, 1.0) if inset > 0.0 else (1.0 if din < -0.0001 else 0.0)
				var ao: float = lerpf(0.5, 1.0, clampf((pos.y + h.y) / minf(size.y, 1.2), 0.0, 1.0))
				cc.append(Color(edge, ao, 0.5, 1.0))
				uv.append(Vector2(cu[i], cv[j]))
		var w: int = cu.size()
		for j: int in cv.size() - 1:
			for i: int in w - 1:
				var a: int = base + j * w + i
				var b: int = a + 1
				var c2: int = a + w + 1
				var d2: int = a + w
				var qn: Vector3 = (nn[a] + nn[c2]).normalized()
				_emit_tri(idx, a, b, c2, v[a], v[b], v[c2], qn)
				_emit_tri(idx, a, c2, d2, v[a], v[c2], v[d2], qn)
	return [v, nn, cc, uv, idx]


## Lathe a profile around +Y. profile: Vector3(radius, y, edge_mask) from bottom to top.
## Consecutive segments bending more than ~50 degrees get a hard edge (split normals).
## arc_deg < 360 makes a partial revolve (arches, hangar roofs) from angle 0 (+X) towards +Z.
static func lathe(profile: PackedVector3Array, sides: int = 16, arc_deg: float = 360.0) -> Array:
	var key: String = "lathe:%d:%.1f:%s" % [sides, arc_deg, str(profile).hash()]
	return _prim(key, func() -> Array: return _lathe(profile, sides, arc_deg))


static func _lathe(profile: PackedVector3Array, sides: int, arc_deg: float = 360.0) -> Array:
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var np: int = profile.size()
	var ymin: float = INF
	var ymax: float = -INF
	for p: Vector3 in profile:
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	var hgt: float = maxf(ymax - ymin, 0.001)
	# segment normals (2D: x = radial, y = up)
	var segn: Array[Vector2] = []
	for s: int in np - 1:
		var d := Vector2(profile[s + 1].x - profile[s].x, profile[s + 1].y - profile[s].y)
		var n2 := Vector2(d.y, -d.x).normalized() if d.length() > 0.00001 else Vector2(1, 0)
		segn.append(n2)
	for s: int in np - 1:
		var n_a: Vector2 = segn[s]
		var n_b: Vector2 = segn[s]
		if s > 0 and segn[s - 1].dot(segn[s]) > 0.64:
			n_a = (segn[s - 1] + segn[s]).normalized()
		if s < np - 2 and segn[s + 1].dot(segn[s]) > 0.64:
			n_b = (segn[s + 1] + segn[s]).normalized()
		var p0: Vector3 = profile[s]
		var p1: Vector3 = profile[s + 1]
		if absf(p0.x) < 0.00001 and absf(p1.x) < 0.00001:
			continue
		var base: int = v.size()
		for k: int in sides + 1:
			var th: float = deg_to_rad(arc_deg) * float(k) / sides
			var cs: float = cos(th)
			var sn: float = sin(th)
			for e: int in 2:
				var p: Vector3 = p0 if e == 0 else p1
				var n2: Vector2 = n_a if e == 0 else n_b
				v.append(Vector3(p.x * cs, p.y, p.x * sn))
				nn.append(Vector3(n2.x * cs, n2.y, n2.x * sn).normalized())
				var ao: float = lerpf(0.5, 1.0, clampf((p.y - ymin) / minf(hgt, 1.2), 0.0, 1.0))
				cc.append(Color(p.z, ao, 0.5, 1.0))
				uv.append(Vector2(float(k) / sides * TAU * maxf(p.x, 0.05), p.y))
		for k: int in sides:
			var a: int = base + k * 2
			var b: int = a + 1
			var c: int = a + 3
			var d: int = a + 2
			var qn: Vector3 = (nn[a] + nn[c]).normalized()
			if v[a].distance_squared_to(v[d]) > 1e-12:
				_emit_tri(idx, a, d, c, v[a], v[d], v[c], qn)
			if v[b].distance_squared_to(v[c]) > 1e-12:
				_emit_tri(idx, a, c, b, v[a], v[c], v[b], qn)
	return [v, nn, cc, uv, idx]


## Arc helper for profiles: points on a quarter arc (centre c, radius r) from angle a0 to a1 (deg).
static func arc(c: Vector2, r: float, a0: float, a1: float, steps: int, edge: float = 1.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k: int in steps + 1:
		var a: float = deg_to_rad(lerpf(a0, a1, float(k) / steps))
		out.append(Vector3(c.x + cos(a) * r, c.y + sin(a) * r, edge))
	return out


## Bevelled cylinder standing on y = 0 (axis +Y), rounded rims, inset rings on caps and sides.
static func bevel_cylinder(radius: float, height: float, bevel: float = 0.03, sides: int = 16) -> Array:
	var b: float = clampf(bevel, 0.0005, minf(radius * 0.9, height * 0.45))
	var e: float = minf(0.05, minf(radius - b, height * 0.5 - b) * 0.5)
	var p := PackedVector3Array()
	p.append(Vector3(0, 0, 0))
	if e > 0.004:
		p.append(Vector3(radius - b - e, 0, 0))
	p.append_array(arc(Vector2(radius - b, b), b, -90, 0, 2))
	if e > 0.004:
		p.append(Vector3(radius, b + e, 0))
		p.append(Vector3(radius, height - b - e, 0))
	p.append_array(arc(Vector2(radius - b, height - b), b, 0, 90, 2))
	if e > 0.004:
		p.append(Vector3(radius - b - e, height, 0))
	p.append(Vector3(0, height, 0))
	return lathe(p, sides)


## Cheap bolt/rivet head (domed, 6 sides) standing on y = 0, ~30 triangles.
static func bolt(radius: float = 0.022, height: float = 0.025) -> Array:
	return lathe(PackedVector3Array([Vector3(radius, 0, 1), Vector3(radius, height * 0.55, 1), Vector3(radius * 0.6, height, 1), Vector3(0, height, 1)]), 6)


## Flat quad in the XY plane facing +Z, UV 0..1 (decals, signs, solar cells).
static func quad(size: Vector2) -> Array:
	var key: String = "quad:%.3f,%.3f" % [size.x, size.y]
	return _prim(key, func() -> Array:
		var hx: float = size.x * 0.5
		var hy: float = size.y * 0.5
		var v := PackedVector3Array([Vector3(-hx, -hy, 0), Vector3(hx, -hy, 0), Vector3(hx, hy, 0), Vector3(-hx, hy, 0)])
		var n := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
		var c := PackedColorArray([Color(0, 1, 0.5), Color(0, 1, 0.5), Color(0, 1, 0.5), Color(0, 1, 0.5)])
		var uv := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		var idx := PackedInt32Array()
		_emit_tri(idx, 0, 1, 2, v[0], v[1], v[2], Vector3.BACK)
		_emit_tri(idx, 0, 2, 3, v[0], v[2], v[3], Vector3.BACK)
		return [v, n, c, uv, idx])


static var _atlas: Dictionary = {}


## UV rect (x, y, w, h) of a decal in the atlas; whole texture if unknown.
static func decal_rect(name: String) -> Rect2:
	if _atlas.is_empty():
		var f := FileAccess.open("res://art/kit/decals/atlas.json", FileAccess.READ)
		if f:
			_atlas = JSON.parse_string(f.get_as_text())
	var r: Array = _atlas.get(name, [0, 0, 1, 1])
	return Rect2(r[0], r[1], r[2], r[3])


## Quad like quad() with UVs mapped to a decal's atlas rect.
static func decal_quad(name: String, size: Vector2) -> Array:
	return _prim("dq:%s:%.3f,%.3f" % [name, size.x, size.y], func() -> Array:
		var a: Array = quad(size).duplicate(true)
		var r: Rect2 = decal_rect(name)
		var uv := PackedVector2Array()
		for p: Vector2 in (a[ARR_UV] as PackedVector2Array):
			uv.append(r.position + p * r.size)
		a[ARR_UV] = uv
		return a)


## Tube swept along a polyline (pipes, cables, rails). bend > 0 rounds corners with that radius
## (elbows). Ends are capped. Not cached (paths are unique); cache the finished mesh instead.
static func sweep(pts: PackedVector3Array, radius: float, sides: int = 8, bend: float = 0.0) -> Array:
	var path := PackedVector3Array()
	if bend > 0.0 and pts.size() > 2:
		path.append(pts[0])
		for i: int in range(1, pts.size() - 1):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			var r: float = minf(bend, minf(a.distance_to(b), b.distance_to(c)) * 0.45)
			var p0: Vector3 = b + (a - b).normalized() * r
			var p1: Vector3 = b + (c - b).normalized() * r
			for k: int in 7:
				var t: float = float(k) / 6.0
				path.append(p0.lerp(b, t).lerp(b.lerp(p1, t), t))
		path.append(pts[pts.size() - 1])
	else:
		path = pts
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var n: int = path.size()
	if n < 2:
		return [v, nn, cc, uv, idx]
	var tang: Vector3 = (path[1] - path[0]).normalized()
	var ref: Vector3 = Vector3.UP if absf(tang.y) < 0.9 else Vector3.RIGHT
	var nx: Vector3 = ref.cross(tang).normalized()
	var dist: float = 0.0
	for i: int in n:
		var t_in: Vector3 = (path[i] - path[maxi(i - 1, 0)]).normalized() if i > 0 else tang
		var t_out: Vector3 = (path[mini(i + 1, n - 1)] - path[i]).normalized() if i < n - 1 else t_in
		var t: Vector3 = (t_in + t_out).normalized()
		if t.length() < 0.5:
			t = t_out
		# parallel transport
		nx = (nx - t * nx.dot(t)).normalized()
		var ny: Vector3 = t.cross(nx).normalized()
		if i > 0:
			dist += path[i].distance_to(path[i - 1])
		for k: int in sides + 1:
			var th: float = TAU * float(k) / sides
			var dir: Vector3 = nx * cos(th) + ny * sin(th)
			v.append(path[i] + dir * radius)
			nn.append(dir)
			cc.append(Color(0.0, 1.0, 0.5, 1.0))
			uv.append(Vector2(float(k) / sides, dist))
	for i: int in n - 1:
		for k: int in sides:
			var a: int = i * (sides + 1) + k
			var b: int = a + 1
			var c: int = a + sides + 2
			var d: int = a + sides + 1
			var qn: Vector3 = (nn[a] + nn[c]).normalized()
			_emit_tri(idx, a, b, c, v[a], v[b], v[c], qn)
			_emit_tri(idx, a, c, d, v[a], v[c], v[d], qn)
	# caps
	for end: int in 2:
		var ci: int = 0 if end == 0 else n - 1
		var cn: Vector3 = (path[0] - path[1]).normalized() if end == 0 else (path[n - 1] - path[n - 2]).normalized()
		var centre: int = v.size()
		v.append(path[ci])
		nn.append(cn)
		cc.append(Color(1.0, 1.0, 0.5, 1.0))
		uv.append(Vector2(0.5, 0.5))
		var ring0: int = v.size()
		for k: int in sides + 1:
			var src: int = ci * (sides + 1) + k
			v.append(v[src])
			nn.append(cn)
			cc.append(Color(1.0, 1.0, 0.5, 1.0))
			uv.append(Vector2.ZERO)
		for k: int in sides:
			_emit_tri(idx, centre, ring0 + k, ring0 + k + 1, v[centre], v[ring0 + k], v[ring0 + k + 1], cn)
	return [v, nn, cc, uv, idx]


# ---------------------------------------------------------------------------------------------
# Composite helpers (add into a Builder). All sizes in metres; t places the piece.
# ---------------------------------------------------------------------------------------------

## Panelled wall in the XY plane (front faces +Z), bottom-left at t.origin, width w, height h.
## Panels are separate bevelled plates with real seams, bolts at the corners, a dark backing frame.
## opts: panel (Vector2 panel size, default 1.2 x 1.0), key (paint key, default "paint:main"),
##       key2 (alternate panel colour key or ""), depth (0.12), missing (0..1 chance a panel is
##       gone - broken state), tilt (0..1 jitter), bolts (true), trim ("" or trim key: glowing
##       strip under the top edge), hazard (true: hazard band at the bottom), patch (0..1 chance a
##       panel is a mismatched "paint:patch" repair panel - repaired state).
static func panel_wall(b: Builder, w: float, h: float, t: Transform3D, opts: Dictionary = {}) -> void:
	var psz: Vector2 = opts.get("panel", Vector2(1.2, 1.0))
	var key: String = opts.get("key", "paint:main")
	var key2: String = opts.get("key2", "")
	var depth: float = opts.get("depth", 0.12)
	var missing: float = opts.get("missing", 0.0)
	var tilt: float = opts.get("tilt", 0.0)
	var bolts: bool = opts.get("bolts", true)
	var trim: String = opts.get("trim", "")
	var hazard: bool = opts.get("hazard", false)
	var patch: float = opts.get("patch", 0.0)
	var nx: int = maxi(1, roundi(w / psz.x))
	var ny: int = maxi(1, roundi(h / psz.y))
	var pw: float = w / nx
	var ph: float = h / ny
	var gap: float = 0.035
	# backing / frame (dark steel, recessed), with posts at both ends
	b.box("dark_steel", Vector3(w, h, depth * 0.5), t * xf(Vector3(w * 0.5, h * 0.5, -depth * 0.35)))
	for side: int in 2:
		var px: float = 0.0 if side == 0 else w
		b.box("dark_steel", Vector3(0.14, h + 0.04, depth + 0.06), t * xf(Vector3(px, h * 0.5, 0.0)), 0.03)
	var y0: float = 0.0
	if hazard:
		b.box("hazard", Vector3(w - 0.1, 0.32, depth * 0.6), t * xf(Vector3(w * 0.5, 0.16, 0.02)), 0.02)
		y0 = 0.34
	var hh: float = h - y0
	ph = hh / ny
	for j: int in ny:
		for i: int in nx:
			if missing > 0.0 and b.rng.randf() < missing:
				# missing panel: leave the frame visible, maybe a bent stub
				if b.rng.randf() < 0.4:
					b.box("rusty", Vector3(pw * 0.4, 0.05, 0.03), t * xf(Vector3((i + 0.3) * pw, y0 + (j + 0.9) * ph, 0.02), Vector3(0, 0, b.rng.randf_range(-30, 30))))
				continue
			var cx: float = (i + 0.5) * pw
			var cy: float = y0 + (j + 0.5) * ph
			var rot := Vector3.ZERO
			var off := Vector3.ZERO
			if tilt > 0.0:
				rot = Vector3(b.rng.randf_range(-4, 4), b.rng.randf_range(-3, 3), b.rng.randf_range(-6, 6)) * tilt
				off.z = b.rng.randf_range(0.0, 0.05) * tilt
			var k: String = key
			if key2 != "" and (i + j * 3) % 4 == 1:
				k = key2
			if patch > 0.0 and b.rng.randf() < patch:
				k = "paint:patch"
			var psize := Vector3(pw - gap, ph - gap, depth * 0.5)
			b.box(k, psize, t * xf(Vector3(cx, cy, 0.0) + off, rot), minf(0.035, depth * 0.2), 1)
			# raised stiffener rib on tall panels
			if ph > 0.9 and b.rng.randf() < 0.5:
				b.box(k, Vector3(pw * 0.62, 0.07, 0.04), t * xf(Vector3(cx, cy, depth * 0.27) + off, rot), 0.012)
			if bolts:
				for bx: int in 2:
					for by: int in 2:
						var bp := Vector3(cx + (bx - 0.5) * (pw - 0.16), cy + (by - 0.5) * (ph - 0.16), depth * 0.25)
						b.add("steel", bolt(), t * xf(bp + off, Vector3(90, 0, 0)), -1.0, 0.0)
	if trim != "":
		b.box("dark_steel", Vector3(w - 0.1, 0.12, 0.08), t * xf(Vector3(w * 0.5, h - 0.22, depth * 0.35)), 0.02)
		b.box(trim, Vector3(w - 0.2, 0.04, 0.03), t * xf(Vector3(w * 0.5, h - 0.22, depth * 0.35 + 0.045)), 0.008)
	# top cap
	b.box(key, Vector3(w + 0.1, 0.1, depth + 0.1), t * xf(Vector3(w * 0.5, h + 0.03, 0.0)), 0.03)


## Grass tuft mesh (a few curved blades, vertex-coloured dark base to light tip). Cached.
static func grass_tuft(blades: int = 11, height: float = 0.34) -> ArrayMesh:
	return cached("tuft:%d:%.2f" % [blades, height], func() -> Resource:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for bi: int in blades:
			var ang: float = rng.randf() * TAU
			var lean: float = rng.randf_range(0.15, 0.5)
			var hgt: float = height * rng.randf_range(0.6, 1.15)
			var wid: float = rng.randf_range(0.03, 0.05)
			var dir := Vector3(cos(ang), 0, sin(ang))
			var side := Vector3(-dir.z, 0, dir.x)
			var root: Vector3 = dir * rng.randf_range(0.0, 0.09)
			var prev_l: Vector3
			var prev_r: Vector3
			for s: int in 4:
				var f: float = float(s) / 3.0
				var c: Vector3 = root + dir * lean * hgt * f * f + Vector3(0, hgt * f, 0)
				var ww: float = wid * (1.0 - f * 0.9)
				var l: Vector3 = c - side * ww
				var r: Vector3 = c + side * ww
				if s > 0:
					var tip := Color(0.52, 0.6, 0.27).lerp(Color(0.66, 0.62, 0.33), rng.randf() * 0.5)
					var col0 := Color(0.17, 0.24, 0.09).lerp(tip, f - 0.33)
					var col1 := Color(0.17, 0.24, 0.09).lerp(tip, f)
					var nrm: Vector3 = (r - l).cross(c - (prev_l + prev_r) * 0.5).normalized()
					for p: Array in [[prev_l, col0], [prev_r, col0], [r, col1], [prev_l, col0], [r, col1], [l, col1]]:
						st.set_color(p[1])
						st.set_normal((nrm + Vector3.UP).normalized())
						st.add_vertex(p[0])
				prev_l = l
				prev_r = r
		return st.commit()) as ArrayMesh


## Small rock / grit chunk (low-poly, irregular). Cached per variant.
static func pebble(variant: int = 0) -> Array:
	return _prim("pebble:%d" % variant, func() -> Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = 911 + variant
		var p := PackedVector3Array()
		p.append(Vector3(0, -0.02, 0))
		p.append(Vector3(rng.randf_range(0.7, 1.0), 0.0, 1))
		p.append(Vector3(rng.randf_range(0.8, 1.0), rng.randf_range(0.3, 0.5), 1))
		p.append(Vector3(rng.randf_range(0.3, 0.6), rng.randf_range(0.7, 0.9), 1))
		p.append(Vector3(0, rng.randf_range(0.8, 1.0), 0))
		var a: Array = _lathe(p, 5 + variant % 3)
		var verts: PackedVector3Array = a[0]
		for i: int in verts.size():
			var q: Vector3 = verts[i]
			var j: float = 1.0 + sin(q.x * 9.0 + variant) * 0.12 + cos(q.z * 7.0) * 0.12
			verts[i] = Vector3(q.x * j, q.y * 0.7, q.z * (2.0 - j))
		a[0] = verts
		return a)


## Ground patch to put under a site instead of a flat slab: an irregular dirt skirt, bevelled
## concrete/steel plates with real gaps (some cracked, sunk or missing when broken), kerbs along
## the edges, painted floor lines when restored, and MultiMesh grit + grass tufts along the edges
## and in the gaps. Returns a Node3D (one mesh + two MultiMeshInstance3D). Cached per params.
## size: footprint in metres (x, z); centred on the origin, top of plates at y = 0.08.
static func ground_patch(size: Vector2, state: String = "repaired", seed_: int = 1, opts: Dictionary = {}) -> Node3D:
	var key: String = "patch:%.1f,%.1f:%s:%d:%s" % [size.x, size.y, state, seed_, str(opts)]
	var data: _PatchData = cached(key, func() -> Resource:
		var r := _PatchData.new()
		_build_patch(r, size, state, seed_, opts)
		return r) as _PatchData
	var root := Node3D.new()
	root.name = "KitGroundPatch"
	var mi := MeshInstance3D.new()
	mi.name = "Plates"
	mi.mesh = data.mesh
	KitMat.apply(mi, state, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # [orbE] perf: 8 cm plates, no visible shadow (51 shadow draws, 581k tris on Verdance's yards)
	root.add_child(mi)
	var gi := MultiMeshInstance3D.new()
	gi.name = "Grit"
	gi.multimesh = data.grit
	gi.material_override = KitMat.concrete(state, Color(0.62, 0.58, 0.52))
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gi)
	var ti := MultiMeshInstance3D.new()
	ti.name = "Tufts"
	ti.multimesh = data.tufts
	ti.material_override = KitMat.foliage(state)
	ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ti)
	return root


class _PatchData:
	extends Resource
	var mesh: ArrayMesh
	var grit: MultiMesh
	var tufts: MultiMesh


static func _build_patch(out: _PatchData, size: Vector2, state: String, seed_: int, opts: Dictionary) -> void:
	var b := Builder.new(seed_, opts.get("palette", {}), state)
	var rng: RandomNumberGenerator = b.rng
	var broken: bool = state == "broken"
	var restored: bool = state == "restored"
	var tile: float = opts.get("tile", 1.5)
	var plate_key: String = opts.get("plate_key", "concrete")
	var hx: float = size.x * 0.5
	var hz: float = size.y * 0.5
	# dirt skirt: noisy blob a bit larger than the footprint
	var skirt := PackedVector3Array()
	var ring: int = 40
	var ph1: float = rng.randf() * TAU
	var ph2: float = rng.randf() * TAU
	for k: int in ring:
		var a: float = TAU * float(k) / ring
		var dx: float = cos(a)
		var dz: float = sin(a)
		# rounded-rectangle radius in this direction
		var rr: float = 1.0 / maxf(absf(dx) / (hx + 1.6), absf(dz) / (hz + 1.6))
		rr = minf(rr, Vector2(hx + 1.6, hz + 1.6).length())
		rr *= 1.0 + 0.1 * sin(a * 3.0 + ph1) + 0.06 * sin(a * 7.0 + ph2)
		skirt.append(Vector3(dx * rr, 0.0, dz * rr))
	_add_disc(b, "dirt", skirt, 0.015)
	# plates
	var nx: int = maxi(1, int(size.x / tile))
	var nz: int = maxi(1, int(size.y / tile))
	var tw: float = size.x / nx
	var td: float = size.y / nz
	var gaps: Array[Vector3] = []
	for j: int in nz:
		for i: int in nx:
			var c := Vector3(-hx + (i + 0.5) * tw, 0.0, -hz + (j + 0.5) * td)
			var r: float = rng.randf()
			if broken and r < 0.14:
				gaps.append(c)
				# rubble chunks where the plate was
				for q: int in 3:
					b.box(plate_key, Vector3(rng.randf_range(0.2, 0.5), 0.1, rng.randf_range(0.2, 0.4)), xf(c + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4)), Vector3(rng.randf_range(-15, 15), rng.randf() * 180, rng.randf_range(-15, 15))), 0.03)
				continue
			var y: float = 0.03
			var rot := Vector3(0, 0, 0)
			if broken:
				y += rng.randf_range(-0.04, 0.03)
				rot = Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
			elif not restored:
				y += rng.randf_range(-0.01, 0.01)
				rot = Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
			var cracked: bool = (broken and r < 0.45) or (not restored and r > 0.88)
			if cracked:
				# two halves split along a diagonal-ish line with a gap
				var split: float = rng.randf_range(0.35, 0.65)
				var w1: float = tw * split - 0.05
				var w2: float = tw * (1.0 - split) - 0.05
				b.box(plate_key, Vector3(w1, 0.1, td - 0.06), xf(c + Vector3(-tw * 0.5 + w1 * 0.5 + 0.03, y, 0), rot), 0.03)
				b.box(plate_key, Vector3(w2, 0.1, td - 0.06), xf(c + Vector3(tw * 0.5 - w2 * 0.5 - 0.03, y - 0.015, 0), rot + Vector3(1.2, 0, -1.0)), 0.03)
				gaps.append(c + Vector3(-tw * 0.5 + tw * split, 0, 0))
			else:
				b.box(plate_key, Vector3(tw - 0.06, 0.1, td - 0.06), xf(c + Vector3(0, y, 0), rot), 0.035)
			gaps.append(c + Vector3(tw * 0.5, 0, td * 0.5))
			# drain grates / manhole plates on some tiles
			if r > 0.93 and not broken:
				b.cyl("dark_steel", minf(tw, td) * 0.22, 0.02, xf(c + Vector3(0, y + 0.05, 0)), 0.01, 14)
	# kerbs along the four sides (with gaps, chunky bevels)
	for side: int in 4:
		var along: float = size.x if side < 2 else size.y
		var n: int = maxi(1, int(along / 1.0))
		var seglen: float = along / n
		for k: int in n:
			if broken and rng.randf() < 0.2:
				continue
			var tcoord: float = -along * 0.5 + (k + 0.5) * seglen
			var pos: Vector3
			var rot := Vector3.ZERO
			match side:
				0:
					pos = Vector3(tcoord, 0.04, -hz - 0.16)
				1:
					pos = Vector3(tcoord, 0.04, hz + 0.16)
				2:
					pos = Vector3(-hx - 0.16, 0.04, tcoord)
					rot.y = 90
				_:
					pos = Vector3(hx + 0.16, 0.04, tcoord)
					rot.y = 90
			if broken:
				rot += Vector3(rng.randf_range(-4, 4), rng.randf_range(-6, 6), rng.randf_range(-4, 4))
			var kk: String = "hazard" if (restored and k % 3 == 0) else "concrete"
			b.box(kk, Vector3(seglen - 0.05, 0.2, 0.28), xf(pos, rot), 0.05, 2)
	# painted lines (restored/repaired): bay lines in yellow paint, thin raised strips
	if not broken:
		var key_line: String = "paint:yellow"
		b.box(key_line, Vector3(size.x - 0.8, 0.01, 0.1), xf(Vector3(0, 0.085, -hz + 0.45)), 0.004)
		b.box(key_line, Vector3(size.x - 0.8, 0.01, 0.1), xf(Vector3(0, 0.085, hz - 0.45)), 0.004)
		if restored:
			b.decal("arrow", Vector2(0.9, 0.9), xf(Vector3(0, 0.085, hz - 1.2), Vector3(-90, 0, 0)))
	# debris (broken): bent plate bits and bolts
	if broken:
		for q: int in 10:
			var p := Vector3(rng.randf_range(-hx - 1, hx + 1), 0.02, rng.randf_range(-hz - 1, hz + 1))
			b.box("rusty", Vector3(rng.randf_range(0.15, 0.6), 0.03, rng.randf_range(0.1, 0.35)), xf(p, Vector3(rng.randf_range(-20, 20), rng.randf() * 180, rng.randf_range(-20, 20))), 0.01)
	out.mesh = b.commit()
	# grit MultiMesh: along kerbs, in gaps, around the skirt edge
	var grit_xf: Array[Transform3D] = []
	var n_grit: int = int((size.x + size.y) * (10.0 if broken else 5.0))
	for q: int in n_grit:
		var p: Vector3
		var u: float = rng.randf()
		if u < 0.55:
			var k: Vector3 = skirt[rng.randi() % skirt.size()]
			p = k * rng.randf_range(0.8, 1.03)
		elif u < 0.8 and not gaps.is_empty():
			p = gaps[rng.randi() % gaps.size()] + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		else:
			p = Vector3(rng.randf_range(-hx, hx), 0, rng.randf_range(-hz, hz))
		var s: float = rng.randf_range(0.03, 0.12) * (1.6 if u < 0.55 else 1.0)
		grit_xf.append(Transform3D(Basis.from_euler(Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6)).scaled(Vector3(s, s, s)), p + Vector3(0, 0.0 if u < 0.55 else 0.06, 0)))
	var pb := Builder.new(seed_ + 1)
	pb.add("rock", pebble(seed_ % 4), Transform3D.IDENTITY, 0.5, 0.0)
	out.grit = _multimesh(pb.commit(), grit_xf)
	# tufts: around the skirt edge and in gaps/cracks
	var tuft_xf: Array[Transform3D] = []
	var n_tuft: int = int((size.x + size.y) * (4.0 if restored else (2.5 if not broken else 1.6)))
	for q: int in n_tuft:
		var p: Vector3
		if rng.randf() < 0.7 or gaps.is_empty():
			var k: Vector3 = skirt[rng.randi() % skirt.size()]
			p = k * rng.randf_range(0.82, 1.08)
		else:
			p = gaps[rng.randi() % gaps.size()] + Vector3(rng.randf_range(-0.15, 0.15), 0.05, rng.randf_range(-0.15, 0.15))
		var s: float = rng.randf_range(0.7, 1.5) * (0.7 if broken else 1.0)
		tuft_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
	out.tufts = _multimesh(grass_tuft(), tuft_xf)


static func _multimesh(mesh: Mesh, xfs: Array[Transform3D]) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	return mm


## Flat polygon (fan) at height y, edge mask 1 on the rim so shaders can roughen it.
static func _add_disc(b: Builder, key: String, outline: PackedVector3Array, y: float) -> void:
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	v.append(Vector3(0, y, 0))
	nn.append(Vector3.UP)
	cc.append(Color(0, 1, 0.5))
	uv.append(Vector2.ZERO)
	for p: Vector3 in outline:
		v.append(Vector3(p.x, y, p.z))
		nn.append(Vector3.UP)
		cc.append(Color(1, 0.8, 0.5))
		uv.append(Vector2(p.x, p.z))
	var n: int = outline.size()
	for k: int in n:
		var a: int = 1 + k
		var c: int = 1 + (k + 1) % n
		_emit_tri(idx, 0, a, c, v[0], v[a], v[c], Vector3.UP)
	b.add(key, [v, nn, cc, uv, idx], Transform3D.IDENTITY, 0.5, 0.0)
