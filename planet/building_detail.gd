class_name BuildingDetail
extends RefCounted
## Procedural building detail for the city, batched into merged meshes that all share one
## material (art/shaders/building_city.gdshader):
##  - proxy buildings (outside CityView.DETAIL_RING): setback tiers, cornices and belt courses,
##    parapets with coping, shopfront ground floors with awnings, balconies, fire escapes, and
##    varied facade palettes (red brick, pale brick, painted concrete in grounded colours);
##  - rooftops for proxy and kit buildings: tar/gravel membrane, stair and elevator bulkheads,
##    hatches, HVAC units, water tanks on stands, satellite dishes, vent stacks, solar arrays,
##    skylights on factories, rooftop junk and a few dead rooftop gardens in planters.
## Vertex data selects the look (see the shader header). CityView makes one "body" mesh (always
## drawn) and one "detail" mesh (props, balconies; distance-culled) per block.

# Kinds (COLOR.a = (kind + 0.5) / 16).
const K_FACADE: int = 0
const K_PLAIN: int = 1
const K_ROOF: int = 2
const K_METAL: int = 3
const K_SOLAR: int = 4
const K_SOIL: int = 5
const K_FLAT: int = 6
const K_COPING: int = 7
const K_DARK: int = 8
const K_GLASS: int = 9
# Flag bits (UV2.y).
const F_SHOP: int = 1
const F_RIBBON: int = 2
const F_ROOF_CONCRETE: int = 4
const F_ROOF_SEAMS_X: int = 8
const F_HOOPS: int = 16
const F_RUST: int = 32
const F_STRIPES: int = 64
# Wall textures (UV2.x).
const T_RED_BRICK: int = 0
const T_BRICK: int = 1
const T_CONCRETE: int = 2

const FLOOR_H: float = 3.0
const BAY: float = 3.0

## Facade palettes: [texture, tint]. Grounded, sun-faded city colours (no green paint).
const APT_PALETTE: Array = [
	[T_RED_BRICK, Color(1.0, 0.96, 0.92)], [T_RED_BRICK, Color(0.9, 0.82, 0.78)],
	[T_BRICK, Color(1.0, 0.9, 0.76)], [T_BRICK, Color(0.92, 0.78, 0.66)], [T_BRICK, Color(0.86, 0.84, 0.82)],
	[T_CONCRETE, Color(0.95, 0.88, 0.74)], [T_CONCRETE, Color(0.92, 0.74, 0.6)], [T_CONCRETE, Color(0.78, 0.8, 0.84)],
	[T_CONCRETE, Color(0.94, 0.92, 0.88)], [T_CONCRETE, Color(0.9, 0.78, 0.55)], [T_CONCRETE, Color(0.86, 0.66, 0.58)],
]
const FAC_PALETTE: Array = [
	[T_CONCRETE, Color(0.8, 0.79, 0.77)], [T_CONCRETE, Color(0.86, 0.82, 0.74)], [T_CONCRETE, Color(0.72, 0.76, 0.8)],
	[T_BRICK, Color(0.92, 0.84, 0.74)], [T_RED_BRICK, Color(0.86, 0.8, 0.76)],
]
const ROOF_TINTS: Array = [Color(0.4, 0.4, 0.41), Color(0.5, 0.49, 0.47), Color(0.6, 0.59, 0.57), Color(0.46, 0.43, 0.41), Color(0.76, 0.76, 0.75)]
const AWNINGS: Array = [Color(0.62, 0.2, 0.16), Color(0.16, 0.3, 0.52), Color(0.72, 0.52, 0.18), Color(0.2, 0.36, 0.34), Color(0.5, 0.18, 0.26), Color(0.58, 0.56, 0.5)]
const JUNK: Array = [Color(0.2, 0.32, 0.62), Color(0.62, 0.24, 0.16), Color(0.5, 0.4, 0.26), Color(0.18, 0.18, 0.2), Color(0.66, 0.58, 0.18), Color(0.56, 0.56, 0.58)]
const METAL_LIGHT := Color(0.74, 0.75, 0.76)
const METAL_DARK := Color(0.16, 0.16, 0.17)
const WOOD := Color(0.44, 0.32, 0.22)
const DEAD_PLANT := Color(0.42, 0.34, 0.24)
const SOIL := Color(0.3, 0.23, 0.17)
const COPING := Color(0.9, 0.88, 0.84)

static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://art/shaders/building_city.gdshader")
		_mat.set_shader_parameter("tex_red_brick", AssetLib.tex("red_brick", "diff"))
		_mat.set_shader_parameter("tex_brick", AssetLib.tex("brick_wall_02", "diff"))
		_mat.set_shader_parameter("tex_concrete", AssetLib.tex("concrete_wall_008", "diff"))
		_mat.set_shader_parameter("nrm_brick", AssetLib.tex("brick_wall_02", "nor_gl"))
		_mat.set_shader_parameter("nrm_concrete", AssetLib.tex("concrete_wall_008", "nor_gl"))
		_mat.set_shader_parameter("tex_roof", AssetLib.tex("asphalt_02", "diff"))
		_mat.set_shader_parameter("tex_roof2", AssetLib.tex("concrete_floor_worn_001", "diff"))
	return _mat


