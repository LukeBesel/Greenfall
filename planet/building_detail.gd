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
const K_LAMP: int = 10  # [art3] a lens that glows after dark (mast beacons)
# Flag bits (UV2.y).
const F_SHOP: int = 1
const F_RIBBON: int = 2
const F_ROOF_CONCRETE: int = 4
const F_ROOF_SEAMS_X: int = 8
const F_HOOPS: int = 16
const F_RUST: int = 32
const F_STRIPES: int = 64
const F_CURTAIN: int = 128   # [art3] glass from column to column over a spandrel band
const F_RUIN: int = 2048     # [art3] whole bays of the skin are gone: rooms and slab edges show
const F_LOUVRE: int = 4096   # [art3] K_METAL: a louvred plant screen
# Wall materials (packed into UV2.y above the flags: * T_SHIFT).
const T_RED_BRICK: int = 0
const T_BRICK: int = 1
const T_CONCRETE: int = 2
const T_PANEL: int = 3       # [art3] composite cladding panels (later additions)
const T_ALLOY: int = 4       # [art3] dark alloy panels
const T_SHEET: int = 5       # [art3] standing-seam metal sheet, rusting
const T_SHIFT: int = 256
## [art3] UV.y / UV2.x of faces that are not walls (no foot or top to weather from).
const NO_WALL: float = 100.0

const FLOOR_H: float = 3.0
const BAY: float = 3.0
## [v8bld] Gaps that keep faces off each other's planes (CoplanarAudit, tests/test_v8bld_zfight.gd).
const SETBACK_IN: float = 0.06
const ROOF_IN: float = 0.02
## [v8bld] Neighbouring buildings' cornices and belt courses reach past their walls into each other;
## each building's trim level (CityLayout "trim", 0..7) moves them TRIM_STEP m a level so the
## overlapping parts never lie on one plane.
const TRIM_STEP: float = 0.012

## Facade palettes: [texture, tint]. Grounded, sun-faded city colours (no green paint).
## [art3] An old harbour town (art/concept/world_target.jpg): aged red and brown brick, soot-dark
## brick, sandstone and weathered render. No pastel paint.
const APT_PALETTE: Array = [
	[T_RED_BRICK, Color(0.92, 0.8, 0.74)], [T_RED_BRICK, Color(0.78, 0.66, 0.62)], [T_RED_BRICK, Color(0.98, 0.78, 0.66)],
	[T_RED_BRICK, Color(0.66, 0.6, 0.6)], [T_BRICK, Color(0.86, 0.7, 0.56)], [T_BRICK, Color(0.7, 0.58, 0.5)],
	[T_BRICK, Color(0.74, 0.72, 0.68)], [T_BRICK, Color(0.9, 0.62, 0.48)],
	[T_CONCRETE, Color(0.74, 0.66, 0.54)], [T_CONCRETE, Color(0.62, 0.6, 0.56)], [T_CONCRETE, Color(0.78, 0.62, 0.48)],
]
const FAC_PALETTE: Array = [
	[T_RED_BRICK, Color(0.8, 0.7, 0.66)], [T_BRICK, Color(0.74, 0.64, 0.56)], [T_RED_BRICK, Color(0.66, 0.58, 0.56)],
	[T_CONCRETE, Color(0.62, 0.6, 0.57)], [T_SHEET, Color(0.44, 0.47, 0.48)], [T_SHEET, Color(0.5, 0.42, 0.36)],
]
const ROOF_TINTS: Array = [Color(0.4, 0.4, 0.41), Color(0.5, 0.49, 0.47), Color(0.6, 0.59, 0.57), Color(0.46, 0.43, 0.41), Color(0.76, 0.76, 0.75)]
const AWNINGS: Array = [Color(0.62, 0.2, 0.16), Color(0.16, 0.3, 0.52), Color(0.72, 0.52, 0.18), Color(0.2, 0.36, 0.34), Color(0.5, 0.18, 0.26), Color(0.58, 0.56, 0.5)]
const JUNK: Array = [Color(0.2, 0.32, 0.62), Color(0.62, 0.24, 0.16), Color(0.5, 0.4, 0.26), Color(0.18, 0.18, 0.2), Color(0.66, 0.58, 0.18), Color(0.56, 0.56, 0.58)]
const METAL_LIGHT := Color(0.74, 0.75, 0.76)
const METAL_DARK := Color(0.16, 0.16, 0.17)
const WOOD := Color(0.44, 0.32, 0.22)
const DEAD_PLANT := Color(0.42, 0.34, 0.24)
const SOIL := Color(0.3, 0.23, 0.17)
const COPING := Color(0.74, 0.71, 0.66)  # [art3] weathered cast stone (was near white)