# --- Geometry --------------------------------------------------------------------------------

## Merged triangle soup with the per-vertex material data the city shader reads.
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var u := PackedVector2Array()
	var u2 := PackedVector2Array()
	# Current "material" for the next primitives.
	var col := Color.WHITE
	var uv := Vector2.ZERO
	var uv2 := Vector2.ZERO

	func mat(kind: int, tint: Color, tex: int = 0, flags: int = 0) -> void:
		col = Color(tint.r, tint.g, tint.b, (float(kind) + 0.5) / 16.0)
		uv2 = Vector2(tex, flags)

	func tri(a: Vector3, b: Vector3, d: Vector3, nrm: Vector3) -> void:
		if (d - a).cross(b - a).dot(nrm) < 0.0:
			var t: Vector3 = b
			b = d
			d = t
		v.append(a)
		v.append(b)
		v.append(d)
		for k: int in 3:
			n.append(nrm)
			c.append(col)
			u.append(uv)
			u2.append(uv2)

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, nrm: Vector3) -> void:
		tri(a, b, d, nrm)
		tri(a, d, e, nrm)

	## Box. top_kind >= 0 gives the top face its own kind (roofs), -2 drops it; the bottom is skipped unless
	## bottom is true. front/front_flags: flags for the side face whose normal is `front`.
	func box(xf: Transform3D, size: Vector3, top_kind: int = -1, bottom: bool = false,
			front: Vector3 = Vector3.ZERO, front_flags: int = 0) -> void:
		var h: Vector3 = size * 0.5
		var base_col: Color = col
		var base_uv2: Vector2 = uv2
		for ax: int in 3:
			for sgn: float in [-1.0, 1.0]:
				if ax == 1 and sgn < 0.0 and not bottom:
					continue
				if ax == 1 and sgn > 0.0 and top_kind == -2:
					continue
				var nl := Vector3.ZERO
				nl[ax] = sgn
				var t := Vector3.ZERO
				t[(ax + 1) % 3] = 1.0
				var bt := Vector3.ZERO
				bt[(ax + 2) % 3] = 1.0
				var ctr: Vector3 = nl * h
				var tt: Vector3 = t * h
				var bb: Vector3 = bt * h
				var nw: Vector3 = (xf.basis * nl).normalized()
				col = base_col
				uv2 = base_uv2
				if ax == 1 and sgn > 0.0 and top_kind >= 0:
					col.a = (float(top_kind) + 0.5) / 16.0
				elif front != Vector3.ZERO and nw.dot(front) > 0.9:
					uv2.y = float(int(base_uv2.y) | front_flags)
				quad(xf * (ctr - tt - bb), xf * (ctr + tt - bb), xf * (ctr + tt + bb), xf * (ctr - tt + bb), nw)
		col = base_col
		uv2 = base_uv2

	## Axis-aligned box from min corner (x, y, z) and size.
	func abox(mn: Vector3, size: Vector3, top_kind: int = -1, front: Vector3 = Vector3.ZERO, front_flags: int = 0) -> void:
		box(Transform3D(Basis.IDENTITY, mn + size * 0.5), size, top_kind, false, front, front_flags)

	## Cylinder along local Y centred on xf.origin.
	func cyl(xf: Transform3D, r_top: float, r_bot: float, h: float, segs: int, cap: bool = true) -> void:
		var pts_t: Array[Vector3] = []
		var pts_b: Array[Vector3] = []
		for i: int in segs + 1:
			var a: float = TAU * float(i) / float(segs)
			var d := Vector3(cos(a), 0.0, sin(a))
			pts_t.append(d * r_top + Vector3(0, h * 0.5, 0))
			pts_b.append(d * r_bot - Vector3(0, h * 0.5, 0))
		for i: int in segs:
			var mid: float = TAU * (float(i) + 0.5) / float(segs)
			var sl: float = (r_bot - r_top) / maxf(h, 0.001)
			var nl := Vector3(cos(mid), sl, sin(mid)).normalized()
			quad(xf * pts_b[i], xf * pts_b[i + 1], xf * pts_t[i + 1], xf * pts_t[i], (xf.basis * nl).normalized())
			if cap and r_top > 0.01:
				tri(xf * Vector3(0, h * 0.5, 0), xf * pts_t[i], xf * pts_t[i + 1], (xf.basis * Vector3.UP).normalized())

	## Square-section rod from a to b.
	func rod(a: Vector3, b: Vector3, r: float) -> void:
		var d: Vector3 = b - a
		var l: float = d.length()
		if l < 0.0005:
			return
		var x: Vector3 = d / l
		var y: Vector3 = x.cross(Vector3.UP)
		if y.length() < 0.01:
			y = x.cross(Vector3.RIGHT)
		y = y.normalized()
		var z: Vector3 = x.cross(y).normalized()
		box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(l, r * 2.0, r * 2.0))

	func empty() -> bool:
		return v.is_empty()

	func tri_count() -> int:
		return v.size() / 3

	## Mesh with vertices relative to origin (so the instance can sit at the block centre and
	## visibility ranges measure from there).
	func mesh(origin: Vector3 = Vector3.ZERO) -> ArrayMesh:
		var vv := PackedVector3Array()
		vv.resize(v.size())
		for i: int in v.size():
			vv[i] = v[i] - origin
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vv
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = u
		arr[Mesh.ARRAY_TEX_UV2] = u2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


# --- Builders --------------------------------------------------------------------------------

var rng := RandomNumberGenerator.new()


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Window-grid offsets so bays start at the building's corner.
static func _bay_uv(r: Rect2, salt: int) -> Vector2:
	return Vector2(-r.position.x + 300.0 + 3.0 * float(salt % 40), -r.position.y + 300.0 + 3.0 * float((salt / 40) % 40))


## Front edge origin and along-direction of a building's facade (same convention as CityView).
static func facade_frame(r: Rect2, face: Vector2) -> Array:
	if face.y < 0:
		return [Vector2(r.position.x, r.position.y), Vector2(1, 0)]
	elif face.y > 0:
		return [Vector2(r.end.x, r.end.y), Vector2(-1, 0)]
	elif face.x < 0:
		return [Vector2(r.position.x, r.end.y), Vector2(0, -1)]
	return [Vector2(r.end.x, r.position.y), Vector2(0, 1)]


## Shrinks a rect on the side facing `face` by `d` (and on the lateral sides by `lat`).
static func _inset_front(r: Rect2, face: Vector2, d: float, lat: float) -> Rect2:
	var out: Rect2 = r
	if face.y < 0:
		out = Rect2(r.position + Vector2(lat, d), r.size - Vector2(lat * 2.0, d))
	elif face.y > 0:
		out = Rect2(r.position + Vector2(lat, 0), r.size - Vector2(lat * 2.0, d))
	elif face.x < 0:
		out = Rect2(r.position + Vector2(d, lat), r.size - Vector2(d, lat * 2.0))
	else:
		out = Rect2(r.position + Vector2(0, lat), r.size - Vector2(d, lat * 2.0))
	return out


## A distant building with real detail. body: always drawn; det: distance-culled detail.
func proxy_building(bd: Dictionary, body: Geo, det: Geo) -> void:
	rng.seed = int(bd["seed"]) + 77
	var r: Rect2 = bd["rect"]
	var face: Vector2 = bd["face"]
	var f3 := Vector3(face.x, 0, face.y)
	var floors: int = int(bd["floors"])
	var factory: bool = bd["style"] == "factory"
	var pal: Array = (FAC_PALETTE if factory else APT_PALETTE)[rng.randi() % (FAC_PALETTE if factory else APT_PALETTE).size()]
	var tex: int = pal[0]
	var tint: Color = pal[1]
	tint = tint.lightened(rng.randf_range(-0.04, 0.06))
	var roof_tint: Color = ROOF_TINTS[rng.randi() % ROOF_TINTS.size()]
	var roof_flags: int = (F_ROOF_CONCRETE if rng.randf() < 0.35 else 0) | (F_ROOF_SEAMS_X if rng.randf() < 0.5 else 0)
	var flags: int = F_RIBBON if factory else 0
	var shop: bool = not factory and rng.randf() < 0.7
	var uvo: Vector2 = _bay_uv(r, int(bd["seed"]) & 0xffff)
	body.uv = uvo
	det.uv = uvo
	var ruined: bool = bd.get("ruined", false)
	# Tiers: one or two (a setback upper block on taller buildings).
	var tiers: Array = []
	var lower: int = floors
	if floors >= 6 and rng.randf() < 0.6:
		lower = floors - rng.randi_range(2, maxi(2, floors / 2))
	tiers.append([r, 0, lower])
	if lower < floors:
		var lat: float = rng.randf_range(0.0, 1.5) if r.size.x > 8.0 and r.size.y > 8.0 else 0.0
		var r2: Rect2 = _inset_front(r, face, rng.randf_range(2.0, 3.2), lat)
		tiers.append([r2, lower, floors])
	var frame: Array = facade_frame(r, face)
	var origin: Vector2 = frame[0]
	var along: Vector2 = frame[1]
	var bays: int = maxi(1, int(round((r.size.x if absf(face.y) > 0.5 else r.size.y) / BAY)))
	for ti: int in tiers.size():
		var tr: Rect2 = tiers[ti][0]
		var y0: float = float(tiers[ti][1]) * FLOOR_H
		var y1: float = float(tiers[ti][2]) * FLOOR_H
		body.mat(K_FACADE, tint, tex, flags)
		body.abox(_v3(tr.position, y0), Vector3(tr.size.x, y1 - y0, tr.size.y), -2, f3, F_SHOP if (shop and ti == 0) else 0)
		# Roof surface (own material, slightly above the walls' top).
		body.mat(K_ROOF, roof_tint, 0, roof_flags)
		body.abox(_v3(tr.position, y1 - 0.05), Vector3(tr.size.x, 0.06, tr.size.y))
		# Cornice at the top of each tier.
		if not factory or rng.randf() < 0.4:
			var g: float = rng.randf_range(0.18, 0.32)
			body.mat(K_COPING, COPING.darkened(rng.randf_range(0.0, 0.15)))
			body.abox(_v3(tr.position - Vector2(g, g), y1 - 0.42), Vector3(tr.size.x + g * 2.0, 0.42, tr.size.y + g * 2.0))
		# Parapet with coping.
		_parapet(body, tr, y1, rng.randf_range(0.8, 1.2), tex, tint)
		# Ruined buildings: a broken notch in the roofline instead of props.
		if ruined and ti == tiers.size() - 1:
			body.mat(K_DARK, Color(0.05, 0.05, 0.05))
			var c: Vector2 = tr.get_center()
			body.abox(_v3(c - Vector2(1.5, 1.5), y1 - 0.02), Vector3(3.0, 0.04, 3.0))
			_junk(det, Rect2(tr.position + Vector2(1, 1), tr.size - Vector2(2, 2)), y1, rng.randi_range(3, 6), [])
		elif ti == tiers.size() - 1:
			dress_roof(body, det, tr.grow(-0.6), y1, floors, factory)
		else:
			# Terrace on the setback: planters, chairs, a dead garden.
			var terrace: Rect2 = _front_strip(tr, face, tr.size.x if absf(face.x) > 0.5 else tr.size.y)
			_dead_garden(det, terrace.grow(-0.7), y1, rng.randi_range(2, 4))
	# Belt course above the ground floor.
	if not factory:
		body.mat(K_COPING, COPING.darkened(0.08))
		var lr: Rect2 = tiers[0][0]
		body.abox(_v3(lr.position - Vector2(0.1, 0.1), 2.95), Vector3(lr.size.x + 0.2, 0.22, lr.size.y + 0.2))
	# Facade dressing on the street side (detail mesh).
	var top0: int = int(tiers[0][2])
	var fe_bay: int = -1
	if not factory and floors >= 3 and rng.randf() < 0.45:
		fe_bay = rng.randi_range(0, maxi(bays - 2, 0))
		_fire_escape(det, origin + along * (float(fe_bay) + 0.5) * BAY, along, face, top0)
	if not factory and rng.randf() < 0.4:
		var phase: int = rng.randi() % 2
		var deep: bool = rng.randf() < 0.5
		det.mat(K_COPING, COPING.darkened(0.1))
		for i: int in bays:
			if i % 2 != phase or i == fe_bay or i == fe_bay + 1:
				continue
			for fl: int in range(1, top0):
				_balcony(det, origin + along * (float(i) + 0.5) * BAY, along, face, float(fl) * FLOOR_H, deep, tint)
	if shop:
		var col: Color = AWNINGS[rng.randi() % AWNINGS.size()]
		var striped: bool = rng.randf() < 0.5
		for i: int in bays:
			if i == fe_bay or rng.randf() < 0.35:
				continue
			_awning(det, origin + along * (float(i) + 0.5) * BAY, along, face, col, striped)
	if factory and rng.randf() < 0.35:
		# Brick chimney stack.
		var cp: Vector2 = r.get_center() + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		var sh: float = rng.randf_range(6.0, 12.0)
		body.mat(K_PLAIN, Color(0.9, 0.8, 0.74), T_RED_BRICK)
		body.cyl(Transform3D(Basis.IDENTITY, _v3(cp, float(floors) * FLOOR_H + sh * 0.5)), 0.7, 0.9, sh, 8)