static var _mat: ShaderMaterial
## [worlds2] Facade tint of a Cradle Mode world (CityView.look_tint).
var world_tint := Color.WHITE


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


static var _ivy_mat: ShaderMaterial


## [art3] The cut-out ivy over kit facades (art/shaders/building_ivy.gdshader).
static func ivy_material() -> ShaderMaterial:
	if _ivy_mat == null:
		_ivy_mat = ShaderMaterial.new()
		_ivy_mat.shader = preload("res://art/shaders/building_ivy.gdshader")
	return _ivy_mat


## [art3] Two ivy cards over a facade: origin at its foot, `along` its length w, `out` its normal,
## h its height. The shader grows the ivy; the cards stand 7 and 13 cm off the wall.
static func ivy_card(origin: Vector3, along: Vector3, out: Vector3, w: float, h: float, seed_v: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var u := PackedVector2Array()
	var u2 := PackedVector2Array()
	var col := Color(float(seed_v % 251) / 251.0, 0, 0)
	for layer: int in 2:
		var o: Vector3 = origin + out * (0.07 + 0.06 * float(layer))
		var corners: Array = [[0.0, 0.0], [w, 0.0], [w, h], [0.0, 0.0], [w, h], [0.0, h]]
		if (Vector3.UP * h).cross(along * w).dot(out) < 0.0:  # front faces look along `out` (Geo.tri's rule)
			corners = [[0.0, 0.0], [w, h], [w, 0.0], [0.0, 0.0], [0.0, h], [w, h]]
		for q: Array in corners:
			v.append(o + along * float(q[0]) + Vector3.UP * float(q[1]))
			n.append(out)
			c.append(col)
			u.append(Vector2(q[0], q[1]))
			u2.append(Vector2(h - float(q[1]), layer))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = u
	arr[Mesh.ARRAY_TEX_UV2] = u2
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


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
		uv2 = Vector2(NO_WALL, flags + tex * T_SHIFT)  # [art3] x: metres below the wall's top (box sides)

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
		var yb: Vector3 = xf.basis.y.normalized()
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
				if ax != 1:
					# [art3] Side faces carry where they are on their wall: UV.y metres above its foot,
					# UV2.x metres below its top (the shader's grime, ivy and rain runs), and UV.x the
					# bay offset of this face alone.
					var off: float = uv.y if absf(nw.x) > absf(nw.z) else uv.x
					for k: int in range(v.size() - 6, v.size()):
						var ly: float = (v[k] - xf.origin).dot(yb)
						u[k] = Vector2(off, ly + h.y)
						u2[k].x = h.y - ly
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
		@warning_ignore("integer_division")
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
	@warning_ignore("integer_division")
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
	tint = tint.lightened(rng.randf_range(-0.04, 0.06)) * world_tint  # [worlds2] world facade tint
	var roof_tint: Color = ROOF_TINTS[rng.randi() % ROOF_TINTS.size()]
	var roof_flags: int = (F_ROOF_CONCRETE if rng.randf() < 0.35 else 0) | (F_ROOF_SEAMS_X if rng.randf() < 0.5 else 0)
	var flags: int = F_RIBBON if factory else 0
	var shop: bool = not factory and rng.randf() < 0.7
	var uvo: Vector2 = _bay_uv(r, int(bd["seed"]) & 0xffff)
	body.uv = uvo
	det.uv = uvo
	var ruined: bool = bd.get("ruined", false)
	var trim: float = TRIM_STEP * float(int(bd.get("trim", 0)))  # [v8bld]
	# Tiers: one or two (a setback upper block on taller buildings).
	var tiers: Array = []
	var lower: int = floors
	if floors >= 6 and rng.randf() < 0.6:
		@warning_ignore("integer_division")
		lower = floors - rng.randi_range(2, maxi(2, floors / 2))
	tiers.append([r, 0, lower])
	if lower < floors:
		var lat: float = rng.randf_range(0.0, 1.5) if r.size.x > 8.0 and r.size.y > 8.0 else 0.0
		# [v8bld] The upper tier stands SETBACK_IN m inside the lower tier on every side: flush, its
		# back and side walls lay on the lower parapet's outer faces and z-fought there (a flickering
		# strip round the setback of every stepped tower as the camera moved).
		var r2: Rect2 = _inset_front(r.grow(-SETBACK_IN), face, rng.randf_range(2.0, 3.2), lat)
		tiers.append([r2, lower, floors])
	var frame: Array = facade_frame(r, face)
	var origin: Vector2 = frame[0]
	var along: Vector2 = frame[1]
	var bays: int = maxi(1, int(round((r.size.x if absf(face.y) > 0.5 else r.size.y) / BAY)))
	# [art3] Low, whole buildings often end in a slate mansard with chimney stacks, not a flat roof.
	var mansard: bool = not factory and not bd.get("roofed", false) and tiers.size() == 1 and floors <= 7 and not ruined and minf(r.size.x, r.size.y) > 7.0 and rng.randf() < 0.45
	var wall_flags: int = flags | (F_RUIN if ruined else 0)
	for ti: int in tiers.size():
		var tr_: Rect2 = tiers[ti][0]
		var y0: float = float(tiers[ti][1]) * FLOOR_H
		var y1: float = float(tiers[ti][2]) * FLOOR_H
		# [art3] Some towers' upper blocks were added later: alloy or composite panels, glass from
		# column to column.
		if ti > 0 and rng.randf() < 0.4:
			tex = T_ALLOY if rng.randf() < 0.5 else T_PANEL
			tint = [Color(0.3, 0.33, 0.36), Color(0.42, 0.4, 0.37), Color(0.5, 0.52, 0.5), Color(0.36, 0.3, 0.26)][rng.randi() % 4] * world_tint
			wall_flags = F_CURTAIN | (F_RUIN if ruined else 0)
		body.mat(K_FACADE, tint, tex, wall_flags)
		body.abox(_v3(tr_.position, y0), Vector3(tr_.size.x, y1 - y0, tr_.size.y), -2, f3, F_SHOP if (shop and ti == 0) else 0)
		# Roof surface (own material, slightly above the walls' top). [v8bld] ROOF_IN m inside the
		# walls: flush, its 5 cm sides lay on the facade's top strip all round and z-fought.
		body.mat(K_ROOF, roof_tint, 0, roof_flags)
		var rr: Rect2 = tr_.grow(-ROOF_IN)
		body.abox(_v3(rr.position, y1 - 0.05), Vector3(rr.size.x, 0.06, rr.size.y))
		# Cornice at the top of each tier ([v8bld] lowered by its trim level: see TRIM_STEP).
		if not factory or rng.randf() < 0.4:
			var g: float = rng.randf_range(0.18, 0.32)
			if bd.has("trim"):  # [v8bld] neighbours' cornice ends overlap: never the same projection
				g = 0.18 + 0.018 * float(int(bd["trim"]))
			body.mat(K_COPING, COPING.darkened(rng.randf_range(0.0, 0.15)))
			body.abox(_v3(tr_.position - Vector2(g, g), y1 - 0.42 - trim), Vector3(tr_.size.x + g * 2.0, 0.42, tr_.size.y + g * 2.0))
		# Parapet with coping.
		var ph: float = rng.randf_range(0.8, 1.2)
		if bd.has("trim"):  # [v8bld] neighbours' copings overlap at the ends: never at one height
			ph = 0.82 + 0.05 * float(int(bd["trim"]))
		if mansard:
			_mansard(body, tr_, y1, trim, tex, tint)
			continue
		_parapet(body, tr_, y1, ph, tex, tint)
		# Ruined buildings: a broken notch in the roofline instead of props.
		if ruined and ti == tiers.size() - 1:
			body.mat(K_DARK, Color(0.05, 0.05, 0.05))
			var c: Vector2 = tr_.get_center()
			body.abox(_v3(c - Vector2(1.5, 1.5), y1 - 0.02), Vector3(3.0, 0.04, 3.0))
			if not bd.get("roofed", false):
				_broken_top(body, tr_, y1, tex, tint)  # [art3] wall stubs and bare frame against the sky
			_junk(det, Rect2(tr_.position + Vector2(1, 1), tr_.size - Vector2(2, 2)), y1, rng.randi_range(3, 6), [])
		elif ti == tiers.size() - 1:
			dress_roof(body, det, tr_.grow(-0.6), y1, floors, factory)
		else:
			# Terrace on the setback: planters, chairs, a dead garden.
			var terrace: Rect2 = _front_strip(tr_, face, tr_.size.x if absf(face.x) > 0.5 else tr_.size.y)
			_dead_garden(det, terrace.grow(-0.7), y1, rng.randi_range(2, 4))
	# Belt course above the ground floor.
	if not factory:
		body.mat(K_COPING, COPING.darkened(0.08))
		var lr: Rect2 = tiers[0][0]
		var bo: float = 0.1 + trim  # [v8bld] and its faces stand out a trim step further
		body.abox(_v3(lr.position - Vector2(bo, bo), 2.95 + trim), Vector3(lr.size.x + bo * 2.0, 0.22, lr.size.y + bo * 2.0))
	# Facade dressing on the street side (detail mesh).
	var top0: int = int(tiers[0][2])
	_facade_relief(body, det, origin, along, face, bays, float(top0) * FLOOR_H, trim, tex, tint, factory)
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


## [art3] Real relief on the street face: brick piers between the bays (they cast the facade's
## shadow lines), iron downpipes at its ends and, on some, a sheet-metal riser added long after the
## building was new. Piers and riser are in the body (they read from far), pipes in the detail mesh.
func _facade_relief(body: Geo, det: Geo, origin: Vector2, along: Vector2, face: Vector2, bays: int, y1: float, trim: float,
		tex: int, tint: Color, factory: bool) -> void:
	var a3 := Vector3(along.x, 0, along.y)
	var f3 := Vector3(face.x, 0, face.y)
	var b := Basis(a3, Vector3.UP, f3)
	var ya: float = 3.3
	var yb: float = y1 - 0.42 - trim - 0.08  # under the cornice
	if yb - ya > 2.0 and bays >= 2 and rng.randf() < (0.7 if factory else 0.5):
		var pd: float = 0.14 + trim + rng.randf_range(0.0, 0.06)
		var step_i: int = 2 if bays >= 6 and rng.randf() < 0.5 else 1
		body.mat(K_PLAIN, tint.darkened(0.07), tex)
		for i: int in range(1, bays, step_i):
			# (Their backs stand 5 cm inside the wall, the riser's 3 cm: no two hidden backs on one plane.)
			var c: Vector3 = _v3(origin + along * float(i) * BAY, (ya + yb) * 0.5) + f3 * (pd * 0.5 - 0.025)
			body.box(Transform3D(b, c), Vector3(0.52, yb - ya, pd + 0.05), -1, true)
	var w: float = float(bays) * BAY
	det.mat(K_METAL, Color(0.11, 0.105, 0.1), 0, F_RUST)
	for k: int in (2 if rng.randf() < 0.5 else 1):
		var px: float = 0.3 if k == 0 else w - 0.3
		var foot: Vector3 = _v3(origin + along * px, 0.25) + f3 * 0.1
		det.rod(foot, foot + Vector3(0, y1 - 0.6, 0), 0.055)
		det.box(Transform3D(b, foot + Vector3(0, y1 - 0.45, 0)), Vector3(0.3, 0.3, 0.2), -1, true)
	if bays >= 3 and y1 > 8.0 and rng.randf() < 0.3:
		var i2: int = rng.randi_range(1, bays - 1)
		var dd: float = 0.42 + trim
		var dc: Vector3 = _v3(origin + along * (float(i2) * BAY + 0.02), 0.0) + f3 * (dd * 0.5)
		body.mat(K_METAL, METAL_LIGHT.darkened(rng.randf_range(0.25, 0.45)), 0, F_RUST | F_HOOPS)
		body.box(Transform3D(b, dc + Vector3(0, (3.4 + y1 + 1.9) * 0.5, 0) - f3 * 0.015), Vector3(0.6, y1 + 1.9 - 3.4, dd + 0.03), -1, true)
		body.box(Transform3D(b, dc + Vector3(0, y1 + 1.62, 0) + f3 * (dd * 0.5 - 0.92)), Vector3(0.58, 0.5, 1.8), -1, true)


## [art3] A slate mansard on the wall head: four slopes, a flat top and brick chimney stacks.
func _mansard(g: Geo, r: Rect2, y: float, trim: float, tex: int, tint: Color) -> void:
	var rise: float = 2.2 + rng.randf_range(0.0, 0.6) + trim * 3.0
	var inset: float = minf(rng.randf_range(1.3, 1.9), minf(r.size.x, r.size.y) * 0.3)
	var slate: Color = [Color(0.2, 0.21, 0.24), Color(0.27, 0.24, 0.22), Color(0.19, 0.24, 0.23), Color(0.33, 0.2, 0.16)][rng.randi() % 4]
	var y0: float = y + 0.012 + trim
	var t: Rect2 = r.grow(-inset)
	var lo: Array[Vector3] = [_v3(r.position, y0), _v3(Vector2(r.end.x, r.position.y), y0), _v3(r.end, y0), _v3(Vector2(r.position.x, r.end.y), y0)]
	var hi: Array[Vector3] = [_v3(t.position, y0 + rise), _v3(Vector2(t.end.x, t.position.y), y0 + rise), _v3(t.end, y0 + rise), _v3(Vector2(t.position.x, t.end.y), y0 + rise)]
	g.mat(K_ROOF, slate, 0, F_ROOF_SEAMS_X)
	var out: Array[Vector3] = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for k: int in 4:
		var nrm: Vector3 = (out[k] * rise + Vector3.UP * inset).normalized()
		g.quad(lo[k], lo[(k + 1) % 4], hi[(k + 1) % 4], hi[k], nrm)
	g.quad(hi[0], hi[1], hi[2], hi[3], Vector3.UP)
	# A lead roll round the top edge.
	g.mat(K_METAL, Color(0.3, 0.31, 0.33))
	g.abox(_v3(t.position - Vector2(0.07, 0.07), y0 + rise - 0.1), Vector3(t.size.x + 0.14, 0.16, t.size.y + 0.14))
	for k: int in rng.randi_range(1, 3):
		var cs := Vector2(0.75, 1.1) if rng.randf() < 0.5 else Vector2(1.1, 0.75)
		if t.size.x < cs.x + 0.8 or t.size.y < cs.y + 0.8:
			break
		var cp := Vector2(rng.randf_range(t.position.x + 0.3, t.end.x - cs.x - 0.3), rng.randf_range(t.position.y + 0.3, t.end.y - cs.y - 0.3))
		var ch: float = rng.randf_range(1.3, 2.4)
		g.mat(K_PLAIN, tint.darkened(0.12), tex)
		g.abox(_v3(cp, y0 + rise - 0.3), Vector3(cs.x, ch + 0.3, cs.y))
		g.mat(K_COPING, COPING.darkened(0.2))
		g.abox(_v3(cp - Vector2(0.06, 0.06), y0 + rise + ch), Vector3(cs.x + 0.12, 0.12, cs.y + 0.12))


## [art3] What is left above a ruined building's roof: stubs of the next floor's walls along two
## sides, stepping down, and a few bare frame posts with a beam.
func _broken_top(g: Geo, r: Rect2, y: float, tex: int, tint: Color) -> void:
	var inr: Rect2 = r.grow(-0.34)
	if inr.size.x < 4.0 or inr.size.y < 4.0:
		return
	var along_x: bool = rng.randf() < 0.5
	var far_side: bool = rng.randf() < 0.5
	g.mat(K_PLAIN, tint.darkened(0.1), tex)
	var len_t: float = inr.size.x if along_x else inr.size.y
	var x: float = 0.0
	var hgt: float = rng.randf_range(2.6, 4.6)
	while x < len_t - 0.8 and hgt > 0.9:
		var l: float = minf(rng.randf_range(1.2, 3.2), len_t - x)
		var p: Vector2 = inr.position + (Vector2(x, inr.size.y - 0.3 if far_side else 0.0) if along_x else Vector2(inr.size.x - 0.3 if far_side else 0.0, x))
		g.abox(_v3(p, y), Vector3(l if along_x else 0.3, hgt, 0.3 if along_x else l))
		x += l
		hgt -= rng.randf_range(0.3, 1.5)
	g.mat(K_METAL, Color(0.2, 0.17, 0.15), 0, F_RUST)
	var c: Vector2 = inr.get_center()
	var prev := Vector3.INF
	for k: int in rng.randi_range(2, 4):
		var q: Vector2 = c + Vector2(rng.randf_range(-0.35, 0.35) * inr.size.x, rng.randf_range(-0.35, 0.35) * inr.size.y)
		var ph: float = rng.randf_range(2.2, 5.5)
		g.abox(_v3(q - Vector2(0.14, 0.14), y), Vector3(0.28, ph, 0.28))
		var top := _v3(q, y + ph - 0.2)
		if prev != Vector3.INF and rng.randf() < 0.7:
			g.rod(prev, top, 0.09)
		prev = top


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
		# [v8bld] The side walls' coping stops where the front and back copings end: overlapping at
		# the corners, their faces shared planes and z-fought.
		var cw: Rect2 = w.grow(0.05) if w.size.x >= w.size.y else Rect2(w.position + Vector2(-0.05, 0.05), w.size + Vector2(0.1, -0.1))
		g.abox(_v3(cw.position, y + h), Vector3(cw.size.x, 0.09, cw.size.y))


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
	# [art3] Later additions that read against the sky: a louvred plant screen, a duct run on
	# sleepers and a lattice mast with a beacon.
	if floors >= 6 and rng.randf() < 0.55:
		var ps := Vector2(rng.randf_range(3.0, 4.6), rng.randf_range(2.2, 3.0))
		var pp: Vector2 = _place(rr, used, ps)
		if pp != Vector2.INF:
			body.mat(K_METAL, METAL_LIGHT.darkened(rng.randf_range(0.3, 0.5)), 0, F_LOUVRE | F_RUST)
			body.abox(_v3(pp - ps * 0.5, y), Vector3(ps.x, rng.randf_range(2.0, 3.2), ps.y))
	if (factory or floors >= 4) and rng.randf() < 0.5:
		var horiz: bool = rr.size.x > rr.size.y
		var dl: float = (rr.size.x if horiz else rr.size.y) * rng.randf_range(0.45, 0.8)
		var ds := Vector2(dl, 0.7) if horiz else Vector2(0.7, dl)
		var dp3: Vector2 = _place(rr, used, ds)
		if dp3 != Vector2.INF and dl > 2.5:
			body.mat(K_METAL, METAL_LIGHT.darkened(rng.randf_range(0.15, 0.35)), 0, F_RUST)
			body.abox(_v3(dp3 - ds * 0.5 + Vector2(0.05, 0.05), y + 0.35), Vector3(ds.x - 0.1, 0.55, ds.y - 0.1), -1)
			det.mat(K_DARK, Color(0.09, 0.09, 0.09))
			for k: int in 3:
				var so: Vector2 = (Vector2(1, 0) if horiz else Vector2(0, 1)) * dl * (float(k) - 1.0) * 0.4
				det.abox(_v3(dp3 + so - Vector2(0.3, 0.3), y), Vector3(0.6, 0.35, 0.6))
	if floors >= 4 and rng.randf() < (0.6 if floors >= 9 else 0.3):
		var mp2: Vector2 = _place(rr, used, Vector2(1.2, 1.2))
		if mp2 != Vector2.INF:
			_mast(body, _v3(mp2, y), rng.randf_range(7.0, 11.0) + (rng.randf_range(4.0, 10.0) if floors >= 9 else 0.0))
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


## [art3] A lattice mast: three legs closing to a point, rings of bracing, a cross-arm with
## aerials, a dish and a red beacon at the head (shader kind K_LAMP: it glows after dark).
func _mast(g: Geo, base: Vector3, h: float) -> void:
	g.mat(K_METAL, Color(0.36, 0.34, 0.33), 0, F_RUST)
	var yaw: float = rng.randf() * TAU
	var legs: Array[Vector3] = []
	for k: int in 3:
		legs.append(Vector3(cos(yaw + TAU * float(k) / 3.0), 0, sin(yaw + TAU * float(k) / 3.0)))
	var top: Vector3 = base + Vector3(0, h, 0)
	var rings: int = int(h / 2.2)
	for k: int in 3:
		g.rod(base + legs[k] * 0.5, top + legs[k] * 0.06, 0.045)
		for j: int in range(1, rings):
			var t0: float = float(j) / float(rings)
			var t1: float = float(j + 1) / float(rings)
			var a0: Vector3 = base.lerp(top, t0) + legs[k] * lerpf(0.5, 0.06, t0)
			var a1: Vector3 = base.lerp(top, t1) + legs[(k + 1) % 3] * lerpf(0.5, 0.06, t1)
			g.rod(a0, a1, 0.022)
	g.rod(top, top + Vector3(0, 1.6, 0), 0.03)
	var arm: Vector3 = legs[0].cross(Vector3.UP)
	g.rod(top - Vector3(0, 1.2, 0) - arm * 1.1, top - Vector3(0, 1.2, 0) + arm * 1.1, 0.03)
	for s: float in [-1.0, 1.0]:
		g.rod(top - Vector3(0, 1.2, 0) + arm * s, top + Vector3(0, 0.1, 0) + arm * s, 0.02)
	g.mat(K_METAL, Color(0.6, 0.6, 0.58))
	g.cyl(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(80.0)), base + Vector3(0, h * 0.62, 0) + legs[1] * 0.5), 0.55, 0.12, 0.25, 8)
	g.mat(K_LAMP, Color(1.0, 0.22, 0.12))
	g.box(Transform3D(Basis.IDENTITY, top + Vector3(0, 1.7, 0)), Vector3(0.22, 0.22, 0.22), -1, true)


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