## Strip along the front of a rect (depth d).
static func _front_strip(r: Rect2, face: Vector2, _len: float) -> Rect2:
	var d: float = 2.8
	if face.y < 0:
		return Rect2(r.position - Vector2(0, d), Vector2(r.size.x, d))
	elif face.y > 0:
		return Rect2(Vector2(r.position.x, r.end.y), Vector2(r.size.x, d))
	elif face.x < 0:
		return Rect2(r.position - Vector2(d, 0), Vector2(d, r.size.y))
	return Rect2(Vector2(r.end.x, r.position.y), Vector2(d, r.size.y))


func _parapet(g: Geo, r: Rect2, y: float, h: float, tex: int, tint: Color, skip_face: Vector2 = Vector2.ZERO) -> void:
	var t: float = 0.28
	g.mat(K_PLAIN, tint, tex)
	var walls: Array = []
	if skip_face != Vector2(0, -1):
		walls.append(Rect2(r.position, Vector2(r.size.x, t)))
	if skip_face != Vector2(0, 1):
		walls.append(Rect2(Vector2(r.position.x, r.end.y - t), Vector2(r.size.x, t)))
	if skip_face != Vector2(-1, 0):
		walls.append(Rect2(Vector2(r.position.x, r.position.y + t), Vector2(t, r.size.y - t * 2.0)))
	if skip_face != Vector2(1, 0):
		walls.append(Rect2(Vector2(r.end.x - t, r.position.y + t), Vector2(t, r.size.y - t * 2.0)))
	for w: Rect2 in walls:
		g.mat(K_PLAIN, tint, tex)
		g.abox(_v3(w.position, y), Vector3(w.size.x, h, w.size.y))
		g.mat(K_COPING, COPING)
		g.abox(_v3(w.position - Vector2(0.05, 0.05), y + h), Vector3(w.size.x + 0.1, 0.09, w.size.y + 0.1))


func _balcony(g: Geo, c: Vector2, along: Vector2, face: Vector2, y: float, deep: bool, tint: Color) -> void:
	var d: float = 1.1 if deep else 0.7
	var w: float = 2.3
	var a3 := Vector3(along.x, 0, along.y)
	var f3 := Vector3(face.x, 0, face.y)
	var b := Basis(a3, Vector3.UP, f3)
	var p: Vector3 = _v3(c, y) + f3 * d * 0.5
	g.mat(K_COPING, COPING.darkened(0.12))
	g.box(Transform3D(b, p), Vector3(w, 0.16, d))
	if deep:
		g.mat(K_PLAIN, tint.darkened(0.08), T_CONCRETE)
		g.box(Transform3D(b, p + f3 * (d * 0.5 - 0.04) + Vector3(0, 0.5, 0)), Vector3(w, 0.85, 0.08))
	else:
		g.mat(K_METAL, METAL_DARK)
		g.box(Transform3D(b, p + f3 * (d * 0.5 - 0.03) + Vector3(0, 0.95, 0)), Vector3(w, 0.05, 0.05))
		for k: int in 5:
			var o: float = -w * 0.5 + 0.05 + float(k) * (w - 0.1) / 4.0
			g.box(Transform3D(b, p + a3 * o + f3 * (d * 0.5 - 0.03) + Vector3(0, 0.5, 0)), Vector3(0.04, 0.9, 0.04))


func _awning(g: Geo, c: Vector2, along: Vector2, face: Vector2, col: Color, striped: bool) -> void:
	var a3 := Vector3(along.x, 0, along.y)
	var f3 := Vector3(face.x, 0, face.y)
	var depth: float = 1.35
	var drop: float = depth * tan(deg_to_rad(rng.randf_range(18.0, 28.0)))
	var back: Vector3 = _v3(c, 2.95)
	var front: Vector3 = back + f3 * depth - Vector3(0, drop, 0)
	var zdir: Vector3 = (front - back).normalized()
	var b := Basis(a3, zdir.cross(a3).normalized(), zdir)
	g.mat(K_FLAT, col.darkened(rng.randf_range(0.0, 0.15)), 0, F_STRIPES if striped else 0)
	g.box(Transform3D(b, (back + front) * 0.5), Vector3(2.6, 0.05, (front - back).length()), -1, true)
	# Valance.
	g.box(Transform3D(Basis(a3, Vector3.UP, f3), front - Vector3(0, 0.12, 0)), Vector3(2.6, 0.25, 0.03))


func _fire_escape(g: Geo, c: Vector2, along: Vector2, face: Vector2, floors: int) -> void:
	var a3 := Vector3(along.x, 0, along.y)
	var f3 := Vector3(face.x, 0, face.y)
	var b := Basis(a3, Vector3.UP, f3)
	var w: float = 2.8
	var d: float = 1.0
	g.mat(K_METAL, Color(0.12, 0.11, 0.1), 0, F_RUST)
	for fl: int in range(1, floors):
		var y: float = float(fl) * FLOOR_H
		var p: Vector3 = _v3(c, y) + f3 * (d * 0.5 + 0.05)
		g.box(Transform3D(b, p), Vector3(w, 0.06, d), -1, true)
		# Rails: outer top rail, side rails and posts.
		var outer: Vector3 = p + f3 * (d * 0.5)
		g.rod(outer + a3 * (-w * 0.5) + Vector3(0, 0.95, 0), outer + a3 * (w * 0.5) + Vector3(0, 0.95, 0), 0.025)
		g.rod(outer + a3 * (-w * 0.5) + Vector3(0, 0.5, 0), outer + a3 * (w * 0.5) + Vector3(0, 0.5, 0), 0.015)
		for s: float in [-0.5, 0.0, 0.5]:
			g.rod(outer + a3 * (w * s), outer + a3 * (w * s) + Vector3(0, 0.95, 0), 0.025)
		# Stair to the next landing, alternating direction.
		if fl < floors - 1:
			var sgn: float = 1.0 if fl % 2 == 0 else -1.0
			var s0: Vector3 = p + a3 * (-w * 0.4 * sgn) + Vector3(0, 0.05, 0)
			var s1: Vector3 = p + a3 * (w * 0.4 * sgn) + Vector3(0, FLOOR_H, 0)
			g.rod(s0 + f3 * 0.2, s1 + f3 * 0.2, 0.04)
			g.rod(s0 - f3 * 0.25, s1 - f3 * 0.25, 0.04)
	# Drop ladder.
	var lp: Vector3 = _v3(c, FLOOR_H) + f3 * (d + 0.05) + a3 * (w * 0.35)
	g.rod(lp, lp - Vector3(0, 1.4, 0), 0.025)
	g.rod(lp + a3 * 0.4, lp + a3 * 0.4 - Vector3(0, 1.4, 0), 0.025)


# --- Rooftops -------------------------------------------------------------------------------

## Free-spot placement on a roof rect.
func _place(rr: Rect2, used: Array, size: Vector2, tries: int = 10) -> Vector2:
	for k: int in tries:
		var hx: float = size.x * 0.5 + 0.2
		var hz: float = size.y * 0.5 + 0.2
		if rr.size.x < hx * 2.0 or rr.size.y < hz * 2.0:
			return Vector2.INF
		var p := Vector2(rng.randf_range(rr.position.x + hx, rr.end.x - hx), rng.randf_range(rr.position.y + hz, rr.end.y - hz))
		var me := Rect2(p - size * 0.5, size).grow(0.35)
		var ok: bool = true
		for o: Rect2 in used:
			if o.intersects(me):
				ok = false
				break
		if ok:
			used.append(Rect2(p - size * 0.5, size))
			return p
	return Vector2.INF


## Rooftop clutter. Big, far-readable pieces go into body; small ones into det.
func dress_roof(body: Geo, det: Geo, rr: Rect2, y: float, floors: int, factory: bool) -> void:
	var used: Array = []
	# Stair bulkhead (and an elevator overrun on tall buildings).
	if floors >= 3 and rng.randf() < 0.85:
		var bs := Vector2(rng.randf_range(2.6, 3.4), rng.randf_range(2.8, 3.6))
		var p: Vector2 = _place(rr, used, bs + Vector2(0.6, 0.6))
		if p != Vector2.INF:
			var bh: float = rng.randf_range(2.5, 2.9)
			var wt := Color(0.86, 0.84, 0.8).darkened(rng.randf_range(0.0, 0.2))
			body.mat(K_PLAIN, wt, T_CONCRETE)
			body.abox(_v3(p - bs * 0.5, y), Vector3(bs.x, bh, bs.y), K_ROOF)
			body.mat(K_COPING, COPING)
			body.abox(_v3(p - bs * 0.5 - Vector2(0.08, 0.08), y + bh), Vector3(bs.x + 0.16, 0.1, bs.y + 0.16))
			# Door on one side.
			var side: int = rng.randi() % 4
			var dn: Vector2 = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)][side]
			var dp: Vector2 = p + dn * (bs * 0.5 + Vector2(0.03, 0.03))
			det.mat(K_METAL, [Color(0.3, 0.33, 0.36), Color(0.45, 0.2, 0.16), Color(0.5, 0.5, 0.48)][rng.randi() % 3])
			det.box(Transform3D(Basis.IDENTITY, _v3(dp, y + 1.03)), Vector3(0.06 if dn.x != 0.0 else 0.9, 2.05, 0.06 if dn.y != 0.0 else 0.9))
			if floors >= 7 and rng.randf() < 0.7:
				var es := Vector2(2.2, 2.4)
				body.mat(K_PLAIN, wt, T_CONCRETE)
				body.abox(_v3(p - bs * 0.5 + Vector2(0.2, 0.2), y + bh), Vector3(es.x, 1.4, es.y), K_ROOF)
	else:
		var p2: Vector2 = _place(rr, used, Vector2(1.0, 1.0))
		if p2 != Vector2.INF:
			det.mat(K_METAL, METAL_LIGHT.darkened(0.2), 0, F_RUST)
			det.abox(_v3(p2 - Vector2(0.5, 0.5), y), Vector3(1.0, 0.45, 1.0))
	# Skylight ridges on factories.
	if factory and rng.randf() < 0.6:
		var n_sk: int = rng.randi_range(2, 4)
		for k: int in n_sk:
			var ss := Vector2(rng.randf_range(4.0, 7.0), 1.4) if rr.size.x > rr.size.y else Vector2(1.4, rng.randf_range(4.0, 7.0))
			var sp: Vector2 = _place(rr, used, ss)
			if sp == Vector2.INF:
				break
			body.mat(K_METAL, METAL_LIGHT.darkened(0.15))
			body.abox(_v3(sp - ss * 0.5, y), Vector3(ss.x, 0.35, ss.y))
			body.mat(K_GLASS, Color(0.3, 0.4, 0.5))
			body.box(Transform3D(Basis.IDENTITY, _v3(sp, y + 0.55)), Vector3(ss.x - 0.2, 0.4, ss.y - 0.2))
	# HVAC units.
	var n_ac: int = rng.randi_range(2, 6) if factory else rng.randi_range(0, 3)
	for k: int in n_ac:
		var big: bool = factory and rng.randf() < 0.5
		var s := Vector2(2.8, 1.8) if big else Vector2(1.5, 1.1)
		if rng.randf() < 0.5:
			s = Vector2(s.y, s.x)
		var ap: Vector2 = _place(rr, used, s)
		if ap == Vector2.INF:
			break
		var ah: float = 1.4 if big else 0.95
		var g: Geo = body if big else det
		g.mat(K_METAL, METAL_LIGHT.darkened(rng.randf_range(0.0, 0.25)), 0, F_RUST if rng.randf() < 0.4 else 0)
		g.abox(_v3(ap - s * 0.5, y), Vector3(s.x, ah, s.y))
		det.mat(K_DARK, Color(0.06, 0.06, 0.065))
		var fans: int = 2 if big else 1
		for fi: int in fans:
			var fo: Vector2 = Vector2.ZERO if fans == 1 else (Vector2(s.x * 0.25, 0) if s.x > s.y else Vector2(0, s.y * 0.25)) * (1.0 if fi == 0 else -1.0)
			det.cyl(Transform3D(Basis.IDENTITY, _v3(ap + fo, y + ah + 0.03)), minf(s.x, s.y) * 0.32, minf(s.x, s.y) * 0.32, 0.06, 10)
	# Water tank on a stand.
	if not factory and floors >= 4 and rng.randf() < 0.45:
		var tp: Vector2 = _place(rr, used, Vector2(2.6, 2.6))
		if tp != Vector2.INF:
			var leg_h: float = rng.randf_range(1.6, 2.6)
			det.mat(K_METAL, Color(0.14, 0.12, 0.11), 0, F_RUST)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					det.rod(_v3(tp + Vector2(sx, sz) * 0.95, y), _v3(tp + Vector2(sx, sz) * 0.95, y + leg_h), 0.07)
			det.rod(_v3(tp + Vector2(-0.95, -0.95), y + leg_h * 0.45), _v3(tp + Vector2(0.95, 0.95), y + leg_h * 0.45), 0.03)
			det.rod(_v3(tp + Vector2(0.95, -0.95), y + leg_h * 0.45), _v3(tp + Vector2(-0.95, 0.95), y + leg_h * 0.45), 0.03)
			det.abox(_v3(tp - Vector2(1.2, 1.2), y + leg_h), Vector3(2.4, 0.12, 2.4))
			var th: float = rng.randf_range(2.2, 3.0)
			body.mat(K_METAL, WOOD.darkened(rng.randf_range(0.0, 0.2)), 0, F_HOOPS)
			body.cyl(Transform3D(Basis.IDENTITY, _v3(tp, y + leg_h + 0.12 + th * 0.5)), 1.05, 1.05, th, 12, false)
			body.mat(K_FLAT, Color(0.2, 0.19, 0.18))
			body.cyl(Transform3D(Basis.IDENTITY, _v3(tp, y + leg_h + 0.12 + th + 0.3)), 0.06, 1.15, 0.6, 12, false)
	# Satellite dishes and an antenna mast.
	if rng.randf() < 0.45:
		for k: int in rng.randi_range(1, 2):
			var dp2: Vector2 = _place(rr, used, Vector2(1.0, 1.0))
			if dp2 == Vector2.INF:
				break
			det.mat(K_METAL, Color(0.86, 0.86, 0.84))
			det.rod(_v3(dp2, y), _v3(dp2, y + 1.1), 0.04)
			var yaw: float = rng.randf() * TAU
			var bdish := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(40.0, 60.0)))
			det.cyl(Transform3D(bdish, _v3(dp2, y + 1.25)), 0.55, 0.1, 0.22, 10)
	if floors >= 5 and rng.randf() < 0.3:
		var mp: Vector2 = _place(rr, used, Vector2(0.6, 0.6))
		if mp != Vector2.INF:
			var mh: float = rng.randf_range(3.0, 6.0)
			det.mat(K_METAL, Color(0.3, 0.3, 0.32), 0, F_RUST)
			det.rod(_v3(mp, y), _v3(mp, y + mh), 0.05)
			for k: int in 3:
				var cy: float = y + mh * (0.55 + 0.15 * float(k))
				det.rod(_v3(mp - Vector2(0.5, 0), cy), _v3(mp + Vector2(0.5, 0), cy), 0.02)
	# Vent stacks.
	det.mat(K_METAL, Color(0.6, 0.6, 0.6))
	for k: int in rng.randi_range(1, 5):
		var vp: Vector2 = _place(rr, used, Vector2(0.4, 0.4), 4)
		if vp == Vector2.INF:
			break
		var vr: float = rng.randf_range(0.07, 0.16)
		var vh: float = rng.randf_range(0.4, 1.1)
		det.cyl(Transform3D(Basis.IDENTITY, _v3(vp, y + vh * 0.5)), vr, vr, vh, 6)
		det.cyl(Transform3D(Basis.IDENTITY, _v3(vp, y + vh + 0.05)), vr * 1.7, vr * 1.7, 0.08, 6)
	# Solar array on some.
	if rng.randf() < 0.28:
		var rows: int = rng.randi_range(2, 4)
		var pw: float = minf(rng.randf_range(3.0, 5.0), rr.size.x - 1.0)
		var area := Vector2(pw, float(rows) * 1.5)
		var sp2: Vector2 = _place(rr, used, area)
		if sp2 != Vector2.INF and pw > 1.5:
			var tilt := Basis(Vector3.RIGHT, deg_to_rad(-24.0))
			for k: int in rows:
				var c: Vector2 = sp2 + Vector2(0, -area.y * 0.5 + 0.75 + float(k) * 1.5)
				body.mat(K_SOLAR, Color.WHITE)
				body.box(Transform3D(tilt, _v3(c, y + 0.45)), Vector3(pw, 0.06, 1.15))
				det.mat(K_METAL, Color(0.5, 0.5, 0.52))
				det.rod(_v3(c + Vector2(-pw * 0.4, 0.3), y), _v3(c + Vector2(-pw * 0.4, 0.3), y + 0.6), 0.03)
				det.rod(_v3(c + Vector2(pw * 0.4, 0.3), y), _v3(c + Vector2(pw * 0.4, 0.3), y + 0.6), 0.03)
	# A dead rooftop garden now and then.
	if not factory and rng.randf() < 0.14:
		var gs := Vector2(minf(5.0, rr.size.x - 1.0), minf(4.0, rr.size.y - 1.0))
		var gp: Vector2 = _place(rr, used, gs)
		if gp != Vector2.INF:
			_dead_garden(det, Rect2(gp - gs * 0.5, gs), y, rng.randi_range(2, 4))
	# Junk.
	_junk(det, rr, y, rng.randi_range(1, 5), used)


func _dead_garden(g: Geo, area: Rect2, y: float, n: int) -> void:
	if area.size.x < 1.2 or area.size.y < 1.2:
		return
	var used: Array = []
	for k: int in n:
		var horiz: bool = rng.randf() < 0.5
		var ps := Vector2(1.8, 0.7) if horiz else Vector2(0.7, 1.8)
		var p: Vector2 = _place(area, used, ps, 6)
		if p == Vector2.INF:
			continue
		var concrete: bool = rng.randf() < 0.4
		g.mat(K_FLAT, Color(0.62, 0.6, 0.57) if concrete else WOOD.darkened(rng.randf_range(0.0, 0.25)))
		g.abox(_v3(p - ps * 0.5, y), Vector3(ps.x, 0.5, ps.y))
		g.mat(K_SOIL, SOIL)
		g.abox(_v3(p - ps * 0.5 + Vector2(0.06, 0.06), y + 0.5), Vector3(ps.x - 0.12, 0.02, ps.y - 0.12))
		# Dry stalks and a withered shrub.
		g.mat(K_FLAT, DEAD_PLANT.darkened(rng.randf_range(0.0, 0.2)))
		for s: int in rng.randi_range(3, 6):
			var sp := Vector2(rng.randf_range(-ps.x * 0.4, ps.x * 0.4), rng.randf_range(-ps.y * 0.4, ps.y * 0.4))
			var tip := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.35, 0.9), rng.randf_range(-0.2, 0.2))
			g.rod(_v3(p + sp, y + 0.5), _v3(p + sp, y + 0.5) + tip, 0.018)
		if rng.randf() < 0.6:
			g.mat(K_FLAT, Color(0.4, 0.36, 0.28))
			g.cyl(Transform3D(Basis.IDENTITY, _v3(p, y + 0.75)), 0.12, 0.32, 0.5, 6)


func _junk(g: Geo, rr: Rect2, y: float, n: int, used: Array) -> void:
	for k: int in n:
		var t: int = rng.randi() % 5
		var s: Vector2 = [Vector2(0.6, 0.6), Vector2(0.6, 0.6), Vector2(1.2, 1.0), Vector2(0.8, 0.8), Vector2(0.9, 0.5)][t]
		var p: Vector2 = _place(rr, used, s, 5)
		if p == Vector2.INF:
			continue
		var col: Color = JUNK[rng.randi() % JUNK.size()].darkened(rng.randf_range(0.0, 0.25))
		match t:
			0:  # crate
				g.mat(K_FLAT, col)
				g.box(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), _v3(p, y + 0.25)), Vector3(0.55, 0.5, 0.55))
			1:  # barrel
				g.mat(K_METAL, col, 0, F_RUST)
				g.cyl(Transform3D(Basis.IDENTITY, _v3(p, y + 0.45)), 0.29, 0.29, 0.9, 8)
			2:  # pallet
				g.mat(K_FLAT, WOOD.lightened(0.15))
				g.box(Transform3D(Basis(Vector3.UP, rng.randf() * 0.5), _v3(p, y + 0.08)), Vector3(1.2, 0.15, 1.0))
			3:  # tyre
				g.mat(K_FLAT, Color(0.07, 0.07, 0.07))
				g.cyl(Transform3D(Basis.IDENTITY, _v3(p, y + 0.11)), 0.36, 0.36, 0.22, 10)
			_:  # tarp-covered heap
				g.mat(K_FLAT, [Color(0.18, 0.3, 0.55), Color(0.5, 0.46, 0.38)][rng.randi() % 2])
				g.box(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), _v3(p, y + 0.2)), Vector3(0.9, 0.4, 0.5))


## Roof for a kit (detail ring) building: membrane, parapets on the non-facade sides and props.
func kit_roof(body: Geo, det: Geo, r: Rect2, face: Vector2, y: float, floors: int, factory: bool, seed_v: int, ruined: bool) -> void:
	rng.seed = seed_v + 991
	var roof_tint: Color = ROOF_TINTS[rng.randi() % ROOF_TINTS.size()]
	var roof_flags: int = (F_ROOF_CONCRETE if rng.randf() < 0.35 else 0) | (F_ROOF_SEAMS_X if rng.randf() < 0.5 else 0)
	body.mat(K_ROOF, roof_tint, 0, roof_flags)
	body.abox(_v3(r.position, y), Vector3(r.size.x, 0.2, r.size.y))
	_parapet(body, _inset_front(r, face, 0.15, 0.0), y + 0.2, 0.75, T_CONCRETE, Color(0.84, 0.82, 0.78), face)
	var rr: Rect2 = _inset_front(r, face, 1.4, 0.0).grow(-0.6)
	if ruined:
		_junk(det, rr, y + 0.2, rng.randi_range(3, 6), [])
	else:
		dress_roof(body, det, rr, y + 0.2, floors, factory)
